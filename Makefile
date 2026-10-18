APP_NAME      = AgentTacho
BUILD_DIR     = build
APP           = $(BUILD_DIR)/$(APP_NAME).app

# Release settings (specs/005-macos-distribution/contracts/make-targets.md).
# Empty values select the scripts' defaults (lib.sh release_defaults). They
# reach the scripts only through the environment and the recipes read them as
# "$$VAR": a value is never pasted into the shell text of a recipe.
SIGN_IDENTITY      ?=
SIGN_IDENTITY_NAME ?=
NOTARY_PROFILE     ?=
ALLOW_ADHOC        ?=
ALLOW_TIER_DOWNGRADE ?=
ALLOW_UNNOTARIZED  ?=
REPLACE            ?=
TAP_REPO           ?=
SITE_REPO          ?=
GH_REPO            ?=
VERSION            ?=
# Update-test build (specs/013-auto-update/contracts/make-targets.md).
UPDATE_TEST        ?=
UPDATE_SOURCE      ?=
# Demo build for screenshots (specs/024-demo-mode-screenshots/contracts/capture-cli.md).
DEMO               ?=
export SIGN_IDENTITY SIGN_IDENTITY_NAME NOTARY_PROFILE ALLOW_ADHOC ALLOW_TIER_DOWNGRADE ALLOW_UNNOTARIZED REPLACE TAP_REPO SITE_REPO GH_REPO VERSION UPDATE_TEST UPDATE_SOURCE DEMO

# Swift Testing macros live in a plugin directory that `swift test` does not
# search by default when only the Command Line Tools are installed.
TOOLCHAIN_PLUGINS = $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
TEST_FLAGS = -Xswiftc -plugin-path -Xswiftc "$(TOOLCHAIN_PLUGINS)"

# The macOS 27 SDK turns SwiftUI property wrappers such as @State into macros
# whose compiler plugin the Command Line Tools do not ship. Build against the
# macOS 26 SDK when it is installed next to it.
SDK26 = $(shell xcode-select -p)/SDKs/MacOSX26.sdk
ifneq ($(wildcard $(SDK26)),)
export SDKROOT ?= $(SDK26)
endif

.PHONY: build test test-release app app-update-test app-demo dmg release cask run clean backgrounds

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

test-release:
	bash scripts/release/tests/run.sh

# Never an update-test or demo build, whatever the environment holds (spec 013
# FR-025, spec 024 FR-002).
app:
	@env -u DEMO -u UPDATE_TEST -u UPDATE_SOURCE bash scripts/release/build-app.sh

# Update-test build reading releases from UPDATE_SOURCE=owner/repo, for the
# end-to-end test of one-click install (spec 013 FR-025, quickstart.md).
app-update-test:
	@UPDATE_TEST=1 bash scripts/release/build-app.sh

# "AgentTacho Demo.app" for screenshots: plays a scenario from Resources/demo/
# instead of reading real usage (spec 024 FR-001).
app-demo:
	@DEMO=1 bash scripts/release/build-app.sh

# Dry run: app plus DMG in build/release/, nothing is published (FR-019).
dmg:
	@bash scripts/release/release.sh --dry-run

# Full release of the vX.Y.Z tag at HEAD (FR-015).
release:
	@bash scripts/release/release.sh

# Cask-only update for an already published release (FR-021a).
cask:
	@if [ -z "$$VERSION" ]; then echo "error: VERSION is required, for example: make cask VERSION=0.2.0" >&2; exit 1; fi
	@bash scripts/release/update-cask.sh "$$VERSION"

run: app
	open "$(APP)"

# Regenerates both committed DMG backgrounds in Resources/dmg/: the notarized
# one draws its title on background-notarized-base.png (spec 023 research R3).
backgrounds:
	swift scripts/release/render-dmg-backgrounds.swift

clean:
	rm -rf .build "$(BUILD_DIR)"
