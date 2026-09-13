#!/usr/bin/env python3
"""Package one desktop build without any local signing/account material."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
from prepare import HAP_SHA, HERE, UPSTREAM

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--hap', type=Path, required=True)
parser.add_argument('--platform', choices=['macOS-arm64', 'Windows-x64'], required=True)
args = parser.parse_args()
if hashlib.sha256(args.hap.read_bytes()).hexdigest() != HAP_SHA:
    raise ValueError('Unexpected HAP')
build = args.source / 'flutter/hap_installer/build'
destination = Path('release-bundles').resolve()
destination.mkdir(exist_ok=True)
name = f'quietstart-0.9.43-{args.platform}-bundle'
with tempfile.TemporaryDirectory(prefix='quietstart-bundle-') as temporary:
    root = Path(temporary)/name
    root.mkdir()
    if args.platform == 'macOS-arm64':
        apps = list((build/'macos/Build/Products/Release').glob('*.app'))
        if len(apps) != 1:
            raise ValueError('Expected exactly one built Mac app')
        subprocess.run(['ditto', str(apps[0]), str(root/apps[0].name)], check=True)
    else:
        binary = build/'windows/x64/runner/Release'
        if not list(binary.glob('*.exe')):
            raise ValueError('Windows executable missing')
        shutil.copytree(binary, root/'小白调试助手-轻启整合版')
    shutil.copyfile(args.hap, root/'quietstart-0.9.43.hap')
    shutil.copyfile(HERE/'USAGE.md', root/'开始使用.md')
    shutil.copyfile(HERE/'THIRD-PARTY.md', root/'第三方说明.md')
    revision = subprocess.check_output(['git', '-C', str(HERE), 'rev-parse', 'HEAD'], text=True).strip()
    (root/'BUILD.txt').write_text(f'XiaoBai source: {UPSTREAM}\nIntegration source: {revision}\nPlatform: {args.platform}\nQuietStart HAP SHA256: {HAP_SHA}\n', encoding='utf-8')
    (root/'SHA256SUMS.txt').write_text(f'{HAP_SHA}  quietstart-0.9.43.hap\n', encoding='utf-8')
    target = destination/(name+'.zip')
    if args.platform == 'macOS-arm64':
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(root), str(target)], check=True)
    else:
        shutil.make_archive(str(target.with_suffix('')), 'zip', temporary, name)
    print(target, hashlib.sha256(target.read_bytes()).hexdigest())
