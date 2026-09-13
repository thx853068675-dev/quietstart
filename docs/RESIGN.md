# 一键重签已有 HAP

用 [resign-hap.py](../tools/resign-hap.py) 自动处理内外两个包。无需编译源码，也不用手动解压、算摘要或回填文件；最终仍只安装一个主 HAP。

## 第一次使用

准备以下材料，放在自己的电脑上：

- 完整的轻启主 HAP，包含内置 UiTest 工作模块。
- 自己的调试证书 `.cer`、设备授权 Profile `.p7b`、密钥库 `.p12` / `.jks`。
- 密钥别名，以及密钥密码和密钥库密码。
- 官方 DevEco Studio / HarmonyOS SDK、Python 3。

Profile 必须有效、授权自己的手机，且与当前包名 `com.tonghongxiang.quietstart` 匹配。证书与密钥也必须匹配。材料申请参见[华为调试 Profile 说明](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)和[自动签名说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-signing-auto)。

**不要改包名解决授权问题。** 轻启目前使用固定包名；其他开发者账号能否申请合适的 Profile，需在该账号实际确认，本次尚未验证跨账号申请。不要把私钥或密码发给作者。

下载仓库后，在项目根目录运行：

```sh
python3 tools/resign-hap.py
```

也可以只下载这个 Python 脚本，在它所在目录执行 `python3 resign-hap.py`，不需要其他项目文件。

按照提示填写主 HAP、输出文件、证书、Profile、密钥库的路径和别名。macOS 默认安装位置的 DevEco 工具会自动找到；找不到时会询问 Java 和 `hap-sign-tool.jar` 的路径。文件路径可以带空格。

接着按官方工具的提示输入密码：先询问密钥密码 `KeyPwd`、再询问密钥库密码 `KeystorePwd`；内包、外包各一次，共四次提示。若两种密码相同，分别输入同一密码。工具提示的输入时限为 30 秒。

脚本不会读取或保存密码，也不会把密码放进命令参数。DevEco 配置中的加密密码不能当作明文输入。如果不知道自动生成密钥的密码，可以继续使用 IDE 的[源码签名构建流程](INSTALL.md#3-从源码生成自己的安装包)。

## 已经配置过，只换一个 HAP

可把工具和材料路径写入本地 JSON，避免每次重复填写。推荐放在 Git 已忽略的 `resign-work/signing.json` 中。下面是模板，所有“你的…”值需要替换，Windows 路径建议使用 `/` 分隔：

```json
{
  "java": "/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java",
  "sign_tool": "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar",
  "certificate": "/你的签名目录/debug.cer",
  "profile": "/你的签名目录/debug.p7b",
  "keystore": "/你的签名目录/debug.p12",
  "key_alias": "你的密钥别名",
  "algorithm": "SHA256withECDSA"
}
```

随后只需一条命令：

```sh
python3 tools/resign-hap.py --input input.hap --output resign-work/quietstart-signed.hap --config resign-work/signing.json
```

每次使用新的输出文件名；脚本不会覆盖原包或已有输出。JSON 不支持密码字段。默认算法适用于本次的 EC 密钥，其他密钥须在配置中选用匹配算法。

## 自动执行了什么

1. 校验原主包与内置模块的签名、包名、版本和摘要。
2. 用你的签名材料重签内置 UiTest 模块。
3. 更新模块的 SHA-256 和文件大小，放回主包。
4. 用同一套材料重签主包。
5. 验证最终签名、内外一致性和程序内容，再输出最终 HAP。

任何一步失败都会停止，临时文件自动清理，不交付未验证的包。原始程序内容保持不变，主包内部只替换工作模块和校验清单。脚本不连接手机、不自动安装或卸载应用、不申请证书、不下载 SDK。

## 安装

看到“完成，只需侧载此主 HAP”后，使用输出路径对应的文件，按[侧载安装指南](INSTALL.md#2-开启开发者模式并连接电脑)开启开发者模式并通过 hdc 安装。

只安装最终主 HAP；首次本机连接时，轻启自行安装内置 UiTest。在线后拔掉 USB，再在手机重新连接一次确认。

若旧版使用不同签名，系统可能拒绝覆盖安装。先备份数据；接受旧规则和配置会被删除后，才卸载旧版再装。脚本不会代你执行卸载。之后升级也需继续使用同一套有效签名。

## 遇到问题

| 提示或现象 | 处理 |
| --- | --- |
| 请在本机交互终端运行 | 打开系统终端运行；不要重定向标准输入，官方工具需要读取密码 |
| 文件不存在 | 检查证书、Profile、密钥库、SDK 路径；配置文件中的路径不自动展开 Shell 环境变量 |
| 密码错误 / 输入超时 | 核对密钥别名和密码，重新运行；不要输入 DevEco 配置里的加密值 |
| 输出已存在 | 选择另一个输出文件名 |
| 包名、模块或摘要错误 | 使用完整的轻启单包，不能使用独立测试 HAP、旧双包或 AGC `.app` 容器 |
| 本体或模块安装失败 | 核对手机是否获 Profile 授权、证书有效性、已有应用签名是否一致；本地校验不代替手机的授权校验 |
| 无线调试没有端口 / 连接超时 | 检查 Wi-Fi 和系统授权，以无线调试页当前显示的端口为准 |

## 验证范围

2026-09-13，使用当前 `tools/resign-hap.py` 在 macOS Apple Silicon / DevEco Studio 26 / SDK 26 上重新签名真实 0.9.42 HAP，四次官方密码交互和内外签名校验均通过。随后安装的就是这次脚本输出文件，未重新编译或替换成其他构建产物。

| 步骤 | 实测结果 |
| --- | --- |
| 安装前清理 | 旧包不存在，应用数据目录不存在，清理轻启临时文件 |
| 只安装脚本输出的主 HAP | 成功；首次启动前仅有 `entry` 模块，files 目录为空 |
| 手机自行安装 UiTest | 成功；出现 `entry_test`（94200），安装回执与脚本产物中的工作模块摘要一致 |
| 首次本机启动 | 成功；新会话初始化完成，持续更新心跳，无接口错误 |
| 独立 UiTest 点击测试 | 1 项通过、0 项失败；点击轻启自身按钮并观察成功标记，3366 ms |
| 拔 USB 后重新本机激活 | 用户确认“在线”；当时电脑已无法连接手机，未直接采集脱机后的日志 |

独立点击测试由电脑 `aa test` 发起，使用的是手机自行安装的工作模块；它与脱机激活的用户确认是两项不同证据。用户未明确报告本轮拔线后的真实广告跳过结果，不将其计为已验证。测试设备为 Pura X / HarmonyOS 7。

该次安装包 SHA-256：`212825e8bf0cf94ea2ec2a4fae62591a1737554ff1abade44827549a6382a4a9`。

早前手动重签实验首次会话曾出现 AAMS 超时，当时电脑也在执行 UiTest 布局采集，未确认因果；本次自动脚本产物的首个会话正常。脚本有 7 项独立离线测试，覆盖失败不交付、拒绝覆盖、程序内容保持一致和损坏输入拒绝。第二个开发者账号、其他设备和 Windows 尚未实测。

**AGC 路线是另一种安装方式，目前失败。** 0.9.42 经 AGC 安装主包后，自行安装发布签名工作模块时，手机返回 `9568322 / signature verification failed due to not trusted app source`。主包显示应用市场来源；存档上传包中的内置模块证书与已安装主包相同，签名校验有效，但发布签名的调试侧载受到系统来源限制。参见[华为发布证书说明](https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-package-structure-65)。本重签脚本的成功不代表 AGC 链路已打通。

官方签名参数见[工具说明](https://github.com/openharmony/developtools_hapsigner/blob/master/README.md)。
