# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          Makefile
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Single entry point for building, running, testing and
#                  inspecting the AaaS system on a developer workstation.
# Related Docs:    CLAUDE.md (sections 6.2, 6.4, 8.1, 9.3), ADR-0002,
#                  docs/PROGRESS.md
#
# Conventions:
#   - `make <verb>` acts on the whole system; `make <verb>-<name>` acts on one
#     service (services/<name>) or microfrontend (frontend/<name>).
#   - build-<name> goes through Docker Compose so that the image is the one
#     Compose runs. test-<name>, lint-<name> and fmt-<name> delegate to the
#     Makefile inside the component directory (see ADR-0002).
#   - Targets that depend on files delivered by a later step fail with a
#     message naming that step instead of a cryptic error.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

# ---------------------------------------------------------------------------
# Configuration (override on the command line: make up PROFILES=core)
# ---------------------------------------------------------------------------

# Compose profiles started by `make up`. `aws-local` is deliberately excluded
# (CLAUDE.md 6.2); start it with `make up PROFILES=aws-local`.
PROFILES ?= core,services,frontend,observability

# Docker Compose invocation. The compose file is delivered by step P0.3.
COMPOSE_FILE ?= docker-compose.yml
COMPOSE := COMPOSE_PROFILES=$(PROFILES) docker compose -f $(COMPOSE_FILE)

# Files delivered by later steps, with the step that delivers them.
NEW_SERVICE_SCRIPT := scripts/new-service.sh
E2E_SCRIPT := scripts/e2e.sh
PROGRESS_FILE := docs/PROGRESS.md

# Component directories: every services/<name> and frontend/<name> that has a
# Makefile takes part in `make test`, `make lint` and `make fmt`.
SERVICE_DIRS := $(sort $(dir $(wildcard services/*/Makefile)))
FRONTEND_DIRS := $(sort $(dir $(wildcard frontend/*/Makefile)))
COMPONENT_DIRS := $(SERVICE_DIRS) $(FRONTEND_DIRS)
COMPONENT_NAMES := $(notdir $(patsubst %/,%,$(COMPONENT_DIRS)))

# Number of lines of `docker compose logs` shown by `make logs`.
TAIL ?= 100

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# require_file <path> <step>: fail with a clear message if <path> is missing.
define require_file
	@if [ ! -e "$(1)" ]; then \
		echo "error: $(1) does not exist yet; it is delivered by step $(2) (see docs/PROGRESS.md)." >&2; \
		exit 1; \
	fi
endef

# component_dir <name>: directory of a service or microfrontend, or empty.
component_dir = $(firstword $(wildcard services/$(1)/Makefile frontend/$(1)/Makefile))

# delegate <name> <target>: run <target> in the component's own Makefile.
define delegate
	@dir="$(call component_dir,$(1))"; \
	if [ -z "$$dir" ]; then \
		echo "error: no services/$(1)/Makefile or frontend/$(1)/Makefile found." >&2; \
		echo "       known components: $(if $(COMPONENT_NAMES),$(COMPONENT_NAMES),none yet)" >&2; \
		exit 1; \
	fi; \
	echo "==> $(2) $(1)"; \
	$(MAKE) -C "$$(dirname "$$dir")" $(2)
endef

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

.PHONY: help
help: ## Show this help
	@echo "AaaS — Addition as a Service"
	@echo
	@echo "Usage: make <target> [PROFILES=core,...] [SVC=<name>] [NAME=<name> LANG=<language>]"
	@echo
	@grep -hE '^[a-zA-Z0-9_%-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Running the system
# ---------------------------------------------------------------------------

.PHONY: up
up: ## Start all profiles except aws-local and wait for healthchecks
	$(call require_file,$(COMPOSE_FILE),P0.3)
	@if [ -z "$$($(COMPOSE) config --services)" ]; then \
		echo "no services defined for profiles '$(PROFILES)' yet; nothing to start."; \
	else \
		$(COMPOSE) up --detach --build --remove-orphans --wait; \
	fi

.PHONY: down
down: ## Stop and remove containers (volumes are kept)
	$(call require_file,$(COMPOSE_FILE),P0.3)
	$(COMPOSE) down --remove-orphans

.PHONY: ps
ps: ## Show container state
	$(call require_file,$(COMPOSE_FILE),P0.3)
	$(COMPOSE) ps --all

.PHONY: logs
logs: ## Follow logs (all containers, or SVC=<name>)
	$(call require_file,$(COMPOSE_FILE),P0.3)
	$(COMPOSE) logs --follow --tail=$(TAIL) $(SVC)

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

.PHONY: build
build: ## Build all images
	$(call require_file,$(COMPOSE_FILE),P0.3)
	$(COMPOSE) build

.PHONY: build-%
build-%: ## Build one image (make build-successor)
	$(call require_file,$(COMPOSE_FILE),P0.3)
	$(COMPOSE) build $*

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------

.PHONY: test
test: ## Run unit tests of every component
	@if [ -z "$(COMPONENT_NAMES)" ]; then echo "no components with a Makefile yet; nothing to test."; fi
	@for name in $(COMPONENT_NAMES); do $(MAKE) test-$$name; done

.PHONY: test-%
test-%: ## Run unit tests of one component (make test-successor)
	$(call delegate,$*,test)

.PHONY: e2e
e2e: ## Run end-to-end tests through the gateway
	$(call require_file,$(E2E_SCRIPT),P1.9)
	$(E2E_SCRIPT)

# ---------------------------------------------------------------------------
# Code quality
# ---------------------------------------------------------------------------

.PHONY: lint
lint: lint-repo lint-scaffold ## Run every linter (repository-level and per component)
	@for name in $(COMPONENT_NAMES); do $(MAKE) lint-$$name; done
	@$(MAKE) temporary

.PHONY: lint-scaffold
lint-scaffold: ## Fail if any TODO(scaffold) marker from new-service.sh remains
	@echo "==> TODO(scaffold) markers"
	@# Exclusions are root-relative pathspecs: the root Makefile, CLAUDE.md,
	@# the generator, templates/ and the top-level docs/ (step logs and ADRs
	@# mention the marker). services/*/docs/ and services/*/Makefile are checked.
	@if git grep -n -F --untracked 'TODO(scaffold)' -- . \
		':(exclude)Makefile' ':(exclude)CLAUDE.md' ':(exclude)scripts/new-service.sh' \
		':(exclude)templates' ':(exclude)docs'; then \
		echo "error: unfinished scaffold; replace the markers above." >&2; exit 1; \
	else echo "    none"; fi

.PHONY: lint-repo
lint-repo: ## Run repository-level linters (pre-commit, delivered by P0.5)
	@if [ -e .pre-commit-config.yaml ]; then \
		echo "==> pre-commit"; \
		pre-commit run --all-files; \
	else \
		echo "==> pre-commit: .pre-commit-config.yaml not present yet (step P0.5); skipping."; \
	fi

.PHONY: lint-%
lint-%: ## Lint one component (make lint-successor)
	$(call delegate,$*,lint)

.PHONY: fmt
fmt: ## Format the code of every component
	@if [ -z "$(COMPONENT_NAMES)" ]; then echo "no components with a Makefile yet; nothing to format."; fi
	@for name in $(COMPONENT_NAMES); do $(MAKE) fmt-$$name; done

.PHONY: fmt-%
fmt-%: ## Format one component (make fmt-successor)
	$(call delegate,$*,fmt)

.PHONY: temporary
temporary: ## List remaining TEMPORARY(P<step>) markers (CLAUDE.md 8.7)
	@echo "==> TEMPORARY markers"
	@grep -rnE 'TEMPORARY\(P[0-9]+\.[0-9a-z]+\)' \
		--exclude-dir=.git --exclude-dir=docs --exclude-dir=node_modules \
		--exclude=CLAUDE.md --exclude=Makefile . \
		|| echo "    none"

# ---------------------------------------------------------------------------
# Scaffolding and housekeeping
# ---------------------------------------------------------------------------

.PHONY: new-service
new-service: ## Scaffold a service: make new-service NAME=<name> LANG=<language>
	$(call require_file,$(NEW_SERVICE_SCRIPT),P0.4)
	@if [ -z "$(NAME)" ] || [ -z "$(LANG)" ]; then \
		echo "usage: make new-service NAME=<kebab-case-name> LANG=<language>" >&2; exit 2; \
	fi
	$(NEW_SERVICE_SCRIPT) "$(NAME)" "$(LANG)"

.PHONY: clean
clean: ## Remove containers, volumes, orphan networks and generated docs
	@if [ -e "$(COMPOSE_FILE)" ]; then \
		$(COMPOSE) down --volumes --remove-orphans; \
	else \
		echo "$(COMPOSE_FILE) not present; no containers to remove."; \
	fi
	rm -rf docs/site

# ---------------------------------------------------------------------------
# Project status
# ---------------------------------------------------------------------------

.PHONY: status
status: ## Print Current State, step in progress, latest step tags and containers
	@echo "=============================================================="
	@echo " AaaS project status"
	@echo "=============================================================="
	@echo
	@awk '/^## Current State/{flag=1; next} /^## /{flag=0} flag' $(PROGRESS_FILE)
	@echo "Step in progress (from $(PROGRESS_FILE)):"
	@step="$$(grep -E '^\| P[0-9]+\.[0-9a-z]+ \|.*\| IN_PROGRESS \|' $(PROGRESS_FILE) | cut -d'|' -f2,3 | sed 's/^ *//')"; \
		echo "  $${step:-none}"
	@echo
	@echo "Latest step snapshots (git tags):"
	@tags="$$(git tag --list 'step/*' --sort=-creatordate | head -5)"; \
		if [ -n "$$tags" ]; then echo "$$tags" | sed 's/^/  /'; else echo "  none"; fi
	@echo
	@echo "Branch: $$(git branch --show-current)  Working tree: $$(if [ -n "$$(git status --porcelain)" ]; then echo dirty; else echo clean; fi)"
	@echo
	@echo "Containers:"
	@if [ -e "$(COMPOSE_FILE)" ]; then \
		$(COMPOSE) ps --all --format 'table {{.Service}}\t{{.State}}\t{{.Status}}' 2>/dev/null | sed 's/^/  /' || echo "  docker compose is not available"; \
	else \
		echo "  $(COMPOSE_FILE) not present yet (step P0.3)."; \
	fi
