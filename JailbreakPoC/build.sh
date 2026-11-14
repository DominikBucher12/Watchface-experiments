#!/usr/bin/env zsh
# Build the Jailbreak PoC Watch App for watchOS 27.0.1
# Ensure you have Xcode 27 installed and the watchOS SDK available.

# Set the project and scheme names
PROJECT="JailbreakPoC.xcodeproj"
SCHEME="JailbreakPoC"

# Destination: generic platform watchOS
DEST="generic/platform=watchOS"

# Build command
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" -configuration Release

if [[ $? -ne 0 ]]; then
    echo "Build failed"
else
    echo "Build succeeded – the binary is in Products/JailbreakPoC.app"
fi
