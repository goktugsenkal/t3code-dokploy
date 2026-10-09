#!/usr/bin/env bash
# Installed as /usr/local/bin/gh, ahead of the real /usr/bin/gh.
#
# Without GITHUB_APP_ID this is the plain GitHub CLI. With it, every call runs
# as the GitHub App installation: installation tokens expire after an hour, so
# a cached token is reused until ten minutes before expiry and a new one is
# minted otherwise. git gets the same token through `gh auth git-credential`.
set -euo pipefail

real_gh=/usr/bin/gh

if [ -z "${GITHUB_APP_ID:-}" ]; then
  exec "$real_gh" "$@"
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/github-app"
token_file="$cache_dir/token.json"

fail() {
  echo "gh: GitHub App: $*" >&2
  return 1
}

b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# PEM text (real or literal \n line breaks) or the PEM file base64-encoded.
private_key() {
  if [[ "$GITHUB_APP_PRIVATE_KEY" == *"BEGIN"* ]]; then
    printf '%b\n' "$GITHUB_APP_PRIVATE_KEY"
  else
    printf '%s' "$GITHUB_APP_PRIVATE_KEY" | base64 -d
  fi
}

app_jwt() {
  local now header payload signature
  [ -n "${GITHUB_APP_PRIVATE_KEY:-}" ] || fail "GITHUB_APP_PRIVATE_KEY is not set" || return
  now="$(date +%s)"
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$GITHUB_APP_ID" | b64url)"
  signature="$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign <(private_key) | b64url)" \
    && [ -n "$signature" ] || fail "could not sign with GITHUB_APP_PRIVATE_KEY" || return
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

app_api() {
  local method="$1" path="$2" jwt response status body
  jwt="$(app_jwt)" || return
  response="$(curl -sS --connect-timeout 10 --max-time 30 -X "$method" -w '\n%{http_code}' \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com$path")" || fail "$method $path: request failed" || return
  status="${response##*$'\n'}"
  body="${response%$'\n'*}"
  if [ "$status" -ge 300 ]; then
    fail "$method $path: HTTP $status $(jq -r '.message // empty' <<< "$body" 2>/dev/null)" || return
  fi
  printf '%s' "$body"
}

installation_id() {
  if [ -n "${GITHUB_APP_INSTALLATION_ID:-}" ]; then
    printf '%s' "$GITHUB_APP_INSTALLATION_ID"
    return
  fi
  local installations count
  installations="$(app_api GET /app/installations)" || return
  count="$(jq 'length' <<< "$installations")"
  [ "$count" = 1 ] || fail "the app has $count installations; set GITHUB_APP_INSTALLATION_ID" || return
  jq -r '.[0].id' <<< "$installations"
}

fresh_token() {
  local expires id response
  if [ -s "$token_file" ]; then
    expires="$(jq -r '.expires_at // empty' "$token_file" 2>/dev/null || true)"
    if [ -n "$expires" ] && [ "$(date -d "$expires" +%s)" -gt "$(($(date +%s) + 600))" ]; then
      jq -r '.token' "$token_file"
      return
    fi
  fi
  id="$(installation_id)" || return
  response="$(app_api POST "/app/installations/$id/access_tokens")" || return
  jq -e '{token, expires_at} | select(.token and .expires_at)' <<< "$response" > "$token_file.tmp" \
    || fail "unexpected token response" || return
  mv "$token_file.tmp" "$token_file"
  jq -r '.token' "$token_file"
}

# A caller that pinned a token (T3 Code does) keeps it.
if [ -z "${GH_TOKEN:-}" ]; then
  umask 077
  mkdir -p "$cache_dir"
  exec 9> "$cache_dir/lock"
  flock 9
  GH_TOKEN="$(fresh_token)" || exit 1
  exec 9>&-
  export GH_TOKEN
fi

# Installation tokens can't call GET /user, which T3 Code uses to learn who is
# signed in (pingdotgg/t3code#11247). GraphQL `viewer` answers the same question.
if [ "${1:-}" = api ] && [ "${2:-}" = user ]; then
  shift 2
  jq_filter=""
  args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -q | --jq) jq_filter="$2"; shift 2 ;;
      --jq=*) jq_filter="${1#--jq=}"; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  viewer="$("$real_gh" api graphql "${args[@]}" -f 'query={viewer{login databaseId}}' \
    --jq '.data.viewer | {login, id: .databaseId}')"
  if [ -n "$jq_filter" ]; then
    jq -r "$jq_filter" <<< "$viewer"
  else
    printf '%s\n' "$viewer"
  fi
  exit
fi

exec "$real_gh" "$@"
