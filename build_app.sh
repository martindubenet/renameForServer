#!/bin/zsh
# Builds RenameForServer.app next to this script. Needs the Xcode Command Line Tools.
# Run it again after any change to RenameForServerApp/.
set -euo pipefail
cd "$(dirname "$0")"
NAME="RenameForServer"
APP="$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/$NAME" "${NAME}App/main.swift"
cp "${NAME}App/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"   # ad-hoc signature, enough for a locally built app
echo "Built: $PWD/$APP"
