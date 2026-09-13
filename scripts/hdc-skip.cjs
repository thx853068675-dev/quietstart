#!/usr/bin/env node
'use strict';

const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFile } = require('node:child_process');
const { TARGETS, findCandidate, parseWindowManager, isForeground, sameCandidate, verifyControlGone } = require('./hdc-rules.cjs');

const HELP = `轻启：电脑连接备用模式（不是独立原生应用）

用法：node scripts/hdc-skip.cjs --device <设备 ID> [--target huya|youku] [--seconds 60] [--run]

默认仅识别并记录，不点击。--run 才会执行点击。
--target 未指定时依次检查虎牙、优酷；只支持这两个应用已验证的开屏布局。
--seconds 为整数 1..3600，默认 60。每个应用窗口在本次运行中最多点击一次。
需要电脑持续连接、手机解锁且已允许 USB 调试；用 Ctrl+C 停止。
仅主屏、普通全屏且无缩放的前台应用窗口可点击。广告消失后不会继续点击。
系统焦点格式无法识别时停止点击。系统升级或广告布局改变后可能不匹配。
只在临时目录读取当前界面布局，退出清理；不读取应用存储，日志不含界面内容。
HDC 可通过环境变量 HDC 指定，默认使用 /Applications/DevEco-Studio.app 的官方工具。
`;

function parseArgs(argv) {
  const options = { run: false, seconds: 60, targets: Object.keys(TARGETS) };
  const seen = new Set();
  for (let index = 0; index < argv.length; index++) {
    const key = argv[index];
    if (key === '--help' || key === '-h') return { help: true };
    if (seen.has(key)) throw new Error('INVALID_ARGUMENTS');
    seen.add(key);
    if (key === '--run') { options.run = true; continue; }
    if (!['--device', '--target', '--seconds'].includes(key) || index + 1 >= argv.length) throw new Error('INVALID_ARGUMENTS');
    const value = argv[++index];
    if (key === '--device') {
      if (!/^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$/.test(value)) throw new Error('INVALID_DEVICE');
      options.device = value;
    } else if (key === '--target') {
      if (!Object.hasOwn(TARGETS, value)) throw new Error('INVALID_TARGET');
      options.targets = [value];
    } else {
      if (!/^\d+$/.test(value) || Number(value) < 1 || Number(value) > 3600) throw new Error('INVALID_SECONDS');
      options.seconds = Number(value);
    }
  }
  if (!options.device) throw new Error('DEVICE_REQUIRED');
  return options;
}

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const output = (bundle, rule, result) => process.stdout.write(JSON.stringify({ bundle, rule, result }) + '\n');

async function createAdapter(options) {
  const hdc = process.env.HDC || path.join(process.env.DEVECO_APP || '/Applications/DevEco-Studio.app',
    'Contents/sdk/default/openharmony/toolchains/hdc');
  await fs.access(hdc);
  const localDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'quietstart-hdc-'));
  await fs.chmod(localDirectory, 0o700);
  const nonce = `${process.pid}-${crypto.randomBytes(8).toString('hex')}`;
  const pendingRemote = new Set();
  let sequence = 0;
  function command(args) {
    return new Promise((resolve, reject) => {
      // Never pass command text through a host shell; all phone shell tokens are fixed or numeric.
      execFile(hdc, ['-t', options.device, ...args], { timeout: 7000, maxBuffer: 1024 * 1024 }, (error, stdout) => {
        if (error) reject(new Error(error.killed ? 'HDC_TIMEOUT' : 'HDC_FAILED'));
        else resolve(stdout);
      });
    });
  }
  async function removeRemote(remote) {
    const result = await command(['shell', 'rm', '-f', remote]);
    if (result.trim()) throw new Error('REMOTE_CLEANUP_FAILED');
    pendingRemote.delete(remote);
  }
  return {
    async snapshot(targetName) {
      const target = TARGETS[targetName];
      if (!target) throw new Error('INVALID_TARGET');
      const filename = `${nonce}-${++sequence}.json`;
      const remote = `/data/local/tmp/quietstart-hdc-${filename}`;
      const local = path.join(localDirectory, filename);
      pendingRemote.add(remote);
      let layout;
      try {
        await command(['shell', 'uitest', 'dumpLayout', '-b', target.bundle, '-p', remote]);
        await command(['file', 'recv', remote, local]);
        const stats = await fs.stat(local);
        if (stats.size > 8 * 1024 * 1024) throw new Error('LAYOUT_TOO_LARGE');
        layout = JSON.parse(await fs.readFile(local, 'utf8'));
      } finally {
        await fs.rm(local, { force: true });
        await removeRemote(remote);
      }
      const windowText = await command(['shell', 'hidumper', '-s', 'WindowManagerService', '-a', '-a']);
      return { layout, windowManager: parseWindowManager(windowText) };
    },
    async click(candidate) {
      if (!Number.isSafeInteger(candidate.x) || !Number.isSafeInteger(candidate.y) || candidate.displayId !== 0) {
        throw new Error('INVALID_COORDINATES');
      }
      await command(['shell', 'uitest', 'uiInput', 'click', String(candidate.x), String(candidate.y)]);
    },
    async close() {
      let failed = false;
      for (const remote of pendingRemote) {
        try { await removeRemote(remote); } catch { failed = true; }
      }
      await fs.rm(localDirectory, { recursive: true, force: true });
      if (failed) throw new Error('REMOTE_CLEANUP_FAILED');
    }
  };
}

async function processTarget(targetName, adapter, state, options, log = output, now = Date.now, pause = delay) {
  const target = TARGETS[targetName];
  const report = result => {
    const key = `${target.bundle}:${result}`;
    if (!state.reported.has(key)) { state.reported.add(key); log(target.bundle, target.rule, result); }
  };
  const initial = await adapter.snapshot(targetName);
  const candidate = findCandidate(initial.layout, targetName);
  if (!candidate) return;
  if (!isForeground(candidate, initial.windowManager)) { report('refused_foreground_not_confirmed'); return; }
  const key = `${candidate.bundle}:${candidate.windowId}`;
  if (state.attempted.has(key)) return;
  if (!options.run) { report('dry_run_matching_foreground_skip'); return; }
  const confirm = await adapter.snapshot(targetName);
  const current = findCandidate(confirm.layout, targetName);
  if (!sameCandidate(candidate, current) || !isForeground(current, confirm.windowManager)) {
    report('refused_target_or_foreground_changed'); return;
  }
  if (state.stopped || now() >= state.deadline) return;
  // Even an uncertain dispatch consumes the window's single attempt.
  state.attempted.add(key);
  await adapter.click(current);
  log(target.bundle, target.rule, 'click_sent');
  await pause(250);
  const after = await adapter.snapshot(targetName);
  const gone = verifyControlGone(after.layout, current);
  if (!after.windowManager || after.windowManager.focusedWindowId !== current.windowId) {
    log(target.bundle, target.rule, 'verification_inconclusive_foreground_changed');
  } else if (gone === true) {
    log(target.bundle, target.rule, 'skip_control_disappeared_after_click');
  } else if (gone === null) {
    log(target.bundle, target.rule, 'verification_inconclusive_layout_missing');
  } else {
    log(target.bundle, target.rule, 'skip_control_still_visible_no_retry');
  }
}

async function main(argv) {
  let options;
  try { options = parseArgs(argv); } catch (error) {
    process.stderr.write(`参数错误：${error.message}\n请使用 --help 查看用法。\n`);
    return 2;
  }
  if (options.help) { process.stdout.write(HELP); return 0; }
  const state = { attempted: new Set(), reported: new Set(), stopped: false, deadline: Date.now() + options.seconds * 1000 };
  const stop = () => { state.stopped = true; };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  let adapter;
  let exitCode = 0;
  try {
    adapter = await createAdapter(options);
    for (const name of options.targets) output(TARGETS[name].bundle, TARGETS[name].rule,
      options.run ? 'run_started_computer_connection_required' : 'dry_run_started_no_clicks');
    while (!state.stopped && Date.now() < state.deadline) {
      for (const name of options.targets) {
        if (state.stopped || Date.now() >= state.deadline) break;
        await processTarget(name, adapter, state, options);
      }
      if (!state.stopped && Date.now() < state.deadline) await delay(250);
    }
  } catch {
    // Command output and exception messages may contain UI text or temporary paths; do not print them.
    output('', 'connection', 'stopped_debug_command_or_layout_failed');
    exitCode = 1;
  } finally {
    if (adapter) {
      try { await adapter.close(); } catch {
        output('', 'cleanup', 'phone_temp_cleanup_failed_reconnect_to_clean');
        exitCode = 1;
      }
    }
    process.removeListener('SIGINT', stop);
    process.removeListener('SIGTERM', stop);
  }
  return exitCode;
}

module.exports = { parseArgs, processTarget, main };
if (require.main === module) main(process.argv.slice(2)).then(code => { process.exitCode = code; });
