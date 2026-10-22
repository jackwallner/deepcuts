-- Tester feedback from TestFlight builds. Lives in the Sports Supabase project
-- (ucoveqbyfuxqvpysmixu) so it costs nothing extra; any fleet app can use it via `app`.
-- No RLS policies: only the tester-feedback edge function (service role) reads or writes.
create table if not exists public.tester_feedback (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  app text not null,
  install_id text not null,
  name text not null default '',
  text text not null,
  context jsonb not null default '{}'::jsonb,
  screenshot text,
  status text not null default 'new'
    check (status in ('new', 'queued', 'working', 'shipped', 'needs_jack', 'declined', 'failed')),
  reply text,
  build text,
  session_url text,
  thread_id text
);
create index if not exists tester_feedback_status on public.tester_feedback (status, created_at);
create index if not exists tester_feedback_install on public.tester_feedback (app, install_id, created_at desc);
alter table public.tester_feedback enable row level security;

-- Deep Cuts live content: questions, songs, covers and stories layered over the bundled crates.
-- A row with a bundled id replaces that item (a fix); status 'retired' hides it. Every insert or
-- update takes a new rev, so the app syncs with ?since=<last rev>. Written only by the
-- deepcuts-content edge function (admin key): scripts/content-remote.py and the weekly job.
create sequence if not exists public.deepcuts_content_rev;
create table if not exists public.deepcuts_content (
  id text primary key,
  crate text not null,
  kind text not null check (kind in ('question', 'song', 'cover', 'story')),
  body jsonb not null,
  status text not null default 'live' check (status in ('live', 'retired')),
  source text not null default 'manual',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  rev bigint not null default nextval('public.deepcuts_content_rev')
);
create index if not exists deepcuts_content_rev_idx on public.deepcuts_content (rev);
create or replace function public.deepcuts_content_touch() returns trigger language plpgsql as $$
begin
  new.rev := nextval('public.deepcuts_content_rev');
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists deepcuts_content_touch on public.deepcuts_content;
create trigger deepcuts_content_touch before update on public.deepcuts_content
  for each row execute function public.deepcuts_content_touch();
alter table public.deepcuts_content enable row level security;
