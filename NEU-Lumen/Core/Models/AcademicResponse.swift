import Foundation

struct GradeReport {
    let semesters: [GradeSemester]
    let failedTerms: [String]
}

enum AcademicResponse {
    struct Term {
        let code: String
        let name: String
        let current: Bool
    }

    static func records(_ value: Any) -> [[String: Any]] {
        if let array = value as? [Any] { return array.compactMap { $0 as? [String: Any] } }
        guard let map = value as? [String: Any] else { return [] }
        for key in ["datas", "data", "rows", "list"] {
            if let nested = map[key] {
                let rows = records(nested)
                if !rows.isEmpty { return rows }
            }
        }
        return []
    }

    static func validate(_ raw: Any, stage: String) throws {
        guard let map = raw as? [String: Any] else {
            throw NetworkError(message: "\(stage)数据格式异常，请打开教务网页后同步")
        }
        let code = map.str("code")
        let message = [map.str("msg"), map.str("message")].first { !$0.isEmpty } ?? ""
        let success = code == "0" || code == "200" || (code.isEmpty && map.bool("success") == true)
        if !success && (message.contains("登录") || ["401", "403", "-401"].contains(code)) {
            throw NetworkError.sessionExpired()
        }
        guard success else {
            throw NetworkError(message: "\(stage)失败\(code.isEmpty ? "" : "（代码 \(code)）")\(message.isEmpty ? "" : "：\(message)")")
        }
    }

    static func terms(_ raw: Any) throws -> [Term] {
        try validate(raw, stage: "学期列表获取")
        return records(raw).compactMap { row in
            let code = row.str("itemCode").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return nil }
            let name = row.str("itemName").trimmingCharacters(in: .whitespacesAndNewlines)
            let selected = row.str("selected").lowercased()
            return Term(code: code, name: name.isEmpty ? code : name, current: selected == "true" || selected == "1")
        }
    }

    static func courses(_ raw: Any) throws -> [GradeCourse] {
        try validate(raw, stage: "成绩获取")
        return records(raw).compactMap { row in
            let name = row.str("courseName").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let text = row.str("score").trimmingCharacters(in: .whitespacesAndNewlines)
            let number = Double(text)
            return GradeCourse(name: name, credit: row.dbl("credit") ?? 0, category: row.str("courseType"),
                               score: number, scoreRaw: number == nil ? text : "")
        }
    }

    static func browserReport(_ raw: Any) throws -> GradeReport {
        guard let map = raw as? [String: Any] else { throw NetworkError(message: "教务网页未返回成绩数据") }
        if !map.str("error").isEmpty { throw NetworkError(message: map.str("error")) }
        let rows = map["semesters"] as? [[String: Any]] ?? []
        var semesters: [GradeSemester] = []
        var failed: [String] = []
        for row in rows {
            let name = row.str("name")
            do {
                let courses = try courses(row["response"] ?? [:])
                semesters.append(GradeSemester(name: name, termCode: row.str("code"),
                                               current: row.bool("current") == true, courses: courses))
            } catch { failed.append(name) }
        }
        guard !semesters.isEmpty else { throw NetworkError(message: "暂未获取到成绩，请确认已进入教务系统学生首页后重试同步") }
        return GradeReport(semesters: semesters, failedTerms: failed)
    }

    /// 只在用户打开的教务页面同源取数，不读取账号密码、不向其他站点发送成绩。
    static let browserScript = #"""
    const root = location.href.split('/jwapp/')[0] + '/jwapp/sys/homeapp/';
    if (!location.pathname.includes('/jwapp/')) return {error: '请先完成认证，进入教务系统学生首页后再同步'};
    const get = async (path) => {
        const r = await fetch(root + path, {credentials: 'include', headers: {
            'Accept': 'application/json', 'Fetch-Api': 'true', 'X-Requested-With': 'XMLHttpRequest'
        }});
        if (!r.ok) throw new Error('教务接口 HTTP ' + r.status);
        const text = await r.text();
        try { return JSON.parse(text); } catch (_) { throw new Error('教务会话尚未建立，请在网页中完成登录后重试'); }
    };
    const rows = (v) => {
        if (Array.isArray(v)) return v;
        if (v && typeof v === 'object') {
            for (const k of ['datas', 'data', 'rows', 'list']) {
                const list = rows(v[k]); if (list.length) return list;
            }
        }
        return [];
    };
    try {
        const calendar = await get('api/home/student/schoolCalendars.do');
        if (!['0','200'].includes(String(calendar.code)) && calendar.success !== true) return {error: calendar.msg || calendar.message || '学期列表获取失败'};
        const semesters = [];
        for (const t of rows(calendar)) {
            if (!t.itemCode) continue;
            let response;
            try { response = await get('api/home/student/scores.do?termCode=' + encodeURIComponent(t.itemCode)); }
            catch (_) { response = {code: '-1'}; }
            semesters.push({code: String(t.itemCode), name: String(t.itemName || t.itemCode),
                current: ['true','1'].includes(String(t.selected).toLowerCase()), response});
        }
        return {semesters};
    } catch (e) { return {error: e.message || '同步失败，请刷新教务网页后重试'}; }
    """#
}
