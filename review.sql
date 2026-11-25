-- 간식 지도: 디스코드 알림의 승인 링크 (새 가게, 위치 수정 제안)
-- Supabase SQL Editor에 통째로 붙여넣고 Run. suggestions.sql 다음에 실행. 여러 번 실행해도 괜찮아요.
--
-- 링크가 있으면 누구나 승인·삭제할 수 있으니 알림 채널은 본인만 보는 비공개 채널로 두세요.
-- 링크는 한 번 쓰거나 7일이 지나면 못 써요. 사장님 승인은 연락처를 봐야 해서 지금처럼 Table Editor에서 해요.
-- 사이트 주소가 바뀌면: update private.settings set value = 'https://새주소/' where key = 'site_url';

-- 링크를 열었을 때 보여 줄 내용 (보기만, 아무것도 안 바꿈)
create or replace function public.review_item(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, private as $$
declare l record; s record; g record;
begin
  select * into l from private.review_links where token_hash = _token_hash(p_token) and created_at > now() - interval '7 days';
  if not found then raise exception 'invalid link'; end if;
  if l.kind = 'stall' then
    select * into s from stalls where id = l.ref_id;
    if not found or s.approved or l.used_at is not null then raise exception 'already handled'; end if;
    return jsonb_build_object('kind', 'stall', 'name', s.name, 'area', s.area, 'types', s.types, 'other_food', s.other_food,
      'menu', s.menu, 'pay', s.pay, 'hours', s.hours, 'lat', s.lat, 'lng', s.lng);
  end if;
  select * into g from location_suggestions where id = l.ref_id;
  if not found or g.approved or l.used_at is not null then raise exception 'already handled'; end if;
  if g.lat <> l.lat or g.lng <> l.lng then raise exception 'changed'; end if;
  select * into s from stalls where id = g.stall_id;
  return jsonb_build_object('kind', 'location', 'name', s.name, 'area', s.area, 'lat', g.lat, 'lng', g.lng,
    'old_lat', s.lat, 'old_lng', s.lng, 'meters', round(meters(s.lat, s.lng, g.lat, g.lng)));
end $$;

-- 승인하거나(true) 지우기(false). 승인 대기 중인 것만 건드려요: 이미 지도에 올라간 가게는 이 링크로 절대 지워지지 않아요.
create or replace function public.review_decide(p_token text, p_approve boolean) returns void
language plpgsql security definer set search_path = public, private as $$
declare l record; n integer;
begin
  if p_approve is null then raise exception 'bad decision'; end if;
  select * into l from private.review_links where token_hash = _token_hash(p_token) and created_at > now() - interval '7 days' for update;
  if not found then raise exception 'invalid link'; end if;
  if l.used_at is not null then raise exception 'already handled'; end if;
  if l.kind = 'stall' then
    if p_approve then update stalls set approved = true where id = l.ref_id and not approved;
    else delete from stalls where id = l.ref_id and not approved; end if;
  else
    if exists (select 1 from location_suggestions where id = l.ref_id and not approved and (lat <> l.lat or lng <> l.lng)) then raise exception 'changed'; end if;
    if p_approve then update location_suggestions set approved = true where id = l.ref_id and not approved and lat = l.lat and lng = l.lng;
    else delete from location_suggestions where id = l.ref_id and not approved and lat = l.lat and lng = l.lng; end if;
  end if;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'already handled'; end if;
  update private.review_links set used_at = now() where token_hash = l.token_hash;
end $$;

revoke all on function public.review_item(text), public.review_decide(text, boolean) from public;
grant execute on function public.review_item(text), public.review_decide(text, boolean) to anon, authenticated;
