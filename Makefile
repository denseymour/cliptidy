APP    = ClipTidy
BUNDLE = $(APP).app
BIN    = .build/release/$(APP)

.PHONY: build app install run clean dmg release

# Compile the release binary.
build:
	swift build -c release

# Assemble a double-clickable .app bundle.
app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@echo "Built $(BUNDLE). Double-click it, or run 'make install'."

# Build the bundle and copy it into /Applications.
install: app
	rm -rf /Applications/$(BUNDLE)
	cp -R $(BUNDLE) /Applications/$(BUNDLE)
	@echo "Installed to /Applications/$(BUNDLE). Open it from Launchpad."

# Run straight from the build directory (no bundle).
run: build
	$(BIN)

# Build a downloadable ClipTidy.dmg locally (no publish).
dmg:
	./scripts/release.sh --no-publish

# Build ClipTidy.dmg and publish it to GitHub Releases (needs gh authed).
release:
	./scripts/release.sh

clean:
	rm -rf .build $(BUNDLE) $(APP).dmg
