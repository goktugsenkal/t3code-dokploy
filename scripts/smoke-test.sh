#!/usr/bin/env bash
# Starts an image with throwaway volumes, as Dokploy would, and checks the
# server comes up.
#   scripts/smoke-test.sh <image>
set -euo pipefail

image="${1:?usage: smoke-test.sh <image>}"
name="t3code-smoke-$$"
port="${SMOKE_PORT:-37730}"
base="http://127.0.0.1:${port}"

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$name-home" "$name-workspace" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Pairing tokens are credentials, even for a throwaway container.
redacted_logs() {
  docker logs "$name" 2>&1 \
    | grep -vE '^[ ▀▄█]+$' \
    | sed -E 's/(token=|Token: ).*/\1<redacted>/'
}

fail() {
  echo "--- container logs" >&2
  redacted_logs >&2 || true
  echo "smoke test failed: $*" >&2
  exit 1
}

run() {
  timeout 60 docker exec "$name" "$@"
}

docker run -d --name "$name" -p "127.0.0.1:${port}:3773" \
  -v "$name-home:/home/t3" -v "$name-workspace:/workspace" \
  "$image" >/dev/null

# The pairing URL can print a moment before the listener is up.
ready=false
for i in $(seq 1 90); do
  if curl -fsS --max-time 5 "$base/.well-known/t3/environment" >/dev/null 2>&1; then
    logs="$(docker logs "$name" 2>&1)"
    if [[ "$logs" == *"Pairing URL:"* ]]; then
      ready=true
      break
    fi
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != "true" ]; then
    fail "container exited"
  fi
  [ $((i % 15)) -eq 0 ] && echo "waiting for server (${i}s)"
  sleep 1
done
[ "$ready" = true ] || fail "server not ready after 90s"
echo "server ready"

curl -fsS --max-time 10 "$base/.well-known/t3/environment" | jq -e '.serverVersion' >/dev/null \
  || fail "environment descriptor"
curl -fsS --max-time 10 "$base/" >/dev/null || fail "web UI"
run t3 auth pairing create --base-url https://example.com | grep -q "https://example.com/pair#token=" \
  || fail "pairing link"
run t3 --version || fail "t3 --version"
run claude --version || fail "claude --version"
gh_version="$(run gh --version | awk 'NR == 1 { print $3 }')"
[ "$(printf '%s\n' 2.81.0 "$gh_version" | sort -V | head -n 1)" = 2.81.0 ] \
  || fail "gh ${gh_version:-missing} is older than 2.81.0"
if docker logs "$name" 2>&1 | grep -q "Claude Code not found"; then
  fail "Claude Code was not seeded into the home volume"
fi
[ "$(run id -u)" != "0" ] || fail "running as root"

echo "smoke test passed: $image"
