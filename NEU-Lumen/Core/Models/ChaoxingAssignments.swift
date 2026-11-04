import Foundation

enum ChaoxingAssignments {
    // Course/work response schema checked against the platform samples documented at
    // github.com/Zhanghuaimin-233/chaoxing-homework-checker/blob/main/API.md.
    static let pageScript = #"""
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const clean = value => (value || '').replace(/\s+/g, ' ').trim();
    if (doc.querySelector('input[type="password"]') || /passport.*login/.test(pageURL)) return {recognized: false};
    const items = new Map();
    for (const li of doc.querySelectorAll('li[data]')) {
      const title = clean(li.querySelector('.overHidden2')?.textContent);
      const status = clean(li.querySelector('.status')?.textContent);
      if (!title || !status) continue;
      let url;
      try { url = new URL(li.getAttribute('data'), pageURL); } catch (_) { continue; }
      if (!url.hostname.endsWith('.chaoxing.com') || !/^https?:$/.test(url.protocol)) continue;
      const workID = url.searchParams.get('workId') || url.searchParams.get('workid');
      if (!workID) continue;
      const time = clean(li.querySelector('.time')?.textContent);
      const absolute = time.match(/\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?/);
      const duration = time.match(/剩余\s*(?:(\d+)天)?\s*(?:(\d+)小时)?\s*(?:(\d+)分钟)?/);
      let deadline = null;
      if (absolute) deadline = Date.parse(absolute[0].replace(/\//g, '-').replace(' ', 'T') + '+08:00');
      else if (duration && duration.slice(1).some(Boolean)) {
        deadline = Date.now() + ((+(duration[1] || 0) * 24 + +(duration[2] || 0)) * 60 + +(duration[3] || 0)) * 60000;
      }
      const completed = !/未交|未提交|待互[评評]/.test(status) && /已完成|已批[改阅閱]|已互[评評]|待批[改阅閱]|已提交/.test(status);
      const id = courseKey + '.' + workID;
      items.set(id, {id, courseKey, courseTitle, title, kind: '作业', url: url.href, deadline,
        deadlineText: time, statusText: status, completed, scoreText: ''});
    }
    const numbers = [...doc.querySelectorAll('#page li')].map(el => Number(el.textContent.trim())).filter(Number.isFinite);
    const recognized = items.size > 0 || !!doc.querySelector('#page, .work-list, .workList') || /暂无作业|没有作业/.test(doc.body.textContent);
    return {recognized, pages: Math.max(1, ...numbers), assignments: [...items.values()]};
    """#
}
