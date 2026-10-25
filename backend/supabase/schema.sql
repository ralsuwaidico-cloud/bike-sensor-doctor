-- Athletics — Supabase schema (run once in the SQL editor of the project; idempotent).
-- Every row belongs to one auth.users id. Row-level security: owners only. Sync = last-writer-wins on
-- client_updated_at (set by the phone), soft deletes via deleted_at so other devices remove the row too.

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------------ helpers
create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ------------------------------------------------------------------ profiles (one per user)
create table if not exists public.profiles (
  user_id            uuid primary key references auth.users(id) on delete cascade,
  schema_version     int  not null default 1,
  payload            jsonb not null,                 -- RiderProfile as the app encodes it (name, birth year, weight, FTP + status, HR, zones, goals, units, mode …)
  client_updated_at  timestamptz not null,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
alter table public.profiles enable row level security;
drop policy if exists "profiles owner" on public.profiles;
create policy "profiles owner" on public.profiles for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop trigger if exists profiles_updated on public.profiles;
create trigger profiles_updated before update on public.profiles for each row execute function public.set_updated_at();

-- ------------------------------------------------------------------ generic per-user records
-- One table per record kind; the phone owns the primary key (its UUID) so offline-created rows never collide.
create table if not exists public.rides (
  id                 uuid primary key,
  user_id            uuid not null references auth.users(id) on delete cascade,
  source_id          text,                            -- stable origin id (board id + start, Health UUID, phone UUID) for dedupe
  started_at         timestamptz not null,
  payload            jsonb not null,                  -- RideRecord
  client_updated_at  timestamptz not null,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
create index if not exists rides_user_started on public.rides(user_id, started_at desc);
create index if not exists rides_user_source on public.rides(user_id, source_id);   -- dedupe is done by the apps (origin id + time); not unique so a late upload never fails a whole batch

create table if not exists public.strength_sessions (
  id                 uuid primary key,
  user_id            uuid not null references auth.users(id) on delete cascade,
  source_id          text,
  started_at         timestamptz not null,
  payload            jsonb not null,                  -- StrengthSession / quick log
  client_updated_at  timestamptz not null,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
create index if not exists strength_user_started on public.strength_sessions(user_id, started_at desc);
create index if not exists strength_user_source on public.strength_sessions(user_id, source_id);

create table if not exists public.templates (
  id                 uuid primary key,
  user_id            uuid not null references auth.users(id) on delete cascade,
  payload            jsonb not null,                  -- StrengthTemplate
  client_updated_at  timestamptz not null,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
create index if not exists templates_user on public.templates(user_id);

create table if not exists public.plans (
  id                 uuid primary key,
  user_id            uuid not null references auth.users(id) on delete cascade,
  day                date not null,
  payload            jsonb not null,                  -- Workout (planned session)
  client_updated_at  timestamptz not null,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);
create index if not exists plans_user_day on public.plans(user_id, day);

create table if not exists public.settings (
  user_id            uuid primary key references auth.users(id) on delete cascade,
  payload            jsonb not null,                  -- AppSettings + WeeklyAvailability + weekday routine defaults + equipment
  client_updated_at  timestamptz not null,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

do $$ declare t text; begin
  foreach t in array array['rides','strength_sessions','templates','plans','settings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%s owner" on public.%I', t, t);
    execute format('create policy "%s owner" on public.%I for all using (auth.uid() = user_id) with check (auth.uid() = user_id)', t, t);
    execute format('drop trigger if exists %I_updated on public.%I', t, t);
    execute format('create trigger %I_updated before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

-- ------------------------------------------------------------------ change feed for pulls
-- The app pulls everything with updated_at > its last pull per table (including soft-deleted rows).
-- No extra table needed; updated_at is server time, so clock skew on phones does not matter for pulls.

-- ------------------------------------------------------------------ account deletion (App Store guideline 5.1.1 (v))
-- Called by the signed-in user from the app. Deletes every row and the auth user itself. SECURITY DEFINER so it may
-- touch auth.users; it only ever acts on auth.uid().
create or replace function public.auth_delete_user() returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not signed in'; end if;
  delete from public.rides where user_id = uid;
  delete from public.strength_sessions where user_id = uid;
  delete from public.templates where user_id = uid;
  delete from public.plans where user_id = uid;
  delete from public.settings where user_id = uid;
  delete from public.profiles where user_id = uid;
  delete from auth.users where id = uid;
end $$;
revoke all on function public.auth_delete_user() from public;
grant execute on function public.auth_delete_user() to authenticated;

-- ------------------------------------------------------------------ data export (one JSON document of everything)
create or replace function public.export_my_data() returns jsonb
language sql security invoker stable as $$
  select jsonb_build_object(
    'profile',  (select payload from public.profiles where user_id = auth.uid() and deleted_at is null),
    'settings', (select payload from public.settings where user_id = auth.uid() and deleted_at is null),
    'rides',    coalesce((select jsonb_agg(payload order by started_at) from public.rides where user_id = auth.uid() and deleted_at is null), '[]'::jsonb),
    'strength', coalesce((select jsonb_agg(payload order by started_at) from public.strength_sessions where user_id = auth.uid() and deleted_at is null), '[]'::jsonb),
    'templates',coalesce((select jsonb_agg(payload) from public.templates where user_id = auth.uid() and deleted_at is null), '[]'::jsonb),
    'plans',    coalesce((select jsonb_agg(payload order by day) from public.plans where user_id = auth.uid() and deleted_at is null), '[]'::jsonb));
$$;
grant execute on function public.export_my_data() to authenticated;
