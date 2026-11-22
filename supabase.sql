-- 겨울 간식 지도: 손님 제보 테이블
-- Supabase 대시보드 > SQL Editor에 붙여넣고 Run 하면 됩니다.

create table if not exists public.reports (
  id          bigint generated always as identity primary key,
  stall_id    integer     not null check (stall_id > 0 and stall_id < 100000),
  is_open     boolean     not null,
  created_at  timestamptz not null default now()
);

create index if not exists reports_created_at_idx on public.reports (created_at desc);

-- 행 단위 보안: 누구나(로그인 없이) 최근 제보를 읽고, 새 제보를 남길 수 있음.
-- 수정·삭제는 아무도 못 함(관리자는 대시보드에서 가능).
alter table public.reports enable row level security;

drop policy if exists "read recent reports" on public.reports;
create policy "read recent reports" on public.reports
  for select to anon
  using (created_at > now() - interval '2 days');

drop policy if exists "anyone can report" on public.reports;
create policy "anyone can report" on public.reports
  for insert to anon
  with check (created_at > now() - interval '1 minute' and created_at < now() + interval '1 minute');

-- 참고: 지금은 장난 제보를 브라우저에서 1분 간격으로만 막고 있어요.
-- 사용자가 늘면 IP별 제한(Edge Function)이나 로그인 제보를 추가하는 게 좋아요.
