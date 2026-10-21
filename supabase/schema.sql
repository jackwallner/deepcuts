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
