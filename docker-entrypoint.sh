#!/bin/sh
set -eu

# A fresh named volume is seeded from the image, but a bind mount or a volume
# created by an older image starts without Claude Code.
if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code not found in $HOME; installing it..."
  curl -fsSL https://claude.ai/install.sh | bash -s stable \
    || echo "warning: Claude Code install failed; install it from a terminal in this container" >&2
fi

# Commits default to the app's bot account unless an identity is already set.
if [ -n "${GITHUB_APP_ID:-}" ]; then
  if viewer="$(gh api graphql -f 'query={viewer{login databaseId}}' \
    --jq '.data.viewer | "\(.login) \(.databaseId)"' 2>&1)"; then
    login="${viewer% *}"
    id="${viewer##* }"
    echo "GitHub: signed in as $login"
    if ! git config --global user.email >/dev/null 2>&1; then
      git config --global user.name "$login"
      git config --global user.email "$id+$login@users.noreply.github.com"
    fi
  else
    echo "warning: GitHub App sign-in failed: $viewer" >&2
  fi
fi

exec "$@"
