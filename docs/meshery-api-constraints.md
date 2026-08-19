# Meshery API constraints for MCP tools

Input for the design discussion, prompted by the point raised on the call that
API failures should return useful, truthful, actionable errors rather than empty
responses.

The reason that is harder than it sounds is that several Meshery endpoints answer
`200` with data that means something other than it appears to. A tool that
forwards the response faithfully still misleads the model. Each item below was
verified against `meshery/meshery` at master, and each needs either a guard in the
shared client or an explicit contract in the tool that exposes it.

## Silent-empty failures

### Cluster scoping returns nothing rather than everything

`GET /api/system/meshsync/resources` builds its query as:

```go
Where("kubernetes_resources.cluster_id IN (?)", filter.ClusterIds)
```

and when `clusterIds` is absent the handler sets `filter.ClusterIds = []string{}`.
An empty `IN` clause matches no rows, so the call succeeds and returns an empty
list. To a model that reads as "this cluster has nothing in it".

`clusterIds` is also a JSON-encoded array in a single parameter, not a repeated
one:

```
?clusterIds=%5B%22ksid-abc%22%5D
```

Its sibling `/api/system/meshsync/resources/summary` requires a cluster too, but
answers `400`, and spells the parameter as a repeated singular `clusterId`. The
two endpoints next to each other disagree on both the name and the encoding.

Suggested contract: make the cluster identifier a required input rather than
optional, and fail in the client rather than passing an empty result upward.

### The design file spelling changed

`MesheryPattern.PatternFile` is a JSON **string** under `patternFile` on current
releases. Older releases spelled it `pattern_file`. A client that decodes only one
spelling gets a zero-valued design and no error, so `get_design` returns a design
with no components rather than failing.

Suggested contract: accept both spellings and both shapes, and treat a missing
design file as an error.

### Relationship evaluation fails open

`GET /api/system/meshsync/resources?asDesign=true` renders discovered state as an
evaluated design, which is where a topology graph comes from since there is no
`/topology` route. On evaluation failure the handler falls back to the
un-evaluated design and still returns `200`:

```go
evalResponse, error := h.EvaluateDesign(...)
if error != nil {
    design = rawDesign
    h.log.Error(...)
}
```

So an empty `relationships` array means either "no edges" or "evaluation failed",
and the caller cannot tell which.

Suggested contract: carry an explicit flag distinguishing the two, so a model is
never told a cluster has no relationships when the evaluation simply did not run.

### Org-scoped routes reject silently from the caller's point of view

`GET /api/environments` and the workspace routes reject any request without
`orgId`:

```go
orgID := q.Get("orgId")
if orgID == "" {
    writeJSONError(w, "orgId is required", http.StatusBadRequest)
    return
}
```

An org comes from `GET /api/identity/orgs`. Resolving it once in the shared client
is cheaper than adding the parameter to every environment and workspace tool.

## Authentication failures do not look like authentication failures

Meshery does not answer an unauthenticated API call with `401`. `AuthMiddleware`
redirects:

```go
http.Redirect(w, req, fmt.Sprintf("/provider?%s", queryParams.Encode()), http.StatusFound)
```

Go's default `http.Client` follows redirects, so a client lands on a `200` HTML
login page, passes any `2xx` check, and fails inside the JSON decoder. The user
sees a parse error rather than "not authenticated".

Two further details that make this harder to notice:

- The credential is the `token` cookie with `meshery-provider` alongside it.
  `RemoteProvider.GetToken` reads only the cookie; no route reads an
  `Authorization` header.
- `DefaultLocalProvider.GetSession` returns `nil` unconditionally, so a locally
  started Meshery accepts anything. An incorrect auth implementation therefore
  works in local development and fails only against a remote provider.

Suggested contract: set `CheckRedirect` to stop, and treat a redirect to
`/provider` or `/auth/login` as an authentication error with remediation text
pointing at `mesheryctl system login`.

## Three identifiers for one cluster

These are not interchangeable and mixing them produces empty results rather than
errors:

| Value | Addresses |
|---|---|
| `kubernetesServerId` | what MeshSync keys discovered resources on |
| `connectionId` | the connection record, used by connection and event APIs |
| K8sContext `id` | the deployment target, passed as `?contexts=` |

`GET /api/system/kubernetes/contexts` returns all three together, which makes it a
natural entry point for cluster-scoped tools.

## Capabilities that are not available

Worth recording so tools are not specified against them:

| Asked for | Reality |
|---|---|
| Kubernetes cluster events | MeshSync does not sync Event objects. `/api/system/events` is Meshery's own notification store, which is a different thing. |
| An active workspace | No server-side concept exists; workspace routes are membership operations. |
| Deleting a performance test result | Results routes are `GET` only. `DELETE` exists on profiles. |
| A performance run ID to poll | The run route is a blocking `text/event-stream` and the caller supplies the UUID. |
| Nighthawk load generation | Removed. `FortioLG` is the only generator, and the parameters are `t` plus `dur`, `qps` and `c`. |

## Suggested error taxonomy

Mapping the above onto the MeshKit-style categories raised on the call:

| Case | Detection | What the user should be told |
|---|---|---|
| Not authenticated | redirect to `/provider` or `/auth/login` | session expired or absent, run `mesheryctl system login` |
| Missing required scope | `400` with `orgId is required`, or an absent cluster identifier | which identifier is missing and where to obtain it |
| Upstream failure | non-2xx with a Meshery error body | Meshery's own message, preserved rather than discarded |
| Ambiguous empty result | empty list where a scope filter was required | that the query was unscoped, not that the resource is empty |
| Unsupported operation | see the table above | that Meshery does not expose this, with the closest alternative |

The general principle behind all of these: an empty result and a failed query
should never be indistinguishable to the caller.
