import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../../NEU-Lumen/Core/Models/NativeMail.swift',import.meta.url),'utf8');
const script=source.split('static let reader = #"""')[1].split('"""#')[0];
const execute=new Function('rootURL','command','expectedEmail','expectedSID','folderID','start','includeFolders','messageID','searchText',
    'fetch','document','location','setTimeout','clearTimeout','AbortController','return(async()=>{'+script+'})();');
async function run(options={}) {
    const requests=[]; let identities=0;
    const email=options.email ?? 'synth-a@stu.neu.edu.cn';
    const document={scripts:[{textContent:"var $, _, X = {s:'SYNTH-ONLY-PRIVATE-TOKEN'};"}],createElement(){
        return {set innerHTML(v){this.value=v.replaceAll('&amp;','&').replaceAll('&lt;','<').replaceAll('&gt;','>');}};
    }};
    const fetch=async(url,init)=>{
        const u=new URL(url); const func=u.searchParams.get('func') || (u.pathname.endsWith('readMessage.jsp')?'read':'');
        const payload=init.headers['Content-Type'].startsWith('application/x-www-form-urlencoded')
            ?Object.fromEntries(new URLSearchParams(init.body)):JSON.parse(init.body);
        requests.push({func,payload,path:u.pathname});
        assert.equal(u.searchParams.get('sid'),'SYNTH-ONLY-PRIVATE-TOKEN');
        let value;
        if(func==='user:getAttrs') value={email:options.changeIdentity && identities++>0?'synth-b@stu.neu.edu.cn':email};
        else if(func==='getAllFolders') value=[{id:1,name:'收件箱',stats:{allMessageCount:2,unreadMessageCount:1}},
            {id:-4,name:'虚拟分组',children:[{id:7,name:'自定义',stats:{}}]}];
        else if(func==='mbox:listMessages'||func==='searchMessages') value=options.rows ?? [
            {id:'SYNTH-MESSAGE-1',subject:'合成通知',from:[{name:'合成发件人',address:'fixture@example.invalid'}],receivedDate:2000000000000,flags:{read:false}},
            {id:'SYNTH-MESSAGE-2',subject:'合成邮件2',from:'fixture2@example.invalid',flags:{read:true}}];
        else if(func==='read') value={mail:{subject:'正文测试',from:'fixture@example.invalid',
            content:'<p>合成正文 &amp; 说明</p><script>BAD_SCRIPT</script><img src="https://tracking.invalid/x">',attachments:[{name:'合成附件.pdf'}]}};
        else throw new Error('unexpected operation '+func);
        return {ok:true,url:u.href,async json(){return {code:options.failed?'FA_NOT_LOGIN':'S_OK',var:value};}};
    };
    const result=await execute('https://mails.neu.edu.cn/coremail/',options.command ?? 'list',options.expectedEmail ?? email,
        options.sid ?? 'SYNTH-A','1',0,true,'SYNTH-MESSAGE-1',options.search ?? '',fetch,document,
        {href:'https://mails.neu.edu.cn/coremail/XT/index.jsp',origin:'https://mails.neu.edu.cn',pathname:'/coremail/XT/index.jsp'},setTimeout,clearTimeout,AbortController);
    assert.ok(!JSON.stringify(result).includes('SYNTH-ONLY-PRIVATE-TOKEN'),'native results must never expose SID');
    return {result,requests};
}
let {result,requests}=await run();
assert.equal(result.email,'synth-a@stu.neu.edu.cn');
assert.equal(result.messages[0].unread,true); assert.equal(result.messages[1].unread,false);
assert.deepEqual(result.folders.map(f=>f.id),['1','7']);
assert.equal(requests.filter(r=>r.func==='user:getAttrs').length,2);
({result,requests}=await run({expectedEmail:'other@stu.neu.edu.cn'}));
assert.equal(result.error,'binding'); assert.equal(requests.length,1,'no message data before binding confirmation');
({result}=await run({changeIdentity:true})); assert.equal(result.error,'identity');
({result}=await run({failed:true})); assert.equal(result.error,'login');
({result}=await run({rows:[]})); assert.deepEqual(result.messages,[]); assert.equal(result.hasMore,false);
({result,requests}=await run({search:'课程 & 通知'}));
assert.equal(requests.find(r=>r.func==='searchMessages').payload.subject,'课程 & 通知');
({result}=await run({command:'read'}));
assert.match(result.body.text,/合成正文 & 说明/); assert.ok(!result.body.text.includes('BAD_SCRIPT'));
assert.ok(!result.body.text.includes('tracking.invalid')); assert.deepEqual(result.body.attachments,['合成附件.pdf']);
console.log('Native Coremail bridge: real script identity gates, pagination/search encoding, SID isolation and inert message text passed');
