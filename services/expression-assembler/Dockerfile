# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       expression-assembler
# Module:          Dockerfile
# Owning Team:     Customer Experience Tribe (CXT)
# Classification:  INTERNAL
# Purpose:         Multi-stage build of the expression-assembler service (C#,
#                  .NET 10). Stages: toolchain (SDK and restored packages),
#                  lint, test, doc-coverage, api-docs, build and the minimal
#                  non-root runtime image used by Compose.
# Related Docs:    services/expression-assembler/README.md, CLAUDE.md (section 6.2),
#                  ADR-0002, ADR-0004, ADR-0014
#
# Stage contract (used by services/expression-assembler/Makefile and the root Makefile):
#   toolchain — .NET SDK with the NuGet packages of both projects restored.
#   lint      — dotnet format in check mode, then a Release build in which
#               every analyzer warning (StyleCop, .NET analyzers) is an error.
#   test      — xUnit tests, including contract tests against contracts/
#               (named build context `contracts`) and storage tests against a
#               real SurrealDB binary copied from the database image.
#   doc-coverage — Release build with CS1591 and StyleCop SA1600-SA1602 as
#               errors for every element, private ones included (CLAUDE.md 6.5.4).
#   api-docs  — DocFX site with an index.html at the root, exported by
#               `make api-docs` and published in the portal (ADR-0010).
#   build     — framework-dependent, portable publish into /out.
#   runtime   — ASP.NET Core runtime on Alpine (busybox wget for the Compose
#               health check, cyrus-sasl for librdkafka), non-root user,
#               port 8080.
#
# The SDK stage is glibc-based (Ubuntu Noble) so that the SurrealDB binary of
# the test stage runs; the published output is portable (no RID, no app
# host), so it runs unchanged on the musl-based runtime image, where
# Confluent.Kafka loads the Alpine build of librdkafka shipped in the package.

FROM mcr.microsoft.com/dotnet/sdk:10.0.402-noble AS toolchain
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
WORKDIR /src
COPY Directory.Build.props stylecop.json .editorconfig global.json ExpressionAssembler.slnx ./
COPY src/ExpressionAssembler/ExpressionAssembler.csproj src/ExpressionAssembler/
COPY tests/ExpressionAssembler.Tests/ExpressionAssembler.Tests.csproj tests/ExpressionAssembler.Tests/
RUN dotnet restore ExpressionAssembler.slnx
COPY . .

FROM toolchain AS lint
RUN dotnet format ExpressionAssembler.slnx --verify-no-changes --no-restore \
    && dotnet build ExpressionAssembler.slnx --configuration Release --no-restore

FROM toolchain AS test
COPY --from=surrealdb/surrealdb:v3.3.4 /surreal /usr/local/bin/surreal
# `contracts` is a named build context (--build-context in the Makefile), not
# a stage, which hadolint cannot know.
# hadolint ignore=DL3022
COPY --from=contracts events/ /contracts/events/
ENV SURREAL_BIN=/usr/local/bin/surreal \
    CONTRACTS_DIR=/contracts \
    MIGRATIONS_DIR=/src/migrations
RUN dotnet test ExpressionAssembler.slnx --configuration Release --no-restore

FROM toolchain AS doc-coverage
RUN dotnet build ExpressionAssembler.slnx --configuration Release --no-restore \
    && echo "doc-coverage: 100% (CS1591 and StyleCop SA1600-SA1602 as errors, private elements included)"

FROM toolchain AS api-docs-build
RUN dotnet tool install --tool-path /tools docfx --version 2.81.0
RUN /tools/docfx metadata docfx.json --warningsAsErrors \
    && /tools/docfx build docfx.json --output /api-docs --warningsAsErrors \
    && test -f /api-docs/index.html

FROM scratch AS api-docs
COPY --from=api-docs-build /api-docs /

FROM toolchain AS build
RUN dotnet publish src/ExpressionAssembler/ExpressionAssembler.csproj --configuration Release --no-restore \
    --output /out -p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0.13-alpine3.24 AS runtime

LABEL org.opencontainers.image.title="expression-assembler" \
      org.opencontainers.image.description="AaaS expression-assembler service (C#): turns key presses into an expression and starts a task." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Customer Experience Tribe (CXT)"

# The Alpine build of librdkafka shipped in librdkafka.redist links
# libsasl2 dynamically; the package is pinned to the Alpine 3.24 release.
RUN apk add --no-cache cyrus-sasl=2.1.28-r9

WORKDIR /app
COPY --from=build /out/ /app/
COPY migrations/ /app/migrations/

# Non-root user (CLAUDE.md 6.2); a numeric UID needs no passwd entry.
USER 10001:10001

EXPOSE 8080
# ASPNETCORE_HTTP_PORTS of the base image is cleared: Kestrel listens on
# AAAS_HTTP_PORT, configured in code. The GC heap is capped at 0x46 = 70%
# of the container memory limit (the value is hexadecimal).
ENV AAAS_SERVICE=expression-assembler \
    AAAS_HTTP_PORT=8080 \
    ASPNETCORE_HTTP_PORTS= \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_gcServer=0 \
    DOTNET_GCHeapHardLimitPercent=0x46

ENTRYPOINT ["dotnet", "/app/expression-assembler.dll"]
