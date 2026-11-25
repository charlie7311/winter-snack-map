// 영업 상태 규칙 검사:  node test-status.js
const fs = require("fs"), path = require("path"), assert = require("assert");
const html = fs.readFileSync(path.join(__dirname, "index.html"), "utf8").replace(/\r\n/g, "\n");
const part = (from, to) => { const i = html.indexOf(from), j = html.indexOf(to, i); assert(i >= 0 && j > i, from); return html.slice(i, j); };
const code = part("const toMin =", "// ---- 손님 제보 ----") + part("const OWNER_FRESH_MIN", "const STORE_KEY") + part("function ago(ts)", "// ---- 지도 ----");
// KST 2026-11-25(수) 시각 → ms
const T = (hm, daysAgo = 0) => Date.parse(`2026-11-25T${hm}:00+09:00`) - daysAgo * 864e5;
function at(hm, { reports = [], owner, hours = null } = {}) {
  const t = T(hm), fakeDate = { now: () => t };
  const api = new Function("Date", "DAYS", "reportsFor", code + "\nreturn { status };")(fakeDate, ["일","월","화","수","목","금","토"], () => reports.map(([open, when, d = 0, o = false]) => ({ open, at: T(when, d), owner: o })).sort((a, b) => b.at - a.at));
  const [h, m] = hm.split(":").map(Number);
  return api.status({ id: 1, hours, ownerOpen: owner ? owner[0] : null, ownerAt: owner ? T(owner[1], owner[2] || 0) : null }, { day: 3, min: h * 60 + m });
}
const O = true, X = false, daily = Array(7).fill(["15:00", "21:00"]);
const is = (s, state, re) => { assert.strictEqual(s.state, state, s.report); if (re) assert.match(s.report, re); };

// 방금 확인
is(at("20:00", { reports: [[O, "19:50"]] }), "open", /손님 제보 · 10분 전/);
is(at("20:00", { reports: [[X, "19:50"]] }), "closed");
is(at("20:00", { owner: [O, "19:00"] }), "open", /사장님 · 1시간 전/);
// 사장님 vs 손님
is(at("20:00", { owner: [O, "19:30"], reports: [[X, "19:50"]] }), "open");      // 사장님이 1시간 안에 눌렀으면 사장님
is(at("20:00", { owner: [O, "18:00"], reports: [[X, "19:50"]] }), "closed");    // 오래됐고 손님이 더 새로우면 손님
is(at("20:00", { owner: [X, "18:00"], reports: [[O, "17:50"]] }), "closed");    // 손님이 더 오래됐으면 사장님
// 거짓 제보 하나로는 안 뒤집힘
is(at("20:00", { reports: [[X, "19:58"], [O, "19:40"], [O, "19:20"]] }), "open");
is(at("20:00", { reports: [[X, "19:58"], [O, "19:40"]] }), "closed");           // 2건이면 최신
// 사장님이 마감을 잊은 경우 / 영업 끝이 다음 영업시간까지
is(at("22:30", { owner: [O, "17:00"], hours: daily }), "unknown");
is(at("23:30", { owner: [O, "17:00"] }), "unknown");
is(at("15:30", { owner: [X, "08:00"], hours: daily }), "unknown");
is(at("20:30", { owner: [X, "16:00"], hours: daily }), "closed");
// 시간표만 있으면 '영업중'이라고 하지 않음
is(at("18:00", { hours: daily }), "unknown", /등록된 영업시간이에요 \(21:00까지\)/);
is(at("22:00", { hours: daily }), "unknown", /영업시간이 아니에요 \(내일 15:00 오픈\)/);
is(at("18:00"), "unknown", /아직 제보가 없어요/);
// 지난 제보 (지금 23:00)
is(at("23:00", { reports: [[O, "23:40", 3]] }), "unknown", /^3일 전 23:40에는 영업중/);      // 이 시각 뒤 영업중
is(at("23:00", { reports: [[X, "22:10", 2]] }), "unknown", /^2일 전 22:10에는 영업이 끝나/); // 이 시각 앞 종료
is(at("23:00", { reports: [[O, "22:40", 3]] }), "unknown", /^3일 전 22:40에는 영업중/);      // 예로 드신 경우
is(at("23:00", { reports: [[O, "22:40", 3], [X, "22:10", 1]] }), "unknown", /22:40/);        // 둘 다 있으면 지금에 가까운 쪽
is(at("23:00", { reports: [[O, "21:30", 1], [X, "22:50", 5]] }), "unknown", /22:50/);
is(at("23:00", { reports: [[X, "23:30", 1]] }), "unknown", /아직 제보가 없어요/);            // 이 시각 뒤 종료는 안 씀
is(at("23:00", { reports: [[O, "12:00", 1]] }), "unknown", /아직 제보가 없어요/);            // 3시간 넘게 차이
is(at("23:00", { reports: [[O, "22:50", 20]] }), "unknown", /아직 제보가 없어요/);           // 14일 넘음
is(at("00:30", { reports: [[X, "23:50", 3]] }), "unknown", /^3일 전 23:50에는 영업이 끝나/); // 자정 넘김 (앞)
is(at("23:30", { reports: [[O, "00:20", 2]] }), "unknown", /^2일 전 00:20에는 영업중/);      // 자정 넘김 (뒤)
is(at("23:00", { reports: [[X, "20:30"], [O, "22:55", 3]] }), "unknown", /^오늘 20:30에는 영업이 끝나/); // 오늘 3시간 안이면 먼저
is(at("23:00", { reports: [[O, "22:40", 2], [X, "22:40", 4, true]] }), "unknown", /사장님/); // 똑같이 가까우면 사장님
is(at("18:00", { hours: daily, reports: [[X, "17:30", 1]] }), "unknown", /어제 17:30/);       // 시간표보다 실제 제보
console.log("영업 상태 규칙 검사 통과");
