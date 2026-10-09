#!/usr/bin/env bash
# Prints the blueprint as the Base64 string Dokploy accepts under
# Compose service > Advanced > Import.
set -euo pipefail

dir="$(cd "$(dirname "$0")/../blueprint/t3code" && pwd)"

jq -n \
  --rawfile compose "$dir/docker-compose.yml" \
  --rawfile config "$dir/template.toml" \
  '{compose: $compose, config: $config}' \
  | base64 -w0
echo
