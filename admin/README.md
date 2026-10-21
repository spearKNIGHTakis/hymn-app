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

## Import and publish

- Select multiple PDFs in one batch (50 MB per PDF). Selectable text is extracted in the browser, and the original PDFs are stored in a private Supabase Storage bucket. Scanned/image-only PDFs need OCR and are not supported yet.
- Each PDF becomes a reviewable source item. **Create draft hymn** opens its extracted text in the hymn editor; a whole-book PDF must be split into individual hymn entries and checked manually. PDF text is not automatically treated as verified content.
- Edit, search, filter, and validate catalogue entries. Changes are saved locally in the browser until you choose **Save draft to cloud**.
- **Publish to app** replaces the current published catalogue. The mobile app fetches published updates and keeps the last valid copy for offline use.
- Import/export `catalogue.json` remains available for working without Supabase or preparing a bundled release.

Check every extracted word, hymn boundary, number, language, attribution, and distribution permission before publishing. See the repository's [content guide](../CONTENT_GUIDE.md).
