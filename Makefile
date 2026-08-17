.PHONY: all build test bundle install run self-test clean

all: build test

## Compile the release binary
build:
	swift build -c release

## Run the assertion suite (no XCTest needed — see docs/PRD.md 2.7)
test:
	swift build -c release --product blackout-tests
	./.build/release/blackout-tests

## Assemble dist/Blackout.app
bundle:
	./scripts/bundle.sh

## Build, install to /Applications, relaunch
install:
	./scripts/install.sh

## Run the menu-bar app straight from the build directory (no login item, no icon)
run: build
	./.build/release/blackout

## Black out every screen for ~1.2s, restore, and verify brightness came back
self-test: build
	./.build/release/blackout --self-test

clean:
	rm -rf .build dist
