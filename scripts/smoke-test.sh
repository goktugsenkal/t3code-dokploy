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

docker run -d --name "$name" -p "127.0.0.1:${port}:3773" \
  -v "$name-home:/home/t3" -v "$name-workspace:/workspace" \
  "$image" >/dev/null

# The pairing URL can print a moment before the listener is up.
ready=false
for _ in $(seq 1 90); do
  if curl -fsS "$base/.well-known/t3/environment" >/dev/null 2>&1 \
    && docker logs "$name" 2>&1 | grep -q "Pairing URL:"; then
    ready=true
    break
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != "true" ]; then
    break
  fi
  sleep 1
done

if [ "$ready" != true ]; then
  docker logs "$name" >&2
  echo "server did not become ready" >&2
  exit 1
fi

curl -fsS "$base/.well-known/t3/environment" | jq -e '.serverVersion' >/dev/null
curl -fsS "$base/" >/dev/null
docker exec "$name" t3 auth pairing create --base-url https://example.com | grep -q "https://example.com/pair#token="
docker exec "$name" t3 --version
docker exec "$name" claude --version
if docker logs "$name" 2>&1 | grep -q "Claude Code not found"; then
  echo "Claude Code was not seeded into the home volume" >&2
  exit 1
fi
[ "$(docker exec "$name" id -u)" != "0" ]

echo "smoke test passed: $image"
