# Adding Verified Hymn Content

The bundled catalogue is `assets/catalogue.json`. It is deliberately empty until verified text and permissions are supplied. `assets/catalogue.sample.json` contains two clearly marked development-only examples and is not loaded by the app. Do not add unverified hymn words, numbering, recordings, or attribution. The app treats the JSON file as content, so adding hymns does not require editing a screen or model.

## Schema

The root object requires `schemaVersion` (currently `1`) and a `hymns` array. Each hymn requires a unique, stable `id`, `number`, `title`, `language` (`english` or `twi`), and a `stanzas` array. Keep stanza breaks as separate array elements and preserve each stanza's line breaks with `\n`. Optional fields are `chorus`, `author`, `composer`, `source`, `copyright`, `attribution`, `permission`, `artwork`, and `recordings`.

Example structure (all values below are instructional placeholders, not hymn content):

```json
{
  "schemaVersion": 1,
  "catalogueVersion": "2026-01",
  "hymns": [
    {
      "id": "english-example-001",
      "number": "001",
      "title": "Verified title goes here",
      "language": "english",
      "stanzas": ["Verified first line\\nVerified second line", "Verified next stanza"],
      "chorus": "Optional verified chorus",
      "author": "Optional author",
      "composer": "Optional composer",
      "source": "Source details",
      "copyright": "Copyright notice",
      "attribution": "Required attribution",
      "permission": "Permission or licence details",
      "recordings": [
        {
          "id": "english-example-001-choir-v1",
          "type": "choir",
          "url": "https://example.org/audio/english-example-001-choir.mp3",
          "durationSeconds": 180,
          "fileSizeBytes": 4500000,
          "attribution": "Recording attribution",
          "permission": "Permission to stream and distribute"
        }
      ]
    }
  ]
}
```

## Add a hymn

1. Verify the hymn number, exact title, language, lyrics, stanza breaks, and any chorus against your authorised source.
2. Add an object to `hymns`. Use a permanent ID that will not change if the title or numbering is corrected. Use `english` or `twi` for language.
3. Put each complete stanza in its own `stanzas` string. Preserve line breaks with JSON `\n`; do not reword or normalise spelling.
4. Include source, copyright, attribution, and permission fields whenever applicable. Confirm that the text and any arrangement may be distributed.
5. Save valid JSON and run `flutter test` before publishing an app build.

## Attach recordings

Add one recording object for each available version. `type` must be `maleSolo`, `femaleSolo`, `choir`, `congregation`, or `instrumental`. Give each recording a globally unique stable ID. Set `url` to a public HTTPS audio file, and include duration, size, attribution, and permission metadata when known. For example, a female solo uses `"type": "femaleSolo"`; a choir uses `"type": "choir"`. Keep files on HTTPS static hosting with a direct audio-file URL and confirm streaming and download rights before publication.

The app streams from HTTPS and offers an individual download for each recording. Downloaded files are kept in the app's documents directory and take precedence during playback. Downloads are written to a temporary file, checked for a successful HTTP response and non-empty complete transfer, then renamed and recorded locally. Removing a download deletes only that app-owned file. Catalogue lyrics and user preferences remain available offline; no remote catalogue-update service is configured in this initial version.

## Publish updates

The current first release bundles `assets/catalogue.json`, so publishing changed content requires validating and rebuilding the app. A future remote catalogue can be hosted as a versioned static JSON file over HTTPS (for example, GitHub Pages or Cloudflare Pages); implement schema validation and retain the last valid downloaded catalogue before enabling updates. Do not put hosting credentials or private keys in the app. Confirm text, arrangement, recording, attribution, and download permissions with the relevant rights holders before publishing.