create table if not exists public.admin_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;
revoke all on public.admin_users from anon, authenticated;

create or replace function public.is_catalogue_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_users
    where user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_catalogue_admin() from public;
grant execute on function public.is_catalogue_admin() to authenticated;

create policy "Admins can read their own admin membership"
on public.admin_users for select
to authenticated
using (user_id = (select auth.uid()));

grant select on public.admin_users to authenticated;

create table if not exists public.catalogue_versions (
  channel text primary key check (channel in ('draft', 'published')),
  content jsonb not null check (
    jsonb_typeof(content) = 'object'
    and content ->> 'schemaVersion' = '1'
    and jsonb_typeof(content -> 'hymns') = 'array'
  ),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

alter table public.catalogue_versions enable row level security;
revoke all on public.catalogue_versions from anon, authenticated;

create policy "Anyone can read the published catalogue"
on public.catalogue_versions for select
to anon, authenticated
using (channel = 'published');

create policy "Admins can manage catalogue versions"
on public.catalogue_versions for all
to authenticated
using ((select public.is_catalogue_admin()))
with check ((select public.is_catalogue_admin()));

grant select on public.catalogue_versions to anon, authenticated;
grant insert, update, delete on public.catalogue_versions to authenticated;

create table if not exists public.pdf_imports (
  id uuid primary key default gen_random_uuid(),
  uploaded_by uuid not null references auth.users (id) on delete cascade,
  original_filename text not null,
  storage_path text not null unique,
  extracted_text text not null,
  page_count integer not null check (page_count > 0),
  created_at timestamptz not null default now()
);

alter table public.pdf_imports enable row level security;
revoke all on public.pdf_imports from anon, authenticated;

create policy "Admins can manage PDF imports"
on public.pdf_imports for all
to authenticated
using ((select public.is_catalogue_admin()))
with check ((select public.is_catalogue_admin()));

grant select, insert, update, delete on public.pdf_imports to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('source-pdfs', 'source-pdfs', false, 52428800, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Admins can read source PDFs"
on storage.objects for select
to authenticated
using (
  bucket_id = 'source-pdfs'
  and (select public.is_catalogue_admin())
);

create policy "Admins can upload source PDFs"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'source-pdfs'
  and (select public.is_catalogue_admin())
);

create policy "Admins can update source PDFs"
on storage.objects for update
to authenticated
using (
  bucket_id = 'source-pdfs'
  and (select public.is_catalogue_admin())
)
with check (
  bucket_id = 'source-pdfs'
  and (select public.is_catalogue_admin())
);

create policy "Admins can delete source PDFs"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'source-pdfs'
  and (select public.is_catalogue_admin())
);
