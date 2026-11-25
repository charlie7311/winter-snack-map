-- 겨울 간식 지도: 손님 제보 테이블
-- Supabase 대시보드 > SQL Editor에 붙여넣고 Run 하면 됩니다.

create table if not exists public.reports (
  id          bigint generated always as identity primary key,
  stall_id    integer     not null check (stall_id > 0 and stall_id < 100000),
  is_open     boolean     not null,
  created_at  timestamptz not null default now()
);

alter table public.reports add column if not exists by_owner boolean not null default false;   -- 사장님이 누른 기록 (owners.sql의 owner_update)

create index if not exists reports_created_at_idx on public.reports (created_at desc);

-- 행 단위 보안: 누구나(로그인 없이) 최근 제보를 읽을 수 있음. 제보 남기기는 security.sql의 add_report 함수로만 (IP별 횟수 제한).
-- 수정·삭제는 아무도 못 함(관리자는 대시보드에서 가능).
alter table public.reports enable row level security;

-- 새 Supabase 프로젝트는 테이블 권한을 자동으로 주지 않아서 직접 허용해요(읽기만).
grant select on public.reports to anon;

drop policy if exists "read recent reports" on public.reports;
create policy "read recent reports" on public.reports
  for select to anon
  using (created_at > now() - interval '15 days');   -- 화면에서 지난 14일 제보를 참고해요

drop policy if exists "anyone can report" on public.reports;
