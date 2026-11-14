import Foundation

/// A read-only presentation of the code the school actually rendered. No code
/// payload is generated, guessed, persisted, copied to the clipboard or logged.
struct ECodeDocument: Decodable {
    struct Fact: Decodable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }
    struct Link: Decodable, Identifiable {
        let title: String
        let url: URL
        var id: String { url.absoluteString }
    }
    let state: String
    let png: String?
    let facts: [Fact]
    let links: [Link]

    static func allows(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil || [80, 443].contains(url.port!),
              let host = url.host?.lowercased(), host.hasSuffix(".neu.edu.cn"),
              !["pass.neu.edu.cn", "webvpn.neu.edu.cn"].contains(host) else { return false }
        return true
    }

    static let reader = #"""
    const empty = state => ({state,png:null,facts:[],links:[]});
    const clean = s => String(s||'').replace(/\s+/g,' ').trim();
    const visible = el => {
      if (!el || !el.isConnected) return false;
      const r=el.getBoundingClientRect();
      if(r.width<=0 || r.height<=0) return false;
      for(let node=el;node;node=node.parentElement) {
        const style=node.ownerDocument.defaultView.getComputedStyle(node);
        if(node.hidden || node.getAttribute('aria-hidden')==='true' || style.display==='none' ||
           style.visibility==='hidden' || style.visibility==='collapse' || Number(style.opacity)===0) return false;
      }
      return true;
    };
    const visibleText = root => {
      const walker=root.ownerDocument.createTreeWalker(root,NodeFilter.SHOW_TEXT);
      const parts=[];
      for(let node=walker.nextNode(),i=0;node && i<300;node=walker.nextNode(),i++) {
        if(visible(node.parentElement)) parts.push(node.textContent);
      }
      return clean(parts.join(' '));
    };
    const docs=[document];
    for(let i=0;i<docs.length && docs.length<8;i++) {
      for(const frame of docs[i].querySelectorAll('iframe,frame')) {
        try { if(visible(frame) && frame.contentDocument && frame.contentWindow.location.origin===location.origin) docs.push(frame.contentDocument); } catch {}
      }
    }
    const links=[];
    for(const doc of docs) {
      if(Array.from(doc.querySelectorAll('input[type="password"]')).some(visible) || /(?:统一身份认证|扫码登录|登录二维码)/.test(doc.title)) continue;
      for(const a of doc.querySelectorAll('a[href]')) {
        const title=clean(a.innerText);
        if(!visible(a) || !/^(?:e码通|校园码|电子校园卡|去刷码|出示校园码|付款码|身份码)$/i.test(title)) continue;
        try { const u=new URL(a.getAttribute('href'),doc.baseURI);
          if(['http:','https:'].includes(u.protocol) && u.hostname.endsWith('.neu.edu.cn') && !u.username && !u.password && !['pass.neu.edu.cn','webvpn.neu.edu.cn'].includes(u.hostname) && !links.some(x=>x.url===u.href)) links.push({title,url:u.href});
        } catch {}
      }
      const body=clean(doc.body?.innerText);
      if(!/(?:e码通|校园码|电子校园卡|付款码|身份码)/i.test(doc.title+' '+body)) continue;
      const identityFields=Array.from(doc.querySelectorAll('[data-field="sid"],[data-field="studentNo"],#studentNo,#studentId,#XH,#xh,input[name="xh"],input[name="XH"],input[name="studentNo"]'));
      const identities=identityFields.map(el=>clean(el.value||el.innerText)).filter(Boolean);
      for(const labeled of body.matchAll(/(?:学工号|学号|工号)\s*[:：]?\s*([A-Za-z0-9-]{4,30})(?![A-Za-z0-9-])/g)) identities.push(labeled[1]);
      // A scoped login cookie alone does not prove the rendered code's owner.
      if(identities.some(s=>s!==expectedAccount)) return empty('account');
      if(!expectedAccount || !identities.includes(expectedAccount)) continue;
      // The school's Vue v-qr directive renders an image inside .qr-code > .code.
      const codeSelector='[id*="qrcode" i],[class*="qrcode" i],[id*="qr-code" i],[class*="qr-code" i],[id*="qr_code" i],[class*="qr_code" i]';
      const candidates=Array.from(doc.querySelectorAll('canvas,img')).filter(el=>
        visible(el) && (el.closest(codeSelector) || /^(?:校园码|e码通|付款码|身份码)$/i.test(clean(el.getAttribute('alt')))));
      for(const el of candidates) {
        const container=el.parentElement?.closest(codeSelector+',figure,[role="img"]') || el.parentElement;
        const local=container && !['BODY','HTML'].includes(container.tagName) ? visibleText(container) : '';
        const description=clean([el.getAttribute('alt'),el.getAttribute('aria-label'),el.getAttribute('title'),local].join(' '));
        if(/扫码登录|登录二维码|二维码登录|统一身份认证/.test(description)) continue;
        if(/(?:二维码|校园码|付款码|身份码)\s*(?:已失效|已过期)(?:[。！!，,\s]|$)/.test(description)) continue;
        if(container && Array.from(container.querySelectorAll('[class*="mask" i],[class*="expired" i],[role="status"],[role="alert"]')).some(node=>visible(node) && /已失效|已过期/.test(clean(node.innerText)))) continue;
        let png='';
        try {
          let canvas=el;
          if(el.tagName==='IMG') {
            if(!el.complete || el.naturalWidth<80 || el.naturalWidth>2048 || el.naturalHeight<80 || el.naturalHeight>2048) continue;
            canvas=doc.createElement('canvas'); canvas.width=el.naturalWidth;canvas.height=el.naturalHeight;
            canvas.getContext('2d').drawImage(el,0,0);
          }
          if(canvas.width<80 || canvas.height<80 || canvas.width>2048 || canvas.height>2048 || Math.abs(canvas.width/canvas.height-1)>0.08) continue;
          const pixels=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
          let dark=0,light=0;
          for(let i=0;i<pixels.length;i+=4) { const l=(pixels[i]+pixels[i+1]+pixels[i+2])/3; if(pixels[i+3]>128 && l<160) dark++; else light++; }
          if(dark<canvas.width*canvas.height*0.03 || light<canvas.width*canvas.height*0.03) continue;
          png=canvas.toDataURL('image/png');
        } catch { continue; }
        if(!png.startsWith('data:image/png;base64,') || png.length>700000) continue;
        const facts=[{label:'学工号',value:expectedAccount}];
        for(const [label,pattern] of [['姓名',/(?:姓名)\s*[:：]\s*([^\s:：]{1,30})/],['学校状态',/(?:通行状态|校园码状态|身份状态|权限状态)\s*[:：]\s*([^:：]{1,60}?)(?=\s(?:姓名|学号|工号|学工号|有效期|刷新)|$)/]]) {
          const match=body.match(pattern); if(match) facts.push({label,value:clean(match[1])});
        }
        return {state:'ready',png,facts,links};
      }
    }
    return {state:docs.some(d=>Array.from(d.querySelectorAll('input[type="password"]')).some(visible) || /(?:统一身份认证|扫码登录|登录二维码)/.test(d.title))?'login':'missing',png:null,facts:[],links};
    """#
}
