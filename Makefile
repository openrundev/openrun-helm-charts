# Copyright (c) ClaceIO, LLC
# SPDX-License-Identifier: Apache-2.0

# Requires GNU Make 4.0+ (uses .RECIPEPREFIX)
# On macOS with old make, use: brew install make && gmake

SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:

# Makefile for OpenRun Helm Charts

CHART_DIR := charts/openrun
HELM := helm

.DEFAULT_GOAL := help
ifeq ($(origin .RECIPEPREFIX), undefined)
  $(error This Make does not support .RECIPEPREFIX. Please use GNU Make 4.0 or later)
endif
.RECIPEPREFIX = >

.PHONY: help lint test template install-test-plugin verify

help: ## Show this help message
> @echo "Usage: make [target]"
> @echo ""
> @echo "Targets:"
> @awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

verify: lint template  template-external-db template-external-db-password test ## Run all checks (lint + test)

lint: ## Lint the Helm chart
> @echo "==> Linting chart..."
> $(HELM) lint $(CHART_DIR)

test: ## Run unit tests using helm-unittest
> @echo "==> Running unit tests..."
> @if ! $(HELM) plugin list | grep -q unittest; then \
>   echo "Error: helm-unittest plugin not installed."; \
>   echo "Install it with: helm plugin install https://github.com/helm-unittest/helm-unittest"; \
>   exit 1; \
> fi
> $(HELM) unittest $(CHART_DIR)

template: ## Render chart templates (for debugging)
> @echo "==> Rendering templates..."
> $(HELM) template test-release $(CHART_DIR) \
>   --set postgres.enabled=true \
>   --set registry.enabled=true

template-external-db: ## Render templates with external database
> @echo "==> Rendering templates with external database..."
> $(HELM) template test-release $(CHART_DIR) \
>   --set postgres.enabled=false \
>   --set externalDatabase.enabled=true \
>   --set externalDatabase.host=mydb.example.com \
>   --set externalDatabase.existingSecretName=my-secret \
>   --set registry.enabled=true

template-external-db-password: ## Render templates with external database (password in values)
> @echo "==> Rendering templates with external database (password in values)..."
> $(HELM) template test-release $(CHART_DIR) \
>   --set postgres.enabled=false \
>   --set externalDatabase.enabled=true \
>   --set externalDatabase.host=mydb.example.com \
>   --set externalDatabase.username=myuser \
>   --set externalDatabase.password=mypassword \
>   --set registry.enabled=true

install-test-plugin: ## Install helm-unittest plugin
> @echo "==> Installing helm-unittest plugin..."
> $(HELM) plugin install https://github.com/helm-unittest/helm-unittest --verify=false || true

check-deps: ## Check if required tools are installed
> @echo "==> Checking dependencies..."
> @command -v helm >/dev/null 2>&1 || { echo "Error: helm is not installed"; exit 1; }
> @echo "  helm: OK"
> @if $(HELM) plugin list | grep -q unittest; then \
>   echo "  helm-unittest: OK"; \
> else \
>   echo "  helm-unittest: NOT INSTALLED (run 'make install-test-plugin')"; \
> fi

ci: lint test ## Run CI checks (same as 'all')
