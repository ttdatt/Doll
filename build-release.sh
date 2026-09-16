#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

readonly identity="${DOLL_SIGN_IDENTITY:-Apple Development: trantiendat1508@gmail.com (C3XZD4SK3G)}"
readonly app="$PWD/.build/release/Build/Products/Release/Doll.app"
readonly archive="$PWD/dist/Doll.zip"

xcodebuild \
  -project Doll.xcodeproj \
  -scheme Doll \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/release \
  MACOSX_DEPLOYMENT_TARGET=12.0 \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$identity" \
  build

codesign --verify --strict --verbose=2 "$app"

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"

echo "Built: $app"
echo "Archive: $archive"
