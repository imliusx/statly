.PHONY: build release app run test clean

build:
	swift build

release:
	swift build -c release

app: release
	bash scripts/build-app.sh

run: build
	./.build/debug/Statly

test:
	swift test

clean:
	rm -rf .build dist
