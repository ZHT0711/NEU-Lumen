import Foundation

struct NativeServiceDocument: Decodable {
    struct Option: Decodable, Identifiable {
        let value: String
        let title: String
        var id: String { value }
    }
    struct Field: Decodable, Identifiable {
        let id: String
        let label: String
        let kind: String
        let value: String
        let required: Bool
        let readOnly: Bool
        let options: [Option]
    }
    struct Action: Decodable, Identifiable {
        let id: String
        let title: String
        let context: String
    }
    struct Table: Decodable, Identifiable {
        let id: String
        let title: String
        let headers: [String]
        let rows: [[String]]
        let truncated: Bool
    }
    let token: String
    let title: String
    let fields: [Field]
    let actions: [Action]
    let tables: [Table]
    let notices: [String]
    let needsWeb: Bool
    let requiresWebsite: Bool?

    /// Reads the currently rendered school document. The original DOM retains
    /// hidden CSRF fields, form actions, JavaScript validators and order identifiers.
    static let bridge = #"""
    const key='__neuServiceDocument';
    const clean=(value,max=4096)=>String(value??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').trim().slice(0,max);
    const visible=el=>el.isConnected && !el.closest('[hidden],[aria-hidden="true"]') && el.getClientRects().length>0 &&
        el.ownerDocument.defaultView.getComputedStyle(el).visibility!=='hidden';
    const label=el=>clean(Array.from(el.labels||[]).map(x=>x.textContent).join(' ') || el.getAttribute('aria-label') ||
        el.getAttribute('placeholder') || el.getAttribute('title') || el.name || el.id,256);
    const text=el=>clean(el.innerText || el.textContent);
    const context=el=>clean(el.closest('tr,form,article,section')?.innerText,4096);
    const actionState=el=>JSON.stringify([el.getAttribute('href'),el.getAttribute('onclick'),el.getAttribute('formaction'),
        el.getAttribute('formmethod'),el.getAttribute('target'),el.getAttribute('type'),el.form?.action,el.form?.method,
        el.getAttribute('aria-disabled')]);
    const currentValue=entry=>entry.kind==='radio'?entry.nodes.find(x=>x.checked)?.value || '':
        entry.kind==='checkbox'?String(entry.node.checked):String(entry.node.value);
    const docs=[];
    const visit=(doc,depth=0)=>{
        if (depth>4 || docs.includes(doc)) return;
        docs.push(doc);
        for (const frame of doc.querySelectorAll('iframe,frame')) {
            try { if (frame.contentDocument && frame.contentWindow.location.origin===location.origin) visit(frame.contentDocument,depth+1); } catch {}
        }
    };
    visit(document);
    if (command==='act' || command==='fill') {
        const state=globalThis[key];
        if (!state || state.token!==token || state.url!==location.href || state.consumed) return {error:'stale'};
        const selected=state.actions.get(actionID);
        if (command==='act' && (!selected || !selected.node.isConnected || !visible(selected.node) || selected.node.disabled ||
            clean(selected.node.innerText || selected.node.value || selected.node.getAttribute('aria-label'),256)!==selected.label ||
            context(selected.node)!==selected.context || actionState(selected.node)!==selected.signature)) return {error:'stale'};
        if (state.hidden.some(entry=>!entry.node.isConnected || entry.node.value!==entry.value)) return {error:'stale'};
        // Check the complete snapshot before writing any fields. Re-read after
        // page-side changes to avoid applying values to a changed order/form.
        for (const [id,entry] of state.fields) {
            const el=entry.node;
            if (!el.isConnected || !visible(el) || currentValue(entry)!==entry.original || el.disabled!==entry.disabled || el.readOnly!==entry.readOnly ||
                (entry.nodes && entry.nodes.some(x=>!x.isConnected)))
                return {error:'stale'};
            if (Object.hasOwn(values,id) && typeof values[id]!=='string') return {error:'format'};
        }
        for (const [id,entry] of state.fields) {
            const el=entry.node;
            if (!Object.hasOwn(values,id) || entry.disabled || entry.readOnly) continue;
            const value=values[id];
            if (value===entry.original) continue;
            if (value.length>100000) return {error:'format'};
            if (el.tagName==='SELECT' && !Array.from(el.options).some(o=>o.value===value && !o.disabled)) return {error:'format'};
            if (entry.kind==='radio' && !entry.nodes.some(x=>x.value===value && !x.disabled)) return {error:'format'};
            if (entry.kind==='checkbox' && !['true','false'].includes(value)) return {error:'format'};
        }
        state.consumed=true;
        for (const [id,entry] of state.fields) {
            const el=entry.node;
            if (!Object.hasOwn(values,id) || entry.disabled || entry.readOnly || values[id]===currentValue(entry)) continue;
            const win=el.ownerDocument.defaultView;
            if (entry.kind==='radio' || entry.kind==='checkbox') {
                for (const node of entry.nodes || [el]) {
                    const checked=entry.kind==='radio'?node.value===values[id]:values[id]==='true';
                    if (node.checked===checked) continue;
                    Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype,'checked').set.call(node,checked);
                    if (entry.kind==='radio' && !checked) continue;
                    node.dispatchEvent(new win.Event('input',{bubbles:true}));
                    node.dispatchEvent(new win.Event('change',{bubbles:true}));
                }
                continue;
            }
            const prototype=el.tagName==='SELECT'?win.HTMLSelectElement.prototype:el.tagName==='TEXTAREA'?win.HTMLTextAreaElement.prototype:win.HTMLInputElement.prototype;
            Object.getOwnPropertyDescriptor(prototype,'value').set.call(el,values[id]);
            el.dispatchEvent(new win.Event('input',{bubbles:true}));
            el.dispatchEvent(new win.Event('change',{bubbles:true}));
        }
        if (command==='fill') return {filled:true};
        if (state.hidden.some(entry=>!entry.node.isConnected || entry.node.value!==entry.value) ||
            context(selected.node)!==selected.context || actionState(selected.node)!==selected.signature)
            return {error:'stale'};
        const el=selected.node;
        const form=el.form || el.closest('form');
        if (form && !form.checkValidity()) return {error:'validation',message:clean(Array.from(form.elements).find(x=>x.validity && !x.validity.valid)?.validationMessage,512)};
        // A single explicit activation uses the school's handlers and confirmation
        // flow. Never replay a POST, call form.submit(), or infer business success.
        if (!el.isConnected || !visible(el)) return {error:'stale'};
        el.click();
        return {activated:true};
    }
    const state={token:crypto.randomUUID(),url:location.href,fields:new Map(),actions:new Map(),hidden:[],consumed:false};
    let needsWeb=false,requiresWebsite=false,serial=0;
    const fields=[],actions=[],tables=[],notices=[];
    const radios=new Set();
    for (const doc of docs) {
        if (Array.from(doc.querySelectorAll('input[type=password],img[src*=qrcode],img[src*=qrCode],[id*=qrcode],[id*=qrCode],canvas'))
            .some(visible)) requiresWebsite=true;
        for (const node of doc.querySelectorAll('input[type=hidden]')) state.hidden.push({node,value:node.value});
        for (const el of doc.querySelectorAll('input,textarea,select')) {
            if (!visible(el) || el.type==='hidden') continue;
            if (el.closest('form')?.querySelector('input[type=password]')) { needsWeb=true; continue; }
            const kind=el.tagName==='SELECT'?'select':el.tagName==='TEXTAREA'?'textarea':el.type;
            if (!['text','email','tel','url','number','date','datetime-local','time','textarea','select','search','checkbox','radio'].includes(kind) || el.multiple) {
                if (!['submit','button','reset','image'].includes(kind)) needsWeb=true;
                continue;
            }
            if (fields.length>=200) { needsWeb=true; break; }
            if (kind==='radio' && radios.has(el)) continue;
            if (kind==='radio' && !el.name) { needsWeb=true; continue; }
            const nodes=kind==='radio'?Array.from(doc.querySelectorAll('input[type=radio]')).filter(x=>x.name===el.name && x.form===el.form && visible(x)):null;
            if (nodes && el.disabled && nodes.some(x=>!x.disabled)) continue;
            if (nodes) nodes.forEach(x=>radios.add(x));
            const id='f'+serial++, name=kind==='radio'?clean(el.closest('fieldset')?.querySelector('legend')?.textContent || el.name || label(el),256):label(el);
            if (!name) { needsWeb=true; continue; }
            const options=kind==='select'?Array.from(el.options).filter(o=>!o.disabled).map(o=>({value:o.value,title:clean(o.text,256)})):
                nodes?nodes.filter(x=>!x.disabled).map(x=>({value:x.value,title:label(x)})):[];
            if (options.length>200) { needsWeb=true; continue; }
            const entry={node:el,nodes,kind,disabled:el.disabled,readOnly:el.readOnly};
            entry.original=currentValue(entry);
            state.fields.set(id,entry);
            fields.push({id,label:name,kind,value:entry.original,required:nodes?nodes.some(x=>x.required):!!el.required,readOnly:!!(el.disabled||el.readOnly),options});
        }
        for (const table of doc.querySelectorAll('table')) {
            if (!visible(table) || table.querySelector('table')) continue;
            const headers=Array.from(table.querySelectorAll('thead th')).map(text);
            const all=Array.from(table.rows).filter(row=>visible(row) && !row.closest('thead'));
            const rows=all.slice(0,200).map(row=>Array.from(row.cells).map(text)).filter(row=>row.some(Boolean));
            if (!rows.length) continue;
            tables.push({id:'t'+serial++,title:clean(table.caption?.textContent || doc.title,256),headers,rows,truncated:all.length>200});
            if (tables.length>=30) { needsWeb=true; break; }
        }
        for (const el of doc.querySelectorAll('a[href],a[onclick],button,input[type=submit],input[type=button],[role=button],[onclick]')) {
            if (!visible(el) || el.disabled || el.getAttribute('aria-disabled')==='true' || el.closest('form')?.querySelector('input[type=password]')) continue;
            if (el.matches('input,select,textarea,img') || el.querySelector('a[href],a[onclick],button,[role=button]')) continue;
            const title=clean(el.innerText || el.value || el.getAttribute('aria-label'),256);
            if (!title) continue;
            const id='a'+serial++;
            state.actions.set(id,{node:el,label:title,context:context(el),signature:actionState(el)});
            actions.push({id,title,context:context(el)});
            if (actions.length>=200) { needsWeb=true; break; }
        }
        for (const el of doc.querySelectorAll('[role=alert],.alert,.error,.validation-summary-errors')) {
            if (visible(el) && text(el)) notices.push(text(el));
        }
        if (doc.querySelector('input[type=file],[contenteditable=true],canvas')) needsWeb=true;
    }
    const contents={title:clean(document.title,256),fields,actions,tables,notices:notices.slice(0,20),needsWeb,requiresWebsite};
    const fingerprint=JSON.stringify(contents);
    if (command==='watch') {
        const previous=globalThis[key];
        return {changed:!previous || previous.fingerprint!==fingerprint ||
            Array.from(previous.actions.values()).some(entry=>!entry.node.isConnected) ||
            Array.from(previous.fields.values()).some(entry=>!entry.node.isConnected)};
    }
    state.fingerprint=fingerprint;
    globalThis[key]=state;
    return {token:state.token,...contents};
    """#
}
