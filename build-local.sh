#!/bin/bash
# =====================================================
# Rdp Virtual Box App — Yerel Derleme Scripti
# =====================================================
# Kullanim: ./build-local.sh [target]
#   target: client (default), server, all
#
# Bu script ISCC + amake/innosetup Docker image kullanarak
# setup.exe dosyalarini uretir. PowerShell test/lint adimlari
# icin ./test-local.sh scriptini calistirin.
#
# Gereksinimler:
#   - macOS (Intel veya Apple Silicon) veya Linux
#   - Docker (macOS icin Docker Desktop veya OrbStack)
#
# Not: Apple Silicon'da ilk calistirma 5-10 dakika surebilir
# (Wine prefix baslatma emulasyon nedeniyle yavas). Intel Mac
# veya Windows + WSL2 uzerinde ~30-60s icinde tamamlanir.
# =====================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DOCKER_IMAGE="amake/innosetup:innosetup6-bookworm"
ISS_CLIENT="src/inno/RdpVirtualBoxApp-Client.iss"
ISS_SERVER="src/inno/RdpVirtualBoxApp-Server.iss"
ISS_FALLBACK_CLIENT="build/client.iss"
ISS_FALLBACK_SERVER="build/server.iss"
OUTPUT_DIR="build/output"
WORK_MOUNT="/work"
USER_FLAG="--user 1000:1000"

# Renkli cikti
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

# Docker kontrol
if ! command -v docker >/dev/null 2>&1; then
  err "Docker bulunamadi. Lutfen Docker Desktop veya OrbStack kurun."
  exit 1
fi

# Image var mi?
if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
  log "Docker image indiriliyor: $DOCKER_IMAGE (~500 MB)"
  docker pull "$DOCKER_IMAGE"
fi

# Build/output dizini hazirla
mkdir -p "$OUTPUT_DIR"
chmod 777 "$OUTPUT_DIR" 2>/dev/null || true

build_setup() {
  local iss_src="$1"
  local iss_name="$2"
  log "$iss_name derleniyor..."

  # Once orijinali dene
  if docker run --rm -i $USER_FLAG \
       -v "$SCRIPT_DIR:$WORK_MOUNT" \
       "$DOCKER_IMAGE" \
       "$WORK_MOUNT/$iss_src" 2>&1 | tee /tmp/iscc_$iss_name.log | tail -10; then

    # /work/Output dizininden al
    if [ -d "Output" ] && [ -n "$(ls Output/*.exe 2>/dev/null)" ]; then
      mv -f Output/*.exe "$OUTPUT_DIR/" 2>/dev/null || true
      rmdir Output 2>/dev/null || true
    fi
    log "$iss_name basariyla derlendi (orijinal .iss)"
    return 0
  else
    warn "Orijinal $iss_name.iss derlenemedi, minimal fallback yaziliyor..."
    tail -20 /tmp/iscc_$iss_name.log
    return 1
  fi
}

build_fallback() {
  local iss_fallback="$1"
  local iss_name="$2"
  log "$iss_name minimal fallback derleniyor..."

  docker run --rm -i $USER_FLAG \
    -v "$SCRIPT_DIR:$WORK_MOUNT" \
    "$DOCKER_IMAGE" \
    "$WORK_MOUNT/$iss_fallback" 2>&1 | tee /tmp/iscc_$iss_name.log | tail -10

  if [ -d "Output" ] && [ -n "$(ls Output/*.exe 2>/dev/null)" ]; then
    mv -f Output/*.exe "$OUTPUT_DIR/" 2>/dev/null || true
    rmdir Output 2>/dev/null || true
    log "$iss_name minimal fallback basariyla derlendi"
  else
    err "$iss_name derlenemedi! Log: /tmp/iscc_$iss_name.log"
    return 1
  fi
}

TARGET="${1:-all}"
log "Hedef: $TARGET"

case "$TARGET" in
  client|all)
    if ! build_setup "$ISS_CLIENT" "Client"; then
      build_fallback "$ISS_FALLBACK_CLIENT" "Client"
    fi
    ;;
esac

case "$TARGET" in
  server|all)
    if ! build_setup "$ISS_SERVER" "Server"; then
      build_fallback "$ISS_FALLBACK_SERVER" "Server"
    fi
    ;;
esac

# Sonuc
echo ""
log "================================================"
log "Derleme tamamlandi. Setup dosyalari:"
ls -la "$OUTPUT_DIR"/*.exe 2>/dev/null || warn "Hiç setup.exe uretilmedi!"
log "================================================"

# SHA256SUMS
if ls "$OUTPUT_DIR"/*.exe >/dev/null 2>&1; then
  log "SHA256SUMS.txt olusturuluyor..."
  cd "$OUTPUT_DIR"
  : > SHA256SUMS.txt
  for f in *.exe; do
    if command -v sha256sum >/dev/null; then
      sha256sum "$f" >> SHA256SUMS.txt
    else
      shasum -a 256 "$f" >> SHA256SUMS.txt
    fi
  done
  cat SHA256SUMS.txt
  cd "$SCRIPT_DIR"
  log "SHA256SUMS.txt: $OUTPUT_DIR/SHA256SUMS.txt"
fi
