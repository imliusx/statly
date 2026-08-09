.PHONY: build run test xcodeproj app dmg clean

XCODE_DD := .build/xcode
VERSION ?= 0.1.0

build:
	swift build

run: build
	./.build/debug/Statly

test:
	@test -d Tests && swift test || echo "无 Tests 目录，跳过"

xcodeproj:
	xcodegen generate

app: xcodeproj
	xcodebuild -project Statly.xcodeproj -scheme Statly -configuration Release -derivedDataPath $(XCODE_DD) build
	rm -rf dist && mkdir -p dist
	cp -R $(XCODE_DD)/Build/Products/Release/Statly.app dist/
	@echo "打包完成: dist/Statly.app"

# 出 DMG（不发布）。发布用 scripts/release.sh <版本> --publish
dmg:
	bash scripts/release.sh $(VERSION)

clean:
	rm -rf .build dist Statly.xcodeproj
