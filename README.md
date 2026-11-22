# 겨울 간식 지도

붕어빵, 호떡, 군고구마부터 타코야끼까지, 지금 열린 겨울 간식 노점을 지도에서 찾는 사이트예요.

- 12개 카테고리 필터, 지금 영업중만 보기, 내 주변 가까운 순 정렬
- 영업 여부는 손님 제보(지금 열림/닫힘)를 2시간 동안 우선으로 보여주고, 제보가 없으면 등록된 영업시간으로 추정
- 손님이 지도에서 위치를 찍어 새 가게(메뉴·결제·영업시간)를 등록할 수 있어요
- "샘플" 표시가 붙은 가게는 예시(가상)예요

## 구조

- `index.html` — 사이트 전체 (Leaflet + OpenStreetMap, 빌드 없음)
- `supabase.sql` — 제보 테이블과 보안 규칙. Supabase SQL Editor에서 실행
- `stalls.sql` — 손님이 등록하는 가게 테이블과 보안 규칙

## 제보 공유 켜기

`index.html`의 `SUPABASE_URL`, `SUPABASE_ANON_KEY`를 채우면 제보가 Supabase에 저장되어 모든 방문자와 공유돼요. 비워 두면 각자 브라우저에만 저장돼요.

## 배포

GitHub Pages (Settings → Pages → Branch: `main`, 폴더 `/`).
