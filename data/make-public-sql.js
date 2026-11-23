// data/public-stalls.json → public-stalls.sql 다시 만들기:  node data/make-public-sql.js
// JSON에 가게를 추가하거나 고친 뒤 실행하고, 나온 public-stalls.sql을 Supabase SQL Editor에서 Run 하세요.
const fs = require("fs"), path = require("path");
const root = path.join(__dirname, ".."), j = JSON.parse(fs.readFileSync(path.join(__dirname, "public-stalls.json"), "utf8"));
const q = v => v == null ? "null" : "'" + String(v).replace(/'/g, "''") + "'";
const hours = h => h == null ? "null" : q(JSON.stringify(typeof h === "string" ? Array(7).fill(h.split("-")) : h)) + "::jsonb";
const rows = j.stalls.map(s => `  (${s.id}, ${q(s.name)}, ${q(s.area)}, ${s.lat}, ${s.lng}, ${q("{" + s.types.join(",") + "}")}, ${q(s.menu)}, ${hours(s.hours)})`);
fs.writeFileSync(path.join(root, "public-stalls.sql"), `-- 겨울 간식 지도: 구청 공개자료 가게(data/public-stalls.json)를 stalls 테이블에도 넣기
-- 이렇게 해야 이 가게들도 "이 가게 사장님이세요?" 신청과 "내 가게" 수정이 돼요.
-- Supabase SQL Editor에 통째로 붙여넣고 Run. owners.sql, categories.sql 다음에 실행. 여러 번 실행해도 괜찮아요(이미 있는 가게는 건드리지 않음).
-- 출처·기준일 같은 정보는 계속 data/public-stalls.json에서 보여주고, 영업시간·가격·사장님 상태는 이 테이블 값을 써요.
-- id 500~999는 공개자료 가게용 (손님 등록 가게는 1000부터).
-- 직접 고치지 말고 node data/make-public-sql.js 로 다시 만드세요.

insert into public.stalls (id, name, area, lat, lng, types, menu, hours)
overriding system value
values
${rows.join(",\n")}
on conflict (id) do nothing;
`);
console.log(`public-stalls.sql: ${rows.length}곳`);
