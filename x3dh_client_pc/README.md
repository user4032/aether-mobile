# x3dh_client_pc

Separate desktop client project (Windows/Linux/macOS) for installer distribution.

## Purpose

- `x3dh_client` stays your web/PWA-oriented client.
- `x3dh_client_pc` is the dedicated desktop app folder for installer builds.

## Run Desktop App

```bash
cd x3dh_client_pc
flutter pub get
flutter run -d windows
```

## Build Windows Installer

Prerequisites:

- Flutter SDK in PATH
- Inno Setup 6 installed

Command:

```powershell
cd x3dh_client_pc
powershell -ExecutionPolicy Bypass -File .\scripts\build_windows_installer.ps1
```

Output installer:

- `x3dh_client_pc/build/installer/LumynMessengerSetup.exe`
