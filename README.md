# PCG Hymns

An offline-first digital hymnbook for verified English and Twi content. The catalogue starts empty intentionally; no official hymn text, numbering, recording, church logo, or endorsement is bundled.

## Development

Install Flutter (including Android toolchain support), then run:

```sh
flutter pub get
dart format .
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is produced at `build/app/outputs/flutter-apk/app-debug.apk` when the Android build succeeds.

## Content

See [CONTENT_GUIDE.md](CONTENT_GUIDE.md) for the JSON schema, exact steps to add verified English/Twi entries and male solo, female solo, choir, congregation, or instrumental audio, and publishing/permission notes. Update `assets/catalogue.json`; do not edit the UI for new content.

## Admin and online catalogue

The Next.js admin lives in [`admin/`](admin/). It supports batch PDF source uploads, text extraction for human review, draft editing, and publishing to Supabase. See [`supabase/README.md`](supabase/README.md) to create a project, apply the database/storage policies, provision an admin, and configure both clients. The Flutter app continues to work offline using its bundled catalogue and the last valid published copy.

The Android launcher icon is an original open hymnbook and music note design. Its SVG source is [`assets/brand/app_icon.svg`](assets/brand/app_icon.svg); Android density and adaptive icon assets are generated from that source.

The app stores favourites, preferences, and singing history on-device. Audio can stream from a direct HTTPS URL or be downloaded individually for app-private offline playback. No analytics or advertising are configured.