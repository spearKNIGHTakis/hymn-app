begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'hymn-audio',
  'hymn-audio',
  true,
  104857600,
  array[
    'audio/mpeg',
    'audio/mp4',
    'audio/aac',
    'audio/wav',
    'audio/x-wav',
    'audio/ogg',
    'audio/flac'
  ]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can listen to hymn audio"
on storage.objects;
drop policy if exists "Admins can upload hymn audio"
on storage.objects;
drop policy if exists "Admins can update hymn audio"
on storage.objects;
drop policy if exists "Admins can delete hymn audio"
on storage.objects;

create policy "Anyone can listen to hymn audio"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'hymn-audio');

create policy "Admins can upload hymn audio"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'hymn-audio'
  and (select public.is_catalogue_admin())
);

create policy "Admins can update hymn audio"
on storage.objects for update
to authenticated
using (
  bucket_id = 'hymn-audio'
  and (select public.is_catalogue_admin())
)
with check (
  bucket_id = 'hymn-audio'
  and (select public.is_catalogue_admin())
);

create policy "Admins can delete hymn audio"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'hymn-audio'
  and (select public.is_catalogue_admin())
);

commit;
