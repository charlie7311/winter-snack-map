-- 겨울 간식 지도: 사장님 기능 ("제 가게예요" 신청 → 관리자 승인 → "내 가게" 화면)
-- Supabase 대시보드 > SQL Editor에 통째로 붙여넣고 Run 하면 됩니다. (여러 번 실행해도 괜찮아요)
-- stalls.sql을 먼저 실행한 뒤에 실행하세요.
--
-- 승인하는 법: Table Editor > owner_claims 에서 연락처로 사장님인지 확인하고 approved 칸을 체크(true)하면 끝.
-- 사장님 폰 브라우저에 저장된 비밀 키로 본인을 확인해요. 그래서 다른 폰·브라우저에서는 다시 신청해야 해요.

-- 1) 사장님이 직접 누르는 "지금 영업중/영업 끝" 상태
alter table public.stalls add column if not exists owner_open    boolean;
alter table public.stalls add column if not exists owner_open_at timestamptz;

-- 2) 사장님 신청. 연락처가 들어 있어서 밖에서는 아무도 읽거나 쓸 수 없고, 아래 함수로만 다뤄요.
create table if not exists public.owner_claims (
  id          bigint generated always as identity primary key,
  stall_id    bigint not null references public.stalls(id) on delete cascade,
  token_hash  text   not null,              -- 비밀 키의 sha256 (키 원문은 저장 안 함)
  contact     text   not null check (char_length(contact) between 2 and 60),
  note        text   check (char_length(note) <= 200),
  approved    boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (stall_id, token_hash)
);
alter table public.owner_claims enable row level security;   -- 정책이 없으니 anon은 직접 접근 불가
revoke all on public.owner_claims from anon, authenticated;

create or replace function public._token_hash(p_token text) returns text
language sql immutable as $$ select encode(sha256(convert_to(p_token, 'UTF8')), 'hex') $$;

-- "제 가게예요" 신청
create or replace function public.claim_stall(p_stall_id bigint, p_token text, p_contact text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_token is null or char_length(p_token) < 32 or char_length(p_token) > 100 then raise exception 'bad token'; end if;
  if not exists (select 1 from stalls where id = p_stall_id) then raise exception 'no such stall'; end if;
  -- 장난 신청이 쌓이지 않게: 승인 안 된 신청은 가게당 5개까지
  if (select count(*) from owner_claims where stall_id = p_stall_id and not approved) >= 5 then
    raise exception 'too many pending claims';
  end if;
  insert into owner_claims (stall_id, token_hash, contact, note)
  values (p_stall_id, _token_hash(p_token), trim(p_contact), nullif(trim(p_note), ''))
  on conflict (stall_id, token_hash) do update set contact = excluded.contact, note = excluded.note;
end $$;

-- 이 키로 신청한 가게와 승인 여부
create or replace function public.owner_stalls(p_token text)
returns table (stall_id bigint, approved boolean) language sql stable security definer set search_path = public as $$
  select stall_id, approved from owner_claims where token_hash = _token_hash(p_token) order by created_at
$$;

-- 승인된 사장님만: p_patch에 들어 있는 항목만 바꿔요.
--   {"open": true|false}                       지금 영업중 / 영업 끝
--   {"hours": [[ "15:00","21:00" ], null, ...]} 일~토 7칸, null = 휴무
--   {"menu": "팥붕 3개 2,000원"}
create or replace function public.owner_update(p_token text, p_stall_id bigint, p_patch jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  if not exists (select 1 from owner_claims
                 where stall_id = p_stall_id and token_hash = _token_hash(p_token) and approved) then
    raise exception 'not an approved owner' using errcode = '42501';
  end if;
  if p_patch ? 'hours' then
    if jsonb_typeof(p_patch->'hours') <> 'array' or jsonb_array_length(p_patch->'hours') <> 7 then
      raise exception 'bad hours';
    end if;
    for d in select * from jsonb_array_elements(p_patch->'hours') loop
      if jsonb_typeof(d) <> 'null' and not (
           jsonb_typeof(d) = 'array' and jsonb_array_length(d) = 2
           and d->>0 ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' and d->>1 ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
           and d->>0 <> d->>1) then
        raise exception 'bad hours';
      end if;
    end loop;
    update stalls set hours = p_patch->'hours' where id = p_stall_id;
  end if;
  if p_patch ? 'menu' then
    update stalls set menu = nullif(trim(p_patch->>'menu'), '') where id = p_stall_id;   -- 길이는 테이블 규칙(100자)이 검사
  end if;
  if p_patch ? 'open' then
    if jsonb_typeof(p_patch->'open') <> 'boolean' then raise exception 'bad open'; end if;
    update stalls set owner_open = (p_patch->>'open')::boolean, owner_open_at = now() where id = p_stall_id;
  end if;
end $$;

revoke all on function public.claim_stall(bigint, text, text, text), public.owner_stalls(text),
                       public.owner_update(text, bigint, jsonb) from public;
grant execute on function public.claim_stall(bigint, text, text, text), public.owner_stalls(text),
                          public.owner_update(text, bigint, jsonb) to anon, authenticated;
