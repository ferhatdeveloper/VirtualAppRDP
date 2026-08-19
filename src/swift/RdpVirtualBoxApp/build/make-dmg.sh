#!/usr/bin/env bash
# =====================================================================
#  make-dmg.sh
#  Rdp Virtual Box App - macOS Native Client
#
#  swift build ciktisini RdpVirtualBoxApp.app bundle haline getirir ve
#  UDZO formatinda DMG olusturur. GitHub Actions build-macos job'u
#  tarafindan cagirilir:
#    bash src/swift/RdpVirtualBoxApp/build/make-dmg.sh \
#      --version "$CLEAN_VERSION" --output build/output
# =====================================================================
set -euo pipefail

VERSION=""
OUTPUT_DIR=""

usage() {
  echo "Usage: $0 --version <version> --output <dir>" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2-}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "${VERSION}" || -z "${OUTPUT_DIR}" ]]; then
  usage
fi

# Leading 'v' prefix'ini kaldir (v1.0.1 -> 1.0.1)
VERSION="${VERSION#v}"

# Branch adi (main) veya semver olmayan degerler icin varsayilan
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-].*)?$ ]]; then
  echo "Version '${VERSION}' is not numeric (e.g. 1.0.1); defaulting to 1.0.1"
  VERSION="1.0.1"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --output relative ise cagiranin CWD'sine gore mutlak yola cevir
if [[ "${OUTPUT_DIR}" != /* ]]; then
  OUTPUT_DIR="$(pwd)/${OUTPUT_DIR}"
fi
mkdir -p "${OUTPUT_DIR}"

echo "==> Building release (package: ${PKG_DIR}, version: ${VERSION})"
swift build -c release --package-path "${PKG_DIR}"

BIN_DIR="$(swift build -c release --package-path "${PKG_DIR}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/RdpVirtualBoxApp"
if [[ ! -f "${BIN_PATH}" ]]; then
  echo "ERROR: release binary not found at ${BIN_PATH}" >&2
  exit 1
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/rdpvb-dmg.XXXXXX")"
cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT

APP_DIR="${STAGE}/RdpVirtualBoxApp.app"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/RdpVirtualBoxApp"
chmod +x "${APP_DIR}/Contents/MacOS/RdpVirtualBoxApp"

RES_SRC="${PKG_DIR}/Sources/RdpVirtualBoxApp/Resources"
if [[ -d "${RES_SRC}" ]]; then
  echo "==> Copying Resources from ${RES_SRC}"
  cp -R "${RES_SRC}/." "${APP_DIR}/Contents/Resources/"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>tr</string>
  <key>CFBundleDisplayName</key>
  <string>Rdp Virtual Box App</string>
  <key>CFBundleExecutable</key>
  <string>RdpVirtualBoxApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.rdpvirtualboxapp.client</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>RdpVirtualBoxApp</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

DMG_NAME="RdpVirtualBoxApp-Client-macOS-v${VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

echo "==> Creating UDZO DMG: ${DMG_PATH}"
hdiutil create \
  -volname "Rdp Virtual Box App" \
  -srcfolder "${STAGE}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "==> DMG ready: ${DMG_PATH}"
ls -lh "${DMG_PATH}"
