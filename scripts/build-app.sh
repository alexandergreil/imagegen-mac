#!/usr/bin/env bash
# Builds build/ImageGen.app: the SwiftUI app, the Python engine sources and a bundled uv binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ImageGen.app"
VERSION="$(grep -m1 '^version' "$ROOT/backend/pyproject.toml" | cut -d'"' -f2)"

echo "Building Swift app..."
swift build -c release --package-path "${ROOT}/app" --arch arm64
BIN="$(swift build -c release --package-path "${ROOT}/app" --arch arm64 --show-bin-path)/ImageGen"

echo "Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/backend"
cp "$BIN" "$APP/Contents/MacOS/ImageGen"

# Engine sources and lockfile. The venv itself is created on first launch in Application Support.
(cd "$ROOT/backend" && uv lock --check >/dev/null 2>&1 || uv lock)
cp "$ROOT/backend/pyproject.toml" "$ROOT/backend/uv.lock" "$APP/Contents/Resources/backend/"
rsync -a --exclude '__pycache__' "$ROOT/backend/imagegen" "$APP/Contents/Resources/backend/"

UV="$(command -v uv || true)"
if [[ -z "$UV" ]]; then
  echo "uv not found. Install it with: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi
cp "$UV" "$APP/Contents/Resources/bin/uv"
mkdir -p "$APP/Contents/Resources/licenses/uv"
cp "$ROOT/third_party/uv/"LICENSE-* "$APP/Contents/Resources/licenses/uv/"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/licenses/"

ICON_LINE=""
if [[ -f "$ROOT/app/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/app/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  ICON_LINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ImageGen</string>
  <key>CFBundleDisplayName</key><string>ImageGen</string>
  <key>CFBundleIdentifier</key><string>com.philippbaldauf.ImageGen</string>
  <key>CFBundleExecutable</key><string>ImageGen</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
  <key>NSHighResolutionCapable</key><true/>
  $ICON_LINE
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "Done: $APP"
