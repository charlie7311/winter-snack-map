-- 겨울 간식 지도: 잘못된 정보 신고 + 신고가 쌓이면 자동 숨김 + 손님 등록 칸 제한
-- Supabase SQL Editor에 통째로 붙여넣고 Run. categories.sql, security.sql 다음에 실행. 여러 번 실행해도 괜찮아요.
--
-- 숨겨진 가게 되살리기: Table Editor > stalls 에서 그 가게의 flag_count를 0으로 바꾸고,
--                      stall_flags 에서 그 가게(stall_id) 신고들을 지우면 돼요.
-- 아예 지우기: stalls 에서 그 가게 줄을 지우면 신고·사장님 신청도 같이 지워져요.

-- 1) 손님은 stalls에 직접 넣을 수 없어요. 가게 등록은 security.sql의 add_stall 함수로만 (승인 대기 + IP별 제한).
--    (직접 넣을 수 있으면 owner_open 같은 칸을 몰래 넣어 가짜 "영업중 (사장님)"을 만들 수 있어요)
revoke insert on public.stalls from anon, authenticated;

-- 2) 신고 수 ("없어짐"·"가짜" 신고만 셈). 화면에서는 3 이상이면 숨겨요.
alter table public.stalls add column if not exists flag_count integer not null default 0;
alter table public.stalls drop constraint if exists stalls_flag_count_check;
alter table public.stalls add constraint stalls_flag_count_check check (flag_count >= 0);

-- 3) 신고 내용. 같은 IP는 한 가게에 한 번만 신고할 수 있어요 (학교 와이파이처럼 IP를 같이 쓰면 한 명으로 셈).
create table if not exists public.stall_flags (
  id             bigint generated always as identity primary key,
  stall_id       bigint not null references public.stalls(id) on delete cascade,
  reporter_hash  text   not null,     -- 신고한 사람의 IP sha256 (IP 원문은 저장 안 함). 같은 IP는 한 가게에 한 번만
  reason         text   not null check (reason in ('gone', 'fake', 'location')),
  created_at     timestamptz not null default now(),
  unique (stall_id, reporter_hash)
);
alter table public.stall_flags enable row level security;   -- 정책 없음 = 밖에서 직접 못 읽고 못 씀
revoke all on public.stall_flags from anon, authenticated;

create or replace function public.flag_stall(p_stall_id bigint, p_reporter text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_reason not in ('gone', 'fake', 'location') then raise exception 'bad reason'; end if;
  if not exists (select 1 from stalls where id = p_stall_id) then raise exception 'no such stall'; end if;
  perform private.hit('flag', 20, interval '1 hour');   -- IP당 1시간 20번 (security.sql)
  insert into stall_flags (stall_id, reporter_hash, reason)
  values (p_stall_id, _token_hash(private.client_ip()), p_reason)   -- p_reporter는 예전 화면 호환용으로만 받음
  on conflict (stall_id, reporter_hash) do nothing;
  if found and p_reason in ('gone', 'fake') then
    update stalls set flag_count = flag_count + 1 where id = p_stall_id;
  end if;
end $$;

revoke all on function public.flag_stall(bigint, text, text) from public;
grant execute on function public.flag_stall(bigint, text, text) to anon, authenticated;
