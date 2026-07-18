PREFIX    ?= $(HOME)/.local
BIN        = manga
LABEL      = com.manga
APP        = manga.app
APP_BUILD  = .build/$(APP)
ICON_PNG   = .build/icon.png
ICON_ICNS  = .build/icon.icns

.PHONY: build dev app install uninstall clean

dev: build
	.build/debug/manga

build:
	swift build
	codesign -fs - .build/debug/$(BIN)
	xattr -d com.apple.quarantine $(PWD)/.build/debug/$(BIN) 2>/dev/null || true

lint:
	swiftlint lint

$(ICON_PNG):
	mkdir -p .build
	swift -e 'import AppKit; let size = NSSize(width: 1024, height: 1024); let image = NSImage(size: size); image.lockFocus(); NSColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0).setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill(); image.unlockFocus(); let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!; try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "$(ICON_PNG)"))'

$(ICON_ICNS): $(ICON_PNG)
	rm -rf .build/icon.iconset
	mkdir -p .build/icon.iconset
	sips -z 16 16       $(ICON_PNG) --out .build/icon.iconset/icon_16x16.png
	sips -z 32 32       $(ICON_PNG) --out .build/icon.iconset/icon_16x16@2x.png
	sips -z 32 32       $(ICON_PNG) --out .build/icon.iconset/icon_32x32.png
	sips -z 64 64       $(ICON_PNG) --out .build/icon.iconset/icon_32x32@2x.png
	sips -z 128 128     $(ICON_PNG) --out .build/icon.iconset/icon_128x128.png
	sips -z 256 256     $(ICON_PNG) --out .build/icon.iconset/icon_128x128@2x.png
	sips -z 256 256     $(ICON_PNG) --out .build/icon.iconset/icon_256x256.png
	sips -z 512 512     $(ICON_PNG) --out .build/icon.iconset/icon_256x256@2x.png
	sips -z 512 512     $(ICON_PNG) --out .build/icon.iconset/icon_512x512.png
	sips -z 1024 1024   $(ICON_PNG) --out .build/icon.iconset/icon_512x512@2x.png
	iconutil -c icns .build/icon.iconset -o $(ICON_ICNS)
	rm -rf .build/icon.iconset

app: $(ICON_ICNS)
	swift build -c release
	rm -rf $(APP_BUILD)
	install -d $(APP_BUILD)/Contents/MacOS $(APP_BUILD)/Contents/Resources
	install -m 644 Info.plist $(APP_BUILD)/Contents/Info.plist
	install -m 644 $(ICON_ICNS) $(APP_BUILD)/Contents/Resources/icon.icns
	install -m 755 .build/release/$(BIN) $(APP_BUILD)/Contents/MacOS/$(BIN)
	codesign --force --sign - $(APP_BUILD)
	xattr -dr com.apple.quarantine $(PWD)/$(APP_BUILD) 2>/dev/null || true

install: app
	install -d $(PREFIX)/bin
	install -m 755 .build/release/$(BIN) $(PREFIX)/bin/$(BIN)
	codesign -fs - $(PREFIX)/bin/$(BIN)
	xattr -d com.apple.quarantine $(PREFIX)/bin/$(BIN) 2>/dev/null || true

uninstall:
	rm -f $(PREFIX)/bin/$(BIN)

clean:
	swift package clean
	rm -f $(ICON_PNG) $(ICON_ICNS)
	rm -rf $(APP_BUILD) .build/icon.iconset
