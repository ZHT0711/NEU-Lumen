import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const source = readFileSync(new URL("../../NEU-Lumen/Core/Models/AcademicResponse.swift", import.meta.url), "utf8");
const script = source.split('static let browserScript = #"""')[1].split('"""#')[0];
const run = new (Object.getPrototypeOf(async function () {}).constructor)("location", "fetch", script);
const responses = [
  { code: 0, datas: { rows: [
    { itemCode: "2026&A", itemName: "春季", selected: "1" },
    { itemCode: "2026-B", itemName: "秋季", selected: false },
  ] } },
  { code: "0", datas: [{ courseName: "数学", score: 92 }] },
];
for (const prefix of ["https://jwxt.neu.edu.cn", "https://webvpn.neu.edu.cn/https/fixture"]) {
  const requests = [];
  let index = 0;
  const report = await run({ href: prefix + "/jwapp/sys/homeapp/index.do", pathname: "/jwapp/sys/homeapp/index.do" },
    async (url, options) => {
      requests.push([url, options]);
      const response = responses[index++];
      if (!response) throw new Error("one semester offline");
      return { ok: true, text: async () => JSON.stringify(response) };
    });
  assert.equal(report.semesters.length, 2);
  assert.equal(report.semesters[0].current, true);
  assert.equal(report.semesters[1].response.code, "-1");
  assert.equal(requests[1][0], prefix + "/jwapp/sys/homeapp/api/home/student/scores.do?termCode=2026%26A");
  assert.ok(requests.every(([, options]) => options.credentials === "include" && options.headers["Fetch-Api"] === "true"));
}
const login = await run({ href: "https://pass.neu.edu.cn/tpass/login", pathname: "/tpass/login" },
  async () => { assert.fail("login page must not request grades"); });
assert.ok(login.error.includes("认证"));
const html = await run({ href: "https://jwxt.neu.edu.cn/jwapp/index.do", pathname: "/jwapp/index.do" },
  async () => ({ ok: true, text: async () => "<html>login</html>" }));
assert.ok(html.error.includes("会话"));
console.log("Academic web bridge: direct/gateway paths, encoding, cookies, partial failures and HTML recovery passed");
