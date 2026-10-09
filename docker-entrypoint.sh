#!/bin/sh
set -eu

# A fresh named volume is seeded from the image, but a bind mount or a volume
# created by an older image starts without Claude Code.
if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code not found in $HOME; installing it..."
  curl -fsSL https://claude.ai/install.sh | bash -s stable \
    || echo "warning: Claude Code install failed; install it from a terminal in this container" >&2
fi

exec "$@"
