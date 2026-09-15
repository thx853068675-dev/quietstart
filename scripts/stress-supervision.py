#!/usr/bin/env python3
"""Bounded fault injection into an already activated QuietStart test build.

Does not install, sign, delete rules, or activate an inactive session. Device
identity is explicit. Each signal checks that the PID still belongs to this app.
"""
import argparse
import json
import pathlib
import re
import subprocess
import time

BUNDLE = 'com.tonghongxiang.quietstart'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', required=True)
parser.add_argument('--case', choices=['observe', 'kill-worker', 'stall-rpc', 'end-session'], required=True)
parser.add_argument('--account', type=int, default=100)
parser.add_argument('--hdc', default='/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc')
parser.add_argument('--out', required=True)
args = parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9.:_-]+', args.serial) or not 0 <= args.account <= 2147483647:
    parser.error('Invalid serial or account')
directory = f'/data/app/el2/{args.account}/base/{BUNDLE}/files'
hdc = [args.hdc, '-t', args.serial, 'shell']
out = pathlib.Path(args.out)
out.parent.mkdir(parents=True, exist_ok=True)
events = []


def shell(command, timeout=12):
    run = subprocess.run(hdc + [command], capture_output=True, text=True, timeout=timeout)
    if run.returncode:
        raise RuntimeError(run.stderr or run.stdout)
    return run.stdout.strip()


def save():
    out.write_text(json.dumps({'case': args.case, 'serial': args.serial,
                               'scope': 'USB-connected test-build self-exit or bounded RPC-wait injection',
                               'events': events}, ensure_ascii=False, indent=2) + '\n')


def note(kind, **values):
    events.append({'at': int(time.time() * 1000), 'event': kind, **values})
    save()
    print(json.dumps(events[-1], ensure_ascii=False), flush=True)


def health():
    fields = shell(f'cat {directory}/worker-health.txt').split()
    if len(fields) != 9 or not re.fullmatch(r'\d{13,16}', fields[0]):
        raise RuntimeError('No valid worker health record; activate in app first')
    return {'token': fields[0], 'pid': int(fields[1]), 'heartbeat': int(fields[2]),
            'rpc': int(fields[4]), 'mode': fields[5], 'operation': fields[6]}


def control():
    return shell(f'cat {directory}/supervision-control.txt').split()


def owns(pid):
    if pid <= 1:
        return False
    return shell(f"cat /proc/{pid}/cmdline 2>/dev/null").split('\x00')[0] == BUNDLE


def snapshot():
    value = health()
    c = control()
    value['control'] = c[1] if len(c) == 3 else 'invalid'
    value['alive'] = owns(value['pid'])
    return value


def click_own(identifier):
    # Test controls only. Refresh the tree for every UI action.
    path = '/data/local/tmp/quietstart-stress-ui.json'
    shell(f'uitest dumpLayout -p {path}')
    try:
        tree = json.loads(shell(f'cat {path}'))
    finally:
        shell(f'rm -f {path}')
    roots = [n for n in tree.get('children', []) if n.get('attributes', {}).get('bundleName') == BUNDLE]
    if len(roots) != 1 or roots[0]['attributes'].get('focused') != 'true':
        raise RuntimeError('QuietStart is not the focused window')

    def nodes(n):
        yield n.get('attributes', {})
        for child in n.get('children', []):
            yield from nodes(child)

    hits = [n for n in nodes(roots[0]) if n.get('id') == identifier and n.get('visible') == 'true']
    if len(hits) != 1:
        raise RuntimeError('Control not visible: ' + identifier)
    a = hits[0]
    box = list(map(int, re.findall(r'-?\d+', a['bounds'])))
    if len(box) != 4 or box[2] <= box[0] or box[3] <= box[1]:
        raise RuntimeError('Invalid control geometry')
    shell(f'uitest uiInput click {(box[0]+box[2])//2} {(box[1]+box[3])//2}')


try:
    package_text = shell('bm dump -n ' + BUNDLE)
    package = json.loads(package_text[package_text.index('{'):])
    if package.get('versionName') != '0.9.54-test':
        raise RuntimeError('Requires isolated 0.9.54-test build')
    initial = snapshot()
    if initial['control'] != 'active' or not initial['alive']:
        raise RuntimeError('Session must already be online')
    now = int(time.time())
    if abs(now - initial['heartbeat']) > 15 or initial['mode'] == 'sleeping':
        raise RuntimeError('Unlock phone and wait for a fresh worker heartbeat')
    note('initial', **initial)
    if args.case == 'end-session':
        shell(f'aa start -b {BUNDLE} -a EntryAbility')
        time.sleep(1)
        click_own('quietstart-tab-home')
        time.sleep(.3)
        try:
            click_own('quietstart-end-session')
        except RuntimeError as error:
            if 'Control not visible' not in str(error):
                raise
            click_own('quietstart-session-details')
            time.sleep(.3)
            click_own('quietstart-end-session')
        note('user-end-session')
    else:
        shell('uitest uiInput keyEvent Home')
        time.sleep(1)
        if args.case in ['kill-worker', 'stall-rpc']:
            kind = 'exit' if args.case == 'kill-worker' else 'stall-rpc'
            shell(f'aa start -b {BUNDLE} -a EntryAbility --ps quietstartStress {kind} --ps quietstartStressToken {initial["token"]}')
            time.sleep(1)
            request = json.loads(shell(f'cat {directory}/supervision-stress.json'))
            if request.get('token') != initial['token'] or request.get('kind') != kind:
                raise RuntimeError('Test fault was not armed for this session')
            shell('uitest uiInput keyEvent Home')
            note('armed-test-build-fault', pid=initial['pid'], fault=kind, delayMs=4000)
    deadline = time.monotonic() + (45 if args.case in ['observe', 'end-session'] else 110)
    recovered = False
    while time.monotonic() < deadline:
        value = snapshot()
        note('sample', **value)
        if value['token'] != initial['token']:
            raise RuntimeError('Session was replaced externally; test inconclusive')
        if args.case in ['kill-worker', 'stall-rpc']:
            if value['pid'] != initial['pid'] and value['alive'] and value['control'] == 'active' and \
                    abs(int(time.time()) - value['rpc']) < 15:
                recovered = True
                break
            if value['control'] != 'active':
                break
        time.sleep(5)
    if args.case in ['kill-worker', 'stall-rpc']:
        passed = recovered
    elif args.case == 'end-session':
        passed = value['control'] == 'stopped' and not value['alive']
    else:
        passed = value['pid'] == initial['pid'] and value['alive'] and value['control'] == 'active' and \
            abs(int(time.time()) - value['heartbeat']) < 15
    journal = shell('cat /data/local/tmp/quietstart-supervisor/supervisor-events.jsonl')
    pathlib.Path(str(out) + '.journal.jsonl').write_text(journal + '\n')
    exits = shell(f'cat {directory}/system-exits.json')
    pathlib.Path(str(out) + '.exits.json').write_text(exits + '\n')
    note('result', passed=passed)
    if not passed:
        raise SystemExit(1)
except Exception as error:
    note('error', message=str(error))
    raise
