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
UNAME_S      := $(shell uname -s)

# Simulator builds need no signing team.
XCFLAGS := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# xcbeautify is optional; without it, raw xcodebuild output floods the terminal,
# so fall back to cat rather than letting that happen.
PRETTY := $(shell command -v xcbeautify >/dev/null 2>&1 && echo xcbeautify || echo cat)

# ---------------------------------------------------------------------------
# Toolchain
#
# SpadesEngine and SpadesEconomy import only Foundation, which is the whole
# point: they build and test anywhere Swift runs, with no Xcode and no
# simulator. On a machine with no Swift toolchain, fall back to the official
# image so the engine loop still works.
#
# The container is pinned to the version the Mac toolchain is expected to be.
# A container silently diverging from a newer local toolchain is a miserable
# class of bug to chase, so every engine invocation prints which path it took
# and warns when the two disagree.
# ---------------------------------------------------------------------------

SWIFT_PIN   := 6.0
SWIFT_IMAGE := swift:$(SWIFT_PIN)-jammy
HAVE_SWIFT  := $(shell command -v swift >/dev/null 2>&1 && echo yes || echo no)

ifeq ($(HAVE_SWIFT),yes)
  LOCAL_SWIFT_VERSION := $(shell swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p' | head -1)
  SWIFT     := swift
  IN_ENGINE := cd $(ENGINE) &&
else
  LOCAL_SWIFT_VERSION :=
  SWIFT := docker run --rm -u "$$(id -u):$$(id -g)" -e HOME=/tmp \
             -e SPADES_SIM_SCALE -e SPADES_SEED_BASE -v "$$PWD:/w" -w /w/$(ENGINE) \
             $(SWIFT_IMAGE) swift
  IN_ENGINE :=
endif

.PHONY: toolchain
toolchain: ## Print which Swift toolchain the engine targets will use
ifeq ($(HAVE_SWIFT),yes)
	@echo ">>> toolchain: local swift $(LOCAL_SWIFT_VERSION)"
	@case "$(LOCAL_SWIFT_VERSION)" in \
	  $(SWIFT_PIN)*) ;; \
	  *) echo ">>> WARNING: local swift $(LOCAL_SWIFT_VERSION) differs from the pinned $(SWIFT_PIN)."; \
	     echo ">>>          Update SWIFT_PIN in the Makefile, or expect results to diverge from CI." ;; \
	esac
else
	@echo ">>> toolchain: docker $(SWIFT_IMAGE)"
	@command -v docker >/dev/null 2>&1 || { echo ">>> ERROR: no local swift and no docker. Install one."; exit 1; }
endif

# Guard for targets that genuinely cannot run off macOS: SwiftUI, UIKit, GameKit
# and AVFoundation do not exist on Linux, so these fail with a clear message
# rather than a confusing linker error.
define REQUIRE_MACOS
	@if [ "$(UNAME_S)" != "Darwin" ]; then \
	  echo ">>> '$@' requires macOS: the app targets link SwiftUI, UIKit, GameKit and AVFoundation,"; \
	  echo ">>>     and the Xcode/Homebrew tooling it drives only exists there."; \
	  echo ">>> On this machine ($(UNAME_S)) use 'make engine-test' / 'make engine-test-full', which are portable."; \
	  exit 1; \
	fi
endef

.PHONY: help
help: ## List available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: bootstrap
bootstrap: ## Install tooling
	@command -v brew >/dev/null || { echo "Homebrew required"; exit 1; }
	brew install xcodegen swiftlint xcbeautify
	@echo "swift-format ships with the Swift 6 toolchain; no separate install needed."
	@echo "Audio is vendored in App/Resources/Audio — no fetch step. See CLAUDE.md §10."

.PHONY: project
project: ## Regenerate Spades.xcodeproj from project.yml
	$(call REQUIRE_MACOS)
	xcodegen generate

$(PROJECT): project.yml
	@$(MAKE) project

# --- Engine and economy ------------------------------------------------------
# The primary iteration loop. No simulator, no Xcode, ~3s.

.PHONY: engine-test
engine-test: toolchain ## Run engine + economy tests fast (simulations at reduced scale)
	@$(IN_ENGINE) SPADES_SIM_SCALE=$${SPADES_SIM_SCALE:-0.005} $(SWIFT) test

.PHONY: engine-test-full
engine-test-full: toolchain ## Full §13 scale, release build (~30s) — CI and pre-PR
	@$(IN_ENGINE) $(SWIFT) test -c release

.PHONY: engine-build
engine-build: toolchain ## Build both library targets
	@$(IN_ENGINE) $(SWIFT) build

.PHONY: sim-nightly
sim-nightly: toolchain ## Rotating-seed simulation sweep (§13) — not the fixed CI seeds
	@seed=$${SPADES_SEED_BASE:-$$(date +%s)}; \
	echo ">>> sim-nightly seed base: $$seed"; \
	echo ">>> a failure prints the offending seed — pin it in the fixed set as a regression case"; \
	$(IN_ENGINE) SPADES_SEED_BASE=$$seed $(SWIFT) test -c release

# --- Purity ------------------------------------------------------------------

.PHONY: purity-check
purity-check: ## Fail if the pure targets reach for a clock, a calendar or a framework
	@echo ">>> purity check: $(ENGINE)/Sources"
	@bash Tools/purity_check.sh

# --- App ---------------------------------------------------------------------

.PHONY: build
build: ## Build the app for the simulator
	$(call REQUIRE_MACOS)
	@$(MAKE) project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -derivedDataPath $(DERIVED) \
		$(XCFLAGS) build | $(PRETTY)

.PHONY: test
test: engine-test-full ## Full engine scale, then app unit tests and the UI smoke test
	$(call REQUIRE_MACOS)
	@$(MAKE) project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -derivedDataPath $(DERIVED) \
		$(XCFLAGS) test | $(PRETTY)

.PHONY: run
run: build ## Build, boot the simulator, install and launch
	$(call REQUIRE_MACOS)
	xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted "$(APP)"
	xcrun simctl launch --console booted $(BUNDLE_ID)

.PHONY: devices
devices: ## List simulators that actually exist on this machine
	$(call REQUIRE_MACOS)
	xcrun simctl list devices available

# --- Quality -----------------------------------------------------------------

.PHONY: lint
lint: ## SwiftLint in strict mode
	$(call REQUIRE_MACOS)
	swiftlint --strict

.PHONY: format
format: ## Format sources in place
	swift-format format --in-place --recursive --configuration .swift-format \
		App $(ENGINE)/Sources $(ENGINE)/Tests Tests

.PHONY: format-check
format-check: ## Fail if anything is unformatted
	swift-format lint --strict --recursive --configuration .swift-format \
		App $(ENGINE)/Sources $(ENGINE)/Tests Tests

.PHONY: ci
ci: lint purity-check engine-test-full test ## What CI runs

.PHONY: ci-portable
ci-portable: purity-check engine-test-full ## The part of CI that runs without macOS

.PHONY: clean
clean: ## Remove build products
	rm -rf .build $(ENGINE)/.build DerivedData
	rm -rf $(PROJECT)
