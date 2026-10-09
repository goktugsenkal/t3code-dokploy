# syntax=docker/dockerfile:1.7
#
# T3 Code server, packaged from upstream's official self-contained release
# archive. Nothing here patches or rebuilds the app.

FROM debian:trixie-slim

ARG T3_VERSION
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git git-lfs jq less libatomic1 openssh-client procps tini unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI from GitHub's own apt repository; Debian's package is older than
# the 2.81.0 T3 Code needs for its GitHub features.
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# The archive's native modules are glibc builds, which is why this is Debian
# and not Alpine. It lives outside the T3 home so the in-app updater treats it
# as a plain copy and never writes into the data volume.
RUN set -eu; \
    test -n "${T3_VERSION}" || { echo "T3_VERSION build arg is required" >&2; exit 1; }; \
    case "${TARGETARCH}" in \
      amd64) arch=x64 ;; \
      arm64) arch=arm64 ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    archive="t3-${T3_VERSION}-linux-${arch}.tar.gz"; \
    base="https://github.com/pingdotgg/t3code/releases/download/v${T3_VERSION}"; \
    cd /tmp; \
    curl -fsSLO "${base}/${archive}"; \
    curl -fsSL "${base}/SHA256SUMS" | grep " ${archive}\$" | sha256sum -c -; \
    mkdir -p /opt/t3; \
    tar -xzf "${archive}" -C /opt/t3 --strip-components=1; \
    rm "${archive}"; \
    ln -s /opt/t3/t3 /usr/local/bin/t3

RUN useradd --create-home --shell /bin/bash --uid 1000 t3 \
 && mkdir -p /workspace \
 && chown t3:t3 /workspace

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Claude Code refuses to skip permission prompts as root, so everything runs as
# an ordinary user whose home is the persistent volume.
USER t3
WORKDIR /home/t3
ENV HOME=/home/t3 \
    PATH=/home/t3/.local/bin:${PATH} \
    T3CODE_HOME=/home/t3/.t3

# Installed into the home so it is seeded into a fresh named volume and can
# update itself there, like on a normal machine.
RUN curl -fsSL https://claude.ai/install.sh | bash -s stable \
 && claude --version

WORKDIR /workspace
EXPOSE 3773

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3773/.well-known/t3/environment >/dev/null || exit 1

LABEL org.opencontainers.image.title="T3 Code" \
      org.opencontainers.image.description="T3 Code server from upstream's official release archive" \
      org.opencontainers.image.version="${T3_VERSION}" \
      org.opencontainers.image.licenses="MIT"

ENTRYPOINT ["tini", "--", "docker-entrypoint.sh"]
CMD ["t3", "serve", "--host", "0.0.0.0", "--port", "3773"]
