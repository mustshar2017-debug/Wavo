# WAVO Mobile

Flutter application for Android and iOS. This is a new mobile client; the existing web application at the repository root is left unchanged.

## Current connection

- Supabase URL: `https://jajaujilwhkroboyhenj.supabase.co`
- Storage bucket: `videos`
- Supabase client key: the public publishable key currently used by the WAVO web client.

The publishable key is intentionally a client-side key. Never put a Supabase service-role key or an AI provider secret in this app. Keep privileged operations in Supabase Edge Functions.

## Run locally

1. Install Flutter stable and the Android/iOS toolchains.
2. From this directory run:

   ```bash
   flutter pub get
   flutter run
   ```

3. For Android: `flutter build apk --release`
4. For iOS: `flutter build ipa --release` (requires macOS and Xcode).

## First mobile milestone

- Vertical video feed backed by the existing public `videos` bucket.
- Email sign-in and sign-up through the existing Supabase Auth project.
- Video upload from the phone gallery.
- Arabic-first WAVO dark/turquoise visual identity.

## Important backend notes

The existing web client uses tables including `wavo_profiles`, `wavo_follows`, `wavo_messages`, and `wavo_notifications`. This first mobile scaffold deliberately does not fake likes, comments, or social actions in local state. Those features should be connected only after the actual table definitions and Row Level Security policies have been verified.

Before public launch, verify Storage policies, Auth redirect URLs, privacy/terms pages, moderation/reporting workflows, push-notification credentials, and Apple/Google store requirements.
