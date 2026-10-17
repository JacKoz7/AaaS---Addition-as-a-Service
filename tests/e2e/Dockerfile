# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       e2e
# Module:          tests/e2e/Dockerfile
# Owning Team:     Customer Experience Tribe (CXT)
# Classification:  INTERNAL
# Purpose:         Image of the end-to-end tests: Playwright's image with its
#                  browsers and the exact test packages of package-lock.json.
# Related Docs:    tests/e2e/README.md, scripts/e2e.sh, ADR-0019
#
# Run by scripts/e2e.sh on the `aaas-public` network, with /results mounted
# for the HTML report and the traces of failed tests. The image version must
# match the @playwright/test version of package.json (the browsers are built
# for it).

FROM mcr.microsoft.com/playwright:v1.64.1-noble

LABEL org.opencontainers.image.title="e2e" \
      org.opencontainers.image.description="AaaS end-to-end tests (Playwright)." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Customer Experience Tribe (CXT)"

WORKDIR /e2e
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY playwright.config.js ./
COPY lib/ lib/
COPY specs/ specs/

# The base image's unprivileged user; /results is writable by any user.
USER pwuser
ENTRYPOINT ["npx", "playwright", "test"]
