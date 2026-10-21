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

The app stores favourites, preferences, and singing history on-device. Audio can stream from a direct HTTPS URL or be downloaded individually for app-private offline playback. No account, analytics, advertising, or remote catalogue update service is configured in this initial build.