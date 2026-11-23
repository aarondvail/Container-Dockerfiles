# Bitfocus Companion — headless, built from an upstream release tag.
#
#   docker build --build-arg COMPANION_VERSION=v5.1.3 -t companion:v5.1.3 .
#
# Mirrors upstream's own Dockerfile (bitfocus/companion/Dockerfile) but pulls the
# source itself, so this folder is self-contained for the Container-Dockerfiles repo
# and Jenkins only has to pass the tag. Reuses upstream's docker-entrypoint.sh.

ARG COMPANION_VERSION=v5.1.3

########## build stage ##########
FROM node:26-trixie AS builder
ARG COMPANION_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        git libusb-1.0-0-dev libudev-dev \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g corepack

# .git is needed: the build stamps its version from git metadata.
RUN git clone --depth 1 --branch "${COMPANION_VERSION}" \
        https://github.com/bitfocus/companion.git /app
WORKDIR /app

# Detached-HEAD builds read the ref from here; matching the tag marks the build "stable".
ENV GITHUB_REF_NAME=${COMPANION_VERSION}

RUN corepack enable \
    && yarn config set httpTimeout 100000 \
    && yarn install --immutable \
    && yarn build:writefile \
    && ELECTRON=0 yarn dist

# Package corepack/yarn for the runtime image (tar keeps the symlinks).
RUN tar -czf /tmp/corepack.tar.gz -C / \
        usr/local/lib/node_modules/corepack \
        usr/local/bin/corepack usr/local/bin/yarn usr/local/bin/yarnpkg

########## runtime stage ##########
FROM debian:trixie-slim
ARG COMPANION_VERSION
ARG UID=1000
ARG GID=1000

LABEL org.opencontainers.image.title="Bitfocus Companion" \
      org.opencontainers.image.source="https://github.com/bitfocus/companion" \
      org.opencontainers.image.version="${COMPANION_VERSION}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates procps curl jq tzdata \
        libusb-1.0-0 libudev1 iputils-ping libcap2-bin \
        libasound2 libfontconfig1 libatomic1 \
    && rm -rf /var/lib/apt/lists/* \
    # generic-ping module needs raw sockets as non-root (upstream #4365)
    && setcap cap_net_raw+ep /usr/bin/ping

WORKDIR /app
COPY --from=builder /app/dist/ /app/
COPY --from=builder --chmod=755 /app/docker-entrypoint.sh /docker-entrypoint.sh
RUN --mount=type=bind,from=builder,source=/tmp/corepack.tar.gz,target=/tmp/corepack.tar.gz \
    tar -xzf /tmp/corepack.tar.gz -C /

ENV PATH="$PATH:/app/node-runtimes/main/bin" \
    COMPANION_CONFIG_BASEDIR=/companion \
    COMPANION_ADMIN_PORT=8000

# Fixed UID/GID so bind mounts under /opt/port line up with -u 1000:1000.
RUN groupadd -g ${GID} companion \
    && useradd -m -s /bin/bash -u ${UID} -g ${GID} companion \
    && mkdir -p /companion /app/module-local-dev \
    && chown -R companion:companion /companion /app/module-local-dev

USER companion

# 8000 admin UI/API, 16622 Satellite TCP, 16623 Satellite WS.
# Modules open their own listeners too (OSC, TCP/UDP, Ember+ ...) — run with --network=host.
EXPOSE 8000 16622 16623
VOLUME ["/companion"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD ["sh", "-c", "curl -fsS -o /dev/null http://localhost:${COMPANION_ADMIN_PORT:-8000}/"]

ENTRYPOINT ["/docker-entrypoint.sh"]
