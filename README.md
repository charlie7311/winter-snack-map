# 겨울 간식 지도

붕어빵, 호떡, 군고구마부터 타코야끼까지, 지금 열린 겨울 간식 노점을 지도에서 찾는 사이트예요.

- 15개 카테고리 필터(떡볶이·순대·기타 포함, 가게가 많은 품목부터 보여줌. 기타는 음식 이름을 직접 적음), 지금 영업중만 보기, 내 주변 가까운 순 정렬
- 영업 여부는 손님 제보(지금 열림/닫힘)를 2시간 동안 우선으로 보여주고, 제보가 없으면 등록된 영업시간으로 추정
- 손님이 지도에서 위치를 찍어 새 가게(메뉴·결제·영업시간)를 등록할 수 있어요. 관리자가 승인하면 지도에 올라가요
- 가게 등록·제보·신고·사장님 신청·위치 제안은 서버에서 브라우저별로, 그리고 넉넉하게 IP별로 횟수를 제한해요. IP는 비밀 값을 섞은 해시만 저장하고 횟수 기록은 2일, 신고 기록의 해시는 30일이 지나면 다음 요청 때 지워요 (security.sql, moderation.sql)
- 열림/닫힘 제보는 가게 500m 안에서만, 위치 수정 제안은 지금 내 위치 200m 안의 자리만 (폰 위치 권한 필요, 서버에서도 다시 검사)
- 사장님이 "이 가게 사장님이세요?"로 신청하고 관리자가 승인하면, "내 가게" 화면에서 영업중/영업 끝, 요일별 영업시간, 가격, 가게 위치를 직접 바꿀 수 있어요. 사장님 바로가기 링크로 다른 폰·브라우저에서도 들어올 수 있어요
- 손님이 "잘못된 정보 신고"를 할 수 있고, 없어짐·가짜 신고가 3번 쌓이면 지도에서 자동으로 숨겨요
- 가게를 등록할 때 30m 안에 같은 품목 가게가 있으면 중복인지 먼저 물어봐요
- 손님이 "위치가 틀려요"로 맞는 자리를 찍어 위치 수정을 제안하고, 관리자가 승인하면 반영돼요
- 사장님 신청, 위치 수정 제안, 신고로 숨겨짐이 생기면 디스코드로 알림
- 구청 허가 거리가게 공개자료(공공데이터포털, 동작·동대문·도봉·성북·송파)에서 겨울 간식·떡볶이·순대 품목이 적힌 노점 51곳을 골라 `data/public-stalls.json`에 넣었어요. 출처·기준일 표시, 좌표는 근사 위치

## 구조

- `index.html` — 사이트 전체 (Leaflet + OpenStreetMap, 빌드 없음)
- `supabase.sql` — 제보 테이블과 보안 규칙. Supabase SQL Editor에서 실행
- `stalls.sql` — 손님이 등록하는 가게 테이블과 보안 규칙
- `security.sql` — 영업시간 모양 검사, 브라우저·IP별 횟수 제한, 새 가게 승인 후 공개, 가게 등록(add_stall)·제보(add_report) 함수. `categories.sql` 다음에 실행
- `categories.sql` — 품목 목록(떡볶이·순대·기타)과 기타일 때 직접 적는 음식 이름 칸. `stalls.sql` 다음에 실행
- `owners.sql` — 사장님 신청·승인·수정 기능. `stalls.sql` 다음에 실행
- `moderation.sql` — 신고·자동 숨김, 손님이 등록할 때 보낼 수 있는 칸 제한. `categories.sql` 다음에 실행
- `notify.sql` — 디스코드 알림. `owners.sql`, `moderation.sql` 다음에 실행
- `suggestions.sql` — 손님 위치 수정 제안과 승인. `notify.sql` 다음에 실행
- `public-stalls.sql` — 공개자료 가게를 stalls 테이블에도 넣어 사장님 신청이 되게 함. `owners.sql`, `categories.sql` 다음에 실행. `data/public-stalls.json`을 바꾸면 `node data/make-public-sql.js`로 다시 만들고 다시 실행
- `data/public-stalls.json` — 구청 공개자료에서 고른 노점 (id 500~)

## 제보 공유 켜기

`index.html`의 `SUPABASE_URL`, `SUPABASE_ANON_KEY`를 채우면 제보가 Supabase에 저장되어 모든 방문자와 공유돼요. 비워 두면 각자 브라우저에만 저장돼요.

## 배포

GitHub Pages (Settings → Pages → Branch: `main`, 폴더 `/`).

## 처음 설치 순서 (Supabase SQL Editor, 파일마다 New query로)

`supabase.sql` → `stalls.sql` → `categories.sql` → `security.sql` → `owners.sql` → `moderation.sql` → `notify.sql` → `suggestions.sql` → `public-stalls.sql`

## 새 가게 승인

손님이 등록한 가게는 `approved = false`로 들어오고 디스코드로 알림이 와요. Table Editor > `stalls`에서 확인하고 `approved`를 체크하면 지도에 올라가요. 장난 등록은 그 줄을 지우면 돼요.

## 사장님 승인

Supabase Table Editor > `owner_claims`에서 연락처로 사장님인지 확인하고 `approved`를 체크하면 돼요. 사장님은 신청한 브라우저에서 "내 가게"에 들어가고, "내 가게" 화면의 바로가기 링크를 열면 다른 폰·브라우저에서도 들어올 수 있어요.

승인하면 연락처와 메모는 자동으로 지워져요. 승인 전에 연락을 마쳐 주세요. 승인하지 않을 신청은 확인한 뒤 줄을 지워 주세요(신청 화면에서 그렇게 안내해요). 자동 삭제 기능 전에 승인한 신청의 연락처는 SQL Editor에서:

```sql
update owner_claims set contact = '확인 완료', note = null where approved;
```

## 위치 수정 제안 승인

Table Editor > `location_suggestions`에서 `approved`를 체크하면 그 가게 위치가 바로 바뀌어요. 디스코드 알림에 지금 위치와 제안 위치 지도 링크, 거리 차이가 같이 와요. 승인하지 않을 제안은 그냥 두거나 지우면 돼요.

## 신고로 숨겨진 가게

- 신고 내용: Table Editor > `stall_flags` (gone 없어짐, fake 가짜)
- 되살리기: `stalls`에서 그 가게의 `flag_count`를 0으로 바꾸고, `stall_flags`에서 그 가게 신고를 지우기
- 아예 지우기: `stalls`에서 그 가게 줄을 지우면 신고·사장님 신청도 같이 지워져요

## 지도 그림

지금은 OpenStreetMap 공식 지도 서버를 써요. 이 서버는 사용량이 많은 서비스엔 쓰지 말라는 정책이 있어서, 사람이 많이 몰리면 키를 받는 지도(Stadia Maps, MapTiler, VWorld 등)로 `index.html`의 `L.tileLayer` 줄을 바꿔야 해요.

## 디스코드 알림 켜기

1. 디스코드에서 알림 받을 서버 채널 → 채널 설정(톱니) → 연동 → 웹후크 → 새 웹후크 → "웹후크 URL 복사"
2. Supabase SQL Editor에서 (URL은 GitHub에 올리지 마세요):

```sql
insert into private.settings (key, value) values ('discord_webhook', '여기에_복사한_URL')
on conflict (key) do update set value = excluded.value;
```
