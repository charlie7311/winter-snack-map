-- 겨울 간식 지도: 공개 전 보안 (영업시간 검사, IP별 횟수 제한, 새 가게 승인 후 공개)
-- Supabase SQL Editor에 통째로 붙여넣고 Run. categories.sql 다음에 실행. 여러 번 실행해도 괜찮아요.
--
-- 새 가게 승인: Table Editor > stalls 에서 approved가 false인 줄을 보고, 괜찮으면 approved를 체크(true).
--              이상한 가게는 그 줄을 지우면 돼요. 새 등록이 오면 디스코드로 알려 줘요.

-- 0) 다른 파일에도 있는 도우미 (이 파일만 먼저 돌려도 되게)
create or replace function public._token_hash(p_token text) returns text
language sql immutable as $$ select encode(sha256(convert_to(p_token, 'UTF8')), 'hex') $$;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- 1) 영업시간은 일~토 7칸, 각 칸은 null(휴무) 또는 ["HH:MM","HH:MM"]만
--    (이게 없으면 영업시간 칸에 코드를 넣어 다른 방문자 화면에서 실행하거나 화면을 멈출 수 있었어요)
create or replace function public.valid_hours(h jsonb) returns boolean
language plpgsql immutable as $$
declare d jsonb;
begin
  if h is null or jsonb_typeof(h) = 'null' then return true; end if;
  if jsonb_typeof(h) <> 'array' or jsonb_array_length(h) <> 7 then return false; end if;
  for d in select * from jsonb_array_elements(h) loop
    if jsonb_typeof(d) = 'null' then continue; end if;
    if jsonb_typeof(d) <> 'array' or jsonb_array_length(d) <> 2
       or jsonb_typeof(d->0) <> 'string' or jsonb_typeof(d->1) <> 'string'
       or (d->>0) !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or (d->>1) !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       or d->>0 = d->>1 then
      return false;
    end if;
  end loop;
  return true;
end $$;
alter table public.stalls drop constraint if exists stalls_hours_valid;
alter table public.stalls add constraint stalls_hours_valid check (valid_hours(hours));

-- 2) IP별 횟수 제한. IP 원문은 저장하지 않고 sha256만 이틀 동안 보관해요.
create table if not exists private.rate_hits (
  ip_hash    text not null,
  action     text not null,
  created_at timestamptz not null default now()
);
create index if not exists rate_hits_lookup on private.rate_hits (action, ip_hash, created_at desc);
alter table private.rate_hits enable row level security;

-- Supabase 앞단(Cloudflare)이 넣어 주는 진짜 접속 IP. 사용자가 바꿀 수 없는 헤더를 먼저 봐요.
create or replace function private.client_ip() returns text
language plpgsql stable as $$
declare h json;
begin
  h := nullif(current_setting('request.headers', true), '')::json;
  return coalesce(nullif(h->>'cf-connecting-ip', ''), nullif(h->>'x-real-ip', ''),
                  nullif(trim(split_part(h->>'x-forwarded-for', ',', 1)), ''), 'unknown');
end $$;

-- 같은 IP가 p_window 안에 p_action을 p_max번 넘게 하면 막아요.
create or replace function private.hit(p_action text, p_max integer, p_window interval) returns void
language plpgsql security definer set search_path = public, private as $$
declare ip text := _token_hash(private.client_ip());
begin
  if (select count(*) from private.rate_hits
      where action = p_action and ip_hash = ip and created_at > now() - p_window) >= p_max then
    raise exception 'rate limited';
  end if;
  insert into private.rate_hits (ip_hash, action) values (ip, p_action);
  if random() < 0.02 then delete from private.rate_hits where created_at < now() - interval '2 days'; end if;
end $$;

-- 확인용: Supabase가 어떤 헤더로 IP를 알려 주는지 (IP 자체는 알려 주지 않음)
create or replace function public.rate_limit_source() returns text
language plpgsql stable as $$
declare h json;
begin
  h := nullif(current_setting('request.headers', true), '')::json;
  return case when nullif(h->>'cf-connecting-ip', '') is not null then 'cf-connecting-ip'
              when nullif(h->>'x-real-ip', '') is not null then 'x-real-ip'
              when nullif(h->>'x-forwarded-for', '') is not null then 'x-forwarded-for'
              else 'none' end;
end $$;
grant execute on function public.rate_limit_source() to anon, authenticated;

-- 3) 새 가게는 승인(approved) 후에 지도에 보여요. 지금까지 있던 가게는 모두 승인된 걸로.
alter table public.stalls add column if not exists approved boolean not null default true;
drop policy if exists "anyone can read stalls" on public.stalls;
drop policy if exists "anyone can read approved stalls" on public.stalls;
create policy "anyone can read approved stalls" on public.stalls for select to anon, authenticated using (approved);

-- 4) 손님 가게 등록은 이 함수로만 (IP당 1시간 3곳, 하루 10곳). 등록되면 승인 대기.
revoke insert on public.stalls from anon, authenticated;
create or replace function public.add_stall(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform private.hit('stall_hour', 3, interval '1 hour');
  perform private.hit('stall_day', 10, interval '1 day');
  if coalesce(jsonb_typeof(p->'types'), '') <> 'array' then raise exception 'bad types'; end if;
  insert into stalls (name, area, lat, lng, types, menu, pay, hours, other_food, approved)
  values (trim(p->>'name'), nullif(trim(p->>'area'), ''), (p->>'lat')::double precision, (p->>'lng')::double precision,
          array(select jsonb_array_elements_text(p->'types')), nullif(trim(p->>'menu'), ''), nullif(trim(p->>'pay'), ''),
          nullif(p->'hours', 'null'::jsonb), nullif(trim(p->>'other_food'), ''), false)
  returning id into v_id;
  begin
    perform private.notify(format(E'🆕 새 가게 등록 (승인 대기): %s · %s (가게 번호 %s)\n위치: https://www.openstreetmap.org/?mlat=%s&mlon=%s#map=19/%s/%s\n승인: Table Editor > stalls 에서 approved 체크, 이상하면 줄 삭제',
      trim(p->>'name'), (select array_to_string(types, ', ') from stalls where id = v_id), v_id,
      p->>'lat', p->>'lng', p->>'lat', p->>'lng'));
  exception when others then null;   -- 알림이 안 돼도 등록은 저장
  end;
  return v_id;
end $$;
revoke all on function public.add_stall(jsonb) from public;
grant execute on function public.add_stall(jsonb) to anon, authenticated;

-- 두 지점 사이 거리(m). 몇 백 m 안팎만 보면 돼서 간단한 평면 근사로 충분해요.
create or replace function public.meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 111320 * sqrt(power(lat2 - lat1, 2) + power((lng2 - lng1) * cos(radians(lat1)), 2))
$$;

-- 5) 영업 제보도 이 함수로만: 가게 500m 안에서만 (폰 위치), 같은 IP는 한 가게에 10분에 1번, 전체 1시간 30번
--    shortcut: 위치는 폰이 알려 주는 값이라 작정하고 속이면 못 막아요. 집에서 장난으로 누르는 건 막혀요.
revoke insert on public.reports from anon, authenticated;
drop policy if exists "anyone can report" on public.reports;
drop function if exists public.add_report(bigint, boolean);
create or replace function public.add_report(p_stall_id bigint, p_is_open boolean, p_lat double precision, p_lng double precision) returns void
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  select lat, lng into s from stalls where id = p_stall_id and approved;
  if p_is_open is null or not found then raise exception 'no such stall'; end if;
  if p_lat is null or p_lng is null or meters(s.lat, s.lng, p_lat, p_lng) > 500 then raise exception 'too far'; end if;
  perform private.hit('report:' || p_stall_id, 1, interval '10 minutes');
  perform private.hit('report_all', 30, interval '1 hour');
  insert into reports (stall_id, is_open) values (p_stall_id, p_is_open);
end $$;
revoke all on function public.add_report(bigint, boolean, double precision, double precision) from public;
grant execute on function public.add_report(bigint, boolean, double precision, double precision) to anon, authenticated;
