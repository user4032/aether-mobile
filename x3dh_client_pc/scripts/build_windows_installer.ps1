Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location "$PSScriptRoot\.."

Write-Host "[1/3] Fetching dependencies..."
flutter pub get

Write-Host "[2/3] Building Windows release..."
flutter build windows --release

Write-Host "[3/3] Building installer (Inno Setup)..."
$inno = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (!(Test-Path $inno)) {
  throw "Inno Setup not found. Install Inno Setup 6 and retry."
}

& $inno "installer\windows\aether_desktop.iss"
Write-Host "Done. Installer is in build\installer"
