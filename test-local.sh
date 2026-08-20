#!/bin/bash
# =====================================================
# Rdp Virtual Box App — Yerel Test/Lint Scripti
# =====================================================
# Kullanim: ./test-local.sh
#   - PowerShell scriptlerini parse eder (syntax check)
#   - PSScriptAnalyzer ile lint yapar
#   - Pester testlerini calistirir
#
# Gereksinimler:
#   - macOS veya Linux
#   - PowerShell 7+ (brew install --cask powershell)
# =====================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[TEST]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

# PowerShell kontrol
if ! command -v pwsh >/dev/null 2>&1; then
  err "pwsh bulunamadi."
  echo ""
  echo "  macOS:  brew install --cask powershell"
  echo "  Ubuntu: sudo apt-get install -y powershell"
  exit 1
fi

# 1. PowerShell syntax check
log "PowerShell syntax check..."
SYNTAX_ERRORS=$(pwsh -NoProfile -Command '
$ErrorActionPreference = "Stop"
$scripts = Get-ChildItem -Path src/powershell -Filter *.ps1 -Recurse -File
$errors = 0
foreach ($s in $scripts) {
    $tokens = $null; $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        Write-Host "  ERR $($s.Name): $($parseErrors[0].Message)" -ForegroundColor Red
        $errors++
    }
}
if ($errors -gt 0) { exit 1 } else { Write-Host "  Tum scriptler temiz" -ForegroundColor Green }
')
if [ $? -ne 0 ]; then
  err "PowerShell syntax hatalari var!"
  exit 1
fi

# 2. PSScriptAnalyzer (opsiyonel - kuruluysa)
log "PSScriptAnalyzer (varsa)..."
if pwsh -NoProfile -Command 'Get-Module PSScriptAnalyzer -ListAvailable' 2>/dev/null | grep -q PSScriptAnalyzer; then
  pwsh -NoProfile -Command '
    Import-Module PSScriptAnalyzer
    $results = Invoke-ScriptAnalyzer -Path ./src -Recurse
    $errCount = ($results | Where-Object { $_.Severity -eq "Error" }).Count
    $warnCount = ($results | Where-Object { $_.Severity -eq "Warning" }).Count
    Write-Host "  Errors: $errCount, Warnings: $warnCount"
    if ($errCount -gt 0) {
      $results | Where-Object { $_.Severity -eq "Error" } | ForEach-Object {
        Write-Host "  [$($_.Severity)] $($_.ScriptName):$($_.Line) - $($_.Message)" -ForegroundColor Red
      }
      exit 1
    }
  ' || warn "PSScriptAnalyzer errors var ama devam ediliyor"
else
  warn "PSScriptAnalyzer kurulu degil, atlaniyor. Kurmak icin:"
  echo "    pwsh -NoProfile -Command 'Install-Module PSScriptAnalyzer -Scope CurrentUser -Force'"
fi

# 3. Pester (opsiyonel - kuruluysa)
log "Pester testleri (varsa)..."
if pwsh -NoProfile -Command 'Get-Module Pester -ListAvailable' 2>/dev/null | grep -q Pester; then
  pwsh -NoProfile -Command '
    Import-Module Pester
    $config = New-PesterConfiguration
    $config.Run.Path = "./tests"
    $config.Output.Verbosity = "Normal"
    Invoke-Pester -Configuration $config
  ' || warn "Pester testleri basarisiz oldu"
else
  warn "Pester kurulu degil, atlaniyor. Kurmak icin:"
  echo "    pwsh -NoProfile -Command 'Install-Module Pester -Scope CurrentUser -Force'"
fi

log "Tum test/lint adimlari tamamlandi."