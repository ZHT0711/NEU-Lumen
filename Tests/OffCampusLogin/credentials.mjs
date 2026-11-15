import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const source = readFileSync(new URL('../../NEU-Lumen/Core/Networking/CampusCredentialBridge.swift', import.meta.url), 'utf8');
const extract = name => source.split(`static let ${name} = #"""`)[1].split('"""#')[0];
function fixture(options = {}) {
  const listeners = {}, messages = [];
  const location = new URL(options.url || 'https://pass.neu.edu.cn/tpass/login?service=https://personal.neu.edu.cn/portal');
  const form = {action: options.action || location.href, method: options.method || 'post'};
  let reads = 0, clicks = 0, secret = options.password || '';
  const account = {value: options.username || '', form, type: 'text', disabled: false, name: 'un', id: 'un'};
  const password = {form, type: 'password', disabled: !!options.disabled, name: 'pd', id: 'pd',
    get value() { reads++; return secret; }, set value(value) { secret = value; }};
  const emit = (type, target, rest = {}) => { for (const fn of listeners[type] || []) fn({type, target, ...rest}); };
  for (const input of [account, password]) {
    input.getClientRects = () => [1];
    input.dispatchEvent = event => emit(event.type, input);
  }
  const button = {id: 'index_login_btn', type: 'button', form, disabled: false,
    closest() { return this; }, click() { clicks++; emit('click', this); }};
  const document = {
    addEventListener(type, fn) { (listeners[type] ||= []).push(fn); },
    querySelector(selector) {
      if (selector === '#second_auth_form') return options.secondAuth ? {} : null;
      if (selector === '#errormsg, #msg, #msg_i18n') return options.error ? {textContent:options.error} : null;
      if (selector.startsWith('#un')) return account;
      if (selector.startsWith('#pd')) return password;
      return options.missingButton ? null : button;
    },
    querySelectorAll() { return [account, password, ...(options.captcha ? [{name:'captcha', type:'text', disabled:false, getClientRects:() => [1]}] : [])]; }
  };
  const window = {__lumenRememberLogin: options.enabled !== false,
    webkit: {messageHandlers: {campusLoginDraft: {postMessage(value) { messages.push(JSON.parse(JSON.stringify(value))); }}}}};
  const context = vm.createContext({location, document, window, URL,
    Event: class { constructor(type) { this.type = type; } }, username:'SYNTH-1', password:'synthetic-password'});
  vm.runInContext(extract('script'), context);
  return {account, password, form, button, messages, window, emit,
    get reads() { return reads; }, get clicks() { return clicks; },
    autofill() { return vm.runInContext(`(async () => {${extract('autofillScript')}})()`, context); },
    rejected() { return vm.runInContext(`(async () => {${extract('rejectionScript')}})()`, context); }};
}

let f = fixture({username:'SYNTH-1', password:'synthetic-password'});
f.emit('input', f.password);
assert.equal(f.messages.length, 0, 'typing must not send a draft to native');
f.button.click();
assert.deepEqual(f.messages, [{username:'SYNTH-1', password:'synthetic-password'}]);
f = fixture({username:'SYNTH-1', password:'synthetic-password', enabled:false});
f.emit('input', f.password); f.button.click();
assert.equal(f.reads, 0); assert.equal(f.messages.length, 0);
for (const url of ['https://pass.neu.edu.cn.attacker.example/tpass/login', 'http://pass.neu.edu.cn/tpass/login', 'https://pass.neu.edu.cn:444/tpass/login', 'https://pass.neu.edu.cn/other']) {
  f = fixture({url, username:'SYNTH-1', password:'synthetic-password'});
  f.button.click();
  assert.equal(f.reads, 0); assert.equal(f.messages.length, 0);
  assert.equal(await f.autofill(), 'untrusted');
}
f = fixture({action:'https://attacker.example/login', username:'SYNTH-1', password:'synthetic-password'});
f.button.click(); assert.equal(f.messages.length, 0);
assert.equal(await f.autofill(), 'untrusted');
f = fixture({username:'SYNTH-1', password:'synthetic-password'});
f.emit('input', f.password); f.password.value = ''; f.emit('input', f.password); f.button.click();
assert.equal(f.messages.length, 0, 'an explicitly cleared password must not reuse an old draft');
f = fixture();
assert.equal(await f.autofill(), 'submitted');
assert.equal(f.clicks, 1); assert.deepEqual(f.messages, [{username:'SYNTH-1', password:'synthetic-password'}]);
for (const options of [{username:'OTHER'}, {password:'user-edited-secret'}]) {
  f = fixture(options); assert.equal(await f.autofill(), 'edited'); assert.equal(f.clicks, 0);
}
f = fixture({captcha:true});
assert.equal(await f.autofill(), 'challenge'); assert.equal(f.clicks, 0);
assert.equal(f.account.value, 'SYNTH-1'); assert.equal(f.messages.length, 0);
f = fixture({secondAuth:true});
assert.equal(await f.autofill(), 'challenge'); assert.equal(f.reads, 0); assert.equal(f.clicks, 0);
f = fixture({missingButton:true});
assert.equal(await f.autofill(), 'unrecognized'); assert.equal(f.account.value, '');
f = fixture({method:'get', username:'SYNTH-1', password:'synthetic-password'});
f.button.click(); assert.equal(f.messages.length, 0); assert.equal(await f.autofill(), 'unrecognized');
f = fixture({username:'SYNTH-1', password:'synthetic-password'});
f.emit('keydown', f.password, {key:'Enter'}); assert.equal(f.messages.length, 1);
for (const error of ['密码错误', '账号或密码不正确', '账号不存在', '账号已锁定', '登录次数超过限制']) {
  assert.equal(await fixture({error}).rejected(), true);
}
for (const error of ['验证码错误', '当前设备需进行身份验证', '请填写短信验证码', '']) {
  assert.equal(await fixture({error}).rejected(), false);
}
console.log('CAS credentials: exact origin, opt-out, submit-only drafts, cleared/user-edited fields, same-origin form, school login control and challenge handoff passed');
