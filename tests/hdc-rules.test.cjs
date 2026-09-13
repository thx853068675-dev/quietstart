'use strict';
const assert = require('node:assert/strict');
const test = require('node:test');
const { bounds, findCandidate, parseWindowManager, isForeground, verifyControlGone } = require('../scripts/hdc-rules.cjs');
const { parseArgs, processTarget } = require('../scripts/hdc-skip.cjs');

function node(attributes, children = []) {
  return { attributes: { enabled: 'true', visible: 'true', opacity: '1.000000', clickable: 'false',
    hostWindowId: '88', displayId: '0', bounds: '[0,0][1320,1150]', accessibilityId: '1',
    hitTestBehavior: 'HitTestMode.Default', ...attributes }, children };
}

function fixture(targetName = 'huya') {
  const label = node({ text: targetName === 'huya' ? '跳过' : '跳过广告', type: 'Text',
    clickable: targetName === 'huya' ? 'true' : 'false', accessibilityId: '42', bounds: '[1120,135][1240,185]' });
  const button = node({ id: targetName === 'huya' ? 'skipButton' : 'oneadbiz_ad_countdown',
    clickable: 'true', accessibilityId: '41', bounds: '[1090,125][1270,200]' }, [node({ accessibilityId: '40' }, [label])]);
  const marker = node({ id: targetName === 'huya' ? 'topAdText' : 'oneadbiz_splash_logo',
    text: targetName === 'huya' ? '广告｜已 WIFI 预加载' : '', accessibilityId: '43', bounds: '[800,140][1080,170]' });
  const root = node({ type: 'root', bundleName: targetName === 'huya' ? 'com.duowan.hyhos' : 'com.youku.next',
    focused: 'false', accessibilityId: '0' }, [button, marker]);
  return { layout: { attributes: { bounds: '[0,0][1320,2120]' }, children: [root] }, label, button, marker, root };
}

function windowText({ id = 88, type = 1, mode = 1, zOrder = 100, scale = 1, hand = 1, display = 0 } = {}) {
  return `----------------------------------WindowManagerService----------------------------------
WindowName           DisplayId Pid     WinId Type Mode Flag ZOrd Orientation [ x    y    w    h    ] [ OffsetX OffsetY ] [ ScaleX  ScaleY  PivotX  PivotY  ]
example0             ${display}         1234    ${id}    ${type}    ${mode}    0    ${zOrder}  0           [ 0    0    1320 2120 ] [ 0       0       ] [ ${scale}       ${scale}       0.5     0.5     ]
Focus window: ${id}
All Focus window:
DisplayId: ${display} WindowId: ${id}
SingleHand: X[0] Y[0] scale[${hand}]
Total window num: 1
`;
}

function snapshot(layout, focusedId = 88) {
  return { layout, windowManager: parseWindowManager(windowText({ id: focusedId })) };
}

test('known splash patterns require both the app-specific controls and ad marker', () => {
  for (const targetName of ['huya', 'youku']) {
    const f = fixture(targetName);
    const result = findCandidate(f.layout, targetName);
    assert.equal(result.x, 1180);
    assert.equal(result.y, 160);
    assert.equal(result.clickNodeId, targetName === 'huya' ? 42 : 41);
    f.marker.attributes.id = 'unrelated';
    assert.equal(findCandidate(f.layout, targetName), null);
  }
});

test('onboarding, unrelated labels, missing target id, hidden ancestors and ambiguous controls never match', () => {
  const changes = [
    f => { f.label.attributes.text = '跳过登录'; },
    f => { f.button.attributes.id = ''; },
    f => { f.root.attributes.bundleName = 'com.unrelated.app'; },
    f => { f.button.attributes.visible = 'false'; },
    f => { f.label.attributes.enabled = 'false'; },
    f => { f.label.attributes.hostWindowId = '99'; },
    f => { f.root.children.push(structuredClone(f.button)); },
    f => { f.label.attributes.bounds = '[20,130][300,190]'; },
    f => { f.label.attributes.bounds = '[1120,850][1240,900]'; }
  ];
  for (const change of changes) {
    const f = fixture(); change(f); assert.equal(findCandidate(f.layout, 'huya'), null, String(change));
  }
  assert.equal(bounds('[0,0][0,100]'), null);
  assert.equal(bounds('[NaN,0][100,100]'), null);
});

test('real window-manager focus is required; layout root.focused is not used', () => {
  const f = fixture();
  const candidate = findCandidate(f.layout, 'huya');
  assert.equal(isForeground(candidate, parseWindowManager(windowText())), true);
  f.root.attributes.focused = 'true';
  assert.equal(isForeground(candidate, parseWindowManager(windowText({ id: 13 }))), false);
  for (const config of [{ type: 2110 }, { mode: 102 }, { zOrder: -1 }, { scale: .85 }, { hand: .85 }, { display: 1 }]) {
    assert.equal(isForeground(candidate, parseWindowManager(windowText(config))), false, JSON.stringify(config));
  }
  assert.equal(parseWindowManager('Focus window: 88'), null);
  assert.equal(parseWindowManager(windowText() + 'Focus window: 13\n'), null);
  assert.equal(parseWindowManager(windowText().replace('DisplayId: 0 WindowId: 88', 'DisplayId: 0 WindowId: 13')), null);
});

test('disappearance verification requires the original app window and checks the node independently of its marker', () => {
  const f = fixture();
  const candidate = findCandidate(f.layout, 'huya');
  f.marker.attributes.visible = 'false';
  assert.equal(verifyControlGone(f.layout, candidate), false);
  f.label.attributes.visible = 'false';
  assert.equal(verifyControlGone(f.layout, candidate), true);
  f.root.attributes.hostWindowId = '99';
  assert.equal(verifyControlGone(f.layout, candidate), null);
});

test('CLI defaults to dry-run and validates device, duration, target and unknown arguments', () => {
  assert.equal(parseArgs(['--device', 'TEST123']).run, false);
  assert.deepEqual(parseArgs(['--device', 'TEST123', '--target', 'youku', '--seconds', '3600', '--run']),
    { device: 'TEST123', targets: ['youku'], seconds: 3600, run: true });
  for (const args of [[], ['--device', 'x;reboot'], ['--device', 'x', '--target', 'unknown'],
    ['--device', 'x', '--seconds', '3601'], ['--device', 'x', '--seconds', '0'],
    ['--device', 'x', '--seconds', 'NaN'], ['--device', 'x', '--force']]) assert.throws(() => parseArgs(args));
});

function scenario(layouts, { run = true } = {}) {
  let reads = 0;
  const clicks = [];
  const logs = [];
  const adapter = { async snapshot() { return layouts[Math.min(reads++, layouts.length - 1)]; },
    async click(candidate) { clicks.push(candidate); } };
  const state = { attempted: new Set(), reported: new Set(), stopped: false, deadline: 10000 };
  return { state, clicks, logs, reads: () => reads,
    async process() { await processTarget('huya', adapter, state, { run },
      (bundle, rule, result) => logs.push({ bundle, rule, result }), () => 0, async () => {}); } };
}

test('dry-run never dispatches; background apps never dispatch even when their nodes are visible', async () => {
  const dry = scenario([snapshot(fixture().layout)], { run: false });
  await dry.process();
  assert.equal(dry.clicks.length, 0);
  assert.equal(dry.reads(), 1);
  assert.equal(dry.logs[0].result, 'dry_run_matching_foreground_skip');
  const background = scenario([snapshot(fixture().layout, 13)]);
  await background.process();
  assert.equal(background.clicks.length, 0);
});

test('second live layout and focus check rejects an app switch or replaced target before dispatch', async () => {
  for (const second of [snapshot(fixture().layout, 13), snapshot({ attributes: {}, children: [] })]) {
    const s = scenario([snapshot(fixture().layout), second]);
    await s.process();
    assert.equal(s.clicks.length, 0);
    assert.equal(s.logs[0].result, 'refused_target_or_foreground_changed');
  }
});

test('uses fresh coordinates, records node disappearance, and never clicks twice in the same window', async () => {
  const first = fixture();
  const next = fixture();
  next.label.attributes.bounds = '[1130,135][1250,185]';
  const gone = fixture(); gone.root.children = [];
  const s = scenario([snapshot(first.layout), snapshot(next.layout), snapshot(gone.layout), snapshot(first.layout)]);
  await s.process();
  await s.process();
  assert.equal(s.clicks.length, 1);
  assert.equal(s.clicks[0].x, 1190);
  assert.equal(s.logs[1].result, 'skip_control_disappeared_after_click');
});

test('expired or stopped runs cannot dispatch after their second snapshot', async () => {
  for (const key of ['deadline', 'stopped']) {
    const s = scenario([snapshot(fixture().layout)]);
    s.state[key] = key === 'deadline' ? 0 : true;
    await s.process();
    assert.equal(s.clicks.length, 0);
  }
});
