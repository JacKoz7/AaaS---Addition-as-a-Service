# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       parser
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the parser service (OCaml 4.14).
#                  Stages: toolchain (opam and pinned packages), lint, test,
#                  doc-coverage, api-docs, build and the minimal non-root
#                  runtime image used by Compose.
# Related Docs:    services/parser/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0015
#
# Stage contract (used by services/parser/Makefile and the root Makefile):
#   toolchain — OCaml 4.14 on Alpine with the opam packages of
#               aaas_parser.opam (exact versions) and the C libraries of the
#               bindings (librdkafka, SQLite, zlib).
#   lint      — ocamlformat check (dune build @fmt) and a build in which every
#               compiler warning is an error (the dune file at the root).
#   test      — Alcotest unit tests against contracts/ (named build context
#               `contracts`), then every event the tests published is
#               validated against its JSON Schema with
#               scripts/validate-events.py (named build context `scripts`).
#   doc-coverage — odoc build of the library with warnings as errors; the
#               presence of a doc comment on every definition is checked by
#               scripts/doc-check.sh (make doc-coverage), see ADR-0015.
#   api-docs  — odoc HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the release executable in /out.
#   runtime   — Alpine with the shared libraries of the bindings, non-root
#               user, port 8080 (the parser has no gRPC API).
#
# The base image is pinned to the OCaml 4.14 branch: the `kafka` bindings
# (0.5, the latest release) require OCaml < 5.0 (ADR-0015). Alpine 3.22 is
# used in every stage so that the runtime libraries match the ones linked.

FROM ocaml/opam:alpine-3.22-ocaml-4.14 AS toolchain
# The base image runs as `opam` (UID 1000); root (UID 0) only installs the
# Alpine packages. Numeric IDs, as hadolint DL3066 asks.
USER 0:0
# Development headers of the C libraries wrapped by the opam bindings; GMP is
# required by zarith, a build dependency of the documentation and formatting
# tools (odoc, ocamlformat), not linked into the service.
RUN apk add --no-cache librdkafka-dev=2.10.0-r0 sqlite-dev=3.49.2-r1 zlib-dev=1.3.2-r1 \
    gmp-dev=6.3.0-r3 linux-headers=6.14.2-r0 pkgconf=2.4.3-r0
USER 1000:1000
WORKDIR /home/opam/src
COPY --chown=opam:opam aaas_parser.opam ./
# The opam repository snapshot of the base image is used as is (no
# `opam update`); every package is pinned to an exact version.
RUN opam install --yes --deps-only --with-test --with-doc ./aaas_parser.opam
COPY --chown=opam:opam . .

FROM toolchain AS lint
RUN opam exec -- dune build @fmt \
    && opam exec -- dune build --profile release @check

FROM toolchain AS test
USER 0:0
RUN apk add --no-cache python3=3.12.15-r0 py3-jsonschema=4.23.0-r0 py3-referencing=0.36.2-r1
USER 1000:1000
# `contracts` and `scripts` are named build contexts (--build-context in the
# Makefile), not stages, which hadolint cannot know.
# hadolint ignore=DL3022
COPY --from=contracts events/ /home/opam/repo/contracts/events/
# hadolint ignore=DL3022
COPY --from=scripts validate-events.py /home/opam/repo/scripts/
ENV CONTRACTS_DIR=/home/opam/repo/contracts \
    MIGRATIONS_DIR=/home/opam/src/migrations \
    PRODUCED_DIR=/tmp/produced
RUN mkdir -p /tmp/produced \
    && opam exec -- dune test --force \
    && python3 /home/opam/repo/scripts/validate-events.py --events /tmp/produced/*.json

FROM toolchain AS doc-coverage
RUN opam exec -- dune build @doc-private \
    && echo "doc-coverage: odoc built without warnings; doc comments on every definition are checked by scripts/doc-check.sh"

FROM toolchain AS api-docs-build
# odoc writes the private library under a hashed directory and no page for
# the wrapper module (its own index.html links to a missing page), so the
# index is replaced by one that lists the module pages. dune makes build
# outputs read-only, hence the chmod.
RUN opam exec -- dune build @doc-private \
    && mkdir -p /tmp/api-docs \
    && cp -r _build/default/_doc/_html/. /tmp/api-docs/ \
    && chmod -R u+w /tmp/api-docs
WORKDIR /tmp/api-docs
RUN { echo '<!doctype html><html lang="en"><head><meta charset="utf-8">'; \
      echo '<title>parser API (aaas_parser)</title><link rel="stylesheet" href="odoc.support/odoc.css"></head>'; \
      echo '<body class="odoc"><main class="odoc-content"><h1>parser: library aaas_parser</h1><ul>'; \
      for page in aaas_parser@*/Aaas_parser/*/index.html; do \
        module="$(basename "$(dirname "$page")")"; \
        echo "<li><a href=\"${page}\">Aaas_parser.${module}</a></li>"; \
      done; \
      echo '</ul></main></body></html>'; } > index.html \
    && grep -q 'Aaas_parser.Grammar' index.html

FROM scratch AS api-docs
COPY --from=api-docs-build /tmp/api-docs /

FROM toolchain AS build
RUN opam exec -- dune build --profile release src/main/main.exe \
    && mkdir -p /home/opam/out \
    && cp _build/default/src/main/main.exe /home/opam/out/parser

FROM alpine:3.22.2 AS runtime

LABEL org.opencontainers.image.title="parser" \
      org.opencontainers.image.description="AaaS parser service (OCaml): turns the text expression into an AST." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# Shared libraries of the bindings, the same versions as in the toolchain.
# busybox wget (part of the base image) serves the Compose health check.
RUN apk add --no-cache librdkafka=2.10.0-r0 sqlite-libs=3.49.2-r1 \
    && mkdir -p /data \
    && chown 10001:10001 /data

WORKDIR /app
COPY --from=build /home/opam/out/parser /app/parser
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); a numeric UID needs no passwd entry. /data
# is owned by it, so a new Compose volume mounted there inherits the owner.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=parser \
    AAAS_HTTP_PORT=8080 \
    AAAS_DB_PATH=/data/parser.db \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/parser"]
