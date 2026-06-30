# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.26.4
ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_TAGS=localnet,docker
ARG IMAGE_CREATED=unknown
ARG RELEASE_TRACK=localnet
ARG MAINNET_LAUNCH_READY=false
FROM golang:${GO_VERSION}-bookworm AS builder

WORKDIR /src

ENV CGO_ENABLED=1
ENV GOFLAGS=-buildvcs=false

ARG APP_VERSION
ARG GIT_COMMIT
ARG BUILD_TAGS

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath \
      -ldflags="-s -w \
        -X github.com/cosmos/cosmos-sdk/version.Name=kudora \
        -X github.com/cosmos/cosmos-sdk/version.AppName=kudorad \
        -X github.com/cosmos/cosmos-sdk/version.Version=${APP_VERSION} \
        -X github.com/cosmos/cosmos-sdk/version.Commit=${GIT_COMMIT} \
        -X github.com/cosmos/cosmos-sdk/version.BuildTags=${BUILD_TAGS}" \
      -o /out/kudorad ./cmd/kudorad

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath -ldflags="-s -w" -o /out/kudora-evm-smoke-helper ./testutil/evm-smoke

RUN --mount=type=cache,target=/go/pkg/mod \
    set -eu; \
    mod_cache="$(go env GOMODCACHE)"; \
    wasmvm_lib_aarch64="$(find "${mod_cache}" -path '*/github.com/!cosm!wasm/wasmvm/v3@*/internal/api/libwasmvm.aarch64.so' | head -n 1)"; \
    wasmvm_lib_x86_64="$(find "${mod_cache}" -path '*/github.com/!cosm!wasm/wasmvm/v3@*/internal/api/libwasmvm.x86_64.so' | head -n 1)"; \
    test -n "${wasmvm_lib_aarch64}"; \
    test -n "${wasmvm_lib_x86_64}"; \
    cp "${wasmvm_lib_aarch64}" /out/libwasmvm.aarch64.so; \
    cp "${wasmvm_lib_x86_64}" /out/libwasmvm.x86_64.so

FROM scratch AS release-binary

COPY --from=builder /out/ /out/

FROM gcr.io/distroless/cc-debian12:nonroot

ARG APP_VERSION
ARG GIT_COMMIT
ARG IMAGE_CREATED
ARG RELEASE_TRACK
ARG MAINNET_LAUNCH_READY

WORKDIR /home/nonroot

LABEL org.opencontainers.image.title="kudorad" \
      org.opencontainers.image.description="Kudora candidate runtime image" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.source="https://github.com/Kudora-Labs/kudora" \
      io.kudora.release_track="${RELEASE_TRACK}" \
      io.kudora.mainnet_launch_ready="${MAINNET_LAUNCH_READY}"

COPY --from=builder /out/kudorad /usr/local/bin/kudorad
COPY --from=builder /out/kudora-evm-smoke-helper /usr/local/bin/kudora-evm-smoke-helper
COPY --from=builder /out/libwasmvm.aarch64.so /usr/lib/libwasmvm.aarch64.so
COPY --from=builder /out/libwasmvm.x86_64.so /usr/lib/libwasmvm.x86_64.so

EXPOSE 26656 26657 1317 9090 8545 8546

USER nonroot:nonroot

ENTRYPOINT ["/usr/local/bin/kudorad"]
CMD ["version", "--long"]
