#!/usr/bin/env python3
"""Reuse XiaoBai's local PEM key and an already signed QuietStart HAP on macOS."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pty
import re
import secrets
import select
import signal
import subprocess
import sys
import tempfile
import time


def openssl(*args, data=None):
    result = subprocess.run(['openssl', *map(str, args)], input=data,
                            capture_output=True, timeout=30)
    if result.returncode:
        raise ValueError('OpenSSL 校验或转换失败；请核对小白当前私钥与所选已签名包。')
    return result.stdout


def certificates(path):
    values = re.findall(b'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',
                        path.read_bytes(), re.S)
    if not values:
        raise ValueError('未提取到证书链。')
    return values


def cert_public_key(cert):
    pem = openssl('x509', '-pubkey', '-noout', data=cert)
    return openssl('pkey', '-pubin', '-outform', 'DER', data=pem)


def cert_identities(chain):
    return sorted(hashlib.sha256(openssl('x509', '-outform', 'DER', data=cert)).hexdigest()
                  for cert in chain)


def sign_with_temporary_password(command, password):
    """Answer official tool prompts with an ephemeral password; never log it."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(command[0], command)
    pending = b''
    deadline = time.monotonic() + 120
    prompts = 0
    reaped = False
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.2)
            if ready:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    chunk = b''
                pending += chunk
                while True:
                    match = re.search(rb'(?i)(?:KeystorePwd|KeyPwd)[^\r\n:]{0,100}:', pending)
                    if not match:
                        break
                    pending = pending[match.end():]
                    prompts += 1
                    if prompts > 2:
                        raise ValueError('官方工具重复询问密码，已停止。')
                    os.write(fd, password + b'\n')
                pending = pending[-4096:]
            done, status = os.waitpid(pid, os.WNOHANG)
            if done:
                reaped = True
                if os.waitstatus_to_exitcode(status) != 0 or prompts != 2:
                    raise ValueError('官方签名工具失败，未生成可交付包。')
                return
        raise ValueError('官方签名工具超时。')
    finally:
        if not reaped:
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description='复用小白的签名身份，重签轻启内外模块；不安装手机应用。')
    parser.add_argument('--input', required=True, help='小白已经签名的完整轻启主 HAP')
    parser.add_argument('--output', required=True, help='新的输出 HAP 路径')
    parser.add_argument('--xiaobai-config', type=Path,
                        default=Path.home() / 'Documents/hap_installer/signConfig.json')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        raise ValueError('此适配脚本目前仅验证 macOS。')
    source, output = Path(args.input).expanduser().resolve(), Path(args.output).expanduser().absolute()
    if output.exists() or output.is_symlink() or source == output.resolve():
        raise ValueError('输出已存在或与输入相同，请换一个新文件名。')
    spec = importlib.util.spec_from_file_location('quietstart_resign', Path(__file__).with_name('resign-hap.py'))
    core = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(core)
    if source.stat().st_size > core.MAX_TOTAL:
        raise ValueError('输入文件过大。')
    original = source.read_bytes()
    core.validate(original)
    config = json.loads(args.xiaobai_config.read_text())
    key = Path(config['keystoreFile']).expanduser()
    # Explicit empty passphrase prevents interactive hangs; encrypted keys are unsupported here.
    key_public = openssl('pkey', '-in', key, '-passin', 'pass:', '-pubout', '-outform', 'DER')
    sdk = Path('/Applications/DevEco-Studio.app/Contents')
    java = sdk / 'jbr/Contents/Home/bin/java'
    jar = sdk / 'sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar'
    if not java.is_file() or not jar.is_file():
        raise ValueError('请先在标准路径安装 DevEco Studio 和 SDK。')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.quietstart-xiaobai-', dir=output.parent) as tmp:
        work = Path(tmp)
        snapshot = work / 'xiaobai-input.hap'
        snapshot.write_bytes(original)
        base = core.Signer({'java': str(java), 'sign_tool': str(jar)})
        base.verify(snapshot, work, 'xiaobai')
        cert, profile = work / 'xiaobai.cer', work / 'xiaobai.p7b'
        chain = certificates(cert)
        if cert_public_key(chain[0]) != key_public:
            raise ValueError('小白当前私钥与输入包不匹配；请选用同一次重置后签名的包。')
        expected_certificates = cert_identities(chain)
        # Preserve the signed Profile exactly; do not regenerate or edit device authorization.
        profile_bytes = profile.read_bytes()
        password = secrets.token_urlsafe(32).encode('ascii')
        store = work / 'temporary.p12'
        openssl('pkcs12', '-export', '-inkey', key, '-passin', 'pass:', '-in', cert,
                '-name', 'quietstart-xiaobai', '-out', store, '-passout', 'stdin', data=password + b'\n')
        store.chmod(0o600)
        sign_config = {'java': str(java), 'sign_tool': str(jar), 'key_alias': 'quietstart-xiaobai',
                       'certificate': str(cert), 'profile': str(profile), 'keystore': str(store),
                       'algorithm': 'SHA256withECDSA'}

        class XiaoBaiSigner(core.Signer):
            def sign(self, src, dst, minimum):
                command = [str(java), '-jar', str(jar), 'sign-app', '-mode', 'localSign',
                           '-keyAlias', sign_config['key_alias'], '-appCertFile', str(cert),
                           '-profileFile', str(profile), '-keystoreFile', str(store),
                           '-signAlg', sign_config['algorithm'], '-compatibleVersion', str(minimum),
                           '-signCode', '1', '-pwdInputMode', '1', '-inFile', str(src), '-outFile', str(dst)]
                sign_with_temporary_password(command, password)

            def verify(self, src, directory, label):
                super().verify(src, directory, label)
                if label in ('worker', 'main'):
                    if cert_identities(certificates(directory / (label + '.cer'))) != expected_certificates:
                        raise ValueError('签名身份发生变化，停止交付。')
                    if (directory / (label + '.p7b')).read_bytes() != profile_bytes:
                        raise ValueError('Profile 发生变化，停止交付。')

        print('小白私钥与输入包匹配；自动处理内外签名，无需输入密码。', flush=True)
        core.resign(snapshot, output, XiaoBaiSigner(sign_config))
        print('已确认：内外包保持小白同一签名身份与原始 Profile。')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.TimeoutExpired) as error:
        print('失败：' + str(error), file=sys.stderr)
        sys.exit(1)
