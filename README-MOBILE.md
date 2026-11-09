# WAVO Mobile

This branch packages the existing WAVO web experience as a shared Android/iOS app using Capacitor.

## Prerequisites
- Node.js 20+
- Android Studio + Android SDK for Android builds
- macOS + Xcode for iOS builds

## Setup
```bash
npm install
npx cap add android
npx cap add ios
npx cap sync
```

## Open native projects
```bash
npx cap open android
npx cap open ios
```

## Updating the app
The bundled app entry point is `www/index.html`. After changing it, run:
```bash
npx cap sync
```

## Important
- The existing Supabase-backed WAVO features and current UI are retained in the bundled web app.
- Android APK signing and Play Store release require a release keystore and Play Console account.
- iOS App Store release requires macOS/Xcode, Apple Developer membership, signing certificates, and provisioning.
- Do not put Supabase service-role keys or AI provider secrets in this repository or client app. Keep them in Supabase Edge Function secrets.
