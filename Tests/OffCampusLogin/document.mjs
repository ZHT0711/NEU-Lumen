import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const source = readFileSync(new URL('../../NEU-Lumen/Core/Networking/PortalLoginDocument.swift', import.meta.url), 'utf8');
const script = source.split('static let script = #"""')[1].split('"""#')[0];
function run(declaration, password = false, sms = false) {
  const context = vm.createContext({window: {}, getComputedStyle: () => ({visibility: 'visible'}),
    document: {scripts: [], querySelector: () => sms ? {} : null,
      querySelectorAll: () => password ? [{disabled: false, getClientRects: () => [1],
        get value() { throw new Error('must not read a password'); }}] : []}});
  vm.runInContext(declaration, context);
  return JSON.parse(vm.runInContext(script, context));
}
for (const declaration of ['const userInfoDSL', 'let userInfoDSL', 'window.userInfoDSL']) {
  const doc = run(declaration + ' = {name:"测试同学",xgh:"20260042",depart:"计算机学院",identity:"本科生"};');
  assert.equal(doc.user.name, '测试同学');
  assert.equal(doc.user.depart, '计算机学院');
  assert.equal(doc.loginForm, false);
}
assert.equal(run('', true).loginForm, true);
assert.equal(run('', false, true).loginForm, true);
assert.equal(run('const userInfoDSL = JSON.stringify({name:"测试同学",xgh:"42"});').user.name, '测试同学');
console.log('Portal document: lexical globals, JSON DSL, visible password/SMS forms and no password access passed');
