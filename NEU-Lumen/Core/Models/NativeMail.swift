import Foundation

struct NativeMailFolder: Identifiable, Hashable {
    let id: String
    let name: String
    let total: Int?
    let unread: Int?
}

struct NativeMailMessage: Identifiable, Hashable {
    let id: String
    let subject: String
    let sender: String
    let dateText: String
    let unread: Bool?
}

struct NativeMailBody: Identifiable {
    let id: String
    let subject: String
    let sender: String
    let text: String
    let attachments: [String]
}

enum NativeMailProtocol {
    static func identity(_ raw: [String: Any]) throws -> String {
        guard let email = raw["email"] as? String, email.count <= 254,
              email.range(of: #"^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$"#, options: .regularExpression) != nil else {
            throw NetworkError(message: "暂未读取到邮箱身份，请完成学校邮箱登录后重试")
        }
        return email.lowercased()
    }
    static func dateText(_ raw: Any?) -> String {
        let text = raw.map { String(describing: $0) } ?? ""
        if let time = Double(text), time.isFinite, time > 100_000_000 {
            let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
            return formatter.string(from: Date(timeIntervalSince1970: time > 100_000_000_000 ? time / 1000 : time))
        }
        return String(text.prefix(64))
    }
    static func messages(_ raw: Any?) throws -> [NativeMailMessage] {
        guard let rows = raw as? [[String: Any]], rows.count <= 100 else { throw NetworkError(message: "学校邮箱列表格式暂不支持") }
        var seen = Set<String>()
        return try rows.map { row in
            guard let id = row["id"] as? String, !id.isEmpty, id.count <= 512, seen.insert(id).inserted else {
                throw NetworkError(message: "学校邮箱返回了无效邮件标识")
            }
            return NativeMailMessage(id: id, subject: String((row["subject"] as? String ?? "无主题").prefix(1024)),
                sender: String((row["sender"] as? String ?? "未提供发件人").prefix(1024)),
                dateText: dateText(row["date"]), unread: row["unread"] as? Bool)
        }
    }

    /// Interface names/encoding verified against the school's shipped Coremail
    /// $.157e8.js / X.157e8.js. Session IDs stay inside the isolated WebKit world.
    static let reader = #"""
    const root = new URL(rootURL);
    if (root.origin !== location.origin || !location.pathname.includes('/coremail/')) return {error:'login'};
    let sid = new URL(location.href).searchParams.get('sid');
    if (!sid) {
        for (const script of document.scripts) {
            const text = script.textContent || '';
            if (!/\bX\s*=\s*\{/.test(text)) continue;
            const m = text.match(/(?:[,\{\s])s\s*:\s*(['"])([A-Za-z0-9._~+\/=\-]{8,512})\1/);
            if (m) { sid=m[2]; break; }
        }
    }
    if (!sid || sid.length>512) return {error:'login'};
    const clean = (value, limit=4096) => String(value ?? '').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').slice(0,limit);
    const address = value => Array.isArray(value) ? value.map(address).filter(Boolean).join(', ')
        : value && typeof value==='object' ? [value.name,value.address || value.email].filter(Boolean).join(' ')
        : clean(value,1024);
    const rpc = async (func, payload={}) => {
        let endpoint='s/json', form=false;
        if (func==='folders') { endpoint='XT/jsp/mail.jsp'; form=true; }
        if (func==='search') { endpoint='XT/jsp/mail.jsp'; form=true; }
        if (func==='read') { endpoint='XT/jsp/readMessage.jsp'; form=true; }
        const url = new URL(endpoint,root);
        url.searchParams.set('sid',sid);
        if (func==='folders') url.searchParams.set('func','getAllFolders');
        else if (func==='search') url.searchParams.set('func','searchMessages');
        else if (func!=='read') url.searchParams.set('func',func);
        const controller=new AbortController(), timer=setTimeout(()=>controller.abort(),15000);
        try {
            const response=await fetch(url.href,{method:'POST',credentials:'include',redirect:'error',cache:'no-store',signal:controller.signal,
                headers:{'Accept':'text/x-json','Content-Type':form?'application/x-www-form-urlencoded;charset=UTF-8':'text/x-json'},
                body:form?new URLSearchParams(payload).toString():JSON.stringify(payload)});
            if (!response.ok || new URL(response.url).origin!==root.origin) throw new Error('login');
            const json=await response.json();
            if (json.code!=='S_OK') throw new Error('login');
            return json.var;
        } finally { clearTimeout(timer); }
    };
    const getIdentity = async () => {
        const user=await rpc('user:getAttrs',{optionalAttrIds:['email','uid','name']});
        const raw=address(user.email || user.uid);
        const match=raw.match(/[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+/);
        if (!match) throw new Error('identity');
        return match[0].toLowerCase();
    };
    try {
        const email=await getIdentity();
        const local=email.split('@')[0];
        const school=email.split('@')[1];
        const matched=expectedEmail ? email===expectedEmail.toLowerCase()
            : expectedSID && local===expectedSID.toLowerCase() && (school==='neu.edu.cn'||school.endsWith('.neu.edu.cn'));
        if (!matched) return {error:'binding',email};
        if (command==='read') {
            if (typeof messageID!=='string'||!messageID||messageID.length>512) throw new Error('format');
            const data=await rpc('read',{mid:messageID,mboxa:'',sid});
            const mail=data.mail || {};
            let content=clean(mail.content || mail.text || '',1000000)
                .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi,'')
                .replace(/<br\s*\/?\s*>|<\/(?:p|div|tr|h[1-6])>/gi,'\n').replace(/<[^>]*>/g,'');
            const decoder=document.createElement('textarea'); decoder.innerHTML=content; content=decoder.value;
            if (await getIdentity()!==email) throw new Error('identity');
            return {email,body:{id:messageID,subject:clean(mail.subject,1024),sender:address(mail.from),text:content,
                attachments:(mail.attachments||[]).slice(0,100).map(a=>clean(a.name||a.filename||'附件',512))}};
        }
        let folders=[];
        if (includeFolders) {
            const raw=await rpc('folders',{stats:'true',threads:'false'});
            const visit=(rows,depth=0)=>{
                if (!Array.isArray(rows)||depth>5) return;
                for (const row of rows) {
                    if (Number.isInteger(Number(row.id)) && Number(row.id)>0) folders.push({id:String(row.id),name:clean(row.name,256),
                        total:row.stats?.allMessageCount ?? null,unread:row.stats?.unreadMessageCount ?? null});
                    visit(row.children || row.items,depth+1);
                    if (folders.length>200) throw new Error('format');
                }
            }; visit(raw);
        }
        const selected=folderID || folders.find(f=>f.id==='1')?.id || folders[0]?.id || '1';
        if (!/^\d{1,12}$/.test(selected) || !Number.isInteger(start) || start<0) throw new Error('format');
        const parameters={fid:Number(selected),start,limit:20,order:'receivedDate',desc:true,returnTotal:true,summaryWindowSize:0};
        if (searchText) parameters.subject=clean(searchText,200);
        const rows=await rpc(searchText?'search':'mbox:listMessages',parameters);
        if (!Array.isArray(rows)||rows.length>100) throw new Error('format');
        if (await getIdentity()!==email) throw new Error('identity');
        return {email,folders,folderID:selected,nextStart:start+rows.length,hasMore:rows.length>=20,
            messages:rows.map(m=>({id:clean(m.id,512),subject:clean(m.subject || '无主题',1024),sender:address(m.from || m.sender),
                date:m.receivedDate || m.sentDate || '',unread:typeof m.flags?.read==='boolean'?!m.flags.read:null}))};
    } catch (error) { return {error:error.name==='AbortError'||error.name==='TypeError'?'network':error.message==='identity'?'identity':error.message==='format'?'format':'login'}; }
    """#
}
