-- 겨울 간식 지도: 손님의 가게 위치 수정 제안 → 관리자 승인 → 위치 반영
-- Supabase SQL Editor에 통째로 붙여넣고 Run. moderation.sql, notify.sql 다음에 실행. 여러 번 실행해도 괜찮아요.
--
-- 승인하는 법: Table Editor > location_suggestions 에서 approved를 체크(true)하면 그 가게 위치가 바로 바뀌어요.
-- 디스코드 알림에 지금 위치·제안 위치 지도 링크가 같이 와요. 승인하지 않을 제안은 그냥 두거나 지우면 돼요.

create table if not exists public.location_suggestions (
  id             bigint generated always as identity primary key,
  stall_id       bigint not null references public.stalls(id) on delete cascade,
  lat            double precision not null check (lat between 33 and 39),
  lng            double precision not null check (lng between 124 and 132),
  reporter_hash  text   not null,     -- 제안한 브라우저의 무작위 키 sha256 (누군지는 알 수 없음)
  approved       boolean not null default false,
  applied_at     timestamptz,
  created_at     timestamptz not null default now(),
  unique (stall_id, reporter_hash)   -- 같은 사람이 다시 보내면 새 위치로 바뀜
);
alter table public.location_suggestions enable row level security;   -- 정책 없음 = 밖에서 직접 못 읽고 못 씀
revoke all on public.location_suggestions from anon, authenticated;

create or replace function public.suggest_location(p_stall_id bigint, p_reporter text, p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_reporter is null or char_length(p_reporter) < 32 or char_length(p_reporter) > 100 then raise exception 'bad reporter'; end if;
  if not exists (select 1 from stalls where id = p_stall_id) then raise exception 'no such stall'; end if;
  -- 장난이 쌓이지 않게: 확인 안 된 제안은 가게당 10개까지 (같은 사람이 다시 보내는 건 괜찮음)
  if (select count(*) from location_suggestions
      where stall_id = p_stall_id and not approved and reporter_hash <> _token_hash(p_reporter)) >= 10 then
    raise exception 'too many suggestions';
  end if;
  insert into location_suggestions (stall_id, lat, lng, reporter_hash)
  values (p_stall_id, p_lat, p_lng, _token_hash(p_reporter))
  on conflict (stall_id, reporter_hash) do update
    set lat = excluded.lat, lng = excluded.lng, created_at = now(), approved = false, applied_at = null;
end $$;
revoke all on function public.suggest_location(bigint, text, double precision, double precision) from public;
grant execute on function public.suggest_location(bigint, text, double precision, double precision) to anon, authenticated;

-- 승인(approved: false → true)하면 가게 위치에 반영
create or replace function public.apply_location_suggestion() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.approved and not old.approved then
    update stalls set lat = new.lat, lng = new.lng where id = new.stall_id;
    new.applied_at := now();
  end if;
  return new;
end $$;
drop trigger if exists location_suggestion_apply on public.location_suggestions;
create trigger location_suggestion_apply before update on public.location_suggestions
  for each row execute function public.apply_location_suggestion();

-- 제안이 들어오면 디스코드 알림 (notify.sql을 안 돌렸어도 제안 저장은 그대로 돼요)
create or replace function public.notify_location_suggestion() returns trigger
language plpgsql security definer set search_path = public as $$
declare s record; meters integer;
begin
  if tg_op = 'UPDATE' and old.lat = new.lat and old.lng = new.lng then return new; end if;   -- 승인할 때는 다시 안 보냄
  select name, lat, lng into s from stalls where id = new.stall_id;
  meters := round(111320 * sqrt(power(new.lat - s.lat, 2) + power((new.lng - s.lng) * cos(radians(s.lat)), 2)));
  begin
    perform private.notify(format(
      E'📍 위치 수정 제안: %s (가게 번호 %s), 약 %sm 이동\n지금: https://www.openstreetmap.org/?mlat=%s&mlon=%s#map=19/%s/%s\n제안: https://www.openstreetmap.org/?mlat=%s&mlon=%s#map=19/%s/%s\n승인: Table Editor > location_suggestions 에서 approved 체크',
      s.name, new.stall_id, meters, s.lat, s.lng, s.lat, s.lng, new.lat, new.lng, new.lat, new.lng));
  exception when others then null;
  end;
  return new;
end $$;
drop trigger if exists location_suggestion_notify on public.location_suggestions;
create trigger location_suggestion_notify after insert or update of lat, lng on public.location_suggestions
  for each row execute function public.notify_location_suggestion();
