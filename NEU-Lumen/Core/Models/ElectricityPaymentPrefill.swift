import Foundation

/// Only fills the room-code input on the verified electricity project page.
/// It never queries a room, changes an amount or starts a school operation.
enum ElectricityPaymentPrefill {
    static let script = #"""
    if (location.protocol!=='https:' || location.hostname!=='pay.neu.edu.cn' ||
        (location.port && location.port!=='443') || location.pathname!=='/openPayElecPagesDbdx51414E039.html' ||
        !/^[0-9]{7}$/.test(room)) return {status:'unavailable'};
    const key='__neuLumenElectricityRoom';
    let state=globalThis[key];
    if (!state) {
        state={room,filled:new WeakSet(),edited:new WeakSet(),roomFields:new WeakSet(),roomEdited:false,applying:false};
        globalThis[key]=state;
        const touched=event=>{
            if (!state.applying && event.target && event.target.matches?.('input')) {
                state.edited.add(event.target);
                if (state.roomFields.has(event.target)) state.roomEdited=true;
            }
        };
        document.addEventListener('input',touched,true);
        document.addEventListener('change',touched,true);
    }
    state.room=room;
    const candidates=()=>Array.from(document.querySelectorAll('input')).filter(el=>{
        if (!['text','tel','number','search'].includes((el.type||'text').toLowerCase()) ||
            el.disabled || el.readOnly || !el.getClientRects().length || (el.maxLength>=0 && el.maxLength<7)) return false;
        const names=[el.name,el.id].map(x=>(x||'').toLowerCase().replace(/[_-]/g,''));
        const label=[...(el.labels||[])].map(x=>x.textContent||'').join(' ')+' '+(el.getAttribute('aria-label')||'')+' '+(el.placeholder||'');
        // Do not split a 7-digit code into unverified building/room selectors.
        // A plain 3/4-digit room number is not the school's electricity room code.
        const identified=names.includes('elecroomno') || /房间(?:码|编码|代码)/.test(label) ||
            (/房间号/.test(label) && /(?:7|七)\s*位/.test(label));
        if (!identified) return false;
        const pattern=el.getAttribute('pattern');
        if (pattern) { try { if (!new RegExp('^(?:'+pattern+')$').test(state.room)) return false; } catch { return false; } }
        state.roomFields.add(el);
        return true;
    });
    const fill=()=>{
        const inputs=candidates();
        if (state.roomEdited) return {status:'edited'};
        if (inputs.length!==1) return {status:'unavailable'};
        const input=inputs[0], current=String(input.value||'').trim();
        if (state.edited.has(input)) { state.roomEdited=true; return {status:'edited'}; }
        if (current) return {status:current===state.room?'filled':'kept'};
        if (state.filled.has(input)) return {status:'edited'};
        state.filled.add(input);
        state.applying=true;
        try {
            const setter=Object.getOwnPropertyDescriptor(input.ownerDocument.defaultView.HTMLInputElement.prototype,'value')?.set;
            if (setter) setter.call(input,state.room); else input.value=state.room;
            const EventType=input.ownerDocument.defaultView.Event;
            input.dispatchEvent(new EventType('input',{bubbles:true}));
            input.dispatchEvent(new EventType('change',{bubbles:true}));
        } finally { state.applying=false; }
        return {status:input.value===state.room?'filled':'unavailable'};
    };
    return fill();
    """#
}
