# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.26.4
ARG COSMOVISOR_VERSION=v1.6.0
ARG RELEASE_IMAGE=kudora/kudorad:v0.1.0-rc.1

FROM golang:${GO_VERSION}-bookworm AS cosmovisor-builder

ARG COSMOVISOR_VERSION
ENV CGO_ENABLED=0
ENV GOFLAGS=-buildvcs=false

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@${COSMOVISOR_VERSION}

FROM ${RELEASE_IMAGE}

ARG COSMOVISOR_VERSION
ARG RELEASE_VERSION=v0.1.0-rc.1
ARG GIT_COMMIT=unknown

LABEL org.opencontainers.image.title="kudorad-cosmovisor" \
      org.opencontainers.image.description="Kudora candidate cosmovisor runtime" \
      org.opencontainers.image.version="${RELEASE_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      io.kudora.release_track="candidate" \
      io.kudora.mainnet_launch_ready="false" \
      io.kudora.cosmovisor_version="${COSMOVISOR_VERSION}"

COPY --from=cosmovisor-builder /go/bin/cosmovisor /usr/local/bin/cosmovisor

ENV DAEMON_NAME=kudorad \
    DAEMON_HOME=/home/nonroot/.kudora \
    DAEMON_RESTART_AFTER_UPGRADE=true \
    DAEMON_ALLOW_DOWNLOAD_BINARIES=false \
    UNSAFE_SKIP_BACKUP=false

WORKDIR /home/nonroot

EXPOSE 26656 26657 1317 9090 8545 8546

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/cosmovisor","run","start"]
