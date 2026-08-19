# Go MCP SDK comparison

Input for the design discussion, covering the criteria raised in the MCP Server
channel: specification support, tools/resources/prompts, transports,
authentication, maintenance maturity, testability, observability and Meshery
ecosystem fit.

Everything below was read from the tagged source of each SDK rather than from
release notes or documentation. Versions compared are `mark3labs/mcp-go` v0.57.0
(the version the scaffold in #28 uses) and `modelcontextprotocol/go-sdk` v1.7.0.
Both are good libraries; the differences that matter here are narrow.

## Summary

| Criterion | mark3labs/mcp-go v0.57.0 | modelcontextprotocol/go-sdk v1.7.0 |
|---|---|---|
| Latest protocol revision | `2025-11-25` | `2026-07-28` |
| `server/discover` | not present | present |
| Transports | stdio, SSE, Streamable HTTP | stdio, SSE, Streamable HTTP |
| Tools, resources, prompts | all three | all three |
| Resource templates and subscriptions | yes | yes |
| Authentication helpers | none in-tree | `auth/` and `oauthex/` packages |
| Conformance suite | none in-tree | `conformance/` with baseline fixtures |
| Observability | `otel/` and `tracing/` packages | none in-tree |
| Test helpers | `mcptest/` package | in-memory transport |
| Stars | 9.0k | 5.0k |
| Open issues | 30 | 97 |
| Licence | MIT | Apache-2.0 (transitioning from MIT) |
| Status | community | maintained by the MCP project |

## Protocol revision

This is the one asymmetry worth a deliberate decision.

`mcp-go` v0.57.0 and v0.58.0 both declare, in `mcp/types.go`:

```go
const LATEST_PROTOCOL_VERSION = "2025-11-25"

var ValidProtocolVersions = []string{
	LATEST_PROTOCOL_VERSION,
	"2025-06-18",
	"2025-03-26",
	"2024-11-05",
}
```

The official SDK declares, in `mcp/shared.go`:

```go
latestProtocolVersion   = protocolVersion20260728
protocolVersion20260728 = "2026-07-28"
```

`2026-07-28` is a breaking revision. It removes the `initialize` handshake and
carries the protocol version in `_meta` on every request, makes `server/discover`
mandatory for advertising capabilities, and replaces `resources/subscribe` with
`subscriptions/listen`.

**Nothing is broken by staying on `2025-11-25` today.** Clients negotiate down,
and `mcp-go` handles an unknown version gracefully rather than erroring:

```go
if slices.Contains(mcp.ValidProtocolVersions, clientVersion) {
	return clientVersion
}
return mcp.LATEST_PROTOCOL_VERSION
```

The gap is on the other side: a client speaking the current revision sends no
`initialize` at all, and there is no `server/discover` in v0.57 for it to reach
instead.

`mcp-go` added the revision in `v1.0.0-beta.1` on 12 August, which is both a beta
and a v1 API break from the 0.x line.

This matters now specifically because the parts of the spec that changed are the
lifecycle and capability advertisement, which is what a registration contract
abstracts. Deciding after the contract exists means changing the contract and
everything registered through it.

## Transports

Both SDKs ship stdio, SSE and Streamable HTTP. Worth noting for any comparison
table that SSE is the transport Streamable HTTP **replaced** in the `2025-03-26`
revision, so new work should target Streamable HTTP and treat SSE as
backwards-compatibility only.

## Tool annotations

A behavioural difference with a practical consequence. `mcp.NewTool` in `mcp-go`
seeds annotations rather than leaving them unset:

```go
Annotations: ToolAnnotation{
	ReadOnlyHint:    ToBoolPtr(false),
	DestructiveHint: ToBoolPtr(true),
	IdempotentHint:  ToBoolPtr(false),
	OpenWorldHint:   ToBoolPtr(true),
},
```

They are `*bool` with `omitempty`, and `omitempty` only drops a nil pointer, so
those defaults are serialized. A read-only tool declared with a bare `NewTool`
therefore goes out as `readOnlyHint: false, destructiveHint: true`, and clients
use those hints to decide what needs confirmation. Both #28 and #34 hit this and
have since set the annotations explicitly.

If a read-only mode is later driven off annotations, which is the cheapest
correct implementation, this default is worth a build-time guard so a new tool
cannot silently inherit it.

## Where each is stronger

**mcp-go** has more adoption, a permissive MIT licence, a much smaller open-issue
count, in-tree OpenTelemetry and tracing packages, and an `mcptest` package for
driving a server in tests. For a project that wants observability out of the box
and does not need the newest revision, it is a reasonable default, and it is
already the scaffold's choice.

**The official SDK** tracks the specification, ships `auth/` and `oauthex/` for
the OAuth 2.1 resource-server flow the spec defines, and includes a conformance
suite with baseline fixtures. Being maintained by the MCP project means revision
support lands there first.

## Suggestion

Not a recommendation of one over the other, since both are defensible, but a
suggestion about sequencing: decide the target protocol revision explicitly and
record it in the decision log, then pick the SDK that serves it. If the answer is
"`2025-11-25` is fine for the MVP", `mcp-go` is the sensible choice and the
scaffold already reflects it. If the answer is "we should be current", that
points at the official SDK today, or at waiting for `mcp-go` v1.0.0 to leave beta
and absorbing its API break.

Either way the decision is much cheaper before the registration contract lands
than after.

## References

- Tracking issue for the protocol revision decision: #42
- `mcp-go` protocol constants: `mcp/types.go`, `server/server.go`
- Official SDK protocol constants: `mcp/shared.go`; methods in `mcp/protocol.go`
- MCP specification revisions: https://modelcontextprotocol.io/specification/versioning
