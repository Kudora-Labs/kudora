FROM node:22-alpine AS builder

ARG PING_DASHBOARD_REPO=https://github.com/ping-pub/explorer.git
ARG PING_DASHBOARD_COMMIT=f001c4f40256d883c67cfdefdbd5c70414de17c9

RUN apk add --no-cache git python3 make g++

WORKDIR /src

RUN git clone "${PING_DASHBOARD_REPO}" . \
  && git checkout "${PING_DASHBOARD_COMMIT}"

COPY deploy/explorers/ping-dashboard/config/kudora.json /src/chains/mainnet/kudora.json

RUN corepack enable \
  && yarn install --ignore-engines \
  && yarn build

FROM nginx:1.27-alpine

COPY --from=builder /src/dist /usr/share/nginx/html

EXPOSE 80
