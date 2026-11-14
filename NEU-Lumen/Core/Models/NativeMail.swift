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
    var flagged: Bool? = nil
    var attached: Bool? = nil
}

struct NativeMailSearch: Equatable {
    var subject = ""
    var from = ""
    var to = ""
    var unreadOnly = false
    var attachedOnly = false
    var flaggedOnly = false

    var normalized: Self {
        var result = self
        result.subject = String(subject.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        result.from = String(from.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        result.to = String(to.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return result
    }

    var parameters: [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in [("subject", subject), ("from", from), ("to", to)] {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result[key] = String(text.prefix(200)) }
        }
        if unreadOnly { result["read"] = false }
        if attachedOnly { result["attachType"] = "attached" }
        if flaggedOnly { result["flagType"] = "flagged" }
        return result
    }
}

enum NativeMailMutation {
    case read(Bool), flagged(Bool), move(String)

    var attributes: [String: Any] {
        switch self {
        case .read(let value): ["flags": ["read": value]]
        case .flagged(let value): value ? ["flags": ["flagged": true]] : ["flags": ["flagged": false], "label0": 0]
        case .move(let folder): ["fid": Int(folder) ?? -1]
        }
    }
}

struct NativeMailBody: Identifiable {
    struct Attachment: Identifiable, Hashable {
        let id: String
        let name: String
        let size: Int64?
        let downloadable: Bool
    }
    struct BodyLink: Identifiable {
        let title: String
        let url: URL
        var id: String { url.absoluteString }
    }
    let id: String
    let subject: String
    let sender: String
    let text: String
    let recipients: String
    let cc: String
    let dateText: String
    let attachments: [Attachment]
    let links: [BodyLink]
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
                dateText: dateText(row["date"]), unread: row["unread"] as? Bool, flagged: row["flagged"] as? Bool,
                attached: row["attached"] as? Bool)
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
        if (func==='compose') { endpoint='XT/jsp/compose.jsp'; form=true; }
        const url = new URL(endpoint,root);
        url.searchParams.set('sid',sid);
        if (func==='folders') url.searchParams.set('func','getAllFolders');
        else if (func==='search') url.searchParams.set('func','searchMessages');
        else if (func!=='read' && func!=='compose') url.searchParams.set('func',func);
        const controller=new AbortController(), timer=setTimeout(()=>controller.abort(),15000);
        try {
            const response=await fetch(url.href,{method:'POST',credentials:'include',redirect:'error',cache:'no-store',signal:controller.signal,
                headers:{'Accept':'text/x-json','Content-Type':form?'application/x-www-form-urlencoded;charset=UTF-8':'text/x-json'},
                body:form?new URLSearchParams(payload).toString():JSON.stringify(payload)});
            if (!response.ok || new URL(response.url).origin!==root.origin) throw new Error('login');
            const json=await response.json();
            if (json.code!=='S_OK') throw new Error(/SESSION|NOT_LOGIN|AUTH/.test(json.code || '')?'login':'operation');
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
        if (command==='compose') {
            if (!['normal','reply','replyall','forward'].includes(composeKind) ||
                (composeKind!=='normal' && (typeof messageID!=='string'||!messageID||messageID.length>512))) throw new Error('format');
            const parameters={ctype:composeKind,mboxa:''};
            if (composeKind!=='normal') parameters.mid=messageID;
            const draft=await rpc('compose',parameters);
            if (await getIdentity()!==email) throw new Error('identity');
            if (typeof draft.id!=='string'||!draft.id||draft.id.length>512) throw new Error('format');
            return {email,composeID:draft.id};
        }
        if (command==='update') {
            if (!Array.isArray(messageIDs)||!messageIDs.length||messageIDs.length>100||new Set(messageIDs).size!==messageIDs.length||
                messageIDs.some(id=>typeof id!=='string'||!id||id.length>512)) throw new Error('format');
            const keys=Object.keys(attributes || {});
            const flags=attributes?.flags;
            const validFlag=flags && Object.keys(flags).length===1 &&
                ['read','flagged'].some(key=>typeof flags[key]==='boolean' && Object.hasOwn(flags,key));
            const validMove=keys.length===1 && Number.isInteger(attributes.fid) && attributes.fid>0;
            const validFlags=validFlag && keys.every(key=>key==='flags'||key==='label0') &&
                (!Object.hasOwn(attributes,'label0') || (flags.flagged===false && attributes.label0===0));
            if (!validMove && !validFlags) throw new Error('format');
            // Verify immediately before a user-requested write as well as after it.
            if (await getIdentity()!==email) throw new Error('identity');
            await rpc('mbox:updateMessageInfos',{mboxa:'',ids:messageIDs,attrs:attributes,returnOriginalMsgInfos:true});
            if (await getIdentity()!==email) throw new Error('identity');
            return {email,updated:true};
        }
        if (command==='read' || command==='download') {
            if (typeof messageID!=='string'||!messageID||messageID.length>512) throw new Error('format');
            const data=await rpc('read',{mid:messageID,mboxa:'',sid});
            const mail=data.mail || {}, info=data.mailInfo || {};
            const attachments=(Array.isArray(mail.attachments)?mail.attachments:[]).slice(0,100).map((a,index)=>{
                const part=typeof a.part==='string'||typeof a.part==='number'?String(a.part):'';
                const downloadable=a.type==='internal' && /^\d{1,6}(?:\.\d{1,6}){0,12}$/.test(part) &&
                    (!a.mid || a.mid===messageID) && !a.deleted && !a.inlined && !mail.smimeStatus && !data.mailCipherEncrypted;
                const size=typeof a.size==='number' || (typeof a.size==='string' && /^\d+$/.test(a.size))?Number(a.size):NaN;
                return {id:part?'part:'+part+':'+index:String(index),name:clean(a.displayName || a.name || a.filename || '附件',512),
                    size:Number.isSafeInteger(size) && size>=0?size:null,downloadable,part};
            });
            if(command==='download') {
                const selected=attachments.find(a=>a.id===attachmentID && a.name===attachmentName);
                if(!selected || !selected.downloadable) throw new Error('format');
                if(await getIdentity()!==email) throw new Error('identity');
                // The school's X.157e8.js internal attachment URL, with the session
                // kept inside this isolated world. WebKit owns the authenticated transfer.
                const url=new URL('s/json',root);
                for(const [key,value] of Object.entries({sid,func:'mbox:getMessageData',mid:messageID,part:selected.part,mode:'download'})) url.searchParams.set(key,value);
                const anchor=document.createElement('a'); anchor.href=url.href; anchor.download=selected.name;
                anchor.hidden=true; document.body.appendChild(anchor);
                try { anchor.click(); } finally { anchor.remove(); }
                return {email,downloadRequested:true};
            }
            const html=clean(mail.content || mail.text || '',1000000)
                .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi,'');
            const decode=value=>{const node=document.createElement('textarea');node.innerHTML=value;return node.value;};
            const links=[];
            for(const match of html.matchAll(/<a\b[^>]*\bhref\s*=\s*(["'])([\s\S]*?)\1[^>]*>([\s\S]*?)<\/a>/gi)) {
                try { const url=new URL(decode(match[2]));
                    if(!['http:','https:'].includes(url.protocol) || url.username || url.password || url.href.length>4096 || links.some(x=>x.url===url.href))continue;
                    links.push({title:clean(decode(match[3].replace(/<[^>]*>/g,'')),512) || url.hostname,url:url.href});
                    if(links.length>=50)break;
                } catch {}
            }
            let content=html
                .replace(/<li\b[^>]*>/gi,'\n• ').replace(/<br\s*\/?\s*>|<\/(?:p|div|tr|li|h[1-6])>/gi,'\n').replace(/<[^>]*>/g,'');
            const decoder=document.createElement('textarea'); decoder.innerHTML=content; content=decoder.value;
            if (await getIdentity()!==email) throw new Error('identity');
            return {email,body:{id:messageID,subject:clean(mail.subject,1024),sender:address(mail.from),text:content,
                recipients:address(mail.to || info.to),cc:address(mail.cc || info.cc),
                date:mail.sentDate || info.sentDate || mail.receivedDate || info.receivedDate || '',
                unread:typeof info.flags?.read==='boolean'?!info.flags.read:null,
                attachments:attachments.map(({part,...attachment})=>attachment),links}};
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
        const condition={};
        for (const key of ['subject','from','to']) {
            if (typeof searchFields[key]==='string' && searchFields[key].trim()) condition[key]=clean(searchFields[key].trim(),200);
        }
        if (searchText && !condition.subject) condition.subject=clean(searchText,200);
        if (searchFields.read===false) condition.read=false;
        if (searchFields.attachType==='attached') condition.attachType='attached';
        if (searchFields.flagType==='flagged') condition.flagType='flagged';
        const rows=await rpc(Object.keys(condition).length?'search':'mbox:listMessages',{...parameters,...condition});
        if (!Array.isArray(rows)||rows.length>100) throw new Error('format');
        if (await getIdentity()!==email) throw new Error('identity');
        return {email,folders,folderID:selected,nextStart:start+rows.length,hasMore:rows.length>=20,
            messages:rows.map(m=>({id:clean(m.id,512),subject:clean(m.subject || '无主题',1024),sender:address(m.from || m.sender),
                date:m.receivedDate || m.sentDate || '',unread:typeof m.flags?.read==='boolean'?!m.flags.read:null,
                flagged:typeof m.flags?.flagged==='boolean'?m.flags.flagged:null,
                attached:typeof m.flags?.attached==='boolean'||typeof m.flags?.linkAttached==='boolean'?!!(m.flags.attached||m.flags.linkAttached):null}))};
    } catch (error) { return {error:error.name==='AbortError'||error.name==='TypeError'?'network':['identity','format','operation'].includes(error.message)?error.message:'login'}; }
    """#
}
