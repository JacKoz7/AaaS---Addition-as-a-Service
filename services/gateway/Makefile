# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       gateway
# Module:          Makefile
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Component Makefile called by the root Makefile
#                  (make test-gateway, lint-gateway, fmt-gateway,
#                  doc-coverage-gateway, api-docs-gateway).
#                  Every target runs inside Docker; neither Go nor Traefik
#                  is required on the host.
# Related Docs:    ADR-0002, ADR-0010, ADR-0012, services/gateway/Dockerfile

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

SERVICE := gateway
IMAGE := aaas/$(SERVICE)
DOCKER_BUILD := docker build --file Dockerfile

# Where `api-docs` exports the native API documentation; the root Makefile
# passes build/api-docs/gateway of the repository (ADR-0010).
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
		gofmt -w src tests

.PHONY: run
run: build ## Run the image alone on 127.0.0.1:8000 (public) and :8080 (health); upstreams are unreachable
	docker run --rm --publish 127.0.0.1:8000:8000 --publish 127.0.0.1:8080:8080 $(IMAGE):dev
