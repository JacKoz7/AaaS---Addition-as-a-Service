# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       expression-assembler
# Module:          Makefile
# Owning Team:     Customer Experience Tribe (CXT)
# Classification:  INTERNAL
# Purpose:         Component Makefile called by the root Makefile
#                  (make test-expression-assembler, lint-expression-assembler, fmt-expression-assembler,
#                  doc-coverage-expression-assembler, api-docs-expression-assembler).
#                  Every target runs inside Docker; no .NET SDK is
#                  required on the host. The test stage also receives
#                  contracts/ as the named build context `contracts`.
# Related Docs:    ADR-0002, ADR-0010, ADR-0014,
#                  services/expression-assembler/Dockerfile

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

SERVICE := expression-assembler
IMAGE := aaas/$(SERVICE)
DOCKER_BUILD := docker build --file Dockerfile --build-context contracts=$(CURDIR)/../../contracts

# Where `api-docs` exports the native API documentation; the root Makefile
# passes build/api-docs/expression-assembler of the repository (ADR-0010).
API_DOCS_DIR ?= $(CURDIR)/../../build/api-docs/$(SERVICE)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: ## Build the runtime image as $(IMAGE):dev
	$(DOCKER_BUILD) --target runtime --tag $(IMAGE):dev .

.PHONY: test
test: ## Run unit tests in the `test` stage
	$(DOCKER_BUILD) --target test --tag $(IMAGE):test .

.PHONY: lint
lint: ## Run formatter check and linter in the `lint` stage
	$(DOCKER_BUILD) --target lint --tag $(IMAGE):lint .

.PHONY: doc-coverage
doc-coverage: ## Run the native documentation coverage tool in the `doc-coverage` stage
	$(DOCKER_BUILD) --target doc-coverage --tag $(IMAGE):doc-coverage .

.PHONY: api-docs
api-docs: ## Export the native API documentation (HTML, index.html) to $(API_DOCS_DIR)
	$(DOCKER_BUILD) --target api-docs --output type=local,dest=$(API_DOCS_DIR) .

.PHONY: fmt
fmt: ## Format sources in place using the toolchain stage
	$(DOCKER_BUILD) --target toolchain --tag $(IMAGE):toolchain .
	docker run --rm --volume "$(CURDIR)":/src --workdir /src $(IMAGE):toolchain \
		dotnet format ExpressionAssembler.slnx

.PHONY: run
run: build ## Run the image alone on 127.0.0.1:8080; without SurrealDB it retries migrations for 30 s and exits 1 (use make up)
	docker run --rm --publish 127.0.0.1:8080:8080 --env AAAS_KAFKA_BROKERS=localhost:9092 \
		--env AAAS_DB_URL=http://localhost:8000 --env EXPRESSION_ASSEMBLER_DB_PASSWORD=change-me $(IMAGE):dev
