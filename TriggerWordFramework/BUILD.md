# Build Settings
Product -> Archive

```bash
xcodebuild archive \
  -scheme TriggerWordFramework \
  -destination "generic/platform=iOS Simulator" \
  -archivePath ./build/TriggerWordFramework-Sim \
  SKIP_INSTALL=NO \
  BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
```

```bash
xcodebuild -create-xcframework \
    -framework /Users/luke/Library/Developer/Xcode/Archives/2025-06-11/TriggerWordFramework\ 6-11-25\,\ 10.10 PM.xcarchive/Products/Library/Frameworks/TriggerWordFramework.framework/ \
    -framework "./build/TriggerWordFramework-Sim.xcarchive/Products/Library/Frameworks/TriggerWordFramework.framework" \
    -output "./build/TriggerWordFramework.xcframework"
```
