.PHONY: build run test xcodeproj app clean

XCODE_DD := .build/xcode

build:
	swift build

run: build
	./.build/debug/Statly

test:
	swift test

xcodeproj:
	xcodegen generate

app: xcodeproj
	xcodebuild -project Statly.xcodeproj -scheme Statly -configuration Release -derivedDataPath $(XCODE_DD) build
	rm -rf dist && mkdir -p dist
	cp -R $(XCODE_DD)/Build/Products/Release/Statly.app dist/
	@echo "打包完成: dist/Statly.app"

clean:
	rm -rf .build dist Statly.xcodeproj
