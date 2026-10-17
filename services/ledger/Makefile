# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          Makefile
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Component Makefile called by the root Makefile
#                  (make test-ledger, lint-ledger, fmt-ledger,
#                  doc-coverage-ledger, api-docs-ledger).
#                  Every target runs inside Docker; no Nim toolchain
#                  is required on the host. The test stage also receives
#                  contracts/ and scripts/ as the named build contexts
#                  `contracts` and `scripts`.
# Related Docs:    ADR-0002, ADR-0010, ADR-0017, services/ledger/Dockerfile

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

SERVICE := ledger
IMAGE := aaas/$(SERVICE)
DOCKER_BUILD := docker build --file Dockerfile \
	--build-context contracts=$(CURDIR)/../../contracts \
	--build-context scripts=$(CURDIR)/../../scripts

# Throw-away immudb for the store tests of `test` (unique per run), the
# image of compose/services.yml and the provisioning image and script.
TEST_NET := ledger-test-$(shell echo $$$$)
TEST_DB := ledger-test-db-$(shell echo $$$$)
IMMUDB_IMAGE := codenotary/immudb:1.11.2
CURL_IMAGE := curlimages/curl:8.17.0

# Where `api-docs` exports the native API documentation; the root Makefile
# passes build/api-docs/ledger of the repository (ADR-0010).
API_DOCS_DIR ?= $(CURDIR)/../../build/api-docs/$(SERVICE)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: ## Build the runtime image as $(IMAGE):dev
	$(DOCKER_BUILD) --target runtime --tag $(IMAGE):dev .

.PHONY: test
test: ## Unit tests and contract check in the `test` stage, then the store tests against a throw-away immudb
	$(DOCKER_BUILD) --target test --tag $(IMAGE):test .
	docker network create $(TEST_NET) >/dev/null
	@trap 'docker rm -f $(TEST_DB) >/dev/null 2>&1; docker network rm $(TEST_NET) >/dev/null 2>&1' EXIT; \
	docker run -d --name $(TEST_DB) --network $(TEST_NET) --env IMMUDB_DEVMODE=false \
		--env IMMUDB_PGSQL_SERVER=false --env IMMUDB_ADMIN_PASSWORD=test-admin $(IMMUDB_IMAGE) >/dev/null; \
	docker run --rm --network $(TEST_NET) --volume "$(CURDIR)/immudb/provision.sh":/provision.sh:ro \
		--env IMMUDB_URL=http://$(TEST_DB):8080 --env IMMUDB_ADMIN_PASSWORD=test-admin \
		--env LEDGER_DB_PASSWORD=test-ledger --entrypoint /bin/sh $(CURL_IMAGE) /provision.sh >/dev/null; \
	docker run --rm --network $(TEST_NET) --env IMMUDB_URL=http://$(TEST_DB):8080 \
		--env LEDGER_DB_PASSWORD=test-ledger --env MIGRATIONS_DIR=/src/migrations \
		$(IMAGE):test /out/test_store

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
		--env HOME=/tmp $(IMAGE):toolchain sh -c \
		'for f in src/ledger.nim src/ledger/*.nim tests/*.nim tools/*.nim config.nims; do nimpretty --indent:2 --maxLineLen:100 "$$f"; done'

.PHONY: run
run: build ## Run the image alone on 127.0.0.1:8080; without immudb it waits and /health fails (use make up)
	docker run --rm --publish 127.0.0.1:8080:8080 --env LEDGER_DB_PASSWORD=change-me $(IMAGE):dev
