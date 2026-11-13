import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const swift = readFileSync(path.join(root, 'NEU-Lumen/Core/Models/AcademicPageReader.swift'), 'utf8');
const script = swift.split('static let browserScript = #"""')[1].split('"""#')[0];
const run = new (Object.getPrototypeOf(async function(){}).constructor)('rootURL','expectedAccount','location','fetch','document',script);
const base = 'https://jwxt.neu.edu.cn/jwapp/sys/homeapp/';
const location = {origin:'https://jwxt.neu.edu.cn', pathname:'/jwapp/sys/synthetic/index.html'};
function documentFixture(rows, options={}) {
  const doc = {title:'合成培养课程表', defaultView:{getComputedStyle:()=>({visibility:'visible'})}};
  const visible = {ownerDocument:doc, getClientRects:()=>[{}]};
  const table = {...visible, tagName:'TABLE'};
  const rowEls = rows.map(cells=>({...visible, closest:()=>table,
    cells:cells.map(value=> typeof value==='object' ? {innerText:value.text,colSpan:1,rowSpan:value.span || 1} : {innerText:value,colSpan:1,rowSpan:1})}));
  table.querySelectorAll=()=>rowEls;
  doc.querySelectorAll=selector=> selector==='iframe' ? [] : [table];
  if(options.hidden) table.getClientRects=()=>[];
  if(options.crossOriginFrame) {
    const frame={...visible}; Object.defineProperty(frame,'contentWindow',{get(){throw new Error('cross origin');}});
    doc.querySelectorAll=selector=>selector==='iframe' ? [frame] : [table];
  }
  return doc;
}
async function read(rows, options={}) {
  const calls=[];
  const fetch = async (url, init) => {
    calls.push([url,init]);
    assert.equal(url, base+'api/home/currentUser.do'); assert.equal(init.method,'GET');
    assert.equal(init.credentials,'include'); assert.equal(init.redirect,'error');
    return {ok:!options.httpError, url:options.redirectURL || url,
      json:async()=>({code:options.businessError ? '403' : '0',datas:{userId:options.identityChange && calls.length>1 ? 'SYNTH-B' : options.account || 'SYNTH-A'}})};
  };
  const result = await run(options.base || base,'SYNTH-A',location,fetch,documentFixture(rows,options));
  return {result,calls};
}
const headers=['课程名称','课程代码','学分','课程模块','修读状态','建议学期'];
const rows=[headers,['合成课程一','SYNTH-C-1','2.5','合成基础模块','已修读','合成学期一']];
let checks=0;
function check(test){test(); checks++;}
let out=await read(rows);
check(()=>assert.deepEqual(out.result.courses,[{name:'合成课程一',code:'SYNTH-C-1',creditsText:'2.5',module:'合成基础模块',studyStatus:'已修读',suggestedTerm:'合成学期一'}]));
check(()=>assert.equal(out.calls.length,2));
check(()=>assert.equal(out.result.sourceURL,location.origin+location.pathname));
out=await read(rows,{account:'SYNTH-B'}); check(()=>assert.equal(out.result.error,'identity'));
out=await read(rows,{identityChange:true}); check(()=>assert.equal(out.result.error,'identity'));
out=await read(rows,{httpError:true}); check(()=>assert.equal(out.result.error,'identity'));
out=await read(rows,{businessError:true}); check(()=>assert.equal(out.result.error,'identity'));
out=await read(rows,{redirectURL:'https://pass.neu.edu.cn/tpass/login'}); check(()=>assert.equal(out.result.error,'identity'));
out=await read(rows,{base:'https://example.invalid/jwapp/sys/homeapp/'}); check(()=>assert.equal(out.calls.length,0));
out=await read([['课程名称','教室'],['合成课程一','合成教室']]); check(()=>assert.equal(out.result.error,'format'));
out=await read([headers]); check(()=>assert.equal(out.result.courses.length,0));
out=await read(rows,{hidden:true}); check(()=>assert.equal(out.result.error,'format'));
out=await read(rows,{crossOriginFrame:true}); check(()=>assert.equal(out.result.courses.length,1));
out=await read([['课程模块','课程名称','学分'],[{text:'合成共享模块',span:2},'合成课程一','2'],['合成课程二','3']]);
check(()=>assert.equal(out.result.courses[1].module,'合成共享模块'));
check(()=>assert.equal(out.result.courses[1].name,'合成课程二'));
out=await read([headers,['合计','','99','','','']]); check(()=>assert.equal(out.result.courses.length,0));
const guardScript = swift.split('static let readOnlyPageGuard = #"""')[1].split('"""#')[0];
const window = {fetch:async()=>true, XMLHttpRequest:{prototype:{open:()=>true}}};
new Function('window','location',guardScript)(window,{href:base});
await assert.rejects(window.fetch(base+'api/home/student/academic-status/collect-growthvalue.do')); checks++;
check(()=>assert.throws(()=>window.XMLHttpRequest.prototype.open('POST',base+'api/home/student/academic-status/record-failscore.do')));
check(()=>assert.equal(window.XMLHttpRequest.prototype.open('GET',base+'api/home/currentUser.do'),true));
check(()=>assert.equal(typeof window.fetch(base+'api/home/currentUser.do').then,'function'));
console.log(`Academic reader JavaScript: ${checks} checks passed (synthetic DOM; no network)`);
