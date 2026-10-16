# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          Makefile
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Single entry point for building, running, testing and
#                  inspecting the AaaS system on a developer workstation.
# Related Docs:    CLAUDE.md (sections 4.2, 6.2, 6.4, 6.5.4, 6.5.7, 6.5.8,
#                  8.1, 9.3), ADR-0002, ADR-0009, ADR-0010, ADR-0011,
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

# Documentation portal (ADR-0010): tool image, how it is run (repository at
# /docs, caller's UID so that generated files are not owned by root), the
# directory that collects the native API docs of components, and the port of
# `make docs-serve`.
DOCS_IMAGE := aaas/docs-portal:dev
DOCS_RUN := docker run --rm --user "$$(id -u):$$(id -g)" --volume "$(CURDIR)":/docs
API_DOCS_DIR := build/api-docs
DOCS_PORT ?= 8000

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

# require_running <service>: fail with a clear message if the Compose
# service is not running (the topic targets need a live broker).
define require_running
	@if [ -z "$$($(COMPOSE) ps --status running --quiet $(1) 2>/dev/null)" ]; then \
		echo "error: $(1) is not running; start it with: make up PROFILES=core" >&2; \
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
# Event bus topics (CLAUDE.md 4.2, ADR-0011)
# ---------------------------------------------------------------------------

.PHONY: topics
topics: ## Create missing Redpanda topics of contracts/events/topics.psv (broker must be up)
	$(call require_running,redpanda)
	$(COMPOSE) run --rm --no-deps redpanda-topics

.PHONY: topics-check
topics-check: ## Verify that every topic exists with its declared partitions and config
	$(call require_running,redpanda)
	$(COMPOSE) run --rm --no-deps redpanda-topics --check

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

# ---------------------------------------------------------------------------
# Documentation coverage (CLAUDE.md 6.5.4, ADR-0009)
# ---------------------------------------------------------------------------

.PHONY: doc-check
doc-check: ## Check file headers and comments before top-level definitions in every file
	@echo "==> doc-check (headers and definitions)"
	scripts/doc-check.sh

.PHONY: doc-coverage
doc-coverage: doc-check doc-coverage-repo ## doc-check, repository Python and the native tool of every component
	@if [ -z "$(COMPONENT_NAMES)" ]; then echo "no components with a Makefile yet; native coverage tools: nothing to run."; fi
	@for name in $(COMPONENT_NAMES); do $(MAKE) doc-coverage-$$name; done

.PHONY: doc-coverage-repo
doc-coverage-repo: docs-image ## interrogate (100%) and doctests of the repository Python scripts
	@echo "==> interrogate and doctests (scripts/*.py)"
	$(DOCS_RUN) --entrypoint sh $(DOCS_IMAGE) -c \
		'interrogate --verbose --fail-under 100 scripts/ && for f in scripts/*.py; do python3 -m doctest "$$f" || exit 1; done && echo "    doctests passed"'

.PHONY: doc-coverage-%
doc-coverage-%: ## Native documentation coverage of one component (make doc-coverage-successor)
	$(call delegate,$*,doc-coverage)

.PHONY: temporary
temporary: ## List remaining TEMPORARY(P<step>) markers (CLAUDE.md 8.7)
	@echo "==> TEMPORARY markers"
	@grep -rnE 'TEMPORARY\(P[0-9]+\.[0-9a-z]+\)' \
		--exclude-dir=.git --exclude-dir=docs --exclude-dir=node_modules \
		--exclude=CLAUDE.md --exclude=Makefile . \
		|| echo "    none"

# ---------------------------------------------------------------------------
# Documentation portal and changelogs (CLAUDE.md 6.5.7, 6.5.8, ADR-0010)
# ---------------------------------------------------------------------------

.PHONY: docs-image
docs-image: ## Build the documentation tool image (MkDocs Material, interrogate)
	@docker build --quiet --tag $(DOCS_IMAGE) infra/docs-portal >/dev/null

.PHONY: api-docs
api-docs: ## Export the native API documentation of every component to build/api-docs
	@if [ -z "$(COMPONENT_NAMES)" ]; then echo "no components with a Makefile yet; no native API documentation to export."; fi
	@for name in $(COMPONENT_NAMES); do $(MAKE) api-docs-$$name; done

.PHONY: api-docs-%
api-docs-%: ## Export the native API documentation of one component (make api-docs-successor)
	@rm -rf "$(API_DOCS_DIR)/$*"
	$(call delegate,$*,api-docs API_DOCS_DIR=$(CURDIR)/$(API_DOCS_DIR)/$*)

.PHONY: docs
docs: api-docs docs-portal ## Native API docs of every component, then the portal into docs/site (strict)

.PHONY: docs-portal
docs-portal: docs-image ## Build the portal from what is in build/api-docs, without exporting API docs (strict)
	@mkdir -p build/portal
	$(DOCS_RUN) $(DOCS_IMAGE) build --strict
	@echo "portal built: docs/site/index.html (make docs-serve to browse it)"

.PHONY: docs-serve
docs-serve: docs-image ## Serve the portal on http://127.0.0.1:8000 with live rebuild
	@mkdir -p build/portal
	$(DOCS_RUN) $$([ -t 0 ] && echo --interactive --tty) --publish 127.0.0.1:$(DOCS_PORT):8000 \
		$(DOCS_IMAGE) serve --dev-addr 0.0.0.0:8000

.PHONY: changelog-%
changelog-%: ## Unreleased changes of a component; with VERSION=X.Y.Z, add them to its CHANGELOG.md
	scripts/changelog.sh "$*" $(VERSION)

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
clean: ## Remove containers, volumes, orphan networks and generated docs and portal sources
	@if [ -e "$(COMPOSE_FILE)" ]; then \
		$(COMPOSE) down --volumes --remove-orphans; \
	else \
		echo "$(COMPOSE_FILE) not present; no containers to remove."; \
	fi
	rm -rf docs/site build/portal $(API_DOCS_DIR)

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
