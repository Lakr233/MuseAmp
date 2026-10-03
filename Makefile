# MuseAmpMusic build automation

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# =============================================================================
# Configuration
# =============================================================================

ROOT_DIR        := $(shell pwd)
WORKSPACE       := $(ROOT_DIR)/MuseAmp.xcworkspace
PROJECT         := $(ROOT_DIR)/MuseAmp.xcodeproj
IOS_SCHEME      := MuseAmp
TV_SCHEME       := MuseAmpTV
CONFIGURATION   := Debug
DERIVED_DATA   ?= /private/tmp/museamp-deriveddata
BUILD_HOME      = $(DERIVED_DATA)/home
XDG_CACHE_HOME  = $(DERIVED_DATA)/xdg-cache
MODULE_CACHE    = $(DERIVED_DATA)/ModuleCache.noindex

HOST_ARCH := $(shell uname -m)

IOS_DESTINATION            := generic/platform=iOS
SIM_DESTINATION            := generic/platform=iOS Simulator
CATALYST_DESTINATION       := generic/platform=macOS,variant=Mac Catalyst
CATALYST_TEST_DESTINATION  := platform=macOS,variant=Mac Catalyst,arch=$(HOST_ARCH)
TVOS_DESTINATION           := generic/platform=tvOS

SWIFTFORMAT_EXCLUDES := Vendor,build,.build,DerivedData

# Pass dirty=1 to allow package-resolve / scan-license on a dirty git tree.
# Intended for release flows where the working tree may carry version bumps.
ifeq ($(dirty),1)
    export ALLOW_DIRTY := 1
endif

# run_xcodebuild.sh wraps xcodebuild, tees the full log, pipes live output
# through xcbeautify when available, and fails with a non-zero status when the
# log contains compiler errors or "** ... FAILED **" markers — even if
# xcodebuild itself returned 0. This guarantees `make test` (build-ios →
# build-catalyst → build-tvos → test-unit) halts at the first real failure.
XCODEBUILD_WRAPPER := ./Resources/DevKit/scripts/run_xcodebuild.sh

XCODEBUILD := $(XCODEBUILD_WRAPPER) \
    -workspace "$(WORKSPACE)" \
    -project "$(PROJECT)" \
    -configuration $(CONFIGURATION) \
    -derivedDataPath "$(DERIVED_DATA)" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

.PHONY: all help \
        build build-ios build-catalyst build-tvos \
        build-device install-device launch-device run-device \
        build-sim install-sim launch-sim run-sim \
        launch-catalyst \
        test test-unit \
        package-resolve scan-license \
        format format-lint \
        strip-xcstrings validate-xcstrings \
        tidy-schemes \
        chore clean

# =============================================================================
# Meta
# =============================================================================

all: build

help:
	@echo "Build:"
	@echo "  build              Build iOS, Mac Catalyst, and tvOS"
	@echo "  build-ios          Build the iOS app (scheme: $(IOS_SCHEME))"
	@echo "  build-catalyst     Build the Mac Catalyst app (scheme: $(IOS_SCHEME))"
	@echo "  build-tvos         Build the tvOS app (scheme: $(TV_SCHEME))"
	@echo ""
	@echo "Device (physical iPhone/iPad):"
	@echo "  build-device       Build the iOS app signed for physical devices"
	@echo "  install-device     Install the built app (device=<name-or-udid>)"
	@echo "  launch-device      Launch the installed app (device=<name-or-udid>)"
	@echo "  run-device         build-device + install-device + launch-device"
	@echo ""
	@echo "Simulator:"
	@echo "  build-sim          Build the iOS app for the iOS Simulator (unsigned)"
	@echo "  install-sim        Install the built app (sim=<name-or-udid>, must be booted)"
	@echo "  launch-sim         Launch the installed app (sim=<name-or-udid>)"
	@echo "  run-sim            build-sim + install-sim + launch-sim"
	@echo ""
	@echo "Mac Catalyst run:"
	@echo "  launch-catalyst    Launch the built Catalyst app in the background (prints pid) with"
	@echo "                     CFFIXED_USER_HOME=<home> (home=<dir> [log=<file>])"
	@echo ""
	@echo "Test:"
	@echo "  test               Build all platforms, then run the full test suite"
	@echo "  test-unit          Run tests on Mac Catalyst only (no platform build)"
	@echo ""
	@echo "Packages & licenses:"
	@echo "  package-resolve    Resolve SwiftPM packages and refresh OpenSourceLicenses.md"
	@echo "  scan-license       Alias for package-resolve"
	@echo ""
	@echo "Formatting:"
	@echo "  format             Run swiftformat + prettier (write)"
	@echo "  format-lint        Run swiftformat + prettier in check mode"
	@echo ""
	@echo "Localization:"
	@echo "  strip-xcstrings    Drop stale keys and mirror keys into en values"
	@echo "  validate-xcstrings Fail on stale keys or missing translations (release gate)"
	@echo ""
	@echo "Workspace:"
	@echo "  tidy-schemes       Hide non-MuseAmp schemes and pin MuseAmp/MuseAmpTV to the front"
	@echo ""
	@echo "Housekeeping:"
	@echo "  chore              Strip xcstrings, refresh licenses, tidy schemes, then format the tree"
	@echo "  clean              Remove derived data"
	@echo ""
	@echo "Flags:"
	@echo "  dirty=1            Allow package-resolve / scan-license on a dirty git tree"

# =============================================================================
# Build
# =============================================================================

build: build-ios build-catalyst build-tvos

build-ios:
	mkdir -p "$(BUILD_HOME)" "$(XDG_CACHE_HOME)" "$(MODULE_CACHE)"
	HOME="$(BUILD_HOME)" XDG_CACHE_HOME="$(XDG_CACHE_HOME)" CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(MODULE_CACHE)" XCBUILD_LABEL=build-ios $(XCODEBUILD) \
	    -scheme $(IOS_SCHEME) \
	    -destination "$(IOS_DESTINATION)" \
	    build

build-catalyst:
	mkdir -p "$(BUILD_HOME)" "$(XDG_CACHE_HOME)" "$(MODULE_CACHE)"
	HOME="$(BUILD_HOME)" XDG_CACHE_HOME="$(XDG_CACHE_HOME)" CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(MODULE_CACHE)" XCBUILD_LABEL=build-catalyst $(XCODEBUILD) \
	    -scheme $(IOS_SCHEME) \
	    -destination "$(CATALYST_DESTINATION)" \
	    SUPPORTS_MACCATALYST=YES \
	    build

build-tvos:
	mkdir -p "$(BUILD_HOME)" "$(XDG_CACHE_HOME)" "$(MODULE_CACHE)"
	HOME="$(BUILD_HOME)" XDG_CACHE_HOME="$(XDG_CACHE_HOME)" CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(MODULE_CACHE)" XCBUILD_LABEL=build-tvos $(XCODEBUILD) \
	    -scheme $(TV_SCHEME) \
	    -destination "$(TVOS_DESTINATION)" \
	    build

# =============================================================================
# Device deploy
# =============================================================================

# Signed build for physical devices. Signing and provisioning need the real
# HOME (login keychain, Xcode accounts), so this variant does not sandbox HOME
# and does not force CODE_SIGNING_ALLOWED=NO like $(XCODEBUILD).
XCODEBUILD_DEVICE := $(XCODEBUILD_WRAPPER) \
    -workspace "$(WORKSPACE)" \
    -project "$(PROJECT)" \
    -configuration $(CONFIGURATION) \
    -derivedDataPath "$(DERIVED_DATA)" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    -allowProvisioningUpdates

DEVICE_APP       := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/MuseAmp.app
DEVICE_BUNDLE_ID := wiki.qaq.muse.amp

build-device:
	mkdir -p "$(XDG_CACHE_HOME)" "$(MODULE_CACHE)"
	CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(MODULE_CACHE)" XCBUILD_LABEL=build-device $(XCODEBUILD_DEVICE) \
	    -scheme $(IOS_SCHEME) \
	    -destination "$(IOS_DESTINATION)" \
	    build

install-device:
	@test -n "$(device)" || { echo "usage: make install-device device=<name-or-udid>"; exit 1; }
	xcrun devicectl device install app --device "$(device)" "$(DEVICE_APP)"

launch-device:
	@test -n "$(device)" || { echo "usage: make launch-device device=<name-or-udid>"; exit 1; }
	xcrun devicectl device process launch --device "$(device)" $(DEVICE_BUNDLE_ID)

run-device: build-device install-device launch-device

# =============================================================================
# Simulator deploy
# =============================================================================

SIM_APP       := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/MuseAmp.app
CATALYST_APP  := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-maccatalyst/MuseAmp.app

build-sim:
	mkdir -p "$(BUILD_HOME)" "$(XDG_CACHE_HOME)" "$(MODULE_CACHE)"
	HOME="$(BUILD_HOME)" XDG_CACHE_HOME="$(XDG_CACHE_HOME)" CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(MODULE_CACHE)" XCBUILD_LABEL=build-sim $(XCODEBUILD) \
	    -scheme $(IOS_SCHEME) \
	    -destination "$(SIM_DESTINATION)" \
	    build

install-sim:
	@test -n "$(sim)" || { echo "usage: make install-sim sim=<name-or-udid>"; exit 1; }
	xcrun simctl install "$(sim)" "$(SIM_APP)"

launch-sim:
	@test -n "$(sim)" || { echo "usage: make launch-sim sim=<name-or-udid>"; exit 1; }
	xcrun simctl launch --terminate-running-process "$(sim)" $(DEVICE_BUNDLE_ID)

run-sim: build-sim install-sim launch-sim

# Runs the unsigned (therefore unsandboxed) Catalyst build with a redirected
# home so it never touches the real ~/Documents or ~/Library. The binary is
# executed directly because `open` does not reliably forward the environment.
# The Debug build is coverage-instrumented, so its .profraw output is also kept
# inside <home> rather than the repository root.
launch-catalyst:
	@test -n "$(home)" || { echo "usage: make launch-catalyst home=<dir> [log=<file>]"; exit 1; }
	@test -x "$(CATALYST_APP)/Contents/MacOS/MuseAmp" || { echo "missing $(CATALYST_APP); run make build-catalyst first"; exit 1; }
	mkdir -p "$(abspath $(home))"
	cd "$(abspath $(home))" || exit 1; CFFIXED_USER_HOME="$(abspath $(home))" LLVM_PROFILE_FILE="$(abspath $(home))/museamp-%p.profraw" nohup "$(CATALYST_APP)/Contents/MacOS/MuseAmp" >"$(or $(log),$(abspath $(home))/museamp-stdout.log)" 2>&1 & echo "launched pid=$$!"

# =============================================================================
# Test
# =============================================================================

test: build test-unit

test-unit:
	mkdir -p "$(BUILD_HOME)" "$(XDG_CACHE_HOME)" "$(MODULE_CACHE)"
	HOME="$(BUILD_HOME)" XDG_CACHE_HOME="$(XDG_CACHE_HOME)" CLANG_MODULE_CACHE_PATH="$(MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(MODULE_CACHE)" XCBUILD_LABEL=test-unit $(XCODEBUILD) \
	    -scheme $(IOS_SCHEME) \
	    -destination "$(CATALYST_TEST_DESTINATION)" \
	    SUPPORTS_MACCATALYST=YES \
	    test

# =============================================================================
# Packages & licenses
# =============================================================================

package-resolve: scan-license

scan-license:
	./Resources/DevKit/scripts/scan.license.sh

# =============================================================================
# Formatting
# =============================================================================

format:
	swiftformat . \
	    --swift-version 6.2 \
	    --disable redundantSendable \
	    --exclude $(SWIFTFORMAT_EXCLUDES)
	npx --yes prettier --write .

format-lint:
	swiftformat . \
	    --swift-version 6.2 \
	    --disable redundantSendable \
	    --exclude $(SWIFTFORMAT_EXCLUDES) \
	    --lint
	npx --yes prettier --check .

# =============================================================================
# Localization (xcstrings)
# =============================================================================

strip-xcstrings:
	python3 ./Resources/DevKit/scripts/strip_stale_xcstrings.py

validate-xcstrings:
	python3 ./Resources/DevKit/scripts/validate_xcstrings.py

# =============================================================================
# Workspace
# =============================================================================

tidy-schemes:
	python3 ./Resources/DevKit/scripts/tidy_workspace_schemes.py

# =============================================================================
# Housekeeping
# =============================================================================

chore:
	$(MAKE) strip-xcstrings
	$(MAKE) scan-license dirty=1
	$(MAKE) tidy-schemes
	$(MAKE) format

clean:
	rm -rf $(DERIVED_DATA)
