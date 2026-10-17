# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       frontend-shell
# Module:          Dockerfile
# Owning Team:     Customer Experience Tribe (CXT)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the temporary calculator page (plain
#                  JavaScript). Stages: toolchain, lint, test, doc-coverage,
#                  api-docs and the nginx runtime image used by Compose.
#                  TEMPORARY(P8.15): replaced by the single-spa shell.
# Related Docs:    frontend/shell/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0018
#
# Stage contract (used by frontend/shell/Makefile and the root Makefile):
#   toolchain — Node.js 24 LTS with the exact development packages of
#               package-lock.json (ESLint, eslint-plugin-jsdoc, Prettier,
#               JSDoc); the page itself has no runtime dependency.
#   lint      — Prettier check and ESLint (recommended and documentation
#               rules).
#   test      — node:test unit tests of the page logic.
#   doc-coverage — ESLint with the documentation rules only, and a strict
#               JSDoc parse of every type expression: 100% or the build fails.
#   api-docs  — JSDoc HTML with an index.html, exported by `make api-docs`.
#   runtime   — unprivileged nginx (UID 101) serving src/ on port 8080. No
#               build step: the browser loads the ES modules as written.

FROM node:24.22.0-alpine3.24 AS toolchain
WORKDIR /src
COPY package.json package-lock.json ./
# Exact versions from the lockfile; no install scripts are needed.
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY . .

FROM toolchain AS lint
RUN npm run -s lint

FROM toolchain AS test
RUN npm test

FROM toolchain AS doc-coverage
RUN npm run -s doc-coverage \
    && echo "doc-coverage: every definition documented with the fields of CLAUDE.md 6.5.3 (100%)"

FROM toolchain AS api-docs-build
RUN npm run -s api-docs

FROM scratch AS api-docs
COPY --from=api-docs-build /src/build/api-docs /

FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24 AS runtime

LABEL org.opencontainers.image.title="frontend-shell" \
      org.opencontainers.image.description="AaaS temporary calculator page (plain JavaScript): keypad and display." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Customer Experience Tribe (CXT)"

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY src/index.html src/style.css src/favicon.svg src/main.js src/app.js src/calculator.js src/api.js src/ids.js /usr/share/nginx/html/

# The base image runs nginx as the unprivileged user 101 (CLAUDE.md 6.2) and
# listens on 8080; BusyBox wget serves the Compose health check.
USER 101:101
EXPOSE 8080
