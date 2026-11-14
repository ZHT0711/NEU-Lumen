import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../../NEU-Lumen/Core/Models/NativeMail.swift',import.meta.url),'utf8');
const script=source.split('static let reader = #"""')[1].split('"""#')[0];
const execute=new Function('rootURL','command','expectedEmail','expectedSID','folderID','start','includeFolders','messageID','searchText',
    'searchFields','messageIDs','attributes','composeKind','attachmentID','attachmentName',
    'fetch','document','location','setTimeout','clearTimeout','AbortController','return(async()=>{'+script+'})();');
async function run(options={}) {
    const requests=[],downloads=[]; let identities=0;
    const email=options.email ?? 'synth-a@stu.neu.edu.cn';
    const document={scripts:[{textContent:"var $, _, X = {s:'SYNTH-ONLY-PRIVATE-TOKEN'};"}],body:{appendChild(){}},createElement(tag){
        if(tag==='a') return {click(){downloads.push({url:this.href,name:this.download});},remove(){}};
        return {set innerHTML(v){this.value=v.replaceAll('&amp;','&').replaceAll('&lt;','<').replaceAll('&gt;','>');}};
    }};
    const fetch=async(url,init)=>{
        const u=new URL(url); const func=u.searchParams.get('func') || (u.pathname.endsWith('readMessage.jsp')?'read':u.pathname.endsWith('compose.jsp')?'compose':'');
        const payload=init.headers['Content-Type'].startsWith('application/x-www-form-urlencoded')
            ?Object.fromEntries(new URLSearchParams(init.body)):JSON.parse(init.body);
        requests.push({func,payload,path:u.pathname});
        if (options.networkFailure===func) throw new TypeError('Synthetic disconnected response');
        assert.equal(u.searchParams.get('sid'),'SYNTH-ONLY-PRIVATE-TOKEN');
        let value;
        if(func==='user:getAttrs') value={email:identities++ >= (options.changeAfter ?? (options.changeIdentity?1:Infinity))?'synth-b@stu.neu.edu.cn':email};
        else if(func==='getAllFolders') value=[{id:1,name:'收件箱',stats:{allMessageCount:2,unreadMessageCount:1}},
            {id:-4,name:'虚拟分组',children:[{id:7,name:'自定义',stats:{}}]}];
        else if(func==='mbox:listMessages'||func==='searchMessages') value=options.rows ?? [
            {id:'SYNTH-MESSAGE-1',subject:'合成通知',from:[{name:'合成发件人',address:'fixture@example.invalid'}],receivedDate:2000000000000,flags:{read:false}},
            {id:'SYNTH-MESSAGE-2',subject:'合成邮件2',from:'fixture2@example.invalid',flags:{read:true}}];
        else if(func==='read') value=options.mailResponse ?? {mail:{subject:'正文测试',from:'fixture@example.invalid',to:[{name:'合成收件人',address:email}],cc:'cc@example.invalid',
            content:'<p>合成正文 &amp; 说明</p><script>BAD_SCRIPT</script><img src="https://tracking.invalid/x"><a href="https://example.invalid/info?x=1&amp;y=2">课程通知</a><a href="javascript:alert(1)">危险链接</a>',
            attachments:[{name:'合成附件.pdf',type:'internal',mid:'SYNTH-MESSAGE-1',part:'2',size:2048},{name:'网盘附件.zip',type:'trs',size:9000}]},
            mailInfo:{sentDate:2000000000000,flags:{read:true}}};
        else if(func==='mbox:updateMessageInfos') value={originalMsgInfos:payload.ids.map(id=>({id,flags:{read:false}}))};
        else if(func==='compose') value={id:'SYNTH-COMPOSE-ID'};
        else throw new Error('unexpected operation '+func);
        return {ok:true,url:u.href,async json(){return {code:options.failed?'FA_NOT_LOGIN':options.reject===func?'FA_INVALID_OPERATION':'S_OK',var:value};}};
    };
    const result=await execute('https://mails.neu.edu.cn/coremail/',options.command ?? 'list',options.expectedEmail ?? email,
        options.sid ?? 'SYNTH-A','1',0,true,'SYNTH-MESSAGE-1',options.search ?? '',
        options.searchFields ?? {},options.messageIDs ?? ['SYNTH-MESSAGE-1'],options.attributes ?? {flags:{read:true}},options.composeKind ?? 'normal',
        options.attachmentID ?? 'part:2:0',options.attachmentName ?? '合成附件.pdf',fetch,document,
        {href:'https://mails.neu.edu.cn/coremail/XT/index.jsp',origin:'https://mails.neu.edu.cn',pathname:'/coremail/XT/index.jsp'},setTimeout,clearTimeout,AbortController);
    assert.ok(!JSON.stringify(result).includes('SYNTH-ONLY-PRIVATE-TOKEN'),'native results must never expose SID');
    return {result,requests,downloads};
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
assert.ok(!result.body.text.includes('tracking.invalid'));
assert.deepEqual(result.body.attachments,[{id:'part:2:0',name:'合成附件.pdf',size:2048,downloadable:true},{id:'1',name:'网盘附件.zip',size:9000,downloadable:false}]);
assert.equal(result.body.recipients,'合成收件人 synth-a@stu.neu.edu.cn');
assert.equal(result.body.cc,'cc@example.invalid'); assert.equal(result.body.date,2000000000000);
assert.equal(result.body.unread,false);
assert.deepEqual(result.body.links,[{title:'课程通知',url:'https://example.invalid/info?x=1&y=2'}]);
{
    const response=await run({command:'download'});
    assert.equal(response.result.downloadRequested,true);
    assert.equal(response.downloads.length,1);
    const url=new URL(response.downloads[0].url);
    assert.equal(url.origin,'https://mails.neu.edu.cn'); assert.equal(url.pathname,'/coremail/s/json');
    assert.equal(url.searchParams.get('func'),'mbox:getMessageData');
    assert.equal(url.searchParams.get('mid'),'SYNTH-MESSAGE-1'); assert.equal(url.searchParams.get('part'),'2');
    assert.equal(url.searchParams.get('mode'),'download'); assert.equal(url.searchParams.get('sid'),'SYNTH-ONLY-PRIVATE-TOKEN');
    assert.equal(response.downloads[0].name,'合成附件.pdf');
    assert.equal(response.requests.filter(r=>r.func==='user:getAttrs').length,2,'download rechecks identity before browser activation');
    assert.ok(!response.requests.some(r=>r.func==='mbox:updateMessageInfos'),'download does not mark or move mail');
}
for(const options of [{attachmentID:'forged'},{attachmentName:'changed.pdf'},{attachmentID:'1',attachmentName:'网盘附件.zip'},{changeIdentity:true}]) {
    const response=await run({command:'download',...options});
    assert.ok(response.result.error); assert.equal(response.downloads.length,0,'invalid or identity-changed attachments never activate');
}
for(const attachment of [
    {type:'internal',part:'../../outside'}, {type:'internal',part:'2',mid:'OTHER-MESSAGE'},
    {type:'internal',part:'2',deleted:true}, {type:'internal',part:'2',inlined:true}, {type:'trs',part:'2'}
]) {
    const response=await run({command:'download',mailResponse:{mail:{attachments:[{name:'合成附件.pdf',...attachment}]}}});
    assert.equal(response.downloads.length,0);assert.equal(response.result.error,'format');
}
({result}=await run({command:'read',mailResponse:{mail:{attachments:[{name:'未知大小',size:null}]}}}));
assert.equal(result.body.attachments[0].size,null,'unknown attachment size is not displayed as zero bytes');
({result,requests}=await run({searchFields:{from:'teacher@example.invalid',to:'synth-a@stu.neu.edu.cn',read:false,attachType:'attached',flagType:'flagged'}}));
const advanced=requests.find(r=>r.func==='searchMessages').payload;
assert.equal(advanced.from,'teacher@example.invalid'); assert.equal(advanced.read,'false');
assert.equal(advanced.to,'synth-a@stu.neu.edu.cn'); assert.equal(advanced.attachType,'attached'); assert.equal(advanced.flagType,'flagged');
for (const attributes of [{flags:{read:true}},{flags:{read:false}},{flags:{flagged:true}},{flags:{flagged:false},label0:0},{fid:7}]) {
    ({result,requests}=await run({command:'update',attributes}));
    assert.equal(result.updated,true);
    assert.deepEqual(requests.find(r=>r.func==='mbox:updateMessageInfos').payload,{mboxa:'',ids:['SYNTH-MESSAGE-1'],attrs:attributes,returnOriginalMsgInfos:true});
    assert.equal(requests.filter(r=>r.func==='user:getAttrs').length,3);
}
for (const attributes of [{fid:-1},{flags:{deleted:true}},{flags:{read:true,flagged:true}},{flags:{read:true},rule:'unsafe'}]) {
    ({result,requests}=await run({command:'update',attributes}));
    assert.equal(result.error,'format'); assert.ok(!requests.some(r=>r.func==='mbox:updateMessageInfos'));
}
({result,requests}=await run({command:'update',changeIdentity:true}));
assert.equal(result.error,'identity'); assert.ok(!requests.some(r=>r.func==='mbox:updateMessageInfos'));
({result,requests}=await run({command:'update',changeAfter:2}));
assert.equal(result.error,'identity'); assert.equal(requests.filter(r=>r.func==='mbox:updateMessageInfos').length,1);
({result,requests}=await run({command:'update',expectedEmail:'other@stu.neu.edu.cn'}));
assert.equal(result.error,'binding'); assert.equal(requests.length,1);
({result,requests}=await run({command:'update',networkFailure:'mbox:updateMessageInfos'}));
assert.equal(result.error,'network'); assert.equal(requests.filter(r=>r.func==='mbox:updateMessageInfos').length,1,'an ambiguous write must never auto-retry');
({result}=await run({command:'update',reject:'mbox:updateMessageInfos'})); assert.equal(result.error,'operation');
({result}=await run({command:'update',messageIDs:['x','x']})); assert.equal(result.error,'format');
for (const kind of ['normal','reply','replyall','forward']) {
    ({result,requests}=await run({command:'compose',composeKind:kind}));
    assert.equal(result.composeID,'SYNTH-COMPOSE-ID');
    const init=requests.find(r=>r.func==='compose'); assert.equal(init.path,'/coremail/XT/jsp/compose.jsp');
    assert.equal(init.payload.ctype,kind); assert.equal(init.payload.mid,kind==='normal'?undefined:'SYNTH-MESSAGE-1');
    assert.ok(!requests.some(r=>/send|deliver/.test(r.func)));
}
console.log('Native Coremail bridge: real script identity gates, pagination/search encoding, SID isolation and inert message text passed');
