-- 겨울 간식 지도: 손님이 등록하는 가게 테이블
-- Supabase 대시보드 > SQL Editor에 통째로 붙여넣고 Run 하면 됩니다. (여러 번 실행해도 괜찮아요)

create table if not exists public.stalls (
  id          bigint generated always as identity (start with 1000) primary key,  -- 1~999는 샘플 가게용
  name        text not null check (char_length(name) between 2 and 40),
  area        text check (char_length(area) <= 40),
  lat         double precision not null check (lat between 33 and 39),
  lng         double precision not null check (lng between 124 and 132),
  types       text[] not null check (
                cardinality(types) between 1 and 12
                and types <@ array['붕어빵','호떡','군고구마','군밤','계란빵','국화빵','어묵','타코야끼','델리만쥬','땅콩과자','와플','옥수수']
              ),
  menu        text check (char_length(menu) <= 100),
  pay         text check (char_length(pay) <= 30),
  hours       jsonb check (hours is null or (jsonb_typeof(hours) = 'array' and jsonb_array_length(hours) = 7)),
  created_at  timestamptz not null default now()
);

create index if not exists stalls_created_at_idx on public.stalls (created_at desc);

-- 읽기 규칙(승인된 가게만)과 등록(add_stall 함수, 승인 대기·IP별 제한)은 security.sql에 있어요. 수정·삭제는 관리자(대시보드)만.
alter table public.stalls enable row level security;
drop policy if exists "anyone can add stall" on public.stalls;
grant select on public.stalls to anon;
