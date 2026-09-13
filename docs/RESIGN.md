# 已有 HAP 的内外包重签

适合已经拿到轻启完整主 HAP、希望用自己的设备授权调试签名侧载的用户。无需重新编译源码，但需要电脑、官方 SDK 签名工具和有效签名材料。普通工具仅重签外层 HAP 不够。

**流程：提取内置模块 → 重签模块 → 更新摘要并放回主包 → 重签主包 → 只安装主包。**

## 1. 准备材料

- 完整的轻启主 HAP，内含 `resources/rawfile/quietstart-worker.hap` 和 `quietstart-worker.json`。不是 AGC 的 `.app` 容器，也不是独立测试 HAP。
- 自己的密钥库 `.p12`（或工具支持的 `.jks`）、密钥别名、密钥库密码和密钥密码。
- 与密钥匹配的调试证书 `.cer`、有效调试 Profile `.p7b`。
- Profile 必须授权目标手机，且包名与当前轻启一致：`com.tonghongxiang.quietstart`。内外包使用同一套材料。
- 官方 DevEco Studio / HarmonyOS SDK、Python 3，以及本仓库中的 `tools/verify-single-package.py`。

签名材料的申请与设备授权参见[华为自动签名说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto)及[调试 Profile 说明](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)。命令参数可查[官方签名工具文档](https://github.com/openharmony/developtools_hapsigner/blob/master/README.md)。

下面命令要求你知道密钥密码。DevEco 自动签名配置里的密码字段可能是加密值，不能直接当作密码输入。不知道密码时可继续用 IDE 按[源码构建流程](INSTALL.md#3-从源码生成自己的安装包)签名构建。

**不要修改包名来绕过 Profile 不匹配。** 当前启动逻辑使用固定包名。另一个开发者账号能否申请符合要求的 Profile，需要在该账号实际确认；本次实验没有覆盖跨账号申请。不要向作者发送密码或私钥。

## 2. 提取内包，生成待签名文件

以下是 macOS 的手动命令流程，适用于 0.9.42 的单包结构。Windows 尚未实测，不能将这些 Shell 命令直接粘贴到 CMD。

在项目根目录新开终端，将原始主 HAP 复制为 `input.hap`。所有输出放入一个新的本地目录，不覆盖原包：

```sh
mkdir -m 700 resign-work
python3 tools/verify-single-package.py input.hap
```

校验通过后，提取并重新生成工作模块 ZIP。重新写入 ZIP 是为了不沿用旧 HAP 的签名块，文件内容保持不变：

```sh
python3 - <<'PY'
from pathlib import Path
from io import BytesIO
from zipfile import ZipFile

with ZipFile('input.hap') as main:
    worker = main.read('resources/rawfile/quietstart-worker.hap')
    Path('resign-work/worker-original.hap').write_bytes(worker)
    with ZipFile(BytesIO(worker)) as old, ZipFile('resign-work/worker-unsigned.hap', 'w') as new:
        for item in old.infolist():
            new.writestr(item, old.read(item.filename))
print('已生成 worker-unsigned.hap')
PY
```

## 3. 先签内包

设置工具和签名文件位置。下列 `你的…` 路径及别名必须替换成自己的值；路径有空格时保留双引号。

```sh
IDE_ROOT="/Applications/DevEco-Studio.app/Contents"
JAVA_BIN="$IDE_ROOT/jbr/Contents/Home/bin/java"
SIGN_JAR="$IDE_ROOT/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
CERT_FILE="/你的签名目录/debug.cer"
PROFILE_FILE="/你的签名目录/debug.p7b"
KEYSTORE_FILE="/你的签名目录/debug.p12"
KEY_ALIAS="你的密钥别名"

sign_hap() {
  local min_api
  min_api=$(python3 -c 'import sys,json,zipfile; print(json.loads(zipfile.ZipFile(sys.argv[1]).read("module.json"))["app"]["minAPIVersion"])' "$1") || return
  "$JAVA_BIN" -jar "$SIGN_JAR" sign-app \
    -mode localSign -keyAlias "$KEY_ALIAS" \
    -appCertFile "$CERT_FILE" -profileFile "$PROFILE_FILE" \
    -keystoreFile "$KEYSTORE_FILE" -signAlg SHA256withECDSA \
    -compatibleVersion "$min_api" -signCode 1 -pwdInputMode 1 \
    -inFile "$1" -outFile "$2"
}

sign_hap resign-work/worker-unsigned.hap resign-work/worker-signed.hap
```

按工具提示交互输入密码，确认签名成功后再继续。示例算法适用于本次使用的 EC 密钥；其他密钥须使用匹配算法。`minAPIVersion` 从包内读取，不要自行改成手机界面显示的系统版本号。

## 4. 放回内包，并更新清单

重签会改变模块文件的二进制内容，因此必须重新计算 SHA-256 和大小。否则轻启会提示“内置工作模块校验失败”。

```sh
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile
from io import BytesIO
import hashlib, json

worker = Path('resign-work/worker-signed.hap').read_bytes()
with ZipFile('input.hap') as old:
    manifest_path = 'resources/rawfile/quietstart-worker.json'
    manifest = json.loads(old.read(manifest_path))
    with ZipFile(BytesIO(worker)) as inner:
        module = json.loads(inner.read('module.json'))
    assert module['app']['bundleName'] == manifest['bundleName']
    assert module['app']['versionCode'] == manifest['versionCode']
    assert module['module']['name'] == manifest['moduleName'] == 'entry_test'
    manifest.update(sha256=hashlib.sha256(worker).hexdigest(), size=len(worker))
    replacements = {
        'resources/rawfile/quietstart-worker.hap': worker,
        manifest_path: (json.dumps(manifest, indent=2) + '\n').encode(),
    }
    with ZipFile('resign-work/main-unsigned.hap', 'w') as new:
        for item in old.infolist():
            new.writestr(item, replacements.get(item.filename, old.read(item.filename)))
print('已生成 main-unsigned.hap，并更新内置模块校验清单')
PY
```

## 5. 最后签主包，并验证两层

在同一个终端中继续使用第 3 步的签名材料：

```sh
sign_hap resign-work/main-unsigned.hap resign-work/quietstart-signed.hap

"$JAVA_BIN" -jar "$SIGN_JAR" verify-app \
  -inFile resign-work/worker-signed.hap \
  -outCertChain resign-work/worker-chain.cer -outProfile resign-work/worker-profile.p7b

"$JAVA_BIN" -jar "$SIGN_JAR" verify-app \
  -inFile resign-work/quietstart-signed.hap \
  -outCertChain resign-work/main-chain.cer -outProfile resign-work/main-profile.p7b

python3 tools/verify-single-package.py resign-work/quietstart-signed.hap
```

两次 `verify-app` 必须成功，最后必须出现 `Single-package verified`。本地校验通过不代替手机的证书信任和设备授权校验。**签完外包后，不要再替换内包或编辑任何包内文件，否则外包签名失效。**

## 6. 只安装最终主包

按[侧载安装指南](INSTALL.md#2-开启开发者模式并连接电脑)开启开发者模式、USB 调试并授权电脑。先用 `hdc list targets` 确认目标设备，再安装：

```sh
HDC_BIN="$IDE_ROOT/sdk/default/openharmony/toolchains/hdc"
"$HDC_BIN" list targets
DEVICE_ID="上一步显示的目标设备ID"
"$HDC_BIN" -t "$DEVICE_ID" install -r resign-work/quietstart-signed.hap
```

**不要安装 `worker-signed.hap`。** 打开轻启，按向导开启无线调试、填写当前端口并允许“轻启本机激活”；轻启会自行安装内置模块。显示在线后拔掉 USB，再在手机重新连接一次确认。

若原来装的是另一套签名，覆盖安装可能被系统拒绝。先备份需要保留的数据；只有接受规则、配置会被删除后，才卸载旧版再安装。本流程不会自动卸载应用。之后升级也要继续使用同一套有效签名。

## 常见问题

| 现象 | 检查项 |
| --- | --- |
| 本体安装成功，但工作模块安装失败 | 是否只签了外层；内外证书、Profile 是否一致；目标设备是否获授权 |
| 内置工作模块校验失败 | 第 4 步是否使用重签后模块重新计算摘要和大小 |
| 包名或 Profile 不匹配 | 是否为当前固定包名申请了合法 Profile；不要修改包名碰运气 |
| 找不到内置模块 | 是否误用了独立测试 HAP、旧版双包或 `.app` 容器 |
| 签名工具提示密码错误 | 是否误把 DevEco 配置中的加密密码当成明文；密钥别名是否正确 |
| 无线调试没有端口或连接超时 | 确认 Wi-Fi 和系统授权，重新进入无线调试页，以当前显示的端口为准 |

## 本次实测范围

2026-09-13，在 macOS / SDK 26 上，把 0.9.42 现成发布签名 HAP 的内外包换成另一套设备授权调试签名，未编译源码。两层程序字节码保持一致；全新安装时仅有主模块、数据为空；UiTest 由轻启自行安装。后续本机会话心跳正常，独立 UiTest 点击自测 1 项通过、0 项失败，用户确认拔掉 USB 后重新本机激活仍在线。

首次工作会话曾出现 AAMS 连接超时，当时电脑也在采集 UiTest 布局，尚未确认两者因果；后续会话正常。实验中的签名密码由本机 IDE 配置读取，本教程使用官方工具的交互密码模式，不提供或公开作者的签名材料。

已验证设备为 Pura X / HarmonyOS 7；不同开发者账号、其他手机、Windows 及 AGC 分发链路尚未覆盖。这是手动重签教程，目前没有面向所有签名工具的一键重签保证。
