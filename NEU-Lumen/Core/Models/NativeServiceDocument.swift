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
        let key: String?
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
        let query: Bool?
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
    const labelText=el=>{
        const copy=el.cloneNode(true);
        for(const control of copy.querySelectorAll('input,textarea,select,[role=combobox],.jqx-dropdownlist,.ant-select,.el-select'))control.remove();
        return clean(copy.textContent,256);
    };
    const label=el=>clean(Array.from(el.labels||[]).map(labelText).join(' ') || el.getAttribute('aria-label') ||
        (el.getAttribute('aria-labelledby') || '').split(/\s+/).map(id=>el.ownerDocument.getElementById(id)).filter(Boolean).map(labelText).join(' ') ||
        el.closest('.bh-form-item,.form-group,.control-group,.ant-form-item,.el-form-item')?.querySelector('.bh-form-label,.control-label,.ant-form-item-label,.el-form-item__label,label')?.textContent ||
        el.getAttribute('placeholder') || el.getAttribute('title') || el.name || el.id,256);
    const text=el=>clean(el.innerText || el.textContent);
    const context=el=>clean(el.closest('tr,[role=row],form,article,section')?.innerText,4096);
    const actionState=el=>JSON.stringify([el.getAttribute('href'),el.getAttribute('onclick'),el.getAttribute('formaction'),
        el.getAttribute('formmethod'),el.getAttribute('target'),el.getAttribute('type'),el.form?.action,el.form?.method,
        el.getAttribute('aria-disabled')]);
    const currentValue=entry=>entry.kind==='choice'?clean(entry.node.getAttribute('aria-valuetext') ||
        entry.node.querySelector('[id^=dropdownlistContent],.ant-select-selection-item,.el-select__selected-item')?.textContent || (entry.node.matches('input')?entry.node.value:entry.node.querySelector('input:not([type=hidden])')?.value) || text(entry.node),256):
        entry.kind==='toggle'?String(entry.node.getAttribute('aria-checked')==='true' || !!entry.node.querySelector('.jqx-checkbox-check-checked')):
        entry.kind==='multiselect'?JSON.stringify(Array.from(entry.node.selectedOptions).map(x=>x.value)):
        entry.kind==='radio'?entry.nodes.find(x=>x.checked)?.value || '':
        entry.kind==='checkbox'?String(entry.node.checked):String(entry.node.value);
    const disabled=el=>!!el.disabled || el.getAttribute('aria-disabled')==='true' || el.classList.contains('jqx-fill-state-disabled') || el.classList.contains('ant-select-disabled') || el.classList.contains('is-disabled') || el.classList.contains('ant-select-item-option-disabled');
    const activate=el=>{
        const win=el.ownerDocument.defaultView;
        el.dispatchEvent(new win.MouseEvent('mousedown',{bubbles:true,button:0,buttons:1}));
        el.dispatchEvent(new win.MouseEvent('mouseup',{bubbles:true}));
        el.click();
    };
    const choiceOptions=el=>{
        const doc=el.ownerDocument, targets=[],control=el.matches('[role=combobox]')?el:el.querySelector('[role=combobox]');
        for (const id of [control?.getAttribute('aria-controls'),control?.getAttribute('aria-owns'),el.getAttribute('aria-controls'),el.getAttribute('aria-owns'),
            el.id && 'listBox'+el.id,el.id && 'innerListBox'+el.id,el.id && 'popup'+el.id].filter(Boolean).flatMap(x=>x.split(/\s+/))) {
            const target=doc.getElementById(id); if (target && !targets.includes(target)) { targets.push(target);const popup=target.closest('.ant-select-dropdown,.el-select-dropdown,.select2-dropdown');if(popup)targets.push(popup); }
        }
        const list=el.matches('[role=listbox]')?el:el.querySelector('[role=listbox]'); if(list)targets.push(list);
        return Array.from(new Set(targets.flatMap(target=>{
            const popup=target.closest('.ant-select-dropdown,.el-select-dropdown'),visual=popup?Array.from(popup.querySelectorAll('.ant-select-item-option,.el-select-dropdown__item')).filter(visible):[];
            return visual.length?visual:Array.from(target.querySelectorAll('[role=option],.jqx-listitem-element'));
        })))
            .filter(x=>visible(x) && !disabled(x) && text(x) && !x.parentElement?.closest('[role=option]')).slice(0,500).map((node,index)=>({node,
                value:clean(node.getAttribute('data-value') || node.getAttribute('value') || node.id || String(index),256),title:clean(text(node),256)}));
    };
    const docs=[];
    const visit=(doc,depth=0)=>{
        if (depth>4 || docs.includes(doc)) return;
        docs.push(doc);
        for (const frame of doc.querySelectorAll('iframe,frame')) {
            try { if (frame.contentDocument && frame.contentWindow.location.origin===location.origin) visit(frame.contentDocument,depth+1); } catch {}
        }
    };
    visit(document);
    if (['act','fill','change','open'].includes(command)) {
        const state=globalThis[key];
        if (!state || state.token!==token || state.url!==location.href || state.consumed) return {error:'stale'};
        const selected=state.actions.get(actionID);
        const changing=state.fields.get(actionID);
        if ((command==='change' || command==='open') && (!changing || disabled(changing.node) || changing.readOnly)) return {error:'stale'};
        if (command==='act' && (!selected || !selected.node.isConnected || !visible(selected.node) || selected.node.disabled ||
            clean(selected.node.innerText || selected.node.value || selected.node.getAttribute('aria-label'),256)!==selected.label ||
            context(selected.node)!==selected.context || actionState(selected.node)!==selected.signature)) return {error:'stale'};
        if (state.hidden.some(entry=>!entry.node.isConnected || entry.node.value!==entry.value)) return {error:'stale'};
        // Check the complete snapshot before writing any fields. Re-read after
        // page-side changes to avoid applying values to a changed order/form.
        for (const [id,entry] of state.fields) {
            const el=entry.node;
            if (!el.isConnected || !visible(el) || currentValue(entry)!==entry.original || disabled(el)!==entry.disabled || (!['choice','toggle'].includes(entry.kind) && !!el.readOnly!==entry.readOnly) ||
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
            if (entry.kind==='select' && !Array.from(el.options).some(o=>o.value===value && !o.disabled)) return {error:'format'};
            if (entry.kind==='multiselect') {
                let selected; try { selected=JSON.parse(value); } catch { return {error:'format'}; }
                if (!Array.isArray(selected) || new Set(selected).size!==selected.length || selected.some(x=>typeof x!=='string' || !Array.from(el.options).some(o=>o.value===x && !o.disabled))) return {error:'format'};
            }
            if (entry.kind==='choice' && value!==entry.original && !entry.options.some(x=>x.value===value && visible(x.node) && !disabled(x.node))) return {error:'format'};
            if (entry.kind==='radio' && !entry.nodes.some(x=>x.value===value && !x.disabled)) return {error:'format'};
            if (['checkbox','toggle'].includes(entry.kind) && !['true','false'].includes(value)) return {error:'format'};
        }
        state.consumed=true;
        if(command==='open') {
            if(changing.kind!=='choice') return {error:'format'};
            activate(changing.node);
            return {opened:true};
        }
        for (const [id,entry] of state.fields) {
            const el=entry.node;
            if (!Object.hasOwn(values,id) || entry.disabled || entry.readOnly || values[id]===currentValue(entry) || (command==='change' && id!==actionID)) continue;
            if(entry.kind==='toggle') { activate(el);continue; }
            if(entry.kind==='choice') {
                const option=entry.options.find(x=>x.value===values[id]);
                if(!option || !visible(option.node) || disabled(option.node))return {error:'stale'};
                activate(option.node);
                continue;
            }
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
            if(entry.kind==='multiselect') {
                const selected=JSON.parse(values[id]);
                for(const option of el.options)option.selected=selected.includes(option.value);
                el.dispatchEvent(new win.Event('input',{bubbles:true}));
                el.dispatchEvent(new win.Event('change',{bubbles:true}));
                continue;
            }
            const prototype=el.tagName==='SELECT'?win.HTMLSelectElement.prototype:el.tagName==='TEXTAREA'?win.HTMLTextAreaElement.prototype:win.HTMLInputElement.prototype;
            Object.getOwnPropertyDescriptor(prototype,'value').set.call(el,values[id]);
            el.dispatchEvent(new win.Event('input',{bubbles:true}));
            el.dispatchEvent(new win.Event('change',{bubbles:true}));
            el.dispatchEvent(new win.FocusEvent('blur',{bubbles:true}));
        }
        if (command==='fill' || command==='change') return {filled:true};
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
    const radios=new Set(),customNodes=new Set();
    for (const doc of docs) {
        if (Array.from(doc.querySelectorAll('input[type=password],img[src*=qrcode],img[src*=qrCode],[id*=qrcode],[id*=qrCode],canvas'))
            .some(visible)) requiresWebsite=true;
        for (const node of doc.querySelectorAll('input[type=hidden]')) state.hidden.push({node,value:node.value});
        // EMAP / jqx dropdowns are DIVs, not SELECTs. Read only rendered choices;
        // opening and selecting are separate explicit user gestures through school handlers.
        for(const el of doc.querySelectorAll('[role=combobox],.jqx-dropdownlist,.ant-select,.el-select,.select2-container')) {
            if(!visible(el) || el.matches('select') || el.closest('[role=option],.jqx-dropdownlist-popup') ||
                el.parentElement?.closest('[role=combobox],.jqx-dropdownlist,.ant-select,.el-select,.select2-container'))continue;
            if(fields.length>=200){needsWeb=true;break;}
            const name=label(el) || label(el.querySelector('input') || el); if(!name){needsWeb=true;continue;}
            const id='f'+serial++,options=choiceOptions(el),entry={node:el,kind:'choice',disabled:disabled(el),readOnly:false,options};
            entry.original=currentValue(entry); state.fields.set(id,entry);customNodes.add(el);
            fields.push({id,key:doc.URL+'#'+(el.id || name),label:name,kind:'choice',value:entry.original,
                required:el.getAttribute('aria-required')==='true',readOnly:entry.disabled,options:options.map(({value,title})=>({value,title}))});
        }
        for(const el of doc.querySelectorAll('[role=checkbox],.jqx-checkbox')) {
            if(!visible(el) || el.matches('input') || el.querySelector('input[type=checkbox]') || el.parentElement?.closest('[role=checkbox],.jqx-checkbox'))continue;
            if(fields.length>=200){needsWeb=true;break;}
            const name=label(el) || clean(el.closest('[role=row],tr')?.innerText,256);
            if(!name){needsWeb=true;continue;}
            const id='f'+serial++,entry={node:el,kind:'toggle',disabled:disabled(el),readOnly:false};
            entry.original=currentValue(entry);state.fields.set(id,entry);customNodes.add(el);
            fields.push({id,key:doc.URL+'#'+(el.id || name),label:name,kind:'toggle',value:entry.original,required:false,readOnly:entry.disabled,options:[]});
        }
        for (const el of doc.querySelectorAll('input,textarea,select')) {
            if (!visible(el) || el.type==='hidden' || Array.from(customNodes).some(x=>x.contains(el))) continue;
            if (el.closest('form')?.querySelector('input[type=password]')) { needsWeb=true; continue; }
            const kind=el.tagName==='SELECT'?(el.multiple?'multiselect':'select'):el.tagName==='TEXTAREA'?'textarea':
                el.type==='text' && (el.closest('.ant-picker,.jqx-datetimeinput') || /日期/.test(label(el))) && /^\d{4}-\d{2}-\d{2}$/.test(el.value)?'date':el.type;
            if (!['text','email','tel','url','number','date','datetime-local','time','textarea','select','multiselect','search','checkbox','radio'].includes(kind)) {
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
            const options=(kind==='select' || kind==='multiselect')?Array.from(el.options).filter(o=>!o.disabled).map(o=>({value:o.value,title:clean(o.text,256)})):
                nodes?nodes.filter(x=>!x.disabled).map(x=>({value:x.value,title:label(x)})):[];
            if (options.length>500) { needsWeb=true; continue; }
            const entry={node:el,nodes,kind,disabled:disabled(el),readOnly:!!el.readOnly};
            entry.original=currentValue(entry);
            state.fields.set(id,entry);
            fields.push({id,key:doc.URL+'#'+(el.id || (el.form?.id || '')+':'+el.name+':'+name),label:name,kind,value:entry.original,required:nodes?nodes.some(x=>x.required):!!el.required,readOnly:!!(el.disabled||el.readOnly),options});
        }
        for (const table of doc.querySelectorAll('table,[role=grid],[role=table]')) {
            if (!visible(table) || table.querySelector('table,[role=grid],[role=table]')) continue;
            const html=table.tagName==='TABLE';
            const headerNodes=Array.from(table.querySelectorAll(html?'thead th':'[role=columnheader]')).filter(visible);
            if(html && !headerNodes.length && table.rows[0]?.querySelector('th'))headerNodes.push(...Array.from(table.rows[0].cells));
            const headers=headerNodes.map(text);
            const all=html?Array.from(table.rows).filter(row=>visible(row) && !row.closest('thead') && !headerNodes.some(x=>x.parentElement===row)):
                Array.from(table.querySelectorAll('[role=row]')).filter(row=>visible(row) &&
                    row.closest('table,[role=grid],[role=table]')===table && row.querySelector('[role=gridcell],[role=cell]'));
            const rows=all.slice(0,200).map(row=>Array.from(html?row.cells:row.querySelectorAll('[role=gridcell],[role=cell]')).map(text)).filter(row=>row.some(Boolean));
            if (!rows.length) continue;
            tables.push({id:'t'+serial++,title:clean(table.caption?.textContent || table.getAttribute('aria-label') || doc.title,256),headers,rows,truncated:all.length>200});
            if (tables.length>=30) { needsWeb=true; break; }
        }
        for (const el of doc.querySelectorAll('a[href],a[onclick],button,input[type=submit],input[type=button],[role=button],[role=tab],[role=menuitem],[onclick]')) {
            if (!visible(el) || disabled(el) || el.closest('form')?.querySelector('input[type=password]')) continue;
            if (Array.from(customNodes).some(x=>x===el || x.contains(el)) || el.closest('[role=option],.jqx-listitem-element') || el.matches('select,textarea,img') || (el.matches('input') && !['submit','button'].includes(el.type)) || el.querySelector('a[href],a[onclick],button,[role=button]')) continue;
            const title=clean(el.innerText || el.value || el.getAttribute('aria-label'),256);
            if (!title) continue;
            const id='a'+serial++;
            state.actions.set(id,{node:el,label:title,context:context(el),signature:actionState(el)});
            const query=/^(查询|搜索|检索|筛选|刷新|重置|清空|确定查询|上一页|下一页|首页|末页)$/.test(title.replace(/\s+/g,'')) ||
                (/^[0-9]+$/.test(title) && !!el.closest('.pagination,.ant-pagination,.jqx-grid-pager,[role=navigation]'));
            actions.push({id,title,context:context(el),query});
            if (actions.length>=200) { needsWeb=true; break; }
        }
        for (const el of doc.querySelectorAll('[role=alert],.alert,.error,.validation-summary-errors,.jqx-grid-emptycell,.ant-empty-description,.ant-message-notice-content,.jqx-notification-content')) {
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
