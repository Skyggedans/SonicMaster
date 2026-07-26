<#
  Build a Windows NSIS installer for SonicMaster. Run ON Windows.

    powershell -ExecutionPolicy Bypass -File tools\package\windows-nsis.ps1
    # -> dist\SonicMaster-<version>-windows-x64-setup.exe

  Needs Flutter (Windows desktop enabled) and makensis (NSIS) on PATH
  (install NSIS: `choco install nsis`, `winget install NSIS.NSIS`, or
  https://nsis.sourceforge.io). The installer is per-machine (Program Files,
  requires elevation), with Start-menu + desktop shortcuts and an
  Add/Remove-Programs uninstaller.
#>
$ErrorActionPreference = 'Stop'

$Root   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$App    = Join-Path $Root 'app'
$Dist   = Join-Path $Root 'dist'
$Nsi    = Join-Path $Root 'tools\package\windows\sonicmaster.nsi'
$Icon   = Join-Path $App  'windows\runner\resources\app_icon.ico'
$Bundle = Join-Path $App  'build\windows\x64\runner\Release'

$m = Select-String -Path (Join-Path $App 'pubspec.yaml') -Pattern '^version:\s*(\S+)'
$Version = ($m.Matches[0].Groups[1].Value) -replace '\+.*$', ''

if (-not (Get-Command makensis -ErrorAction SilentlyContinue)) {
  Write-Error "makensis (NSIS) not found on PATH. Install NSIS: 'choco install nsis' / 'winget install NSIS.NSIS'."
}

Write-Host "==> flutter build windows --release (v$Version)"
Push-Location $App
try { flutter build windows --release } finally { Pop-Location }

$Exe = Join-Path $Bundle 'sonicmaster.exe'
if (-not (Test-Path $Exe)) { Write-Error "Release bundle not found: $Exe" }

# Ship the licenses inside the install (the .nsi copies the whole bundle dir).
Copy-Item (Join-Path $Root 'LICENSE') -Destination $Bundle -Force
Copy-Item (Join-Path $Root 'THIRD_PARTY_NOTICES.md') -Destination $Bundle -Force

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$Out = Join-Path $Dist "SonicMaster-$Version-windows-x64-setup.exe"

Write-Host "==> makensis"
& makensis "/DVERSION=$Version" "/DBUNDLE=$Bundle" "/DICON=$Icon" "/DOUTFILE=$Out" $Nsi
if ($LASTEXITCODE -ne 0) { Write-Error "makensis failed (exit $LASTEXITCODE)" }

Write-Host "==> Done: $Out"
