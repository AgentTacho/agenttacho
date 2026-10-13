APP_NAME      = LLM Usage
BUNDLE_ID     = dev.rhuss.llm-usage-menubar
EXECUTABLE    = LLMUsageMenuBar
BUILD_DIR     = build
APP           = $(BUILD_DIR)/$(APP_NAME).app
RELEASE_DIR   = .build/release
# SwiftPM names the resource bundle <package>_<target>.bundle; Bundle.module
# looks for it in the app's Contents/Resources.
RESOURCE_BUNDLE = $(RELEASE_DIR)/llm-usage-menubar_UsageCore.bundle

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

.PHONY: build test app run clean

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(RELEASE_DIR)/$(EXECUTABLE)" "$(APP)/Contents/MacOS/$(EXECUTABLE)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp -R "$(RESOURCE_BUNDLE)" "$(APP)/Contents/Resources/"
	codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP)"
	@echo "Built $(APP)"

run: app
	open "$(APP)"

clean:
	rm -rf .build "$(BUILD_DIR)"
