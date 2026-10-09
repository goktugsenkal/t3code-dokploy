#!/usr/bin/env bash
# Points every file at one upstream T3 Code version.
#   scripts/bump.sh 0.0.46
set -euo pipefail

version="${1:?usage: bump.sh <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"

printf '%s\n' "$version" > "$root/T3_VERSION"
sed -i -E "s#(image: ghcr\.io/[^:]+/t3code:).*#\1${version}#" "$root/blueprint/t3code/docker-compose.yml"
sed -i -E "s#(T3_VERSION: ).*#\1${version}#" "$root/compose.yaml"
tmp="$(mktemp)"
jq --arg v "$version" '.version = $v' "$root/blueprint/t3code/meta.json" > "$tmp"
mv "$tmp" "$root/blueprint/t3code/meta.json"
