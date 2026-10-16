# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          infra/docs-portal/Dockerfile
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Tool image of the documentation portal: MkDocs Material,
#                  which builds and serves the portal, plus interrogate for
#                  the documentation coverage of the portal generator
#                  (scripts/docs-portal.py).
# Related Docs:    ADR-0010, mkdocs.yml, scripts/docs-portal.py, Makefile
#                  (targets docs, docs-serve, doc-coverage-repo)
#
# The image is a developer tool, not a runtime service: it is built and run by
# `make docs`, never by Compose. The repository is mounted at /docs and the
# container runs with the caller's UID so that generated files are not owned
# by root. The base image is multi-arch (linux/amd64, linux/arm64).

FROM squidfunk/mkdocs-material:9.7.7

LABEL org.opencontainers.image.title="docs-portal" \
      org.opencontainers.image.description="AaaS documentation portal toolchain: MkDocs Material, interrogate" \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Platform Enablement Guild (PEG)"

# interrogate: docstring coverage of Python (CLAUDE.md 6.5.4). Linting and
# formatting of Python (ruff) run as pre-commit hooks instead.
RUN pip install --no-cache-dir "interrogate==1.7.0"

# Material 9.7 prints a banner about the incompatible MkDocs 2.0 on every run.
# The image pins MkDocs 1.6.1, so the banner is noise here; the risk itself is
# tracked in docs/governance/RISK_REGISTER.md (R-009) and ADR-0010.
ENV NO_MKDOCS_2_WARNING=1

# The upstream entrypoint is `mkdocs`; the Makefile overrides it for the
# generator and the checks.
WORKDIR /docs
