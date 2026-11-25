-- Orgs: accounts, personal spaces, business orgs, members and roles, and
-- the rules that keep each org's data to its own members.
--
-- The model (see CLAUDE.md, "Orgs"):
--   * Everyone signs in (Supabase Auth). Each account has one personal
--     space (an org of kind 'personal', just them) and may belong to at
--     most one business org (kind 'business'), as owner, admin or member.
--   * Every synced record carries "orgId": the org it belongs to. The app
--     only ever receives records of its own orgs.
--   * Inside an org, everyone sees everything, except personal projects
--     (and their tasks and comments), which only their owner sees, and
--     Activity, which only its recipient (and whoever caused it) sees.
--   * Orgs, memberships, invites and domains are changed only through the
--     functions below, which check the caller's role. Clients can't write
--     those tables directly.
--   * A licensed org keeps its data in its own database: its connection
--     settings (org_connections) are the owner's alone, and each member's
--     own database login (member_credentials) is readable by that member
--     and the owner.
--
-- Every row a person can reach is decided here, in the database: the app
-- hiding something is never the protection.

begin;

-- Helpers live in a schema the Data API doesn't expose.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

-- Orgs and who's in them ---------------------------------------------------

create table if not exists public.orgs (
  id text primary key default gen_random_uuid()::text,
  name text not null check (length(trim(name)) between 1 and 100),
  kind text not null check (kind in ('personal', 'business')),
  -- Set by hand (the vendor, in the dashboard) until billing exists.
  plan text not null default 'free'
    check (plan in ('free', 'trial', 'subscription', 'license')),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.org_members (
  org_id text not null references public.orgs (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  -- The org's kind, repeated so one rule can say: one of each per person.
  kind text not null check (kind in ('personal', 'business')),
  role text not null check (role in ('owner', 'admin', 'member')),
  -- Their profile (a record in "profiles") in this org.
  profile_id text not null check (length(profile_id) > 0),
  joined_at timestamptz not null default now(),
  primary key (org_id, user_id),
  unique (user_id, kind),
  unique (org_id, profile_id)
);

create table if not exists public.org_invites (
  id uuid primary key default gen_random_uuid(),
  org_id text not null references public.orgs (id) on delete cascade,
  email text not null check (email = lower(trim(email)) and email like '%_@_%'),
  role text not null default 'member' check (role in ('admin', 'member')),
  -- A placeholder person (a profile with no login) the invitee becomes,
  -- keeping the tasks assigned to them.
  profile_id text,
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  unique (org_id, email)
);

-- Email domains an org has claimed: anyone verified on one joins it.
create table if not exists public.org_domains (
  domain text primary key
    check (domain = lower(trim(domain)) and domain like '%_._%'
           and domain not like '%@%'),
  org_id text not null references public.orgs (id) on delete cascade,
  claimed_by uuid references auth.users (id) on delete set null,
  claimed_at timestamptz not null default now()
);

-- Where a licensed org keeps its data: its database and file storage.
-- The owner's alone.
create table if not exists public.org_connections (
  org_id text primary key references public.orgs (id) on delete cascade,
  database jsonb,
  storage jsonb,
  updated_at timestamptz not null default now()
);

-- Each member's own login to a licensed org's database and storage, set
-- by the owner. Readable by that member and the owner.
create table if not exists public.member_credentials (
  org_id text not null,
  user_id uuid not null,
  database jsonb,
  storage jsonb,
  updated_at timestamptz not null default now(),
  primary key (org_id, user_id),
  foreign key (org_id, user_id)
    references public.org_members (org_id, user_id) on delete cascade
);

-- Every synced record belongs to an org. Records already there (synced
-- before orgs) have none: nobody can reach them until the app sends them
-- again with one.
alter table public.projects
  add column if not exists "orgId" text references public.orgs (id) on delete cascade;
alter table public.tasks
  add column if not exists "orgId" text references public.orgs (id) on delete cascade;
alter table public.profiles
  add column if not exists "orgId" text references public.orgs (id) on delete cascade;
alter table public.activity
  add column if not exists "orgId" text references public.orgs (id) on delete cascade;
alter table public.comments
  add column if not exists "orgId" text references public.orgs (id) on delete cascade;

-- Sync reads one org's changes in (updated_at, id) order.
create index if not exists projects_org_sync_idx on public.projects ("orgId", updated_at, id);
create index if not exists tasks_org_sync_idx on public.tasks ("orgId", updated_at, id);
create index if not exists profiles_org_sync_idx on public.profiles ("orgId", updated_at, id);
create index if not exists activity_org_sync_idx on public.activity ("orgId", updated_at, id);
create index if not exists comments_org_sync_idx on public.comments ("orgId", updated_at, id);
create index if not exists tasks_origin_idx on public.tasks ("originId");
create index if not exists comments_task_idx on public.comments ("taskId");

-- Helpers for the rules ----------------------------------------------------
-- security definer: they read memberships and projects without the rules
-- applying to themselves (which would loop). Each only answers about the
-- signed-in person.

create or replace function private.my_org_ids()
returns setof text
language sql stable security definer set search_path = ''
as $$
  select org_id from public.org_members where user_id = (select auth.uid())
$$;

create or replace function private.role_in(org text)
returns text
language sql stable security definer set search_path = ''
as $$
  select role from public.org_members
  where org_id = org and user_id = (select auth.uid())
$$;

create or replace function private.my_profile_in(org text)
returns text
language sql stable security definer set search_path = ''
as $$
  select profile_id from public.org_members
  where org_id = org and user_id = (select auth.uid())
$$;

-- A task can be seen by every member of its org, unless it was created
-- in someone else's personal project.
create or replace function private.task_visible(org text, origin text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select not exists (
    select 1 from public.projects p
    where p.id = origin
      and p."ownerId" is not null
      and p."ownerId" is distinct from private.my_profile_in(org)
  )
$$;

-- A comment can be seen when its task can (or the task hasn't arrived).
create or replace function private.comment_visible(task text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select not exists (
    select 1 from public.tasks t
    where t.id = task and not private.task_visible(t."orgId", t."originId")
  )
$$;

-- A profile can be edited by the person it belongs to, by the org's
-- owner and admins, or by anyone in the org when it's a placeholder (a
-- person without a login).
create or replace function private.can_edit_profile(org text, profile text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select private.my_profile_in(org) = profile
      or private.role_in(org) in ('owner', 'admin')
      or not exists (
        select 1 from public.org_members m
        where m.org_id = org and m.profile_id = profile
      )
$$;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- Rules: synced records ----------------------------------------------------

alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.profiles enable row level security;
alter table public.activity enable row level security;
alter table public.comments enable row level security;

-- Projects: the org's, except other people's personal projects.
drop policy if exists "org members' projects" on public.projects;
create policy "org members' projects" on public.projects
  for all to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and ("ownerId" is null or "ownerId" = private.my_profile_in("orgId"))
  )
  with check (
    "orgId" in (select private.my_org_ids())
    and ("ownerId" is null or "ownerId" = private.my_profile_in("orgId"))
  );

-- Tasks: the org's, except ones in other people's personal projects.
drop policy if exists "org members' tasks" on public.tasks;
create policy "org members' tasks" on public.tasks
  for all to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and private.task_visible("orgId", "originId")
  )
  with check (
    "orgId" in (select private.my_org_ids())
    and private.task_visible("orgId", "originId")
  );

-- Profiles: everyone in the org is seen; editing is limited (above).
drop policy if exists "org members see profiles" on public.profiles;
create policy "org members see profiles" on public.profiles
  for select to authenticated
  using ("orgId" in (select private.my_org_ids()));

drop policy if exists "org members add profiles" on public.profiles;
create policy "org members add profiles" on public.profiles
  for insert to authenticated
  with check ("orgId" in (select private.my_org_ids()));

drop policy if exists "edit own or placeholder profiles" on public.profiles;
create policy "edit own or placeholder profiles" on public.profiles
  for update to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and private.can_edit_profile("orgId", id)
  )
  with check (
    "orgId" in (select private.my_org_ids())
    and private.can_edit_profile("orgId", id)
  );

drop policy if exists "delete placeholder profiles" on public.profiles;
create policy "delete placeholder profiles" on public.profiles
  for delete to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and private.can_edit_profile("orgId", id)
  );

-- Activity: its recipient's, and whoever caused it (who writes it).
drop policy if exists "own activity" on public.activity;
create policy "own activity" on public.activity
  for all to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and private.my_profile_in("orgId") in ("recipientId", "actorId")
  )
  with check (
    "orgId" in (select private.my_org_ids())
    and private.my_profile_in("orgId") in ("recipientId", "actorId")
  );

-- Comments: seen with their task; written as yourself; changed by their
-- author or the org's owner and admins.
drop policy if exists "see comments" on public.comments;
create policy "see comments" on public.comments
  for select to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and private.comment_visible("taskId")
  );

drop policy if exists "write own comments" on public.comments;
create policy "write own comments" on public.comments
  for insert to authenticated
  with check (
    "orgId" in (select private.my_org_ids())
    and "authorId" = private.my_profile_in("orgId")
    and private.comment_visible("taskId")
  );

drop policy if exists "change own comments" on public.comments;
create policy "change own comments" on public.comments
  for update to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and private.comment_visible("taskId")
    and ("authorId" = private.my_profile_in("orgId")
         or private.role_in("orgId") in ('owner', 'admin'))
  )
  with check (
    "orgId" in (select private.my_org_ids())
    and private.comment_visible("taskId")
  );

drop policy if exists "delete own comments" on public.comments;
create policy "delete own comments" on public.comments
  for delete to authenticated
  using (
    "orgId" in (select private.my_org_ids())
    and ("authorId" = private.my_profile_in("orgId")
         or private.role_in("orgId") in ('owner', 'admin'))
  );

-- Rules: orgs and memberships (read only; changed through the functions) --

alter table public.orgs enable row level security;
alter table public.org_members enable row level security;
alter table public.org_invites enable row level security;
alter table public.org_domains enable row level security;
alter table public.org_connections enable row level security;
alter table public.member_credentials enable row level security;

drop policy if exists "members see their orgs" on public.orgs;
create policy "members see their orgs" on public.orgs
  for select to authenticated
  using (id in (select private.my_org_ids()));

drop policy if exists "members see each other" on public.org_members;
create policy "members see each other" on public.org_members
  for select to authenticated
  using (org_id in (select private.my_org_ids()));

-- Invites: the org's owner and admins, and the person invited.
drop policy if exists "admins and invitees see invites" on public.org_invites;
create policy "admins and invitees see invites" on public.org_invites
  for select to authenticated
  using (
    private.role_in(org_id) in ('owner', 'admin')
    or email = lower((select auth.jwt()) ->> 'email')
  );

drop policy if exists "members see domains" on public.org_domains;
create policy "members see domains" on public.org_domains
  for select to authenticated
  using (org_id in (select private.my_org_ids()));

-- Where the data lives: the owner's alone.
drop policy if exists "owner manages connection" on public.org_connections;
create policy "owner manages connection" on public.org_connections
  for all to authenticated
  using (private.role_in(org_id) = 'owner')
  with check (private.role_in(org_id) = 'owner');

drop policy if exists "member reads own login" on public.member_credentials;
create policy "member reads own login" on public.member_credentials
  for select to authenticated
  using (user_id = (select auth.uid()) or private.role_in(org_id) = 'owner');

drop policy if exists "owner manages logins" on public.member_credentials;
create policy "owner manages logins" on public.member_credentials
  for all to authenticated
  using (private.role_in(org_id) = 'owner')
  with check (private.role_in(org_id) = 'owner');

-- Nothing for people who aren't signed in.
revoke all on public.projects, public.tasks, public.profiles, public.activity,
  public.comments, public.orgs, public.org_members, public.org_invites,
  public.org_domains, public.org_connections, public.member_credentials
  from anon;

-- Functions the app calls (Data API: rpc/<name>) ---------------------------
-- Each checks who's calling and their role; the tables they change can't
-- be written directly.

-- The signed-in person's personal space, made the first time (with them
-- as its owner, as [new_profile]). Returns its id.
create or replace function public.ensure_personal_space(
  space_name text, new_profile text
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  org text;
begin
  if uid is null then raise exception 'Sign in first.'; end if;
  select m.org_id into org from public.org_members m
  where m.user_id = uid and m.kind = 'personal';
  if org is not null then return org; end if;
  insert into public.orgs (name, kind, plan, created_by)
  values (coalesce(nullif(trim(space_name), ''), 'Personal'), 'personal', 'free', uid)
  returning id into org;
  insert into public.org_members (org_id, user_id, kind, role, profile_id)
  values (org, uid, 'personal', 'owner', new_profile);
  return org;
end
$$;

-- A new business org, with the caller as its owner. One per person.
create or replace function public.create_business_org(
  org_name text, new_profile text
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  org text;
begin
  if uid is null then raise exception 'Sign in first.'; end if;
  if exists (select 1 from public.org_members m
             where m.user_id = uid and m.kind = 'business') then
    raise exception 'You already belong to an org.';
  end if;
  insert into public.orgs (name, kind, plan, created_by)
  values (trim(org_name), 'business', 'trial', uid)
  returning id into org;
  insert into public.org_members (org_id, user_id, kind, role, profile_id)
  values (org, uid, 'business', 'owner', new_profile);
  return org;
end
$$;

-- Joins the business org the caller was invited to (or whose email
-- domain they're verified on). [new_profile] is their new profile, unless
-- the invite names a placeholder for them to become. Returns the org, the
-- role and the profile to use.
create or replace function public.join_org(new_profile text)
returns table (org text, member_role text, profile text)
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  mail text;
  confirmed timestamptz;
  inv public.org_invites;
  joined_org text;
  joined_role text;
  joined_profile text := new_profile;
begin
  if uid is null then raise exception 'Sign in first.'; end if;
  select lower(u.email), u.email_confirmed_at into mail, confirmed
  from auth.users u where u.id = uid;
  if exists (select 1 from public.org_members m
             where m.user_id = uid and m.kind = 'business') then
    raise exception 'You already belong to an org.';
  end if;

  select * into inv from public.org_invites i
  where i.email = mail and i.accepted_at is null
  order by i.created_at desc limit 1;

  if inv.id is not null then
    joined_org := inv.org_id;
    joined_role := inv.role;
    -- Become the placeholder, unless someone has taken it since.
    if inv.profile_id is not null and not exists (
      select 1 from public.org_members m
      where m.org_id = inv.org_id and m.profile_id = inv.profile_id
    ) then
      joined_profile := inv.profile_id;
    end if;
    update public.org_invites set accepted_at = now() where id = inv.id;
  elsif confirmed is not null then
    select d.org_id into joined_org from public.org_domains d
    where d.domain = split_part(mail, '@', 2);
    joined_role := 'member';
  end if;

  if joined_org is null then
    raise exception 'There''s no invite for %.', mail;
  end if;
  insert into public.org_members (org_id, user_id, kind, role, profile_id)
  values (joined_org, uid, 'business', joined_role, joined_profile);
  return query select joined_org, joined_role, joined_profile;
end
$$;

-- Invites [invitee_email] to a business org. Owners invite admins and members;
-- admins invite members. [placeholder] is a profile without a login the
-- invitee will become.
create or replace function public.invite_member(
  org text, invitee_email text, member_role text default 'member',
  placeholder text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  caller text := private.role_in(org);
  mail text := lower(trim(invitee_email));
  invite uuid;
begin
  if caller is null or caller = 'member' then
    raise exception 'Only an owner or admin can invite people.';
  end if;
  if (select o.kind from public.orgs o where o.id = org) <> 'business' then
    raise exception 'A personal space can''t have members.';
  end if;
  if member_role not in ('admin', 'member') then
    raise exception 'Invite as admin or member.';
  end if;
  if member_role = 'admin' and caller <> 'owner' then
    raise exception 'Only the owner can invite admins.';
  end if;
  if exists (
    select 1 from public.org_members m join auth.users u on u.id = m.user_id
    where m.org_id = org and lower(u.email) = mail
  ) then
    raise exception '% is already a member.', mail;
  end if;
  insert into public.org_invites (org_id, email, role, profile_id, invited_by)
  values (org, mail, member_role, placeholder, auth.uid())
  on conflict (org_id, email) do update
    set role = excluded.role, profile_id = excluded.profile_id,
        invited_by = excluded.invited_by, created_at = now(),
        accepted_at = null
  returning id into invite;
  return invite;
end
$$;

create or replace function public.cancel_invite(invite uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.org_invites i
  where i.id = invite and private.role_in(i.org_id) in ('owner', 'admin');
end
$$;

-- The owner makes someone an admin or a member.
create or replace function public.change_role(
  org text, member uuid, member_role text
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if private.role_in(org) is distinct from 'owner' then
    raise exception 'Only the owner can change roles.';
  end if;
  if member_role not in ('admin', 'member') then
    raise exception 'Make them an admin or a member.';
  end if;
  update public.org_members m set role = member_role
  where m.org_id = org and m.user_id = member and m.role <> 'owner';
end
$$;

-- The owner hands the org to another member (and becomes an admin).
create or replace function public.transfer_ownership(org text, member uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if private.role_in(org) is distinct from 'owner' then
    raise exception 'Only the owner can hand the org over.';
  end if;
  if not exists (select 1 from public.org_members m
                 where m.org_id = org and m.user_id = member
                   and m.kind = 'business') then
    raise exception 'They aren''t a member.';
  end if;
  update public.org_members m set role = 'admin'
  where m.org_id = org and m.user_id = auth.uid();
  update public.org_members m set role = 'owner'
  where m.org_id = org and m.user_id = member;
end
$$;

-- Removes someone: the owner removes anyone else; admins remove members.
create or replace function public.remove_member(org text, member uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  caller text := private.role_in(org);
  target text;
begin
  select m.role into target from public.org_members m
  where m.org_id = org and m.user_id = member and m.kind = 'business';
  if target is null then return; end if;
  if member = auth.uid() then
    raise exception 'Use leave_org to leave.';
  end if;
  if not (caller = 'owner' or (caller = 'admin' and target = 'member')) then
    raise exception 'You can''t remove them.';
  end if;
  delete from public.org_members m
  where m.org_id = org and m.user_id = member;
end
$$;

-- Leaves a business org (the owner hands it over first).
create or replace function public.leave_org(org text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if private.role_in(org) = 'owner' then
    raise exception 'Hand the org to someone else before leaving.';
  end if;
  delete from public.org_members m
  where m.org_id = org and m.user_id = auth.uid() and m.kind = 'business';
end
$$;

create or replace function public.rename_org(org text, new_name text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if private.role_in(org) not in ('owner', 'admin') then
    raise exception 'Only an owner or admin can rename the org.';
  end if;
  update public.orgs o set name = trim(new_name), updated_at = now()
  where o.id = org;
end
$$;

-- The owner claims their own email's domain for the org: anyone verified
-- on it can then join. Not for shared email providers.
create or replace function public.claim_domain(org text, new_domain text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  d text := lower(trim(new_domain));
  mail text;
begin
  if private.role_in(org) is distinct from 'owner' then
    raise exception 'Only the owner can claim a domain.';
  end if;
  if (select o.kind from public.orgs o where o.id = org) <> 'business' then
    raise exception 'A personal space can''t claim a domain.';
  end if;
  select lower(u.email) into mail from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if mail is null or split_part(mail, '@', 2) <> d then
    raise exception 'You can only claim your own email''s domain (%).',
      split_part(coalesce(mail, ''), '@', 2);
  end if;
  if d in ('gmail.com', 'googlemail.com', 'outlook.com', 'hotmail.com',
           'live.com', 'msn.com', 'yahoo.com', 'icloud.com', 'me.com',
           'mac.com', 'aol.com', 'proton.me', 'protonmail.com',
           'gmx.com', 'zoho.com', 'yandex.com', 'mail.com', 'fastmail.com',
           'hey.com') then
    raise exception '% is a shared email provider.', d;
  end if;
  insert into public.org_domains (domain, org_id, claimed_by)
  values (d, org, auth.uid());
exception when unique_violation then
  raise exception '% is already claimed.', d;
end
$$;

create or replace function public.release_domain(org text, old_domain text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if private.role_in(org) is distinct from 'owner' then
    raise exception 'Only the owner can release a domain.';
  end if;
  delete from public.org_domains d
  where d.org_id = org and d.domain = lower(trim(old_domain));
end
$$;

-- The org's members with their emails, for its members.
create or replace function public.org_people(org text)
returns table (
  user_id uuid, email text, role text, profile_id text, joined_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select m.user_id, u.email, m.role, m.profile_id, m.joined_at
  from public.org_members m join auth.users u on u.id = m.user_id
  where m.org_id = org and org in (select private.my_org_ids())
  order by m.joined_at
$$;

revoke all on function
  public.ensure_personal_space(text, text),
  public.create_business_org(text, text),
  public.join_org(text),
  public.invite_member(text, text, text, text),
  public.cancel_invite(uuid),
  public.change_role(text, uuid, text),
  public.transfer_ownership(text, uuid),
  public.remove_member(text, uuid),
  public.leave_org(text),
  public.rename_org(text, text),
  public.claim_domain(text, text),
  public.release_domain(text, text),
  public.org_people(text)
  from public, anon;
grant execute on function
  public.ensure_personal_space(text, text),
  public.create_business_org(text, text),
  public.join_org(text),
  public.invite_member(text, text, text, text),
  public.cancel_invite(uuid),
  public.change_role(text, uuid, text),
  public.transfer_ownership(text, uuid),
  public.remove_member(text, uuid),
  public.leave_org(text),
  public.rename_org(text, text),
  public.claim_domain(text, text),
  public.release_domain(text, text),
  public.org_people(text)
  to authenticated;

-- Files: <orgId>/tasks/<file>, <orgId>/profiles/<file>, ... in the
-- hosted bucket ("codename"). Members reach their own orgs' folders only.
drop policy if exists "org members' files" on storage.objects;
create policy "org members' files" on storage.objects
  for all to authenticated
  using (
    bucket_id = 'codename'
    and (storage.foldername(name))[1] in (select private.my_org_ids())
  )
  with check (
    bucket_id = 'codename'
    and (storage.foldername(name))[1] in (select private.my_org_ids())
  );

commit;
