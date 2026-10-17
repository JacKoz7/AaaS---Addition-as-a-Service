# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       parser
# Module:          Makefile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Component Makefile called by the root Makefile
#                  (make test-parser, lint-parser, fmt-parser,
#                  doc-coverage-parser, api-docs-parser).
#                  Every target runs inside Docker; no OCaml toolchain
#                  is required on the host. The test stage also receives
#                  contracts/ and scripts/ as the named build contexts
#                  `contracts` and `scripts`.
# Related Docs:    ADR-0002, ADR-0010, ADR-0015, services/parser/Dockerfile

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

SERVICE := parser
IMAGE := aaas/$(SERVICE)
DOCKER_BUILD := docker build --file Dockerfile \
	--build-context contracts=$(CURDIR)/../../contracts \
	--build-context scripts=$(CURDIR)/../../scripts

# Where `api-docs` exports the native API documentation; the root Makefile
# passes build/api-docs/parser of the repository (ADR-0010).
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
	docker run --rm --volume "$(CURDIR)":/home/opam/src --workdir /home/opam/src \
		--user "$$(id -u):$$(id -g)" --env HOME=/tmp --env PATH=/home/opam/.opam/4.14/bin:/usr/bin:/bin \
		--entrypoint sh $(IMAGE):toolchain -c 'dune fmt --root . --build-dir /tmp/_build; dune build @fmt --root . --build-dir /tmp/_build'

.PHONY: run
run: build ## Run the image alone on 127.0.0.1:8080 with a throw-away database; without a broker it waits 60 s and exits 1 (use make up)
	docker run --rm --publish 127.0.0.1:8080:8080 --env AAAS_KAFKA_BROKERS=host.docker.internal:9092 \
		--tmpfs /data:uid=10001 $(IMAGE):dev
