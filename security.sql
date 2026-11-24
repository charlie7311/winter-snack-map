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

-- 2) 횟수 제한: 브라우저별로 주로 걸고, IP는 넉넉하게만 걸어요 (학교 와이파이·통신사는 여러 명이 IP 하나를 같이 써요).
--    IP 원문은 저장하지 않아요. 이 데이터베이스만 아는 비밀 값(ip_salt)을 섞은 해시만 두고, 2일 지난 건 다음 요청 때 지워요.
--    shortcut: 브라우저 키를 계속 바꾸는 스크립트는 IP 제한까지만 막혀요. 심해지면 로그인이나 캡차를 붙여요.
create table if not exists private.settings (key text primary key, value text not null);
alter table private.settings enable row level security;
insert into private.settings (key, value) values ('ip_salt', gen_random_uuid()::text || gen_random_uuid()::text) on conflict (key) do nothing;

create table if not exists private.rate_hits (
  ip_hash    text not null,      -- 'ip:' + IP 해시 또는 'key:' + 브라우저 키 해시
  action     text not null,
  created_at timestamptz not null default now()
);
create index if not exists rate_hits_lookup on private.rate_hits (action, ip_hash, created_at desc);
create index if not exists rate_hits_age on private.rate_hits (created_at);
alter table private.rate_hits enable row level security;
delete from private.rate_hits where ip_hash not like 'ip:%' and ip_hash not like 'key:%';   -- 비밀 값 없이 저장했던 예전 횟수 기록

-- Cloudflare가 넣는 접속 IP. IPv6는 한 사람이 주소를 많이 쓰므로 앞 64비트만 봐요.
create or replace function private.client_ip() returns text
language plpgsql stable as $$
declare ip text := nullif(nullif(current_setting('request.headers', true), '')::json->>'cf-connecting-ip', '');
begin
  if ip is null then return 'unknown'; end if;
  return case when family(ip::inet) = 6 then network(set_masklen(ip::inet, 64))::text else host(ip::inet) end;
exception when others then return 'unknown';
end $$;

create or replace function private.ip_hash() returns text
language sql stable security definer set search_path = public, private as $$
  select 'ip:' || _token_hash((select value from private.settings where key = 'ip_salt') || private.client_ip())
$$;

-- p_window 안에 같은 브라우저가 p_key_max번, 같은 IP가 p_ip_max번 넘게 하면 막아요.
drop function if exists private.hit(text, integer, interval);
create or replace function private.hit(p_action text, p_key text, p_key_max integer, p_ip_max integer, p_window interval) returns void
language plpgsql security definer set search_path = public, private as $$
declare v_ip text := private.ip_hash(); v_key text;
begin
  perform pg_advisory_xact_lock(hashtext(p_action || v_ip));   -- 동시에 여러 번 보내서 제한을 넘지 못하게
  delete from private.rate_hits where created_at < now() - interval '2 days';
  if (select count(*) from private.rate_hits where action = p_action and ip_hash = v_ip and created_at > now() - p_window) >= p_ip_max then
    raise exception 'rate limited';
  end if;
  insert into private.rate_hits (ip_hash, action) values (v_ip, p_action);
  if p_key is not null then
    v_key := 'key:' || _token_hash(p_key);
    if (select count(*) from private.rate_hits where action = p_action and ip_hash = v_key and created_at > now() - p_window) >= p_key_max then
      raise exception 'rate limited';
    end if;
    insert into private.rate_hits (ip_hash, action) values (v_key, p_action);
  end if;
end $$;

drop function if exists public.rate_limit_source();   -- 점검용이었고 이제 안 써요

-- 3) 새 가게는 승인(approved) 후에 지도에 보여요. 지금까지 있던 가게는 모두 승인된 걸로.
alter table public.stalls add column if not exists approved boolean not null default true;
drop policy if exists "anyone can read stalls" on public.stalls;
drop policy if exists "anyone can read approved stalls" on public.stalls;
create policy "anyone can read approved stalls" on public.stalls for select to anon, authenticated using (approved);

-- 4) 손님 가게 등록은 이 함수로만 (브라우저당 1시간 3곳·하루 10곳, IP당 1시간 30곳·하루 100곳). 등록되면 승인 대기.
revoke insert on public.stalls from anon, authenticated;
drop function if exists public.add_stall(jsonb);
create or replace function public.add_stall(p jsonb, p_key text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform private.hit('stall_hour', p_key, 3, 30, interval '1 hour');
  perform private.hit('stall_day', p_key, 10, 100, interval '1 day');
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
revoke all on function public.add_stall(jsonb, text) from public;
grant execute on function public.add_stall(jsonb, text) to anon, authenticated;

-- 두 지점 사이 거리(m). 몇 백 m 안팎만 보면 돼서 간단한 평면 근사로 충분해요.
create or replace function public.meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 111320 * sqrt(power(lat2 - lat1, 2) + power((lng2 - lng1) * cos(radians(lat1)), 2))
$$;

-- 5) 영업 제보도 이 함수로만: 가게 500m 안에서만 (폰 위치). 한 가게에 10분 동안 브라우저당 1번·IP당 20번, 전체 1시간에 브라우저당 30번·IP당 600번
--    shortcut: 위치는 폰이 알려 주는 값이라 작정하고 속이면 못 막아요. 집에서 장난으로 누르는 건 막혀요.
revoke insert on public.reports from anon, authenticated;
drop policy if exists "anyone can report" on public.reports;
drop function if exists public.add_report(bigint, boolean);
drop function if exists public.add_report(bigint, boolean, double precision, double precision);
create or replace function public.add_report(p_stall_id bigint, p_is_open boolean, p_lat double precision, p_lng double precision, p_key text default null) returns void
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  select lat, lng into s from stalls where id = p_stall_id and approved;
  if p_is_open is null or not found then raise exception 'no such stall'; end if;
  if p_lat is null or p_lng is null or meters(s.lat, s.lng, p_lat, p_lng) > 500 then raise exception 'too far'; end if;
  perform private.hit('report:' || p_stall_id, p_key, 1, 20, interval '10 minutes');
  perform private.hit('report_all', p_key, 30, 600, interval '1 hour');
  insert into reports (stall_id, is_open) values (p_stall_id, p_is_open);
end $$;
revoke all on function public.add_report(bigint, boolean, double precision, double precision, text) from public;
grant execute on function public.add_report(bigint, boolean, double precision, double precision, text) to anon, authenticated;
