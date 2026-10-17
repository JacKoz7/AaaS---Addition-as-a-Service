# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          Dockerfile
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the ledger service (Nim 2.2).
#                  Stages: toolchain, lint, test, doc-coverage, api-docs,
#                  build and the minimal non-root runtime image used by
#                  Compose.
# Related Docs:    services/ledger/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0017
#
# Stage contract (used by services/ledger/Makefile and the root Makefile):
#   toolchain — the official Nim image (full distribution: compiler,
#               nimpretty, the nim doc assets and dist/checksums) with the
#               librdkafka headers.
#   lint      — nimpretty check (every file formatted, no diff) and
#               `nim check` with every warning and every unused declaration
#               treated as a failure (styleCheck:error in config.nims).
#   test      — unit tests (tests/test_unit.nim) against contracts/ (named
#               build context `contracts`), then every event the tests
#               built is validated against its JSON Schema with
#               scripts/validate-events.py (named build context `scripts`).
#               The store tests need immudb and run in `make test`.
#   doc-coverage — `nim doc` of the whole project (runs every
#               runnableExamples block) and tools/doc_coverage.nim over the
#               `nim jsondoc --docInternal` output: 100% or the build fails.
#   api-docs  — `nim doc --project --docInternal` HTML with an index.html,
#               exported by `make api-docs` (ADR-0010).
#   build     — the release executable in /out.
#   runtime   — Debian slim with librdkafka, non-root user, port 8080 (the
#               ledger has no gRPC API).
#
# Debian bookworm in both the toolchain and the runtime: the official Nim
# image is built on it, and the runtime libraries must match the ones
# linked (librdkafka 2.0.2, as in the successor image, ADR-0016).

FROM nimlang/nim:2.2.12 AS toolchain
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update \
    && apt-get install -y --no-install-recommends librdkafka-dev=2.0.2-1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY . .

FROM toolchain AS lint
# nimpretty has no check mode: format a copy and compare it with the source.
RUN cp -r /src /tmp/formatted
WORKDIR /tmp/formatted
RUN for f in src/ledger.nim src/ledger/*.nim tests/*.nim tools/*.nim config.nims; do \
      nimpretty --indent:2 --maxLineLen:100 "$f"; \
    done \
    && diff -ru /src /tmp/formatted
WORKDIR /src
# Inherited from the toolchain stage; repeated for hadolint (DL4006).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# A warning or an unused declaration in the ledger's own code fails the
# stage; the standard library's own hints under /opt/nim are ignored.
RUN for f in src/ledger.nim tests/test_unit.nim tests/test_store.nim tools/doc_coverage.nim; do \
      nim check -d:lintHints --hint:all:off --hint:XDeclaredButNotUsed:on "$f" > /tmp/check.log 2>&1 \
        || { cat /tmp/check.log; exit 1; }; \
      if grep -E 'Warning:|XDeclaredButNotUsed' /tmp/check.log | grep -v '/opt/nim/'; then exit 1; fi; \
    done \
    && echo "lint: nimpretty clean, no compiler warnings, no unused declarations"

FROM toolchain AS test
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-venv=3.11.2-1+b1 \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /venv \
    && /venv/bin/pip install --no-cache-dir "jsonschema==4.26.0" "jsonschema-specifications==2025.9.1" \
       "referencing==0.37.0" "rpds-py==2026.9.1" "rfc3339-validator==0.1.4" "six==1.17.0" "attrs==25.4.0"
# `contracts` and `scripts` are named build contexts (--build-context in the
# Makefile), not stages, which hadolint cannot know.
# hadolint ignore=DL3022
COPY --from=contracts events/ /repo/contracts/events/
# hadolint ignore=DL3022
COPY --from=scripts validate-events.py /repo/scripts/
ENV CONTRACTS_DIR=/repo/contracts \
    PRODUCED_DIR=/tmp/produced
RUN mkdir -p /tmp/produced \
    && nim c -r --out:/tmp/test_unit tests/test_unit.nim \
    && nim c --out:/out/test_store tests/test_store.nim \
    && /venv/bin/python3 /repo/scripts/validate-events.py --events /tmp/produced/*.json

FROM toolchain AS doc-coverage
RUN nim doc --project --docInternal --outdir:/tmp/doc src/ledger.nim > /tmp/doc.log 2>&1 \
       || { cat /tmp/doc.log; exit 1; } \
    && for f in src/ledger.nim src/ledger/*.nim tools/doc_coverage.nim tests/*.nim; do \
         nim jsondoc --docInternal --outdir:"/tmp/json/$(dirname "$f")" "$f" > /tmp/json.log 2>&1 \
           || { cat /tmp/json.log; exit 1; }; \
       done \
    && nim c -r --out:/tmp/doc_coverage tools/doc_coverage.nim /tmp/json

FROM toolchain AS api-docs-build
RUN nim doc --project --docInternal --index:on --outdir:/api-docs src/ledger.nim > /tmp/doc.log 2>&1 \
       || { cat /tmp/doc.log; exit 1; } \
    && nim buildIndex -o:/api-docs/theindex.html /api-docs > /dev/null 2>&1 \
    && cp /api-docs/ledger.html /api-docs/index.html \
    && rm -f /api-docs/*.idx /api-docs/ledger/*.idx

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN nim c -d:release --opt:speed --out:/out/ledger src/ledger.nim

FROM debian:bookworm-20251020-slim AS runtime

LABEL org.opencontainers.image.title="ledger" \
      org.opencontainers.image.description="AaaS ledger service (Nim): immutable hash-chained record of every result." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Transaction Integrity Office (TIO)"

# Shared library of the executable; wget serves the Compose health check.
RUN apt-get update \
    && apt-get install -y --no-install-recommends librdkafka1=2.0.2-1 wget=1.21.3-1+deb12u1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /out/ledger /app/ledger
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); a numeric UID needs no passwd entry.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=ledger \
    AAAS_HTTP_PORT=8080 \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/ledger"]
