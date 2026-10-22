# Supabase setup

The PCG Hymns app reads the public published catalogue anonymously. The admin requires Supabase email/password authentication plus an explicit `admin_users` membership. Source PDFs and extracted text are private to admins.

## Create and configure a project

1. Create a Supabase project. Keep its database password and any `service_role`/secret key private; neither app uses a service key.
2. Run [`migrations/202610210001_catalogue.sql`](./migrations/202610210001_catalogue.sql), [`migrations/202610210002_hymn_audio.sql`](./migrations/202610210002_hymn_audio.sql), and [`migrations/202610220001_recordings.sql`](./migrations/202610220001_recordings.sql) in order in the Supabase SQL Editor. If the first two migrations are already applied, run only the recordings migration.
3. In **Authentication → Providers**, enable Email and disable public signups. Invite/create each admin account from the Supabase dashboard.
4. In **Authentication → Users**, copy the invited user's UUID. Add that user to the admin allowlist in the SQL Editor:

   ```sql
   insert into public.admin_users (user_id)
   values ('PASTE_AUTH_USER_UUID_HERE');
   ```

   Do not accept admin membership from a browser/client. Only project owners should add or remove rows in `admin_users`.
5. Copy the project URL and publishable key from the Supabase API settings into `admin/.env.local` using [`admin/.env.example`](../admin/.env.example). Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Restart the admin dev server after changing environment variables.
6. Sign into the admin with the invited account. Import a catalogue or create a draft, then choose **Save draft to cloud**. Check the extracted PDF text and all permission/attribution information, then explicitly choose **Publish to app**.
7. To build/run the Flutter app with online sync, provide the same public values as compile-time defines:

   ```sh
   flutter run \
     --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=your-project-publishable-key
   ```

   For a release build, pass the same defines to `flutter build apk` (or the target platform's build command). Existing builds may continue using `SUPABASE_ANON_KEY`. These are public client values; never pass a service-role/secret key to Flutter.

## Data and access model

- `catalogue_versions` has separate `draft` and `published` rows. Anonymous users can read only the published row. Admins can save drafts and publish updates.
- `admin_users` is a project-owner-managed allowlist. RLS uses `is_catalogue_admin()` to guard catalogue writes, PDF metadata, and Storage objects.
- `source-pdfs` is a private bucket restricted to admins. The dashboard extracts selectable PDF text in the browser and stores both the source PDF and extracted text for review. A PDF import does not publish or automatically approve content.
- `hymn_recordings` stores uploaded recording metadata. Hymns are currently stable text IDs embedded in `catalogue_versions` JSON, not rows in a `hymns` table, so `hymn_id` is indexed text and cannot have a relational foreign key. RLS restricts all table access to `admin_users` members.
- The `hymn-audio` bucket is private and accepts MP3 uploads up to 100 MB. Only authenticated catalogue admins can upload, update, or delete objects. Anonymous playback is permitted only when a recording's Storage path and ID are part of the published catalogue and match a `hymn_recordings` row. Flutter requests a one-hour signed URL with the public Supabase key after loading the published catalogue.
- The recordings migration converts existing dashboard-generated `hymn-audio` public URLs in cloud draft/published catalogues to Storage paths before making the bucket private. New uploads insert a `hymn_recordings` row; save the draft to cloud and explicitly publish it before the Flutter app can play the recording. Removing a recording from a draft does not delete its stored file or metadata row.
- The app requests the published row on launch, resolves published Storage paths to signed URLs, validates schema version 1, caches the last valid catalogue without signed URLs, and falls back to the cache or bundled catalogue when offline. Existing downloaded audio remains available offline; streaming-only recordings require an online refresh to obtain a new signed URL.

The dashboard currently makes one draft and one published slot rather than keeping release history. Export a JSON backup before major changes. Configure Supabase database backups and project access separately for production.
