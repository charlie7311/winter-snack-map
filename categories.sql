-- 겨울 간식 지도: 품목 목록(떡볶이·순대·기타 추가)과 기타일 때 직접 적는 음식 이름
-- Supabase SQL Editor에 통째로 붙여넣고 Run. stalls.sql 다음에 실행. 여러 번 실행해도 괜찮아요.

-- 기타를 고르면 무엇을 파는지 직접 적는 칸 (예: 떡볶이, 꼬치어묵)
alter table public.stalls add column if not exists other_food text;

alter table public.stalls drop constraint if exists stalls_other_food_check;
alter table public.stalls add constraint stalls_other_food_check
  check (char_length(other_food) between 1 and 30);

-- 품목 목록에 떡볶이·순대·기타 추가 (원래 규칙은 stalls.sql에 있어요). 품목을 또 늘리면 여기와 index.html의 CATS를 같이 고쳐요
alter table public.stalls drop constraint if exists stalls_types_check;
alter table public.stalls add constraint stalls_types_check check (
  cardinality(types) between 1 and 15
  and types <@ array['붕어빵','호떡','군고구마','군밤','계란빵','국화빵','어묵','타코야끼','델리만쥬','땅콩과자','와플','옥수수','떡볶이','순대','기타']
);

-- 기타를 골랐으면 음식 이름을 꼭 적어야 해요
alter table public.stalls drop constraint if exists stalls_other_food_required;
alter table public.stalls add constraint stalls_other_food_required
  check (not ('기타' = any(types)) or other_food is not null);
