import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const source = readFileSync(new URL("../../NEU-Lumen/Core/Models/MOOCScripts.swift", import.meta.url), "utf8");
const raw = name => source.split(`static let ${name} = `)[1].split('#"""')[1].split('"""#')[0];
const helpers = raw("parser");
const parse = new Function("data", "course", helpers + "\nreturn extractHomeworkFromTermDto(data, course);");
const meta = { courseId: "NEU-1", termId: "42", courseName: "测试课程", pageUrl: "https://www.icourse163.org/spoc/learn/NEU-1?tid=42" };
const deadline = Date.UTC(2026, 10, 10, 15, 59);
const data = { result: { mocTermDto: { chapters: [
  { id: 1, lessons: [], homeworks: [{ id: 11, name: "本周作业", contentType: 3, test: { id: 111, name: "本周作业", deadline, usedTryCount: 1, type: 3 } }] },
  { id: 2, lessons: [], homeworks: [{ id: 12, name: "本周作业", contentType: 3, deadline }] },
] } } };
const rows = parse(data, meta);
assert.equal(rows.length, 2, "Same-name assignments in different weeks must both survive");
assert.equal(new Set(rows.map(row => row.uid)).size, 2);
assert.equal(rows[0].checkedOff, true);
assert.equal(rows[1].checkedOff, false);
assert.equal(Date.parse(rows[0].deadline), deadline);
const peer = parse({ chapters: [{ id: 1, lessons: [], homeworks: [{ id: 3, name: "互评作业", contentType: 3,
  deadline, enableEvaluation: true, evaluateStart: 1, evaluateEnd: Date.now() + 86400000, usedTryCount: 1 }] }] }, meta);
assert.equal(peer[0].hwPhase, "peerreview");
assert.equal(peer[0].checkedOff, true, "Submission survives a peer-review phase");
const zero = parse({ chapters: [{ id: 1, lessons: [], homeworks: [{ id: 4, name: "零分作业", contentType: 3,
  deadline, score: 0, totalScore: 10, usedTryCount: 1 }] }] }, meta);
assert.equal(zero[0].score, 0);
assert.equal(zero[0].checkedOff, true);

const statuses = [
  { userSubmitStatus: 1 }, { userSubmitStatus: "1" }, { userScore: 0 }, { usedTryCount: 1 },
  { userSubmitStatus: 0, usedTryCount: 0, userScore: -1 }, { score: 0, totalScore: 10 },
];
for (const [index, status] of statuses.entries()) {
  const [row] = parse({ chapters: [{ id: 1, lessons: [], homeworks: [
    { id: 5, name: "简答作业", contentType: 3, test: { deadline, ...status } },
  ] }] }, meta);
  assert.equal(row.checkedOff, index < 4, `Personal submission state ${JSON.stringify(status)}`);
}

const readCourse = new Function("DOMParser", "html", "responses", "course", helpers + raw("readCourse"));
const metadata = { chapters: [{ id: 1, lessons: [], homeworks: [
  { id: 5, name: "简答作业", contentType: 3, test: { deadline } },
] }] };
const personal = structuredClone(metadata);
personal.chapters[0].homeworks[0].test.userSubmitStatus = 1;
const staleFlight = `self.__next_f.push([1,${JSON.stringify('1:["$","div",null,{"outline":' + JSON.stringify(metadata) + '}]\n')}])`;
class FixtureDOMParser {
  parseFromString() { return { querySelectorAll: () => [{ textContent: staleFlight }] }; }
}
const merged = readCourse(FixtureDOMParser, "", [{ raw: JSON.stringify(personal), termID: "42" }],
  { id: "NEU-1", termID: "42", title: "测试课程", url: meta.pageUrl });
assert.equal(merged.assignments.length, 1);
assert.equal(merged.assignments[0].completed, true, "Outline metadata must not erase an authenticated submission");
const [withoutDeadline] = parse({ chapters: [{ id: 1, lessons: [], homeworks: [
  { id: 8, name: "未定期限作业", contentType: 3, test: { userSubmitStatus: 0, actionLabel: "查看成绩" } },
] }] }, meta);
assert.equal(withoutDeadline.checkedOff, false);
assert.equal(withoutDeadline.deadline, null);

const taskOnlyData = { id: 99, name: "软件测试课程", endTime: deadline, chapters: [
  { id: 1, name: "测试与作业", endTime: deadline, lessons: [
    { id: 2, name: "单元测验课程", contentType: 2, endTime: deadline, units: [
      { id: 3, name: "视频课程测试", contentType: 1, endTime: deadline },
      { id: 4, name: "本周测验", contentType: 2, test: { deadline, usedTryCount: 1 } },
      { id: 5, name: "简答任务", contentType: 3, test: { userSubmitStatus: 1 } },
      { id: 6, name: "期末考试", contentType: 6, test: { deadline } },
      { id: 7, name: "测试讨论", contentType: 4, endTime: deadline },
    ] },
  ], homeworks: [{ id: 8, name: "补充练习", deadline }] },
] };
const strict = parse(taskOnlyData, meta);
assert.deepEqual(strict.map(row => row.title), ["本周测验", "简答任务", "期末考试", "补充练习"],
  "Course, chapter, lesson, video and discussion metadata must not become tasks");
const filtered = readCourse(FixtureDOMParser, "", [{ raw: JSON.stringify(taskOnlyData), termID: "42" }],
  { id: "NEU-1", termID: "42", title: "测试课程", url: meta.pageUrl });
assert.deepEqual(filtered.assignments.map(row => row.title).sort(), ["本周测验", "简答任务", "补充练习", "简答作业"].sort());
assert.ok(filtered.assignments.every(row => ["作业", "测验"].includes(row.kind)));

const outline = { chapters: [], exams: [{ id: 99, name: "期末考试", taskType: "exam", parts: [{ endTime: deadline, usedTryCount: 1 }] }] };
const flight = `self.__next_f.push([1,${JSON.stringify('14:["$","div",null,{"outline":' + JSON.stringify(outline) + '}]\n')}])`;
const decode = new Function("text", helpers + "\nreturn extractLearnOutlines(text);");
const outlines = decode(flight);
assert.equal(outlines.length, 1);
const exams = parse(outlines[0], meta);
assert.equal(exams.length, 1);
assert.equal(exams[0].type, "exam");
assert.equal(exams[0].checkedOff, true);
assert.equal(Date.parse(exams[0].deadline), deadline);

// Compile each script as WebKit does, including its named native arguments.
new Function("html", "responses", "course", helpers + raw("readCourse"));
new Function(raw("discover"));
const cg = readFileSync(new URL("../../NEU-Lumen/Core/Models/CGAssignments.swift", import.meta.url), "utf8").split('static let browserScript = #"""')[1].split('"""#')[0];
new (Object.getPrototypeOf(async function () {}).constructor)("rootURL", "originalRootURL", cg);
const cx = readFileSync(new URL("../../NEU-Lumen/Core/Models/ChaoxingAssignments.swift", import.meta.url), "utf8").split('static let pageScript = #"""')[1].split('"""#')[0];
new Function("html", "pageURL", "courseKey", "courseTitle", cx);
console.log("Learning parsers passed for personal submission flags, zero grades, drafts, metadata merging, peer-review phases, repeated titles and Next.js exams");
