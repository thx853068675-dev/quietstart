#!/usr/bin/env python3
"""Re-sign QuietStart's embedded worker and main HAP with official SDK tools."""
import argparse
import copy
import io
import json
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

BUNDLE = 'com.tonghongxiang.quietstart'
WORKER = 'resources/rawfile/quietstart-worker.hap'
MANIFEST = 'resources/rawfile/quietstart-worker.json'
MAX_TOTAL = 256 * 1024 * 1024


def archive(data):
    """Read bounded ZIP contents without extracting paths to the filesystem."""
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        infos = z.infolist()
        names = [i.filename for i in infos]
        if len(names) != len(set(names)):
            raise ValueError('HAP 内有重复文件名，已停止。')
        if len(names) > 4096 or sum(i.file_size for i in infos) > MAX_TOTAL:
            raise ValueError('HAP 解包内容超过支持大小。')
        return infos, {i.filename: z.read(i.filename) for i in infos}


def validate(data):
    _, files = archive(data)
    main = json.loads(files['module.json'])
    manifest = json.loads(files[MANIFEST])
    worker = files[WORKER]
    _, inner = archive(worker)
    module = json.loads(inner['module.json'])
    if any(n.endswith(('quietstart-worker.hap', 'quietstart-worker.json')) for n in inner):
        raise ValueError('内置工作模块递归嵌套。')
    if not (main['app']['bundleName'] == module['app']['bundleName'] == manifest['bundleName'] == BUNDLE
            and main['app']['versionCode'] == module['app']['versionCode'] == manifest['versionCode']
            and module['module']['name'] == manifest['moduleName'] == 'entry_test'
            and main['module']['name'] == 'entry'):
        raise ValueError('主包、内置模块或清单的包名、模块名、版本不匹配。')
    if (manifest['size'] != len(worker) or manifest['sha256'] != hashlib.sha256(worker).hexdigest()
            or not 1024 <= len(worker) <= 16777216):
        raise ValueError('内置模块大小或摘要错误，请使用完整原包。')
    for m in (main, module):
        if not isinstance(m['app']['minAPIVersion'], int) or m['app']['minAPIVersion'] <= 0:
            raise ValueError('包内最低 API 版本无效。')
    return main, module, manifest, worker


def repack(data, target, replacements=None):
    infos, files = archive(data)
    with zipfile.ZipFile(target, 'w') as z:
        for info in infos:
            z.writestr(copy.copy(info), (replacements or {}).get(info.filename, files[info.filename]))


def unchanged_payload(before, after, replacements=None):
    _, a = archive(before)
    _, b = archive(after)
    expected = dict(a)
    expected.update(replacements or {})
    if expected != b:
        raise ValueError('签名前后包内文件发生非预期变化，未交付输出。')


def run_tool(java, jar, arguments, interactive=False):
    command = [str(java), '-jar', str(jar), *arguments]
    if interactive:
        # Inherit the terminal so the official tool can read passwords without echo.
        # Do not put passwords in argv, config, environment, or generated files.
        result = subprocess.run(command)
        if result.returncode:
            raise ValueError('官方签名工具失败，请检查上方提示、密钥别名和签名材料。')
    else:
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        if result.returncode or 'verify-app success' not in result.stdout:
            raise ValueError('官方校验工具失败：\n' + (result.stdout + result.stderr)[-1800:])


class Signer:
    def __init__(self, config):
        self.config = config

    def verify(self, source, directory, label):
        run_tool(self.config['java'], self.config['sign_tool'], [
            'verify-app', '-inFile', str(source),
            '-outCertChain', str(directory / (label + '.cer')),
            '-outProfile', str(directory / (label + '.p7b'))])

    def sign(self, source, target, minimum):
        c = self.config
        run_tool(c['java'], c['sign_tool'], [
            'sign-app', '-mode', 'localSign', '-keyAlias', c['key_alias'],
            '-appCertFile', c['certificate'], '-profileFile', c['profile'],
            '-keystoreFile', c['keystore'], '-signAlg', c['algorithm'],
            '-compatibleVersion', str(minimum), '-signCode', '1', '-pwdInputMode', '1',
            '-inFile', str(source), '-outFile', str(target)], interactive=True)


def resign(source, output, signer):
    source, output = Path(source).resolve(), Path(output).absolute()
    if source == output.resolve() or output.exists() or output.is_symlink():
        raise ValueError('输出已存在或与原包相同。请换一个新文件名，不会覆盖原文件。')
    if source.stat().st_size > MAX_TOTAL:
        raise ValueError('输入文件过大。')
    original = source.read_bytes()
    main, module, manifest, worker = validate(original)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.quietstart-resign-', dir=output.parent) as tmp:
        work = Path(tmp)
        # Snapshot the input, so validation and signing use exactly the same bytes.
        snapshot = work / 'input.hap'
        snapshot.write_bytes(original)
        original_worker = work / 'worker-original.hap'
        original_worker.write_bytes(worker)
        print('1/5 校验原包与内置模块', flush=True)
        signer.verify(snapshot, work, 'input')
        signer.verify(original_worker, work, 'input-worker')
        unsigned_worker, signed_worker = work / 'worker-unsigned.hap', work / 'worker-signed.hap'
        repack(worker, unsigned_worker)
        print('2/5 重签内置模块', flush=True)
        signer.sign(unsigned_worker, signed_worker, module['app']['minAPIVersion'])
        signer.verify(signed_worker, work, 'worker')
        new_worker = signed_worker.read_bytes()
        unchanged_payload(worker, new_worker)
        manifest.update(size=len(new_worker), sha256=hashlib.sha256(new_worker).hexdigest())
        replacements = {WORKER: new_worker, MANIFEST: (json.dumps(manifest, indent=2) + '\n').encode()}
        unsigned_main, signed_main = work / 'main-unsigned.hap', work / 'main-signed.hap'
        print('3/5 自动更新摘要、大小并回填主包', flush=True)
        repack(original, unsigned_main, replacements)
        print('4/5 重签主包', flush=True)
        signer.sign(unsigned_main, signed_main, main['app']['minAPIVersion'])
        print('5/5 验证签名、内外一致性及程序内容', flush=True)
        signer.verify(signed_main, work, 'main')
        result = signed_main.read_bytes()
        validate(result)
        unchanged_payload(original, result, replacements)
        # Exclusive creation prevents overwriting an output created during signing.
        created = False
        try:
            with output.open('xb') as f:
                created = True
                f.write(result)
        except BaseException:
            if created:
                output.unlink()
            raise
    print('完成，只需侧载此主 HAP：' + str(output))
    print('SHA-256：' + hashlib.sha256(result).hexdigest())


def ask(label, default=''):
    value = input(label + (f' [{default}]' if default else '') + '：').strip()
    return (value or default).strip('"\'')


def configuration(args):
    c = {}
    if args.config:
        c = json.loads(Path(args.config).read_text(encoding='utf-8'))
    allowed = {'java', 'sign_tool', 'certificate', 'profile', 'keystore', 'key_alias', 'algorithm'}
    if not isinstance(c, dict) or set(c) - allowed:
        raise ValueError('配置只允许工具路径和签名材料路径、别名、算法；不支持保存密码。')
    ide = Path('/Applications/DevEco-Studio.app/Contents')
    defaults = {'java': str(ide / 'jbr/Contents/Home/bin/java') if sys.platform == 'darwin' else (shutil.which('java') or ''),
                'sign_tool': str(ide / 'sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar') if sys.platform == 'darwin' else '',
                'algorithm': 'SHA256withECDSA'}
    labels = {'java': 'Java 可执行文件路径', 'sign_tool': 'hap-sign-tool.jar 路径',
              'certificate': '调试证书 .cer 路径', 'profile': '调试 Profile .p7b 路径',
              'keystore': '密钥库 .p12 / .jks 路径', 'key_alias': '密钥别名'}
    for key, label in labels.items():
        if not c.get(key):
            default = defaults.get(key, '')
            c[key] = default if default and Path(default).is_file() else ask(label, default)
        if not isinstance(c[key], str) or not c[key]:
            raise ValueError('配置缺少有效值：' + key)
        if key != 'key_alias':
            c[key] = str(Path(c[key]).expanduser().resolve())
            if not Path(c[key]).is_file():
                raise ValueError('文件不存在：' + c[key])
    c.setdefault('algorithm', defaults['algorithm'])
    if not isinstance(c['algorithm'], str) or c['algorithm'] not in {'SHA256withECDSA', 'SHA384withECDSA', 'SHA256withRSA', 'SHA384withRSA'}:
        raise ValueError('不支持的签名算法。')
    return c


def main():
    parser = argparse.ArgumentParser(description='自动重签轻启内外 HAP；原包保持不变，不安装或卸载手机应用。')
    parser.add_argument('--input', help='完整主 HAP 路径；省略则交互询问')
    parser.add_argument('--output', help='输出 HAP 路径；必须是新文件')
    parser.add_argument('--config', help='签名材料路径 JSON；不含密码')
    args = parser.parse_args()
    if not sys.stdin.isatty():
        raise ValueError('请在本机交互终端运行，官方工具需要安全读取签名密码。')
    source = Path(args.input or ask('完整主 HAP 路径')).expanduser()
    if not source.is_file():
        raise ValueError('找不到主 HAP。')
    if not args.output:
        args.output = ask('输出 HAP 路径', str(Path('resign-work') / (source.stem + '-resigned.hap')))
    c = configuration(args)
    resign(source, Path(args.output).expanduser(), Signer(c))


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\n已取消，未交付未验证的包。', file=sys.stderr)
        sys.exit(130)
    except (ValueError, TypeError, KeyError, OSError, EOFError, zipfile.BadZipFile, subprocess.SubprocessError) as e:
        print('重签失败：' + str(e), file=sys.stderr)
        sys.exit(1)
