APP_NAME      = AgentMeter
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
REPLACE            ?=
TAP_REPO           ?=
GH_REPO            ?=
VERSION            ?=
export SIGN_IDENTITY SIGN_IDENTITY_NAME NOTARY_PROFILE ALLOW_ADHOC REPLACE TAP_REPO GH_REPO VERSION

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

.PHONY: build test test-release app dmg release cask run clean backgrounds

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

test-release:
	bash scripts/release/tests/run.sh

app:
	@bash scripts/release/build-app.sh

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

# Regenerates the committed DMG backgrounds in Resources/dmg/.
backgrounds:
	swift scripts/release/render-dmg-backgrounds.swift

clean:
	rm -rf .build "$(BUILD_DIR)"
