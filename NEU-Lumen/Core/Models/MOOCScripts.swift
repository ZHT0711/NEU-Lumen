import Foundation

// Adapted from furina061006/MOOC_reminder under the MIT License.
// The bundled MOOC-reminder-LICENSE.txt contains the copyright and license.
enum MOOCScripts {
    static let discover = #"""
    const clean = value => (value || '').replace(/\s+/g, ' ').trim();
    const courses = new Map();
    function add(raw, title) {
      try {
        const url = new URL(raw, location.href);
        if (url.hostname !== 'www.icourse163.org' || /forum|detail/.test(url.hash)) return;
        const match = url.pathname.match(/\/(?:mooc\/|spoc\/)?learn\/([^/?#]+)/);
        const tid = url.searchParams.get('tid');
        if (!match || !tid || !/^\d+$/.test(tid)) return;
        courses.set(match[1] + '.' + tid, {id: match[1], termID: tid,
          title: clean(title) || match[1], url: url.href});
      } catch (_) {}
    }
    const own = /\/(?:mooc\/|spoc\/)?learn\//.test(location.pathname);
    if (own) add(location.href, document.querySelector('.course-name, .f-cb .f-fl h4, h1')?.textContent || document.title);
    else for (const link of document.querySelectorAll('a[href*="/learn/"]')) {
      add(link.href, link.getAttribute('title') || link.textContent);
    }
    return [...courses.values()];
    """#

    static let readCourse = parser + #"""
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const outlines = extractLearnOutlines([...doc.querySelectorAll('script')].map(el => el.textContent).join('\n'));
    const route = new URL(course.url);
    const term = html.match(/(?:moocTerm|term)Dto\s*=\s*\{\s*["']?id["']?\s*:\s*(\d+)/)
      || html.match(/"(?:moocTerm|term)Dto"\s*:\s*\{[^}]*?"id"\s*:\s*(\d+)/)
      || html.match(/(?:moocTerm|term)Dto\s*=\s*new\s+\w+\s*[({]\s*(\d+)/);
    const items = new Map();
    let recognized = outlines.length > 0;
    function hasOutline(value, depth = 0) {
      if (!value || typeof value !== 'object' || depth > 12) return false;
      if (Array.isArray(value.chapters)) return true;
      return Object.values(value).some(child => child && typeof child === 'object' && hasOutline(child, depth + 1));
    }
    for (const response of responses) {
      const data = coerceJson(response.raw);
      if (!hasOutline(data)) continue;
      recognized = true;
      const meta = {courseId: course.id, termId: response.termID, courseName: course.title, pageUrl: course.url};
      for (const item of extractHomeworkFromTermDto(data, meta)) items.set(item.uid, item);
    }
    for (const outline of outlines) {
      const meta = {courseId: course.id, termId: course.termID, courseName: course.title, pageUrl: course.url};
      for (const item of extractHomeworkFromTermDto(outline, meta)) items.set(item.uid, item);
    }
    function destination(type) {
      const url = new URL(course.url);
      if (/\/learn\/[^/]+\//.test(url.pathname)) {
        url.pathname = url.pathname.replace(/(\/learn\/[^/]+)\/.*/, '$1/' + (type === 'exam' ? 'exams' : 'assessments'));
        url.hash = '';
      } else url.hash = type === 'exam' ? '/learn/examlist' : '/learn/testlist';
      return url.href;
    }
    return {recognized, activeTermID: route.pathname.includes('/spoc/') && term ? term[1] : '',
      assignments: [...items.values()].map(item => ({id: item.uid, courseKey: course.id + '.' + course.termID,
        courseTitle: course.title, title: item.title,
        kind: ({exam:'考试', quiz:'测验', homework:'作业', discussion:'讨论'})[item.type] || '作业',
        url: destination(item.type), deadline: item.deadline ? Date.parse(item.deadline) : null,
        deadlineText: '', completed: item.hwPhase !== 'peerreview' && item.checkedOff === true,
        statusText: item.hwPhase === 'peerreview' ? '待互评' : item.checkedOff ? '已提交 / 已完成' : '未发现完成记录',
        scoreText: item.score == null ? '' : String(item.score) + (item.totalScore == null ? '' : ' / ' + item.totalScore)}))};
    """#

    static let parser = #"""
function coerceJson(input) {
  if (input == null) return null;
  if (typeof input === 'object') return input;
  if (typeof input !== 'string') return null;
  try {
    return JSON.parse(input);
  } catch {
    
  }
  const i = input.search(/[{[]/);
  if (i > 0) {
    try {
      return JSON.parse(input.slice(i));
    } catch {
      return null;
    }
  }
  return null;
}

const DEADLINE_FIELDS = [
  'deadline', 'endTime', 'submitEndTime', 'evaluationEndTime',
  'examEndTime', 'testEndTime', 'homeworkEndTime', 'jobDeadline', 'closeTime'
];
const SCORE_FIELDS = ['mark', 'score', 'studentScore', 'finalMark', 'userScore'];
const TOTAL_FIELDS = ['totalMark', 'totalScore', 'fullMark', 'allMark'];

function firstNumber(obj, fields) {
  for (const f of fields) {
    const v = obj[f];
    if (typeof v === 'number' && isFinite(v) && v > 0) return v;
    if (typeof v === 'string' && /^\d+(\.\d+)?$/.test(v)) return parseFloat(v);
  }
  return null;
}

function firstPartNumber(node, fields) {
  if (!node || !Array.isArray(node.parts)) return null;
  for (const part of node.parts) {
    if (!part || typeof part !== 'object') continue;
    const v = firstNumber(part, fields);
    if (v != null) return v;
  }
  return null;
}

function isExplicitExam(node) {
  if (!node || typeof node !== 'object') return false;
  const task = String(node.taskType || '').toLowerCase();
  if (task === 'exam') return true;
  const nodeType = String(node.nodeType || '').toLowerCase();
  if (nodeType === 'exam' || nodeType === 'legacy-exam') return true;
  const eid = node.examId;
  if (typeof eid === 'number' && eid > 0) return true;
  if (typeof eid === 'string' && /^\d+$/.test(eid) && eid !== '0') return true;
  return false;
}

function pad(n) {
  return String(n).padStart(2, '0');
}

function msToLocalIso(ms) {
  const n = typeof ms === 'string' ? parseInt(ms, 10) : ms;
  if (typeof n !== 'number' || !isFinite(n) || n <= 0) return null;
  const d = new Date(n);
  if (isNaN(d.getTime())) return null;
  const tzOffset = -d.getTimezoneOffset();
  const sign = tzOffset >= 0 ? '+' : '-';
  const tzH = pad(Math.floor(Math.abs(tzOffset) / 60));
  const tzM = pad(Math.abs(tzOffset) % 60);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T` +
    `${pad(d.getHours())}:${pad(d.getMinutes())}:00${sign}${tzH}:${tzM}`;
}

function detectPhase(node) {
  const nt = node.test || {};
  const t = String(node.type || nt.type || node.contentType || '');
  if (t !== '3') return null;
  const e = node.enableEvaluation != null ? node.enableEvaluation : nt.enableEvaluation;
  const es = node.evaluateStart != null ? node.evaluateStart : nt.evaluateStart;
  if (!e || es == null) return null;
  const pub = parseInt(node.scorePubStatus != null ? node.scorePubStatus : nt.scorePubStatus, 10) || 0;
  if (pub === 2) return 'results';
  if (pub === 1) {
    const now = Date.now();
    const start = parseInt(es, 10);
    const end = parseInt((node.evaluateScoreReleaseTime || nt.evaluateScoreReleaseTime) || (node.evaluateEnd || nt.evaluateEnd), 10);
    if (end && now >= end) return 'results';
    if (start && now < start) return 'submit';
    return 'peerreview';
  }
  const now = Date.now();
  const start = parseInt(es, 10);
  const end = parseInt((node.evaluateScoreReleaseTime || nt.evaluateScoreReleaseTime) || (node.evaluateEnd || nt.evaluateEnd), 10);
  if (start && now < start) return 'submit';
  if (end && now >= end) return 'results';
  return 'peerreview';
}

function hasCompletedText(node, depth) {
  if (!node || typeof node !== 'object' || (depth || 0) > 6) return false;
  const d = depth || 0;
  const pat = /已完成|已成功提交|已提交|已批阅|已通过|已互评|查看成绩|查看分数/i;
  for (const key of Object.keys(node)) {
    const v = node[key];
    if (typeof v === 'string' && pat.test(v)) return true;
    if (Array.isArray(v)) {
      for (const e of v) {
        if (e && typeof e === 'object' && hasCompletedText(e, d + 1)) return true;
      }
    } else if (v && typeof v === 'object' && hasCompletedText(v, d + 1)) {
      return true;
    }
  }
  return false;
}

function classifyType(name, rawType) {
  const rt = rawType !== undefined ? String(rawType) : '';
  if (rt === '6' || rt === '2' || rt === '3') {
    if (rt === '6') return 'exam';
    if (rt === '2') return 'quiz';
    if (rt === '3') return 'homework';
  }
  const t = String(name || '');
  if (rt === '6' || /期末|考试|exam/i.test(t)) return 'exam';
  if (rt === '2' || /测验|quiz|测试/i.test(t)) return 'quiz';
  if (/讨论|discussion/i.test(t)) return 'discussion';
  return 'homework';
}

function extractHomeworkFromTermDto(input, course) {
  const data = coerceJson(input);
  if (!data || !course) return [];
  const out = [];
  const seen = new Set();
  const nearMisses = [];
  let visited = 0;

  function looksLikeChapter(node) {
    return Array.isArray(node.lessons) || /chapter/i.test(node.type || '');
  }
  function looksLikeLesson(node) {
    return Array.isArray(node.units) || /lesson/i.test(node.type || '');
  }

  function visit(node, chapterId, lessonId) {
    if (!node || typeof node !== 'object' || visited > 5000) return;
    visited++;

    if (Array.isArray(node)) {
      for (const child of node) visit(child, chapterId, lessonId);
      return;
    }

    const name = node.name || node.title || node.unitName || '';
    const deadlineMs = firstNumber(node, DEADLINE_FIELDS)
      || (node.test ? firstNumber(node.test, DEADLINE_FIELDS) : null)
      || firstPartNumber(node, DEADLINE_FIELDS);
    const score = firstNumber(node, SCORE_FIELDS)
      || (node.test ? firstNumber(node.test, SCORE_FIELDS) : null)
      || firstPartNumber(node, SCORE_FIELDS);
    const totalScore = firstNumber(node, TOTAL_FIELDS)
      || (node.test ? firstNumber(node.test, TOTAL_FIELDS) : null)
      || firstPartNumber(node, TOTAL_FIELDS);
    const hasSignal = deadlineMs != null || (score != null && totalScore != null);
    var ct = String(node.contentType || '');
    var ctIsAssessed = ct === '2' || ct === '3' || ct === '6';
    var explicitExam = isExplicitExam(node);
    var isAssessed = typeof name === 'string' && name.trim() && hasSignal &&
        (ctIsAssessed || explicitExam || (!ct && /测验|作业|考试|测试|quiz|exam|homework|test/i.test(name)));
    if (isAssessed) {

      const homeworkId = String(
        node.id || node.jobId || node.quizId || node.testId || node.homeworkId || ''
      ) || ('h' + (out.length + 1));
      const uid = `${course.courseId}_tid${course.termId}_ch${chapterId || ''}_le${lessonId || ''}_hw${homeworkId}`;

      if (!seen.has(uid)) {
        seen.add(uid);
        const phase = detectPhase(node);
        const nt2 = node.test || {};
        let phaseDeadline = deadlineMs;
        if (phase === 'peerreview') {
          const pe = parseInt(node.evaluateEnd || nt2.evaluateEnd, 10);
          if (pe > 0) phaseDeadline = pe;
        }
        const deadline = phaseDeadline != null ? msToLocalIso(phaseDeadline) : null;
        const nType = explicitExam ? 6 : (parseInt(node.type || nt2.type || node.contentType, 10) || NaN);
        const usedTryCount = parseInt(node.usedTryCount || nt2.usedTryCount, 10)
          || (explicitExam ? parseInt(firstPartNumber(node, ['usedTryCount']), 10) : 0) || 0;
        const submitted = usedTryCount > 0 && (nType === 3 || nType === 6);
        const inPeerReview = phase === 'peerreview';
        const done = (score != null && totalScore != null && score > 0)
          || (submitted && !inPeerReview)
          || hasCompletedText(node, 0);

        out.push({
          uid,
          courseId: course.courseId,
          termId: course.termId,
          chapterId: chapterId || '',
          lessonId: lessonId || '',
          homeworkId,
          title: name.trim(),
          type: classifyType(name, explicitExam ? '6' : (node.contentType || (nt2 && nt2.type) || null)),
          courseName: course.courseName || '',
          schoolName: course.schoolName || '',
          courseType: course.courseType || '',
          status: done ? 'completed' : 'unfinished',
          checkedOff: done,
          manuallyCheckedOff: false,
          autoDetectedCompleted: done,
          completionReason: done ? 'auto' : null,
          hwPhase: phase,
          deadline,
          deadlineRaw: deadline ? '(API)' : null,
          score,
          totalScore,
          source: 'api',
          pageUrl: course.pageUrl || '',
          apiCompleted: done
        });
      }
    } else if (typeof name === 'string' && name.trim() && hasSignal) {
      if (nearMisses.length < 5) {
        nearMisses.push({
          name: String(name).trim().slice(0, 40),
          contentType: ct || null,
          type: node.type != null ? node.type : null,
          testType: (node.test && node.test.type != null) ? node.test.type : null
        });
      } else if (nearMisses.length === 5) {
        nearMisses.push('…');
      }
    }
    const nextChapter = node.chapterId || (looksLikeChapter(node) ? node.id : chapterId);
    const nextLesson = node.lessonId || (looksLikeLesson(node) ? node.id : lessonId);
    for (const key of Object.keys(node)) {
      if (key === 'test') continue;
      if (explicitExam && key === 'parts') continue;
      const v = node[key];
      if (v && typeof v === 'object') {
        visit(v, nextChapter, nextLesson);
      } else if (typeof v === 'string' && v.length > 50 && (v.charAt(0) === '{' || v.charAt(0) === '[')) {
        const embedded = coerceJson(v);
        if (embedded && typeof embedded === 'object') visit(embedded, nextChapter, nextLesson);
      }
    }
  }

  visit(data, '', '');

  const byContainer = new Map();
  out.forEach((item) => {
    if (!item.chapterId) return;
    const key = item.chapterId + '|' + String(item.lessonId || '');
    if (!byContainer.has(key)) byContainer.set(key, []);
    byContainer.get(key).push(item);
  });
  const dropped = new Set();
  byContainer.forEach((group) => {
    if (group.length < 2) return;
    const sorted = group.slice().sort((a, b) => a.title.length - b.title.length);
    for (let i = 1; i < sorted.length; i++) {
      const longer = sorted[i];
      if (dropped.has(longer)) continue;
      for (let j = 0; j < i; j++) {
        const shorter = sorted[j];
        if (dropped.has(shorter)) continue;
        if (shorter.title && longer.title.indexOf(shorter.title) === 0 &&
            longer.title.length - shorter.title.length <= 2) {
          dropped.add(longer);
          break;
        }
      }
    }
  });
  if (dropped.size > 0) {
    for (let i = out.length - 1; i >= 0; i--) {
      if (dropped.has(out[i])) out.splice(i, 1);
    }
  }

  return out;
}




function decodeNextFlight(scriptText) {
  if (typeof scriptText !== 'string' || !scriptText) return '';
  const chunks = [];
  const re = /self\.__next_f\.push\(\s*\[\s*1\s*,\s*("(?:[^"\\]|\\.)*")\s*\]\s*\)/g;
  let m;
  while ((m = re.exec(scriptText))) {
    try { chunks.push(JSON.parse(m[1])); } catch {  }
  }
  return chunks.join('');
}


function readJsonValueAt(text, start) {
  if (typeof text !== 'string') return null;
  let i = start;
  while (i < text.length && /\s/.test(text[i])) i++;
  if (text[i] !== '{' && text[i] !== '[') return null;
  const open = text[i];
  const close = open === '{' ? '}' : ']';
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let j = i; j < text.length; j++) {
    const c = text[j];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === open) depth++;
    else if (c === close) {
      depth--;
      if (depth === 0) {
        try { return JSON.parse(text.slice(i, j + 1)); } catch { return null; }
      }
    }
  }
  return null;
}


function findLearnOutlines(flightText) {
  if (typeof flightText !== 'string' || !flightText) return [];
  const out = [];
  let idx = 0;
  while ((idx = flightText.indexOf('"outline":', idx)) !== -1) {
    const valueStart = idx + '"outline":'.length;
    const outline = readJsonValueAt(flightText, valueStart);
    idx = valueStart;
    if (!outline || typeof outline !== 'object') continue;
    if (!Array.isArray(outline.chapters)) continue;
    out.push(outline);
  }
  return out;
}


function findLearnOutline(flightText) {
  const outlines = findLearnOutlines(flightText);
  return outlines.find((outline) => Array.isArray(outline.exams) && outline.exams.length > 0)
    || outlines[0]
    || null;
}


function extractLearnOutlines(scriptText) {
  return findLearnOutlines(decodeNextFlight(scriptText));
}


function extractLearnOutline(scriptText) {
  return findLearnOutline(decodeNextFlight(scriptText));
}


function hasUsableExam(outline) {
  return !!(outline && Array.isArray(outline.exams) && outline.exams.some(
    (exam) => exam && typeof exam === 'object' && (exam.name || exam.title)
  ));
}
"""#
}
