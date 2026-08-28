#!/usr/bin/env bash
#
# Builds and runs a Meshery Server from source, for testing an MCP server
# against something real.
#
# The published image is amd64 only and crashes under emulation on arm64 during
# content seeding, which is why so much of this work gets tested against mocks.
# The source builds and runs natively.
#
#   ./scripts/meshery-dev-server.sh                 # clones into ./.meshery-src
#   ./scripts/meshery-dev-server.sh /path/to/meshery
#
# Serves on $PORT (default 9081) with the built-in Local provider, so no remote
# provider, credentials or network are needed.
set -euo pipefail

PORT="${PORT:-9081}"
SRC="${1:-.meshery-src}"

if [ ! -d "$SRC" ]; then
  echo "cloning meshery/meshery into $SRC"
  git clone --depth 1 https://github.com/meshery/meshery.git "$SRC"
fi

if ! command -v go >/dev/null 2>&1; then
  echo "go is required; meshery/meshery targets the version in its go.mod" >&2
  exit 1
fi

BIN="$(cd "$SRC" && pwd)/meshery-server"
echo "building the server (first build pulls a large dependency tree)"
(cd "$SRC/server/cmd" && go build -o "$BIN" .)

echo "serving on http://127.0.0.1:$PORT with the Local provider"
cd "$SRC/server/cmd"
PORT="$PORT" \
PROVIDER=Local \
USE_GO_POLICY_ENGINE=true \
LOG_LEVEL="${LOG_LEVEL:-3}" \
APP_PATH=./apps.json \
KEYS_PATH=../../server/permissions/keys.csv \
MESHSYNC_DEFAULT_DEPLOYMENT_MODE=operator \
exec "$BIN"
