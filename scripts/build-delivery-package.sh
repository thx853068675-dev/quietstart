#!/bin/bash
# Packages one signed main HAP with its embedded worker; official hdc is obtained separately.
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:-mac}"
[[ "$platform" == mac || "$platform" == win ]] || { echo 'Use mac or win' >&2; exit 2; }
python3 tools/verify-single-package.py
python3 - "$platform" <<'PY'
import pathlib,re,sys,zipfile
p=pathlib.Path.cwd(); platform=sys.argv[1]
files=[p/'entry/build/default/outputs/default/entry-default-signed.hap',p/('tools/install-to-user-device.'+('sh' if platform=='mac' else 'bat'))]
for f in files:
 if not f.is_file():raise SystemExit('Missing build output: '+str(f))
out=p/'dist'/('qingqi-delivery-'+platform+'.zip');out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
 for f in files:z.write(f,f.name)
 z.writestr('README.txt','轻启单包安装\n\n1. 本包必须已为你的手机签名授权；作者个人调试包不适用于所有设备。\n2. 电脑准备官方 SDK hdc，并用 HDC_BIN 指定工具路径。\n3. 手机开启开发者模式、USB 调试，连接电脑并允许授权；只保留一个连接目标。\n4. 在当前目录运行安装脚本，只安装 entry-default-signed.hap。\n5. 手机开启无线调试，在轻启向导填入当前端口并允许本机激活；工作模块由轻启自动安装。\n6. 等待概览在线，拔掉 USB 验证；新规则在规则页确认后启用。\n\n不需要手动安装 UiTest，不需要外网下载工作模块。详细步骤及 macOS / Windows 命令见 INSTALL.md。\n')
 # The delivery archive has no source docs; keep references readable without broken links.
 guide=(p/'docs/INSTALL.md').read_text()
 guide=re.sub(r'\[([^\]]+)\]\(BUILD\.md(?:#[^)]*)?\)',r'\1（源码包中的 docs/BUILD.md）',guide)
 z.writestr('INSTALL.md',guide)
print(out)
PY
