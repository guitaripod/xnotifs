.PHONY: build run clean debug install

APP_NAME := xnotifs-menubar
BUNDLE_ID := ml.rawdog.xnotifs-menubar
BUILD_DIR := .build
RELEASE_DIR := $(BUILD_DIR)/release
APP_BUNDLE := $(RELEASE_DIR)/xnotifs.app

build:
	swift build -c release --arch arm64 --arch x86_64
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BUILD_DIR)/apple/Products/Release/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	cp Sources/xnotifs-menubar/Resources/Info.plist "$(APP_BUNDLE)/Contents/"
	defaults write "$(APP_BUNDLE)/Contents/Info" CFBundleExecutable "$(APP_NAME)"
	plutil -convert binary1 "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

debug:
	swift build

run: debug
	swift run

clean:
	rm -rf $(BUILD_DIR)
	rm -rf "$(RELEASE_DIR)"

install: build
	cp -R "$(APP_BUNDLE)" /Applications/

ifeq ($(PREFIX),)
	PREFIX := /usr/local
endif
