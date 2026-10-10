APP      := build/DisplayToggle.app
BIN      := $(APP)/Contents/MacOS/DisplayToggle
VERSION  := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

.PHONY: all app install uninstall zip icon clean

all: app

app: $(BIN)

$(BIN): Sources/main.swift Resources/Info.plist Resources/AppIcon.icns
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	swiftc -O Sources/main.swift -o $(BIN) -target arm64-apple-macos13 -target-variant x86_64-apple-macos13 2>/dev/null \
	  || ( swiftc -O Sources/main.swift -o build/arm64 -target arm64-apple-macos13 \
	    && swiftc -O Sources/main.swift -o build/x86_64 -target x86_64-apple-macos13 \
	    && lipo -create build/arm64 build/x86_64 -output $(BIN) && rm build/arm64 build/x86_64 )
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP)

install: app
	-pkill -x DisplayToggle
	rm -rf /Applications/DisplayToggle.app
	cp -R $(APP) /Applications/
	open /Applications/DisplayToggle.app

uninstall:
	-/Applications/DisplayToggle.app/Contents/MacOS/DisplayToggle login off
	-pkill -x DisplayToggle
	rm -rf /Applications/DisplayToggle.app

zip: app
	cd build && ditto -c -k --keepParent DisplayToggle.app DisplayToggle-$(VERSION).zip

# Regenerate Resources/AppIcon.icns from scripts/make-icon.swift
icon:
	mkdir -p build/AppIcon.iconset
	swift scripts/make-icon.swift build/icon_raw.png
	sips -z 1024 1024 build/icon_raw.png --out build/icon_1024.png >/dev/null
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s build/icon_1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  d=$$((s*2)); sips -z $$d $$d build/icon_1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf build
