# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       frontend-shell
# Module:          Makefile
# Owning Team:     Customer Experience Tribe (CXT)
# Classification:  INTERNAL
# Purpose:         Component Makefile called by the root Makefile
#                  (make test-shell, lint-shell, fmt-shell,
#                  doc-coverage-shell, api-docs-shell).
#                  Every target runs inside Docker; no Node.js is required
#                  on the host.
# Related Docs:    ADR-0002, ADR-0010, ADR-0018, frontend/shell/Dockerfile

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

COMPONENT := shell
IMAGE := aaas/frontend-$(COMPONENT)
DOCKER_BUILD := docker build --file Dockerfile

# Throw-away runtime container for the HTTP checks of `test` (unique per run).
TEST_NAME := frontend-shell-test-$(shell echo $$$$)

# Where `api-docs` exports the native API documentation; the root Makefile
# passes build/api-docs/shell of the repository (ADR-0010).
API_DOCS_DIR ?= $(CURDIR)/../../build/api-docs/$(COMPONENT)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: ## Build the runtime image as $(IMAGE):dev
	$(DOCKER_BUILD) --target runtime --tag $(IMAGE):dev .

.PHONY: test
test: build ## Unit tests in the `test` stage, then HTTP checks of the runtime image
	$(DOCKER_BUILD) --target test --tag $(IMAGE):test .
	@trap 'docker rm -f $(TEST_NAME) >/dev/null 2>&1' EXIT; \
	docker run -d --name $(TEST_NAME) $(IMAGE):dev >/dev/null; \
	for i in $$(seq 1 20); do docker exec $(TEST_NAME) wget -qO- http://127.0.0.1:8080/health >/dev/null 2>&1 && break; sleep 0.5; done; \
	check() { echo "    $$1"; shift; "$$@" >/dev/null || { echo "FAILED" >&2; exit 1; }; }; \
	echo "==> HTTP checks of the runtime image"; \
	check "GET / serves the page" sh -c "docker exec $(TEST_NAME) wget -qO- http://127.0.0.1:8080/ | grep -q 'id=\"keypad\"'"; \
	check "GET /main.js serves the module" sh -c "docker exec $(TEST_NAME) wget -qO- http://127.0.0.1:8080/main.js | grep -q createApp"; \
	check "GET /favicon.svg serves the icon" sh -c "docker exec $(TEST_NAME) wget -qO- http://127.0.0.1:8080/favicon.svg | grep -q '<svg'"; \
	check "Content-Security-Policy is set" sh -c "docker exec $(TEST_NAME) wget -qS -O /dev/null http://127.0.0.1:8080/ 2>&1 | grep -q \"Content-Security-Policy: default-src 'self'\""; \
	check "GET /health answers ok" sh -c "docker exec $(TEST_NAME) wget -qO- http://127.0.0.1:8080/health | grep -q '\"status\":\"ok\"'"; \
	check "GET /metrics exposes frontend_shell_up" sh -c "docker exec $(TEST_NAME) wget -qO- http://127.0.0.1:8080/metrics | grep -q '^frontend_shell_up 1'"; \
	check "/health is hidden from the gateway" sh -c "! docker exec $(TEST_NAME) wget -qO- --header 'X-Forwarded-For: 10.0.0.1' http://127.0.0.1:8080/health 2>/dev/null"; \
	check "unknown paths are 404" sh -c "! docker exec $(TEST_NAME) wget -qO- http://127.0.0.1:8080/nope 2>/dev/null"; \
	check "access log lines are JSON" sh -c "docker logs $(TEST_NAME) 2>/dev/null | grep -q '\"service\":\"frontend-shell\"'"; \
	check "runs as UID 101" sh -c "test \"\$$(docker exec $(TEST_NAME) id -u)\" = 101"; \
	echo "    all HTTP checks passed"

.PHONY: lint
lint: ## Run Prettier check and ESLint in the `lint` stage
	$(DOCKER_BUILD) --target lint --tag $(IMAGE):lint .

.PHONY: doc-coverage
doc-coverage: ## Run the documentation rules and the strict JSDoc parse in the `doc-coverage` stage
	$(DOCKER_BUILD) --target doc-coverage --tag $(IMAGE):doc-coverage .

.PHONY: api-docs
api-docs: ## Export the JSDoc HTML (index.html) to $(API_DOCS_DIR)
	$(DOCKER_BUILD) --target api-docs --output type=local,dest=$(API_DOCS_DIR) .

.PHONY: fmt
fmt: ## Format sources in place with Prettier using the toolchain stage
	$(DOCKER_BUILD) --target toolchain --tag $(IMAGE):toolchain .
	docker run --rm --volume "$(CURDIR)":/w --workdir /w --user "$$(id -u):$$(id -g)" --env HOME=/tmp \
		$(IMAGE):toolchain sh -c 'NODE_PATH=/src/node_modules /src/node_modules/.bin/prettier --write .'

.PHONY: run
run: build ## Serve the page alone on 127.0.0.1:8081 (the API needs the gateway: use make up)
	docker run --rm --publish 127.0.0.1:8081:8080 $(IMAGE):dev
