-- Project status: how a shared project is going (On track, At risk, Off
-- track, On hold), and the status updates people post about it.

-- The current status, stored by name (onTrack, atRisk, offTrack, onHold);
-- null until the first update. Set from the latest update.
alter table public.projects add column if not exists "status" text;

-- status_updates ---------------------------------------------------------
-- One per update posted: the status it set and what was written
-- (Markdown). Kept apart from the project, like comments.

create table if not exists public.status_updates (
  id text primary key,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.status_updates
  add column if not exists "projectId" text,
  add column if not exists "authorId" text,
  add column if not exists "status" text,
  add column if not exists "body" text,
  add column if not exists "createdAt" timestamptz,
  add column if not exists "orgId" text references public.orgs (id) on delete cascade;

create index if not exists status_updates_sync_idx
  on public.status_updates (updated_at, id);
create index if not exists status_updates_org_sync_idx
  on public.status_updates ("orgId", updated_at, id);
create index if not exists status_updates_project_idx
  on public.status_updates ("projectId");

-- Rules: seen by the org with their project (never on someone else's
-- personal project); posted as yourself; changed or deleted by their
-- author or the org's owner and admins.
alter table public.status_updates enable row level security;

drop policy if exists "see status updates" on public.status_updates;
create policy "see status updates" on public.status_updates
  for select to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and private.task_visible("orgId", "projectId")
  );

drop policy if exists "post own status updates" on public.status_updates;
create policy "post own status updates" on public.status_updates
  for insert to authenticated
  with check (
    "orgId" in (select private.my_org_ids())
    and "authorId" = private.my_profile_in("orgId")
    and private.task_visible("orgId", "projectId")
  );

drop policy if exists "change own status updates" on public.status_updates;
create policy "change own status updates" on public.status_updates
  for update to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and private.task_visible("orgId", "projectId")
    and ("authorId" = private.my_profile_in("orgId")
         or private.role_in("orgId") in ('owner', 'admin'))
  )
  with check (
    "orgId" in (select private.my_org_ids())
    and private.task_visible("orgId", "projectId")
  );

drop policy if exists "delete own status updates" on public.status_updates;
create policy "delete own status updates" on public.status_updates
  for delete to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and ("authorId" = private.my_profile_in("orgId")
         or private.role_in("orgId") in ('owner', 'admin'))
  );

revoke all on public.status_updates from anon;
