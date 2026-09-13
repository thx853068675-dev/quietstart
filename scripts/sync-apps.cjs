#!/usr/bin/env node
'use strict';
const { execFileSync } = require('node:child_process');
const { randomUUID } = require('node:crypto');
function createParts(raw, batch = randomUUID()) {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 2000) throw new Error('手机未返回有效的应用列表');
  const apps = raw.filter(app => app && typeof app.label === 'string' &&
    typeof app.bundleName === 'string' && /^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(app.bundleName))
    .map(app => ({ bundleName: app.bundleName, label: app.label.slice(0, 100) }));
  if (!apps.length) throw new Error('安装列表为空，保留手机上次列表');
  const groups = []; let group = [];
  for (const app of apps) {
    if (Buffer.byteLength(JSON.stringify([...group, app])) > 2000 && group.length) { groups.push(group); group = []; }
    group.push(app);
  }
  if (group.length) groups.push(group);
  return groups.map((items, index) => Buffer.from(JSON.stringify({ batch, index, total: groups.length, apps: items })).toString('base64'));
}
function main() {
  const [hdc, device] = process.argv.slice(2);
  if (!hdc || !device || process.argv.length !== 4) throw new Error('需要指定 hdc 和目标手机');
  const call = (args) => execFileSync(hdc, ['-t', device, ...args], { encoding: 'utf8', timeout: 20000, maxBuffer: 1024 * 1024 });
  const raw = JSON.parse(call(['shell', 'bm', 'dump', '-a', '-l']));
  for (const part of createParts(raw)) {
    const result = call(['shell', 'aa', 'test', '-b', 'com.tonghongxiang.quietstart', '-m', 'entry_test',
      '-s', 'unittest', 'OpenHarmonyTestRunner', '-s', 'mode', 'catalogImport', '-s', 'catalog', part, '-w', '10']);
    if (!result.includes('TestFinished-ResultCode: 0') || !result.includes('QuietStartCatalog: imported part')) {
      throw new Error('应用列表同步未完成：' + result.slice(0, 300));
    }
  }
  console.log('已同步手机安装列表，随后可在轻启中离线搜索和勾选。');
}
if (require.main === module) { try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; } }
module.exports = { createParts };
