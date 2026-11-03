const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('AnimeApp/AnimeApp.swift', 'utf8');
const script = source.match(/let script = #"""([\s\S]*?)"""#/)[1];
function fixture(host = 'ru.yummyani.me', address = 'https://api.yani.tv/profile/login', ok = true) {
  const messages = [];
  class XHR {
    open() {}
    addEventListener(name, listener) { this.listener = listener; }
  }
  const window = {
    fetch: async () => ({ ok, url: address, clone: () => ({ json: async () => ({ response: { token: 'test-session' } }) }) }),
    webkit: { messageHandlers: { yaniSignIn: { postMessage: value => messages.push(value) } } }
  };
  vm.runInNewContext(script, { window, location: { hostname: host, href: `https://${host}/` }, URL, XMLHttpRequest: XHR });
  return { window, messages, XHR };
}
test('captures a successful login response on the trusted site', async () => {
  const f = fixture(); await f.window.fetch('https://api.yani.tv/profile/login');
  await new Promise(setImmediate); assert.deepEqual(f.messages, ['test-session']);
});
test('rejects a token-shaped response from a different API host', async () => {
  const f = fixture('ru.yummyani.me', 'https://example.com/profile/login'); await f.window.fetch('ignored');
  await new Promise(setImmediate); assert.deepEqual(f.messages, []);
});
test('ignores non-authentication API responses', async () => {
  const f = fixture('ru.yummyani.me', 'https://api.yani.tv/anime/1'); await f.window.fetch('ignored');
  await new Promise(setImmediate); assert.deepEqual(f.messages, []);
});
test('ignores failed authentication responses', async () => {
  const f = fixture('ru.yummyani.me', 'https://api.yani.tv/profile/login', false); await f.window.fetch('ignored');
  await new Promise(setImmediate); assert.deepEqual(f.messages, []);
});
test('does not install a bridge on an unrelated website', async () => {
  const f = fixture('example.com'); await f.window.fetch('ignored');
  await new Promise(setImmediate); assert.deepEqual(f.messages, []);
});
test('handles successful XMLHttpRequest login responses', () => {
  const f = fixture(); const request = new f.XHR(); request.open('POST', 'https://api.yani.tv/profile/login');
  request.status = 200; request.responseURL = 'https://api.yani.tv/profile/login';
  request.responseText = JSON.stringify({ response: { token: 'test-xhr-session' } });
  request.listener.call(request); assert.deepEqual(f.messages, ['test-xhr-session']);
});
