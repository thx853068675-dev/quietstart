# 轻启 · QuietStart

HarmonyOS 原生开屏广告辅助工具。在本机识别广告按钮、学习样式，支持确认启用、可选自动启用，以及手动示范学习。

**当前源码版本：0.9.55** · 最低要求 HarmonyOS 6.1.1（API 24）。已在 Pura 70 Pro / HarmonyOS 6.1 和 Pura X / HarmonyOS 7（API 26）验证识别与运行链路；6.1 的 30 分钟后台压力测试见[测试报告](docs/pressure-test-6.1-0.9.60.md)。

## 讨论群组
QQ群: 1125359809
<img width="280" alt="image" src="https://github.com/user-attachments/assets/06f91e87-3d29-400b-8fcf-2830af468d55" />


## 安装与使用

**只安装一个轻启主 HAP。UiTest 工作模块已内置，首次本机连接时由轻启自行安装，不需要手动导入第二个包。**

1. 在 [Release](https://github.com/thx853068675-dev/quietstart-installer/releases) 下载对应电脑的整合 ZIP，内含小白调试助手修改版和轻启 HAP。
2. 打开整合版，登录自己的华为账号、连接手机，点“选择 HAP”，再点“开始调试”。内外模块会自动一起重签、安装，不需要 DevEco、SDK、Java 或脚本。
3. 按手机向导开启无线调试、填写端口并允许授权，等待显示“在线”。
4. 正常打开其他应用，在轻启中确认并启用新规则。

已有小白轻启整合版的用户，可只下载 Release 中的独立 HAP，在助手里“更换版本”后重新签名安装；手机上再完成本机连接，工作模块会自动更新。

**整合包操作见 [开始使用](https://github.com/thx853068675-dev/quietstart-installer/blob/main/USAGE.md)**。自行编译或使用官方工具的步骤见 [侧载安装指南](docs/INSTALL.md)；已有签名材料仍可用 [重签脚本](docs/RESIGN.md)。安装后的规则管理见 [使用说明](docs/USAGE.md)。

整合版由轻启维护者修改小白源码构建，**不是小白官方版**。提供 Mac Apple 芯片和 Windows x64 包；请保留完整目录。小白官方项目与下载见 [auto-installer](https://github.com/likuai2010/auto-installer)，修改和第三方权利见 [整合说明](https://github.com/thx853068675-dev/quietstart-installer/blob/main/THIRD-PARTY.md)。

首次构建和 USB 安装需要电脑；本机激活成功后不需要电脑持续连接。调试包的签名必须授权目标设备，不能把个人调试包当作所有人通用的安装包。自动重签包已完成真机全新侧载和本机激活验证。AGC 主包能安装，但其内置工作模块安装被系统拒绝，当前 AGC 链路不可用。

## 功能

- 优先读取控件文字、描述和结构，OCR 作为本机兜底。
- 同一应用支持多种广告样式，可逐条确认或自动启用新规则。
- 按应用管理检测；强化学习保留旧规则，通过一次手动关闭追加规则。支持未见广告时自动暂停及定期复查。
- 位置示意、运行时间线、累计通知和明暗主题。

识别、规则和记录保存在本机，无云订阅。社区规则用于识别经验与回放测试，不直接执行 Android 点击脚本。识别可能遗漏或误判，测试通过数不代表广告覆盖率。

## 开发

[构建说明](docs/BUILD.md) · [架构](docs/ARCHITECTURE.md) · [测试](docs/TESTING.md) · [贡献](CONTRIBUTING.md) · [发布](docs/RELEASING.md) · [隐私与安全](SECURITY.md)

## 许可

原创代码采用 [MIT](LICENSE)，第三方内容见 [第三方声明](THIRD_PARTY_NOTICES.md)。
