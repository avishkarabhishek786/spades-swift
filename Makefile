# Canonical entry point for every operation in this repo (CLAUDE.md §3).
# If you need a new command, add a target here rather than running a one-off.

SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT      := Spades.xcodeproj
SCHEME       := Spades
SIMULATOR    ?= iPhone 16
BUNDLE_ID    := com.example.spades
DERIVED      := .build/DerivedData
APP          := $(DERIVED)/Build/Products/Debug-iphonesimulator/Spades.app
ENGINE       := Packages/SpadesEngine
DESTINATION  := platform=iOS Simulator,name=$(SIMULATOR)

# Simulator builds need no signing team.
XCFLAGS := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# xcbeautify is optional; without it, raw xcodebuild output floods the terminal,
# so fall back to cat rather than letting that happen.
PRETTY := $(shell command -v xcbeautify >/dev/null 2>&1 && echo xcbeautify || echo cat)

# SpadesEngine imports only Foundation, which is the whole point: it builds and
# tests anywhere Swift runs, with no Xcode and no simulator. On a machine with
# no Swift toolchain (a Linux CI box, a container) fall back to the official
# Swift image so the engine loop still works.
SWIFT_IMAGE := swift:6.0-jammy
ifeq ($(shell command -v swift >/dev/null 2>&1 && echo yes),yes)
  SWIFT := swift
  IN_ENGINE := cd $(ENGINE) &&
else
  SWIFT := docker run --rm -u "$$(id -u):$$(id -g)" -e HOME=/tmp \
             -e SPADES_SIM_SCALE -v "$$PWD:/w" -w /w/$(ENGINE) $(SWIFT_IMAGE) swift
  IN_ENGINE :=
endif

.PHONY: help
help: ## List available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: bootstrap
bootstrap: ## Install tooling and fetch the Kenney audio packs
	@command -v brew >/dev/null || { echo "Homebrew required"; exit 1; }
	brew install xcodegen swiftlint swift-format
	./Tools/fetch_audio.sh

.PHONY: project
project: ## Regenerate Spades.xcodeproj from project.yml
	xcodegen generate

$(PROJECT): project.yml
	$(MAKE) project

# --- Engine -----------------------------------------------------------------
# This is the primary iteration loop. No simulator, no Xcode, ~2s.

.PHONY: engine-test
engine-test: ## Run engine tests fast (simulations at reduced scale)
	@$(IN_ENGINE) SPADES_SIM_SCALE=$${SPADES_SIM_SCALE:-0.005} $(SWIFT) test

.PHONY: engine-test-full
engine-test-full: ## Run engine tests at full scale in release (~30s) — what CI runs
	@$(IN_ENGINE) $(SWIFT) test -c release

.PHONY: engine-build
engine-build: ## Build the engine only
	@$(IN_ENGINE) $(SWIFT) build

# --- App --------------------------------------------------------------------

.PHONY: build
build: $(PROJECT) ## Build the app for the simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -derivedDataPath $(DERIVED) \
		$(XCFLAGS) build | $(PRETTY)

.PHONY: test
test: engine-test-full $(PROJECT) ## Engine tests, app unit tests and the UI smoke test
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -derivedDataPath $(DERIVED) \
		$(XCFLAGS) test | $(PRETTY)

.PHONY: run
run: build ## Build, boot the simulator, install and launch
	xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted "$(APP)"
	xcrun simctl launch --console booted $(BUNDLE_ID)

.PHONY: devices
devices: ## List simulators that actually exist on this machine
	xcrun simctl list devices available

# --- Quality ----------------------------------------------------------------

.PHONY: lint
lint: ## SwiftLint in strict mode
	swiftlint --strict

.PHONY: format
format: ## Format sources in place with swift-format
	swift-format format --in-place --recursive --configuration .swift-format \
		App $(ENGINE)/Sources $(ENGINE)/Tests Tests

.PHONY: format-check
format-check: ## Fail if anything is unformatted
	swift-format lint --strict --recursive --configuration .swift-format \
		App $(ENGINE)/Sources $(ENGINE)/Tests Tests

.PHONY: clean
clean: ## Remove build products
	rm -rf .build $(ENGINE)/.build DerivedData
	rm -rf $(PROJECT)
