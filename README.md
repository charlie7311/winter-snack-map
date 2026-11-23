# 겨울 간식 지도

붕어빵, 호떡, 군고구마부터 타코야끼까지, 지금 열린 겨울 간식 노점을 지도에서 찾는 사이트예요.

- 12개 카테고리 필터, 지금 영업중만 보기, 내 주변 가까운 순 정렬
- 영업 여부는 손님 제보(지금 열림/닫힘)를 2시간 동안 우선으로 보여주고, 제보가 없으면 등록된 영업시간으로 추정
- 손님이 지도에서 위치를 찍어 새 가게(메뉴·결제·영업시간)를 등록할 수 있어요
- 사장님이 "이 가게 사장님이세요?"로 신청하고 관리자가 승인하면, "내 가게" 화면에서 영업중/영업 끝, 요일별 영업시간, 가격을 직접 바꿀 수 있어요
- 구청 허가 거리가게 공개자료(공공데이터포털, 동작·동대문·도봉·성북·송파)에서 겨울 간식 품목이 적힌 노점 37곳을 골라 `data/public-stalls.json`에 넣었어요. 출처·기준일 표시, 좌표는 근사 위치

## 구조

- `index.html` — 사이트 전체 (Leaflet + OpenStreetMap, 빌드 없음)
- `supabase.sql` — 제보 테이블과 보안 규칙. Supabase SQL Editor에서 실행
- `stalls.sql` — 손님이 등록하는 가게 테이블과 보안 규칙
- `owners.sql` — 사장님 신청·승인·수정 기능. `stalls.sql` 다음에 실행
- `public-stalls.sql` — 공개자료 가게를 stalls 테이블에도 넣어 사장님 신청이 되게 함. `owners.sql` 다음에 실행. `data/public-stalls.json`을 바꾸면 다시 만들어야 해요
- `data/public-stalls.json` — 구청 공개자료에서 고른 노점 (id 500~)

## 제보 공유 켜기

`index.html`의 `SUPABASE_URL`, `SUPABASE_ANON_KEY`를 채우면 제보가 Supabase에 저장되어 모든 방문자와 공유돼요. 비워 두면 각자 브라우저에만 저장돼요.

## 배포

GitHub Pages (Settings → Pages → Branch: `main`, 폴더 `/`).

## 사장님 승인

Supabase Table Editor > `owner_claims`에서 연락처로 사장님인지 확인하고 `approved`를 체크하면 돼요. 사장님은 신청한 폰 브라우저로만 "내 가게"에 들어갈 수 있어요. 폰을 바꾸면 다시 신청해야 해요.
