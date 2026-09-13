# 构建说明

用户从零侧载请按 [安装指南](INSTALL.md) 操作。本文仅说明构建入口。

已有完整主 HAP、希望不编译源码直接换签名，请看[内外包重签教程](RESIGN.md)。

## 环境与签名

维护环境为 macOS Apple Silicon、DevEco Studio 26.0.0、HarmonyOS SDK 26。先创建本机 `build-profile.json5`，在 IDE 同步依赖并为目标手机配置自己的调试签名。首次步骤见 [安装指南第 3 节](INSTALL.md#3-从源码生成自己的安装包)。

主包和内置工作模块必须使用同一签名配置。构建期间不要切换 Profile，也不要并行构建同一输出目录。签名材料不得提交。

## 构建入口

```sh
# 一次构建工作模块和主包，并校验内置模块
bash scripts/build.sh

# 将最新的、适用于目标设备的主 HAP 打成安装 ZIP
bash scripts/build-delivery-package.sh mac
bash scripts/build-delivery-package.sh win

# 配置合法发布签名后，生成 AGC 标准 APP 容器
bash scripts/build-app.sh
```

- 侧载 HAP：`entry/build/default/outputs/default/entry-default-signed.hap`
- 安装 ZIP：`dist/qingqi-delivery-mac.zip` / `dist/qingqi-delivery-win.zip`
- AGC APP：`build/outputs/default/harmony-ad-skip-default-signed.app`

`build.sh` 先清除旧的内嵌资源，再构建 `entry_test`，校验并嵌入主包，最后构建主 HAP。`verify-single-package.py` 检查包名、版本、大小和摘要；它不验证目标设备授权或代替系统签名校验。源码不包含已签名模块，必须构建生成。

`build-test.sh` 仅用于工作模块开发，不是用户的第二个安装步骤。`activate.sh` 是开发调试工具，依赖已安装模块，不用于证明手机首次自安装。

脚本默认 DevEco 位于 `/Applications/DevEco-Studio.app`，可通过 `DEVECO_APP` 修改。Windows 的接收者可安装已签名交付包；本仓库尚无经过验证的 Windows 自动构建脚本。

## 发布包与侧载包

`build-app.sh` 不会上传或提交审核，也不会自动将调试签名改为发布签名。AGC `.app` 和设备调试 HAP 应分开管理；构建发布包后，如需侧载交付包，请先恢复调试签名并重新运行 `build.sh`，避免误打包上一次的发布产物。

AGC 上传解析成功不等于邀请分发后的本机工作模块安装已验证。当前验证范围见 [测试说明](TESTING.md)。
