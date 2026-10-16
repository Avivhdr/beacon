# Beacon — common dev tasks.
#
# The Xcode project is generated from project.yml and git-ignored.
# project.yml stays the source of truth.
#
#   make run        Build a Debug .app and launch it
#   make build      Build a Debug .app
#   make test       Run the Core tests (swift test)
#   make package    Signed, notarized DMG (see package.sh)
#   make snapshots  Write panel PNGs into snapshots/

PROJECT := Beacon.xcodeproj
SCHEME  := Beacon
DERIVED := build
APP     := $(DERIVED)/Build/Products/Debug/Beacon.app

.PHONY: run build test package snapshots icon

run: build
	open "$(APP)"

build: icon
	xcodegen generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration Debug -derivedDataPath $(DERIVED) build

test:
	swift test

package:
	./package.sh

icon:
	swift Tools/generate-icon.swift Sources/Beacon/Assets.xcassets/AppIcon.appiconset

snapshots: build
	mkdir -p snapshots
	"$(APP)/Contents/MacOS/Beacon" --snapshot "$(CURDIR)/snapshots"
