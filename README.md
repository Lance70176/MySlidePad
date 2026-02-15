# MacSlide

## Packaging

Build archive (Release):

```bash
cd MySlidePad
xcodebuild -scheme MacSlide -configuration Release -archivePath build/MacSlide.xcarchive archive
```

Create DMG (drag-to-Applications layout):

```bash
cd MySlidePad
rm -rf build/dmg && mkdir -p build/dmg && \
  cp -R build/MacSlide.xcarchive/Products/Applications/MacSlide.app build/dmg/ && \
  ln -s /Applications build/dmg/Applications
hdiutil create -volname "MacSlide" -srcfolder build/dmg -ov -format UDZO build/MacSlide.dmg
```

Output:

- `MySlidePad/build/MacSlide.dmg`
