# PCG Hymns Content Studio

The admin dashboard manages verified hymn content, source PDFs, and publication to the mobile app.

## Run locally

```sh
npm install
cp .env.example .env.local
# Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in .env.local
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). Create a Supabase project and apply the setup in [`../supabase/README.md`](../supabase/README.md) before signing in. Only accounts explicitly added to `admin_users` can access the cloud dashboard. Never put a Supabase service-role/secret key in this app.

## Deploy to Vercel

1. Import this repository into Vercel and set the project **Root Directory** to `admin`. Leave the framework preset, install command, and build command at their Next.js defaults.
2. Add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` from your Supabase project settings to the Vercel project's environment variables. Add them to each environment you plan to use (Production, Preview, and/or Development). Do not add a service-role/secret key.
3. Deploy the project. Vercel will build the admin app and automatically create deployments for subsequent pushes to the connected Git branch.
4. In Supabase Authentication URL Configuration, set the **Site URL** to the production Vercel URL. Add any Vercel preview URLs as redirect URLs if you use authentication flows that redirect users.

Only accounts explicitly added to Supabase's `admin_users` table can access the cloud dashboard. Apply the database and storage setup in [`../supabase/README.md`](../supabase/README.md) before using it.

## Import and publish

- Select multiple PDFs in one batch (50 MB per PDF). Selectable text is extracted in the browser, and the original PDFs are stored in a private Supabase Storage bucket. Scanned/image-only PDFs need OCR and are not supported yet.
- Each PDF becomes a reviewable source item. **Create draft hymn** opens its extracted text in the hymn editor; a whole-book PDF must be split into individual hymn entries and checked manually. PDF text is not automatically treated as verified content.
- Edit, search, filter, and validate catalogue entries. Changes are saved locally in the browser until you choose **Save draft to cloud**.
- Use **Upload audio** beside any hymn to add MP3, M4A, AAC, WAV, OGG, or FLAC recordings (up to 100 MB), select the recording style, and attach the resulting playback URL to that hymn. The editor also supports adding recordings while creating or editing a hymn. Audio playback is public for the app; only admins can upload audio. These changes update the local catalogue draft; choose **Save draft to cloud**, then **Publish to app** to make the recording available to mobile users. Apply or rerun the hymn-audio migration described in [`../supabase/README.md`](../supabase/README.md) before enabling uploads.
- For Twi entries, legacy text codes are converted in title/lyrics metadata fields: `4` → `ɔ`, `1` → `ɛ`, and `$` → `Ɔ`. Hymn numbers and stable IDs are not converted.
- **Publish to app** replaces the current published catalogue. The mobile app fetches published updates and keeps the last valid copy for offline use.
- Import/export `catalogue.json` remains available for working without Supabase or preparing a bundled release.

Check every extracted word, hymn boundary, number, language, attribution, and distribution permission before publishing. See the repository's [content guide](../CONTENT_GUIDE.md).
