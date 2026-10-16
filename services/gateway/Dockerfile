# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       gateway
# Module:          Dockerfile
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the gateway service (Traefik with the
#                  local Go plugin `edge`). Stages: toolchain (Go and the
#                  documentation tools), lint, test, doc-coverage, api-docs
#                  and the non-root Traefik runtime image used by Compose.
# Related Docs:    services/gateway/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0012
#
# Stage contract (used by services/gateway/Makefile and the root Makefile):
#   toolchain    — Go toolchain, revive, godoclint and doc2go, the Traefik
#                  binary, the configuration at /etc/traefik and the plugin
#                  at /plugins-local/src/aaas/edge (where Traefik loads it).
#   lint         — gofmt check and go vet of the plugin and the tests.
#   test         — unit tests of the plugin and integration tests that run
#                  the real Traefik binary with the real configuration
#                  against stub upstreams.
#   doc-coverage — revive `exported` and godoclint `require-doc` including
#                  unexported symbols and tests (CLAUDE.md 6.5.4).
#   api-docs     — HTML documentation of the plugin (doc2go) and the
#                  configuration files, with an index.html (ADR-0010).
#   build        — the artifact: configuration and plugin source (the
#                  plugin is interpreted by Traefik, nothing is compiled).
#   runtime      — traefik image, non-root user, ports 8000 (public entry
#                  point, host port 80) and 8080 (health, metrics).
#
# The gateway has no gRPC interface; port 9090 of the template is not used.

FROM traefik:v3.7.14 AS traefik

FROM golang:1.27.2-alpine3.24 AS toolchain
# Pinned tool versions; `go install` fetches them from the Go module proxy.
ARG REVIVE_VERSION=v1.17.1
ARG GODOCLINT_VERSION=v0.11.4
ARG DOC2GO_VERSION=v0.12.2
# godoclint pins golang.org/x/tools v0.49.0, which cannot read the export
# data of Go 1.27; it is built in a throwaway module with a newer x/tools.
ARG XTOOLS_VERSION=v0.52.0
RUN go install "github.com/mgechev/revive@${REVIVE_VERSION}" \
 && go install "go.abhg.dev/doc2go@${DOC2GO_VERSION}" \
 && mkdir /tmp/godoclint && go -C /tmp/godoclint mod init tools \
 && go -C /tmp/godoclint get "github.com/godoc-lint/godoc-lint/cmd/godoclint@${GODOCLINT_VERSION}" "golang.org/x/tools@${XTOOLS_VERSION}" \
 && go -C /tmp/godoclint build -o /go/bin/godoclint github.com/godoc-lint/godoc-lint/cmd/godoclint \
 && rm -rf /tmp/godoclint
COPY --from=traefik /usr/local/bin/traefik /usr/local/bin/traefik
WORKDIR /src
COPY . .
RUN mkdir -p /plugins-local/src/aaas \
 && cp -r src/edge /plugins-local/src/aaas/edge \
 && cp -r config /etc/traefik

FROM toolchain AS lint
RUN unformatted="$(gofmt -l src tests)" \
 && if [ -n "$unformatted" ]; then echo "gofmt: not formatted:" "$unformatted" >&2; exit 1; fi \
 && go -C src/edge vet ./... \
 && go -C tests vet ./...

FROM toolchain AS test
ENV TRAEFIK_BIN=/usr/local/bin/traefik
RUN go -C src/edge build ./... \
 && go -C tests test -count=1 -v ./...

FROM toolchain AS doc-coverage
RUN revive -config revive.toml -set_exit_status ./src/edge/... ./tests/...
WORKDIR /src/src/edge
RUN godoclint -config /src/.godoc-lint.yaml ./...
WORKDIR /src/tests
RUN godoclint -config /src/.godoc-lint.yaml ./... \
 && echo "doc-coverage: 100% (revive exported, godoclint require-doc incl. unexported and tests)"

FROM toolchain AS api-docs-build
RUN mkdir -p /api-docs/edge /api-docs/config \
 && cp config/traefik.yml config/dynamic/routes.yml /api-docs/config/ \
 && cp api-docs.html /api-docs/index.html
WORKDIR /src/src/edge
RUN doc2go -out /api-docs/edge -home aaas/edge ./...

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN mkdir -p /out/etc /out/plugins-local/src/aaas/edge \
 && cp -r config /out/etc/traefik \
 && cp src/edge/go.mod src/edge/.traefik.yml src/edge/*.go /out/plugins-local/src/aaas/edge/

FROM traefik:v3.7.14 AS runtime

LABEL org.opencontainers.image.title="gateway" \
      org.opencontainers.image.description="AaaS gateway service (Traefik): Single entry point, routing and forwardAuth middleware." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Platform Enablement Guild (PEG)"

# Traefik reads /etc/traefik/traefik.yml by default and loads local plugins
# from ./plugins-local relative to its working directory (/).
COPY --from=build /out/etc/traefik /etc/traefik
COPY --from=build /out/plugins-local /plugins-local

# Non-root user (CLAUDE.md 6.2); the public entry point therefore listens
# on the unprivileged port 8000. The image contains busybox `wget` for the
# Compose health check.
USER 10001:10001

EXPOSE 8000 8080
ENV AAAS_SERVICE=gateway \
    AAAS_HTTP_PORT=8080
