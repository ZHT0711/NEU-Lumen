import Foundation

struct CGProblem: Identifiable, Hashable {
    enum Status: String { case complete, needsWork, notSubmitted, submitted }
    let id: String
    let title: String
    let url: URL?
    let statusText: String

    var status: Status {
        if ["还未提交", "尚未提交", "未提交"].contains(where: statusText.contains) { return .notSubmitted }
        if ["未通过", "答案错误", "部分正确", "运行错误", "超时", "编译错误", "内存超限"].contains(where: statusText.contains) { return .needsWork }
        if statusText.contains("完全正确") { return .complete }
        return .submitted
    }
    var statusLabel: String {
        switch status {
        case .complete: "已完成"
        case .needsWork: "需完善"
        case .notSubmitted: "未提交"
        case .submitted: "完成情况待确认"
        }
    }
}

struct CGAssignment: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL?
    let deadlineText: String
    let late: Bool
    let history: Bool
    let loaded: Bool
    let problems: [CGProblem]

    var completedCount: Int { problems.filter { $0.status == .complete }.count }
    var isComplete: Bool { loaded && !problems.isEmpty && completedCount == problems.count }
    var deadline: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = deadlineText.count == 16 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: deadlineText)
    }
}

struct CGAssignmentReport {
    let assignments: [CGAssignment]
    let warnings: [String]

    static func decode(_ raw: Any) throws -> CGAssignmentReport {
        guard let payload = raw as? [String: Any] else { throw NetworkError(message: "CG 作业返回格式异常") }
        if let error = payload["error"] as? String { throw NetworkError(message: error) }
        guard let rows = payload["assignments"] as? [[String: Any]], !rows.isEmpty else {
            throw NetworkError(message: "未读取到 CG 作业，请打开平台登录后同步")
        }
        let assignments = rows.compactMap { row -> CGAssignment? in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            let problems = (row["problems"] as? [[String: Any]] ?? []).compactMap { item -> CGProblem? in
                guard let number = item["id"] as? String else { return nil }
                return CGProblem(id: id + "." + number, title: item["title"] as? String ?? "第 \(number) 题",
                    url: webURL(item["url"]), statusText: item["statusText"] as? String ?? "")
            }
            return CGAssignment(id: id, title: row["title"] as? String ?? "作业 \(id)",
                url: webURL(row["url"]), deadlineText: row["deadline"] as? String ?? "",
                late: row["late"] as? Bool ?? false, history: row["history"] as? Bool ?? false,
                loaded: row["loaded"] as? Bool ?? false, problems: problems)
        }
        guard !assignments.isEmpty else { throw NetworkError(message: "CG 作业列表缺少有效记录") }
        return CGAssignmentReport(assignments: assignments, warnings: payload["warnings"] as? [String] ?? [])
    }

    private static func webURL(_ raw: Any?) -> URL? {
        guard let text = raw as? String, let url = URL(string: text),
              ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { return nil }
        return url
    }

    /// Runs with the CG website's own session, including WebVPN URL prefixes.
    static let browserScript = #"""
    const root = new URL(rootURL);
    const original = new URL(originalRootURL);
    const prefix = root.pathname.slice(0, root.pathname.indexOf('/assignment/'));
    const assignments = new Map();
    const warnings = [];
    const clean = value => (value || '').replace(/\s+/g, ' ').trim();
    function route(raw, pageURL) {
      try {
        let url = new URL(raw, pageURL);
        if (url.origin === original.origin) url = new URL(prefix + url.pathname + url.search, root.origin);
        else if (raw.startsWith('/assignment/')) url = new URL(prefix + raw, root.origin);
        if (url.origin !== root.origin || !url.pathname.startsWith(prefix + '/assignment/')) return null;
        url.hash = '';
        return url;
      } catch (_) { return null; }
    }
    async function get(url) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 12000);
      try {
        const response = await fetch(url, {credentials: 'include', signal: controller.signal});
        if (!response.ok) throw new Error('HTTP ' + response.status);
        const html = await response.text();
        const doc = new DOMParser().parseFromString(html, 'text/html');
        if (!html.trim() || doc.querySelector('input[type="password"]') || !route(response.url, rootURL)) {
          throw new Error('请打开 CG 网页完成登录后同步作业');
        }
        return {doc, url: response.url};
      } finally { clearTimeout(timeout); }
    }
    function parse(doc, pageURL) {
      let history = false;
      for (const el of doc.querySelectorAll('.col-2 span.text-muted, a[href*="index.jsp"][href*="assignID="]')) {
        if (el.matches('span.text-muted')) { history = el.textContent.includes('历史'); continue; }
        const url = route(el.getAttribute('href'), pageURL);
        const id = url && url.searchParams.get('assignID');
        if (!id) continue;
        const copy = el.cloneNode(true);
        copy.querySelectorAll('.badge').forEach(badge => badge.remove());
        if (!assignments.has(id)) assignments.set(id, {id, title: clean(copy.textContent) || ('作业 ' + id),
          url: url.href, history, late: /补交/.test(el.textContent), loaded: false, deadline: '', problems: []});
      }
      const text = clean(doc.body.textContent);
      const time = text.match(/作业时间[:：]\s*[\d-]+\s+[\d:]+\s*至\s*([\d-]+\s+[\d:]+)/);
      const seen = new Set();
      for (const link of doc.querySelectorAll('a[href*="programList.jsp"]')) {
        const url = route(link.getAttribute('href'), pageURL);
        const id = url && url.searchParams.get('assignID');
        const number = url && url.searchParams.get('proNum');
        if (!id || !number || seen.has(id + '.' + number)) continue;
        seen.add(id + '.' + number);
        if (!assignments.has(id)) assignments.set(id, {id, title: clean(doc.querySelector('h4')?.textContent) || ('作业 ' + id),
          url: pageURL, history: false, late: false, loaded: false, deadline: '', problems: []});
        const assignment = assignments.get(id);
        assignment.loaded = true;
        if (time) assignment.deadline = time[1];
        const row = link.closest('tr');
        const cells = row ? [...row.children].filter(el => el.tagName === 'TD') : [];
        const status = cells.at(-1);
        const problem = {id: number, title: clean(link.textContent).replace(/^\d+[.、]\s*/, '') || ('第 ' + number + ' 题'), url: url.href,
          statusText: clean(status?.querySelector('small')?.textContent || status?.textContent)};
        const index = assignment.problems.findIndex(item => item.id === number);
        if (index < 0) assignment.problems.push(problem); else assignment.problems[index] = problem;
      }
    }
    try {
      const first = await get(rootURL);
      parse(first.doc, first.url);
      const pending = [...assignments.values()].filter(item => !item.loaded);
      if (pending.length > 100) warnings.push('作业数量超过单次同步上限，部分作业尚未读取');
      let next = 0;
      await Promise.all(Array.from({length: 3}, async () => {
        while (next < Math.min(pending.length, 100)) {
          const item = pending[next++];
          try { const page = await get(item.url); parse(page.doc, page.url); }
          catch (error) { warnings.push(item.title + '：' + error.message); }
        }
      }));
      if (!assignments.size) return {error: '未读取到 CG 作业，请打开平台登录后同步'};
      return {assignments: [...assignments.values()], warnings};
    } catch (error) { return {error: 'CG 作业同步失败：' + error.message}; }
    """#
}
