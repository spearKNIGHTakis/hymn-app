begin;

create table if not exists public.hymn_recordings (
  id uuid primary key default gen_random_uuid(),
  hymn_id text not null check (length(btrim(hymn_id)) > 0),
  storage_path text not null unique check (length(btrim(storage_path)) > 0),
  language text not null check (language in ('english', 'twi')),
  recording_type text not null check (
    recording_type in ('maleSolo', 'femaleSolo', 'choir', 'congregation', 'instrumental')
  ),
  file_size_bytes bigint check (file_size_bytes is null or file_size_bytes > 0),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists hymn_recordings_hymn_id_idx
  on public.hymn_recordings (hymn_id);

alter table public.hymn_recordings enable row level security;
revoke all on public.hymn_recordings from anon, authenticated;

create policy "Admins can manage hymn recordings"
on public.hymn_recordings for all
to authenticated
using ((select public.is_catalogue_admin()))
with check ((select public.is_catalogue_admin()));

grant select, insert, update, delete on public.hymn_recordings to authenticated;

create or replace function public.is_published_hymn_audio(object_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.catalogue_versions published
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(published.content -> 'hymns') = 'array'
          then published.content -> 'hymns'
        else '[]'::jsonb
      end
    ) hymn(value)
    join public.hymn_recordings recording_row
      on recording_row.hymn_id = hymn.value ->> 'id'
    where published.channel = 'published'
      and recording_row.storage_path = object_path
      and exists (
        select 1
        from jsonb_array_elements(
          case
            when jsonb_typeof(hymn.value -> 'recordings') = 'array'
              then hymn.value -> 'recordings'
            else '[]'::jsonb
          end
        ) catalogue_recording(value)
        where catalogue_recording.value ->> 'id' = recording_row.id::text
          and catalogue_recording.value ->> 'storagePath' = recording_row.storage_path
      )
  );
$$;

revoke all on function public.is_published_hymn_audio(text) from public;
grant execute on function public.is_published_hymn_audio(text) to anon, authenticated;

-- Migrate dashboard-created public audio URLs to private object references.
with legacy_recordings as (
  select
    recording.value as recording,
    hymn.value as hymn,
    split_part(
      recording.value ->> 'url',
      '/storage/v1/object/public/hymn-audio/',
      2
    ) as storage_path
  from public.catalogue_versions catalogue
  cross join lateral jsonb_array_elements(catalogue.content -> 'hymns') hymn(value)
  cross join lateral jsonb_array_elements(
    case
      when jsonb_typeof(hymn.value -> 'recordings') = 'array'
        then hymn.value -> 'recordings'
      else '[]'::jsonb
    end
  ) recording(value)
  where catalogue.channel in ('draft', 'published')
    and recording.value ->> 'url' like '%/storage/v1/object/public/hymn-audio/%'
    and recording.value ->> 'id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    and hymn.value ->> 'language' in ('english', 'twi')
    and recording.value ->> 'type' in (
      'maleSolo', 'femaleSolo', 'choir', 'congregation', 'instrumental'
    )
    and split_part(
      recording.value ->> 'url',
      '/storage/v1/object/public/hymn-audio/',
      2
    ) <> ''
)
insert into public.hymn_recordings (
  id,
  hymn_id,
  storage_path,
  language,
  recording_type,
  file_size_bytes
)
select
  (recording ->> 'id')::uuid,
  hymn ->> 'id',
  storage_path,
  hymn ->> 'language',
  recording ->> 'type',
  case
    when recording ->> 'fileSizeBytes' ~ '^[1-9][0-9]*$'
      then (recording ->> 'fileSizeBytes')::bigint
    else null
  end
from legacy_recordings
on conflict (storage_path) do nothing;

update public.catalogue_versions catalogue
set content = jsonb_set(
  catalogue.content,
  '{hymns}',
  (
    select coalesce(
      jsonb_agg(
        case
          when jsonb_typeof(hymn.value -> 'recordings') = 'array' then
            jsonb_set(
              hymn.value,
              '{recordings}',
              (
                select coalesce(
                  jsonb_agg(
                    case
                      when recording_row.id is not null then
                        (recording.value - 'url')
                          || jsonb_build_object('storagePath', recording_row.storage_path)
                      else recording.value
                    end
                    order by recording.ordinality
                  ),
                  '[]'::jsonb
                )
                from jsonb_array_elements(hymn.value -> 'recordings')
                  with ordinality recording(value, ordinality)
                left join public.hymn_recordings recording_row
                  on recording_row.hymn_id = hymn.value ->> 'id'
                  and recording_row.storage_path = split_part(
                    recording.value ->> 'url',
                    '/storage/v1/object/public/hymn-audio/',
                    2
                  )
              )
            )
          else hymn.value
        end
        order by hymn.ordinality
      ),
      '[]'::jsonb
    )
    from jsonb_array_elements(catalogue.content -> 'hymns')
      with ordinality hymn(value, ordinality)
  )
)
where catalogue.channel in ('draft', 'published')
  and jsonb_typeof(catalogue.content -> 'hymns') = 'array';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hymn-audio', 'hymn-audio', false, 104857600, array['audio/mpeg'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can listen to hymn audio" on storage.objects;
drop policy if exists "Admins can upload hymn audio" on storage.objects;
drop policy if exists "Admins can update hymn audio" on storage.objects;
drop policy if exists "Admins can delete hymn audio" on storage.objects;
drop policy if exists "Admins can read hymn audio" on storage.objects;
drop policy if exists "Published recordings can be played" on storage.objects;

create policy "Admins can read hymn audio"
on storage.objects for select
to authenticated
using (
  bucket_id = 'hymn-audio'
  and (select public.is_catalogue_admin())
);

create policy "Published recordings can be played"
on storage.objects for select
to anon, authenticated
using (
  bucket_id = 'hymn-audio'
  and (select public.is_published_hymn_audio(storage.objects.name))
);

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
