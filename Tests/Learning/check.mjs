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
assert.equal(peer[0].checkedOff, false);

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
console.log("Learning parsers passed for repeated weekly titles, submissions, peer review, Next.js exams, part deadlines and script syntax");
