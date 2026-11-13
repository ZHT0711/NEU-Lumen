import Foundation

/// 用户主动同步当前获准页面；只解析已渲染表格，唯一联网操作是官方 currentUser.do 身份核验。
/// 不截获任意 XHR、不探测未知接口、不自动翻页、点击、展开或提交表单。
enum AcademicPageReader {
    static func decode(_ raw: Any, expectedAccount: String, expectedSourceURL: URL, now: Date = Date()) throws -> AcademicPageSnapshot {
        guard let map = raw as? [String: Any] else { throw AcademicQueryError.invalid("网页同步") }
        if let error = map["error"] as? String {
            if error == "identity" { throw AcademicQueryError.accountMismatch }
            throw AcademicQueryError.invalid("当前网页表格")
        }
        guard let account = map["account"] as? String,
              AcademicQueryPolicy.acceptsPageAccount(account, expected: expectedAccount) else {
            throw AcademicQueryError.accountMismatch
        }
        guard let countText = AcademicQueryParser.scalar(map["recognizedTables"]), let count = Int(countText), count > 0, count <= 100,
              let rows = map["courses"] as? [[String: Any]], rows.count <= 5000,
              let urlText = map["sourceURL"] as? String, let url = URL(string: urlText),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.path.contains("/jwapp/") else {
            throw AcademicQueryError.invalid("当前网页表格")
        }
        // 去掉认证参数 / 查询值，不持久化，不输出到日志。
        var safeURL = URLComponents(url: url, resolvingAgainstBaseURL: false)
        safeURL?.query = nil; safeURL?.fragment = nil; safeURL?.user = nil; safeURL?.password = nil
        var expectedURL = URLComponents(url: expectedSourceURL, resolvingAgainstBaseURL: false)
        expectedURL?.query = nil; expectedURL?.fragment = nil; expectedURL?.user = nil; expectedURL?.password = nil
        guard let source = safeURL?.url, source == expectedURL?.url else { throw AcademicQueryError.invalid("网页来源") }
        let courses = try rows.enumerated().map { index, row -> AcademicPageCourse in
            guard let name = AcademicQueryParser.scalar(row["name"]) else { throw AcademicQueryError.invalid("网页课程") }
            return AcademicPageCourse(id: "\(index)", name: name, code: AcademicQueryParser.scalar(row["code"]),
                creditsText: AcademicQueryParser.scalar(row["creditsText"]), module: AcademicQueryParser.scalar(row["module"]),
                studyStatus: AcademicQueryParser.scalar(row["studyStatus"]), suggestedTerm: AcademicQueryParser.scalar(row["suggestedTerm"]))
        }
        return AcademicPageSnapshot(account: account, title: AcademicQueryParser.scalar(map["title"]) ?? "教务当前页面",
            sourceURL: source, courses: courses, recognizedTables: count, updatedAt: now)
    }

    /// 官方首页学业树会自动写动画状态；同步窗口阻断已核实的两条写接口，不阻断 CAS 正常认证。
    static let readOnlyPageGuard = #"""
    (() => {
        const blocked = input => {
            try {
                const raw = typeof input === 'string' ? input
                    : input && typeof input.url === 'string' ? input.url : String(input);
                const path = new URL(raw, location.href).pathname;
                return /\/api\/home\/student\/academic-status\/(collect-growthvalue|record-failscore)\.do$/.test(path);
            } catch (_) { return false; }
        };
        const fetch = window.fetch.bind(window);
        window.fetch = (input, options) => blocked(input)
            ? Promise.reject(new Error('只读同步窗口不执行学校写操作')) : fetch(input, options);
        const open = window.XMLHttpRequest.prototype.open;
        window.XMLHttpRequest.prototype.open = function(method, url, ...args) {
            if (blocked(url)) throw new Error('只读同步窗口不执行学校写操作');
            return open.call(this, method, url, ...args);
        };
    })();
    """#

    static let browserScript = #"""
    const base = new URL(rootURL);
    if (base.origin !== location.origin || !base.pathname.endsWith('/jwapp/sys/homeapp/') ||
        !location.pathname.includes('/jwapp/') || !expectedAccount) return {error:'identity'};
    const identity = async () => {
        try {
            const target = new URL('api/home/currentUser.do', base);
            const r = await fetch(target.href, {
                method:'GET', credentials:'include', redirect:'error', cache:'no-store',
                headers:{'Accept':'application/json','Fetch-Api':'true','X-Requested-With':'XMLHttpRequest'}
            });
            const source = new URL(r.url);
            if (!r.ok || source.origin !== target.origin || source.pathname !== target.pathname || source.search !== target.search)
                throw new Error('identity');
            const j = await r.json();
            if (!j || String(j.code) !== '0' || !j.datas || Array.isArray(j.datas) ||
                String(j.datas.userId || '') !== expectedAccount) throw new Error('identity');
            return String(j.datas.userId);
        } catch (_) { throw new Error('identity'); }
    };
    const clean = v => String(v || '').replace(/\s+/g,' ').trim().slice(0,4096);
    const header = v => clean(v).replace(/[\s：:]/g,'');
    const names = {
        name:['课程名称','课程名'], code:['课程代码','课程号','课程编码'], creditsText:['学分','课程学分'],
        module:['课程模块','模块','模块名称','所属模块'], studyStatus:['修读状态','修读情况','完成情况'],
        suggestedTerm:['建议学期','建议修读学期','开课学期']
    };
    const visible = el => {
        try {
            const visibility = el.ownerDocument.defaultView.getComputedStyle(el).visibility;
            return el.getClientRects().length > 0 && visibility !== 'hidden' && visibility !== 'collapse';
        } catch (_) { return false; }
    };
    try {
        const account = await identity();
        const docs = [document];
        for (let depth=0; depth<3; depth++) {
            const pending = [];
            for (const doc of docs.slice()) for (const frame of doc.querySelectorAll('iframe')) {
                try {
                    if (visible(frame) && frame.contentWindow.location.origin === base.origin &&
                        frame.contentWindow.location.pathname.includes('/jwapp/') && frame.contentDocument &&
                        !docs.includes(frame.contentDocument) && !pending.includes(frame.contentDocument)) pending.push(frame.contentDocument);
                } catch (_) {} // 跨源页面不读、不绕过同源策略。
            }
            if (!pending.length) break;
            docs.push(...pending);
            if (docs.length > 10) throw new Error('format');
        }
        const courses = []; let recognizedTables = 0;
        for (const doc of docs) for (const table of doc.querySelectorAll('table,[role="grid"],[role="table"]')) {
            if (!visible(table)) continue;
            const isHTML = table.tagName === 'TABLE';
            const rowEls = Array.from(table.querySelectorAll(isHTML ? 'tr' : '[role="row"]'))
                .filter(r => r.closest('table,[role="grid"],[role="table"]') === table && visible(r));
            if (rowEls.length > 5001) throw new Error('format');
            const grid = [], spans = [];
            for (const [rowIndex,row] of rowEls.entries()) {
                const cells = isHTML ? Array.from(row.cells) : Array.from(row.querySelectorAll('[role="columnheader"],[role="gridcell"],[role="cell"]'));
                const values = []; let col = 0;
                for (const cell of cells) {
                    while (spans[col] && spans[col].left > 0) { values[col] = spans[col].text; spans[col].left--; col++; }
                    const text = clean(cell.innerText || cell.textContent);
                    const width = Number(isHTML ? cell.colSpan : cell.getAttribute('aria-colspan') || 1);
                    const rawHeight = Number(isHTML ? cell.rowSpan : cell.getAttribute('aria-rowspan') || 1);
                    const groupRemaining = rowEls.slice(rowIndex).filter(r => r.parentElement === row.parentElement).length;
                    const height = isHTML ? (rawHeight === 0 ? groupRemaining : Math.min(rawHeight,groupRemaining)) : rawHeight;
                    if (!Number.isInteger(width) || width < 1 || width > 50 ||
                        !Number.isInteger(height) || height < 1 || height > 5001 || col+width > 100) throw new Error('format');
                    for (let k=0;k<width;k++) { values[col] = text; if (height>1) spans[col] = {text,left:height-1}; col++; }
                }
                while (col < spans.length) { if (spans[col] && spans[col].left>0) { values[col]=spans[col].text; spans[col].left--; } col++; }
                grid.push(values);
            }
            let mapping, firstData = -1;
            for (let i=0;i<Math.min(grid.length,8);i++) {
                const keys = {}; grid[i].forEach((text,index) => {
                    for (const [key,aliases] of Object.entries(names)) if (aliases.includes(header(text))) keys[key]=index;
                });
                if (keys.name !== undefined && (keys.creditsText !== undefined || keys.module !== undefined || keys.studyStatus !== undefined)) {
                    mapping=keys; firstData=i+1; break;
                }
            }
            if (!mapping) continue;
            recognizedTables++;
            for (const values of grid.slice(firstData)) {
                const name = clean(values[mapping.name]);
                if (!name || ['合计','总计','课程名称','课程名','暂无数据','没有数据'].includes(name)) continue;
                const course = {name};
                for (const [key,index] of Object.entries(mapping)) if (key !== 'name') {
                    const text=clean(values[index]); if (text) course[key]=text;
                }
                courses.push(course);
                if (courses.length > 5000) throw new Error('format');
            }
        }
        if (!recognizedTables) return {error:'format'};
        if (await identity() !== account) return {error:'identity'};
        return {account, title:clean(document.title), sourceURL:location.origin+location.pathname, courses, recognizedTables};
    } catch (e) { return {error:e.message === 'identity' ? 'identity' : 'format'}; }
    """#
}
