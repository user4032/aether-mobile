# x3dh_client

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Deploy on Vercel

This repository is configured for Vercel in the root `vercel.json` file.

### Notes

- Vercel deploys only the Flutter Web client (`x3dh_client`).
- The Socket.IO backend (`index.js`) should be deployed separately (for example Render/Railway/VM).

### Required Vercel environment variables (if email verification is used on backend)

- `EMAIL_USER`
- `EMAIL_PASS`
