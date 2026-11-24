# Builds the Ascender packages from a checkout of the Ascender source.
#
#   make packages                      clone the source named in source.env and build deb and rpm for amd64
#   make packages SOURCE_DIR=../ascender-go ARCH=arm64 FORMATS=deb
#   make test                          install the packages in Debian 13 and Rocky Linux 9 containers and smoke test them
#   make repo                          lay out an apt and a yum repository from build/packages in site/
include source.env

SOURCE_DIR ?= build/src
ARCH       ?= amd64
FORMATS    ?= deb rpm
BUILD      ?= build
NFPM       ?= nfpm
VERSION    ?= $(shell test -e $(SOURCE_DIR)/.git && scripts/version.sh $(SOURCE_DIR))
# The Go that builds the binaries. The source's go.mod pins a toolchain,
# and when a newer patch release fixes a standard library vulnerability
# (govulncheck reports it) the packages should carry the fix before the
# source moves: the go command downloads the release named here.
GOTOOLCHAIN ?= go1.27.4

export BUILD NFPM GOTOOLCHAIN

.PHONY: help source binaries packages test repo clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | column -t -s "$$(printf '\t')"

source: ## Clone the Ascender source named in source.env into build/src (unless SOURCE_DIR points elsewhere)
	@test -e $(SOURCE_DIR)/.git || { git clone https://github.com/$(SOURCE_REPO).git $(SOURCE_DIR) && git -C $(SOURCE_DIR) checkout --quiet $(SOURCE_REF); }

binaries: source ## Build ascender-web and ascender-task for ARCH into build/bin/ARCH, and collect the files the packages ship
	scripts/build-binaries.sh $(SOURCE_DIR) $(ARCH) $(BUILD)

packages: binaries ## Build the packages (FORMATS) for ARCH into build/packages
	VERSION=$(VERSION) ARCH=$(ARCH) scripts/build-packages.sh $(FORMATS)

test: ## Install build/packages in Debian 13 and Rocky Linux 9 containers and run tests/smoke.sh
	VERSION=$(VERSION) tests/run-local.sh

repo: ## Lay out an apt and a yum repository in site/ from build/packages (signed when GPG_PRIVATE_KEY is set)
	scripts/repo-build.sh site $(BUILD)/packages

clean: ## Remove build/ and site/
	rm -rf $(BUILD) site
