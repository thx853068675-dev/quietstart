## 下载一个整合包即可

| 你的电脑 | 下载文件 |
| --- | --- |
| Mac（Apple 芯片） | `quietstart-0.9.43-macOS-arm64-bundle.zip` |
| Windows（x64） | `quietstart-0.9.43-Windows-x64-bundle.zip` |

**每个 ZIP 都包含修改后的小白调试助手、轻启 HAP 和使用说明。无需另外下载助手、DevEco Studio、HarmonyOS SDK、Java、Python 或重签脚本。** `SHA256SUMS.txt` 仅用于核对下载完整性。

## 使用步骤

1. 完整解压，打开包内“小白调试助手 · 轻启整合版”。Windows 请保留 EXE 旁的 DLL 和 data 目录。
2. 手机开启开发者模式和 USB 调试，连接电脑并允许调试。
3. 在助手中登录自己的华为账号、连接手机，点 **“选择 HAP”**，选择包内或自行准备的轻启主 HAP；核对显示的版本和文件名，再点 **“开始调试”**。
4. 等待申请设备授权、重签工作模块、重签主包及安装完成。两层使用同一套签名材料，不用手动找第二个包。
5. 手机打开轻启，按向导开启无线调试，填写当前端口并允许连接；轻启自行准备工作模块，显示“在线”后即可脱离电脑运行。

Mac 修改版未做 Apple 公证；确认来源后按系统“隐私与安全性”的提示打开。不要关闭系统整体安全保护。Intel Mac、Windows ARM 未在此次包的支持范围内。

[完整安装说明](https://github.com/thx853068675-dev/quietstart/blob/main/integrations/xiaobai/USAGE.md) · [轻启使用说明](https://github.com/thx853068675-dev/quietstart/blob/main/docs/USAGE.md)

## 本次改动与验证

- 直接修改小白源码，在原签名流程中加入内外模块自动重签和手动选择轻启版本入口。
- 检查模块摘要、版本、程序内容、Profile 一致性；失败时停止安装，避免只签主包就显示成功。
- 使用包内签名器独立缓存，不依赖用户电脑上旧的小白工具文件。
- Mac、Windows 均从源码编译并生成整合包，签名编排测试包含真实 HAP 回放。
- 此前 Mac 整合版已实际完成“请求签名 → 签名应用 → 安装应用”；Pura X / HarmonyOS 7 已确认工作模块自安装后在线。
- 包内原生签名器生成的内外 HAP 已通过官方工具独立验签。该工具仅用于开发验证，用户使用整合包时不需要它。
- Windows 已完成编译和自动测试，尚未完成 Windows 电脑连接手机的端到端实测。其他华为账号的 Profile 申请仍需实际验证。

轻启应用版本仍为 0.9.43；本次更新重点是安装工具。调试授权必须覆盖使用者自己的手机，签名过期后重新执行完整流程。AGC 工作模块安装问题不因本次整合而自动解决。

## 上游与授权

这是**轻启维护者修改版，不是小白官方发布版**。小白作者为 likuai2010，源码基线 `24388dd86e6c3c7cab83fc27d3e6f4f9cb1b7801`。发布者已确认取得修改与再分发授权，第三方原代码和工具不自动适用轻启的 MIT 许可。

[小白官方源码](https://github.com/likuai2010/auto-installer/tree/flutter) · [小白官方最新版本](https://github.com/likuai2010/auto-installer/releases/latest) · [修改与第三方说明](https://github.com/thx853068675-dev/quietstart/blob/main/integrations/xiaobai/THIRD-PARTY.md)
