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

# Scan bench (specs/039-faster-session-scan/contracts/bench-cli.md). As
# above, a value reaches the recipes only through the environment, read as
# "$$VAR", never pasted into the shell text; the bench targets alone export
# them.
READER    ?= claude
DIR       ?=
CONFIG    ?=
SINCE     ?=
UNTIL     ?=
DIGEST    ?=
WORKERS   ?=
BENCH_BIN ?=
A         ?=
B         ?=
BENCH_TARGETS = bench-scan bench-compare bench-digests
$(BENCH_TARGETS): export READER := $(READER)
$(BENCH_TARGETS): export DIR := $(DIR)
$(BENCH_TARGETS): export CONFIG := $(CONFIG)
$(BENCH_TARGETS): export SINCE := $(SINCE)
$(BENCH_TARGETS): export UNTIL := $(UNTIL)
$(BENCH_TARGETS): export DIGEST := $(DIGEST)
$(BENCH_TARGETS): export WORKERS := $(WORKERS)
$(BENCH_TARGETS): export BENCH_BIN := $(BENCH_BIN)
$(BENCH_TARGETS): export A := $(A)
$(BENCH_TARGETS): export B := $(B)
# The fixture digests of spec 039 FR-008: fixed trees, configurations and
# window start, so the committed digests do not change with the calendar.
FIXTURE_SCAN    = Tests/UsageCoreTests/Fixtures/scan
FIXTURE_DIGESTS = Tests/UsageCoreTests/Fixtures/digests
FIXTURE_SINCE   = 2026-10-01T00:00:00Z

.PHONY: build test test-release app app-update-test app-demo dmg release cask run clean backgrounds bench-scan bench-compare bench-digests

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

# One bench run over a session directory (spec 039 FR-001, FR-002). Builds
# scan-bench in release unless BENCH_BIN names a saved binary, such as the
# baseline's; the report goes to stdout, the build output to stderr.
bench-scan:
	@set -e; \
	if [ -n "$$BENCH_BIN" ]; then \
	  bin="$$BENCH_BIN"; \
	  commit="$${SCAN_BENCH_COMMIT:-baseline-binary}"; \
	else \
	  swift build -c release --product scan-bench >&2; \
	  bin="$$(swift build -c release --show-bin-path)/scan-bench"; \
	  commit="$$(git rev-parse --short HEAD)"; \
	  if [ -n "$$(git status --porcelain)" ]; then commit="$$commit-dirty"; fi; \
	fi; \
	set -- run --reader "$${READER:-claude}"; \
	if [ -n "$$DIR" ]; then set -- "$$@" --dir "$$DIR"; fi; \
	if [ -n "$$CONFIG" ]; then set -- "$$@" --config "$$CONFIG"; fi; \
	if [ -n "$$SINCE" ]; then set -- "$$@" --since "$$SINCE"; fi; \
	if [ -n "$$UNTIL" ]; then set -- "$$@" --until "$$UNTIL"; fi; \
	if [ -n "$$DIGEST" ]; then set -- "$$@" --digest "$$DIGEST"; fi; \
	if [ -n "$$WORKERS" ]; then set -- "$$@" --workers "$$WORKERS"; fi; \
	SCAN_BENCH_COMMIT="$$commit" "$$bin" "$$@"

# Compares two records digests: exit 0 identical, 1 different, 2 a missing
# or unreadable digest (spec 039 FR-005).
bench-compare:
	@set -e; \
	if [ -n "$$BENCH_BIN" ]; then \
	  bin="$$BENCH_BIN"; \
	else \
	  swift build -c release --product scan-bench >&2; \
	  bin="$$(swift build -c release --show-bin-path)/scan-bench"; \
	fi; \
	"$$bin" compare "$$A" "$$B"

# Regenerates the committed fixture digests; the only way they change
# (spec 039 FR-008).
bench-digests:
	@set -e; \
	swift build -c release --product scan-bench >&2; \
	bin="$$(swift build -c release --show-bin-path)/scan-bench"; \
	"$$bin" digest --reader claude --dir "$(FIXTURE_SCAN)/claude" --config "$(FIXTURE_DIGESTS)/claude-config.json" \
	  --since "$(FIXTURE_SINCE)" --out "$(FIXTURE_DIGESTS)/claude.digest"; \
	"$$bin" digest --reader codex --dir "$(FIXTURE_SCAN)/codex" --config "$(FIXTURE_DIGESTS)/codex-config.json" \
	  --since "$(FIXTURE_SINCE)" --out "$(FIXTURE_DIGESTS)/codex.digest"

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
