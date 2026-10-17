# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       successor
# Module:          Makefile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Component Makefile called by the root Makefile
#                  (make test-successor, lint-successor, fmt-successor,
#                  doc-coverage-successor, api-docs-successor).
#                  Every target runs inside Docker; no Haskell toolchain
#                  is required on the host. The test stage also receives
#                  contracts/ and scripts/ as the named build contexts
#                  `contracts` and `scripts`; `test` then runs the CouchDB
#                  specs against a throw-away successor-db container.
# Related Docs:    ADR-0002, ADR-0010, ADR-0016, services/successor/Dockerfile

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

SERVICE := successor
IMAGE := aaas/$(SERVICE)
DOCKER_BUILD := docker build --file Dockerfile \
	--build-context contracts=$(CURDIR)/../../contracts \
	--build-context scripts=$(CURDIR)/../../scripts

# Throw-away CouchDB for the integration specs of `test` (unique per run).
TEST_NET := successor-test-$(shell echo $$$$)
TEST_DB := successor-test-db-$(shell echo $$$$)

# Where `api-docs` exports the native API documentation; the root Makefile
# passes build/api-docs/successor of the repository (ADR-0010).
API_DOCS_DIR ?= $(CURDIR)/../../build/api-docs/$(SERVICE)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: ## Build the runtime image as $(IMAGE):dev
	$(DOCKER_BUILD) --target runtime --tag $(IMAGE):dev .

.PHONY: test
test: ## Unit tests, doctests and contract test in the `test` stage, then the CouchDB specs
	$(DOCKER_BUILD) --target test --tag $(IMAGE):test .
	docker build --quiet --tag $(IMAGE)-db:dev couchdb >/dev/null
	docker network create $(TEST_NET) >/dev/null
	@trap 'docker rm -f $(TEST_DB) >/dev/null 2>&1; docker network rm $(TEST_NET) >/dev/null 2>&1' EXIT; \
	docker run -d --name $(TEST_DB) --network $(TEST_NET) --env COUCHDB_USER=successor \
		--env COUCHDB_PASSWORD=change-me $(IMAGE)-db:dev >/dev/null; \
	for i in $$(seq 1 60); do \
		docker exec $(TEST_DB) curl -fs http://127.0.0.1:5984/_up >/dev/null 2>&1 && break; sleep 1; \
	done; \
	docker run --rm --network $(TEST_NET) --env COUCHDB_URL=http://$(TEST_DB):5984 \
		--env MIGRATIONS_DIR=/src/migrations $(IMAGE):test successor-spec --match CallLog

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
	docker run --rm --volume "$(CURDIR)":/src --workdir /src --user "$$(id -u):$$(id -g)" \
		$(IMAGE):toolchain sh -c 'find src app tests -name "*.hs" -exec ormolu --mode inplace {} +'


.PHONY: run
run: build ## Run the image alone on 127.0.0.1:8080; without CouchDB it retries for 60 s and exits 1 (use make up)
	docker run --rm --publish 127.0.0.1:8080:8080 --env SUCCESSOR_DB_PASSWORD=change-me $(IMAGE):dev
