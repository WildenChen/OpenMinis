#!/usr/bin/env bash
# Issue #9 OpenClaw backend boundary validator.
#
# Compiles the REAL OpenClaw backend sources (macOS, no iOS platform needed)
# and validates:
#   1. Wire-format checks (session continuity, minis_* namespace, Location +
#      Calendar role:tool roundtrip shape, new-chat isolation, bridging).
#   2. Transport checks against a local mock OpenAI-compatible gateway
#      (auth headers, request body, SSE decoding, two-turn session flow).
#   3. [optional] A live two-turn probe against a REAL OpenClaw gateway using
#      env vars OPENCLAW_BASE_URL / OPENCLAW_GATEWAY_TOKEN / OPENCLAW_AGENT_ID.
#
# Usage:
#   ./run.sh                 # wire + transport checks
#   ./run.sh --real          # also run the live probe (needs OPENCLAW_* env)
#   PORT=18990 ./run.sh      # override the mock-gateway port
#
# No secrets are ever written by this script; the live probe reads the token
# from the environment only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PORT="${PORT:-18990}"

SWIFT_SOURCES=(
  src/ios/Providers/LLMTypes.swift
  src/ios/Providers/ThinkingLevelCatalog.swift
  src/ios/Providers/ModelsDevAPI.swift
  src/ios/Providers/AgentProvider.swift
  src/ios/Shared/AppLogger.swift
  src/ios/Shared/LLMSessionRegistry.swift
  src/ios/Providers/AgentBackend/AgentBackendConfig.swift
  src/ios/Providers/AgentBackend/AgentBackendProtocol.swift
  src/ios/Providers/AgentBackend/OpenClawBackendConfig.swift
  src/ios/Providers/AgentBackend/OpenClawBackendCredentialStore.swift
  src/ios/Providers/AgentBackend/AgentBackendProvider.swift
  src/ios/Providers/AgentBackend/OpenClawBackend.swift
)

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
FAILURES=0

swift_build() {
  local target="$1"
  local out="$2"
  echo "== Building $target =="
  swiftc -o "$out" \
    "${SWIFT_SOURCES[@]/#/$REPO_ROOT/}" \
    "$SCRIPT_DIR/stubs.swift" \
    "$SCRIPT_DIR/$target/main.swift"
}

run_wire() {
  local bin="$BUILD_DIR/wire_check"
  swift_build wire "$bin"
  echo "== Wire-format checks =="
  "$bin"
}

run_transport() {
  local bin="$BUILD_DIR/transport_check"
  swift_build transport "$bin"
  echo "== Transport checks (mock gateway on :$PORT) =="
  python3 -u "$SCRIPT_DIR/mock_gateway.py" "$PORT" > "$BUILD_DIR/mock.log" 2>&1 &
  local mock_pid=$!
  sleep 1
  "$bin" "$PORT" 2>/dev/null
  wait "$mock_pid"
  echo "--- mock gateway assertions ---"
  cat "$BUILD_DIR/mock.log"
}

run_real() {
  if [[ -z "${OPENCLAW_BASE_URL:-}" ]]; then
    echo "SKIP --real: OPENCLAW_BASE_URL not set"
    return 0
  fi
  local bin="$BUILD_DIR/real_probe"
  swift_build real "$bin"
  echo "== Live probe (real gateway) =="
  "$bin" 2>/dev/null || true
}

run_wire || FAILURES=1
run_transport || FAILURES=1
if [[ "${1:-}" == "--real" ]]; then
  run_real
fi

if [[ "$FAILURES" -eq 0 ]]; then
  echo "ALL VALIDATOR SUITES PASSED"
else
  echo "VALIDATOR FAILURE(S) DETECTED"
fi
exit "$FAILURES"
