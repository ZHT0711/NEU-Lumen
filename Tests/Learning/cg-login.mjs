import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../../NEU-Lumen/Core/Models/CGAssignments.swift', import.meta.url), 'utf8');
const script = source.split('static let campusLoginScript = #"""')[1].split('"""#')[0];
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const run = new AsyncFunction('document', 'MutationObserver', 'setTimeout', 'clearTimeout', script);
let clicks = 0;
const node = (text, visible = true, disabled = false) => ({
  innerText: text, disabled, getAttribute: () => null,
  getClientRects: () => visible ? [{}] : [], click: () => clicks++,
});
await run({ querySelectorAll: () => [node('校园统一登录帮助'), node('校园统一登录', false),
  node('校园统一登录', true, true), node(' 校园 统一登录 ')] });
assert.equal(clicks, 1, 'Click exactly the visible enabled login control');

let callback;
let disconnected = false;
let nodes = [];
class Observer {
  constructor(fn) { callback = fn; }
  observe() {}
  disconnect() { disconnected = true; }
}
const pending = run({ querySelectorAll: () => nodes, documentElement: {} }, Observer, () => 1, () => {});
nodes = [node('校园统一登录')];
callback();
assert.equal(await pending, true);
assert.equal(clicks, 2);
assert.equal(disconnected, true);

let timeout;
const missing = run({ querySelectorAll: () => [], documentElement: {} }, Observer, fn => { timeout = fn; }, () => {});
timeout();
assert.equal(await missing, false, 'A missing login control must finish without clicking');
console.log('PASS: CG login exact match, visibility, disabled controls, async render and timeout');
