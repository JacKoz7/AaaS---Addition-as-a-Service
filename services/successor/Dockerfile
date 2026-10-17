# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       successor
# Module:          Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the successor service (Haskell, GHC
#                  9.10). Stages: toolchain (GHC, pinned dependencies and
#                  tools), lint, test, doc-coverage, api-docs, build and the
#                  minimal non-root runtime image used by Compose.
# Related Docs:    services/successor/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0016
#
# Stage contract (used by services/successor/Makefile and the root Makefile):
#   toolchain — GHC 9.10.3 and cabal on Debian bookworm, librdkafka, the
#               dependencies of cabal.project.freeze and the tools ormolu,
#               hlint and doctest at pinned versions.
#   lint      — ormolu in check mode, hlint, and a build with -Werror.
#   test      — the hspec suite (without CouchDB; the Makefile runs the
#               CouchDB specs against a throw-away container afterwards),
#               the doctests of every documentation example, and the JSON
#               Schema check of every event the tests published (contracts/
#               and scripts/ as named build contexts).
#   doc-coverage — Haddock with --ignore-all-exports, so that private
#               definitions count too; fails below 100% in any module.
#   api-docs  — Haddock HTML with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — the release executable in /out.
#   runtime   — Debian bookworm slim with librdkafka, non-root user, port
#               8080 (HTTP; gRPC arrives with P2.1).

FROM haskell:9.10.3-slim-bookworm AS toolchain
# Pipes in RUN instructions fail on any failing command (hadolint DL4006);
# the stages built from this one inherit the shell (repeated where hadolint
# needs to see it).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update \
    && apt-get install -y --no-install-recommends librdkafka-dev=2.0.2-1 pkg-config=1.8.1-1 \
       zlib1g-dev=1:1.2.13.dfsg-1 python3-venv=3.11.2-1+b1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# The Hackage index is resolved at the index-state of cabal.project; the
# tools are installed at the same index state and exact versions.
RUN cabal update "hackage.haskell.org,2026-10-15T00:00:00Z" \
    && cabal install --index-state=2026-10-15T00:00:00Z --installdir=/usr/local/bin \
       --install-method=copy ormolu-0.8.0.2 hlint-3.10 doctest-0.25.0.2
COPY successor.cabal cabal.project cabal.project.freeze ./
RUN cabal build --only-dependencies all
COPY . .

FROM toolchain AS lint
RUN find src app tests -name '*.hs' -exec ormolu --mode check {} + \
    && hlint src app tests \
    && cabal build all

FROM toolchain AS test
RUN python3 -m venv /venv \
    && /venv/bin/pip install --no-cache-dir "jsonschema==4.26.0" "jsonschema-specifications==2025.9.1" \
       "referencing==0.37.0" "rpds-py==2026.9.1" "rfc3339-validator==0.1.4" "six==1.17.0" "attrs==25.4.0"
# `contracts` and `scripts` are named build contexts (--build-context in the
# Makefile), not stages, which hadolint cannot know.
# hadolint ignore=DL3022
COPY --from=contracts events/ /repo/contracts/events/
# hadolint ignore=DL3022
COPY --from=scripts validate-events.py /repo/scripts/
ENV PRODUCED_DIR=/tmp/produced \
    MIGRATIONS_DIR=/src/migrations
RUN cabal test --test-show-details=direct \
    && cabal repl --with-compiler=doctest --repl-options=-Wno-missing-export-lists successor \
    && /venv/bin/python /repo/scripts/validate-events.py --events /tmp/produced/*.json \
    && cp "$(cabal list-bin spec)" /usr/local/bin/successor-spec

FROM toolchain AS doc-coverage
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Haddock prints one "NN% ( x / y) in 'Module'" line per module; every one
# must be 100%.
RUN cabal haddock --haddock-all --haddock-options=--ignore-all-exports 2>&1 | tee /tmp/haddock.log \
    && grep -E "^ *[0-9]+% " /tmp/haddock.log \
    && ! grep -E "^ *[0-9]+% " /tmp/haddock.log | grep -v "^ *100% " \
    && echo "doc-coverage: 100% (Haddock, private definitions included)"

FROM toolchain AS api-docs-build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN cabal haddock --haddock-all --haddock-hyperlink-source --haddock-options=--ignore-all-exports \
    && mkdir -p /api-docs \
    && cp -r "$(dirname "$(find dist-newstyle -path '*doc/html/successor/index.html' -print -quit)")"/. /api-docs/ \
    && test -f /api-docs/index.html

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN mkdir -p /out \
    && cabal install exe:successor --installdir=/out --install-method=copy

FROM debian:bookworm-20251020-slim AS runtime

LABEL org.opencontainers.image.title="successor" \
      org.opencontainers.image.description="AaaS successor service (Haskell): computes n+1 through the digit services and carry." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

# Shared libraries of the executable; wget serves the Compose health check.
RUN apt-get update \
    && apt-get install -y --no-install-recommends librdkafka1=2.0.2-1 libgmp10=2:6.2.1+dfsg1-1.1 \
       libffi8=3.4.4-1 wget=1.21.3-1+deb12u1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /out/successor /app/successor
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); a numeric UID needs no passwd entry.
USER 10001:10001

EXPOSE 8080
ENV AAAS_SERVICE=successor \
    AAAS_HTTP_PORT=8080 \
    AAAS_MIGRATIONS_DIR=/app/migrations

ENTRYPOINT ["/app/successor"]
