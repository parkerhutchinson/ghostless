-- The Storage bucket the app keeps its files in (Settings › Data › Files):
-- card images, attachments, profile photos and background images, at
-- tasks/<file>, profiles/<file> and backgrounds/<file>. The database only
-- has their names; this is where every Mac gets the files themselves.
--
-- Private: no public URLs, and no policies on storage.objects, so only
-- the project's secret key (which the app uses, kept on each Mac) can
-- read or write it. Files never change once written, so they're uploaded
-- with a one-year cache lifetime and served from Supabase's CDN.
--
-- 25 MB a file at most: the app compresses images (2048px, JPEG), so this
-- mostly limits attachments. Larger ones stay on the Mac that added them
-- (Settings shows how many). Change file_size_limit here, in a new
-- migration, to allow more.

insert into storage.buckets (id, name, public, file_size_limit)
values ('files', 'files', false, 25 * 1024 * 1024)
on conflict (id) do nothing;
