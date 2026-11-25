-- The tables the app syncs with (Settings › Sync, Postgres), for Supabase.
--
-- Mirrors `appSchema` in lib/sync/app_schema.dart: one table per synced
-- collection, one column per field, named exactly as the app's fields
-- (camelCase, so quoted). test/supabase_migrations_test.dart checks the
-- two stay in step. When a model gains a field, add a NEW migration file
-- (never edit one that has been applied).
--
-- Safe to run on an empty project or over tables made by hand earlier:
-- every table and column is created only if it's missing.
--
-- What sync needs in every table (see SqlTable in packages/sync_engine):
--   id          text primary key: the app's record ids.
--   updated_at  timestamptz: when the record last changed. The app writes
--               it (last write wins), so there is deliberately no trigger
--               setting it to now(): that would make every server copy look
--               newer than the Macs' edits.
--   deleted_at  timestamptz, null unless deleted: deletes sync between Macs
--               as soft deletes. Without it a delete on one Mac wouldn't
--               reach the others.
--
-- Field types: text for text (dueDate is 'YYYY-MM-DD' and dueTime 'HH:MM'
-- text, as the app stores them), timestamptz for dates and times, numbers
-- as integer or double precision, and jsonb for lists and objects (the app
-- sends JSON). Every field is nullable: the app leaves some empty, and
-- reads a missing value as its default.

begin;

-- projects --------------------------------------------------------------

create table if not exists public.projects (
  id text primary key,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.projects
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists "name" text,
  add column if not exists "colorIndex" integer,
  add column if not exists "order" double precision,
  add column if not exists "columns" jsonb,
  add column if not exists "ownerId" text,
  add column if not exists "logo" jsonb,
  add column if not exists "labels" jsonb,
  add column if not exists "labelColors" jsonb,
  add column if not exists "description" text,
  add column if not exists "createdAt" timestamptz;

-- tasks -----------------------------------------------------------------

create table if not exists public.tasks (
  id text primary key,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.tasks
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists "title" text,
  add column if not exists "description" text,
  add column if not exists "status" text,
  add column if not exists "order" double precision,
  add column if not exists "tags" jsonb,
  add column if not exists "images" jsonb,
  add column if not exists "attachments" jsonb,
  add column if not exists "originId" text,
  add column if not exists "projectIds" jsonb,
  add column if not exists "dueDate" text,
  add column if not exists "dueTime" text,
  add column if not exists "completedIn" jsonb,
  add column if not exists "placements" jsonb,
  add column if not exists "subtasks" jsonb,
  add column if not exists "assigneeId" text,
  add column if not exists "reminder" integer,
  add column if not exists "createdAt" timestamptz;

-- profiles --------------------------------------------------------------

create table if not exists public.profiles (
  id text primary key,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.profiles
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists "name" text,
  add column if not exists "department" text,
  add column if not exists "jobTitle" text,
  add column if not exists "description" text,
  add column if not exists "imageFile" text,
  add column if not exists "personalProjectId" text,
  add column if not exists "theme" jsonb,
  add column if not exists "favoriteProjects" jsonb,
  add column if not exists "createdAt" timestamptz;

-- activity --------------------------------------------------------------

create table if not exists public.activity (
  id text primary key,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.activity
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists "recipientId" text,
  add column if not exists "actorId" text,
  add column if not exists "taskId" text,
  add column if not exists "taskTitle" text,
  add column if not exists "kind" text,
  add column if not exists "changes" jsonb,
  add column if not exists "dueAt" timestamptz,
  add column if not exists "excerpt" text,
  add column if not exists "createdAt" timestamptz,
  add column if not exists "readAt" timestamptz,
  add column if not exists "dismissedAt" timestamptz;

-- comments --------------------------------------------------------------

create table if not exists public.comments (
  id text primary key,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.comments
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists "taskId" text,
  add column if not exists "authorId" text,
  add column if not exists "body" text,
  add column if not exists "createdAt" timestamptz;

-- Sync reads each table's changes in (updated_at, id) order, after the last
-- one it saw: an index on exactly that keeps it quick as tables grow.
create index if not exists projects_sync_idx on public.projects (updated_at, id);
create index if not exists tasks_sync_idx on public.tasks (updated_at, id);
create index if not exists profiles_sync_idx on public.profiles (updated_at, id);
create index if not exists activity_sync_idx on public.activity (updated_at, id);
create index if not exists comments_sync_idx on public.comments (updated_at, id);

-- Row Level Security on, with no policies: Supabase's public API (the anon
-- and authenticated keys, through PostgREST) can't read or write these
-- tables at all. The app connects to Postgres directly as the tables'
-- owner (the `postgres` user), which RLS doesn't restrict.
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.profiles enable row level security;
alter table public.activity enable row level security;
alter table public.comments enable row level security;

commit;
