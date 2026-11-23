-- 겨울 간식 지도: 디스코드 알림 (사장님 신청이 오면, 신고가 쌓여 가게가 숨겨지면)
-- Supabase SQL Editor에 통째로 붙여넣고 Run. owners.sql, moderation.sql 다음에 실행. 여러 번 실행해도 괜찮아요.
--
-- 알림 받을 디스코드 주소 넣기 (한 번만, 이 파일과 따로 SQL Editor에서 실행):
--   insert into private.settings (key, value) values ('discord_webhook', 'https://discord.com/api/webhooks/...')
--   on conflict (key) do update set value = excluded.value;
-- 웹후크 주소는 비밀번호처럼 다뤄요. 이 파일이나 GitHub에 적지 마세요.
-- 주소를 안 넣으면 알림만 안 가고 나머지는 그대로 동작해요.

create extension if not exists pg_net;   -- Supabase가 밖으로 HTTP 요청을 보내게 해 주는 확장

-- 사이트(anon)에서 보이지 않는 설정 보관 장소
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.settings (key text primary key, value text not null);
alter table private.settings enable row level security;   -- 정책 없음 = 사이트에서는 못 읽음 (알림 함수는 테이블 주인이라 읽을 수 있어요)

create or replace function private.notify(p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare url text;
begin
  select value into url from private.settings where key = 'discord_webhook';
  if url is null then return; end if;
  perform net.http_post(
    url     := url,
    body    := jsonb_build_object('content', left(p_text, 1900)),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
exception when others then
  raise warning '알림 보내기 실패: %', sqlerrm;   -- 알림이 실패해도 신청·신고 저장은 그대로 돼요
end $$;

-- 사장님 신청이 들어오면
create or replace function private.on_owner_claim() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform private.notify(format(E'🧑‍🍳 사장님 신청: %s (가게 번호 %s)\n연락처: %s%s\n승인: Supabase Table Editor > owner_claims 에서 approved 체크',
    (select name from stalls where id = new.stall_id), new.stall_id, new.contact,
    coalesce(E'\n메모: ' || new.note, '')));
  return new;
end $$;
drop trigger if exists owner_claim_notify on public.owner_claims;
create trigger owner_claim_notify after insert on public.owner_claims
  for each row execute function private.on_owner_claim();

-- 신고가 3번 쌓여 지도에서 숨겨지면 (화면의 HIDE_FLAGS와 같은 숫자)
create or replace function private.on_stall_hidden() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform private.notify(format(E'🚩 신고가 쌓여 지도에서 숨겨졌어요: %s (가게 번호 %s)\n확인: Table Editor > stall_flags\n되살리려면 stalls 에서 flag_count를 0으로',
    new.name, new.id));
  return new;
end $$;
drop trigger if exists stall_hidden_notify on public.stalls;
create trigger stall_hidden_notify after update of flag_count on public.stalls
  for each row when (old.flag_count < 3 and new.flag_count >= 3)
  execute function private.on_stall_hidden();
