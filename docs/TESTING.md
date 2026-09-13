# 测试

开源整理回归：0.9.43 离线套件共 418 项通过，包含源码导出过滤、凭据检测、安装目标选择和安装失败处理。Windows 批处理仅做静态审阅，未在 Windows 真机运行。

0.9.42 单包安装使用 local-activation、worker-installer 和 hdc-protocol 测试，覆盖安装失败不得启动、同连接收发顺序、首次安装、已有模块和损坏传输；真机范围见 [单包安装验证](single-package-0.9.42.md)。

回归工具使用 DevEco 随附的 TypeScript 转译器与 Node.js 测试运行器。需要先安装 DevEco，默认 macOS 路径可用 `DEVECO_APP` 覆盖。

```sh
python3 tools/run-tests.py
```

上面的基础回归不读取社区原始快照。完整社区回放需主动下载公开来源数据：

```sh
python3 tools/community/fetch-reviewed.py
python3 tools/run-tests.py --community
```

下载工具只接受来源清单中的 URL 和 SHA-256，不提取图片；网络失败或内容变化时停止。原始数据保存在 Git 忽略目录中，不属于项目 MIT 授权内容。不要未经审阅把真实手机全量布局、截图或社区原件提交到仓库。

0.9.40 的 348 项数字对应 worker、community-replay、community-structural 三个测试文件，并非所有测试总数。离线测试不证明真机时延、耗电或广告覆盖率；缺失 enabled、层次信息的模拟实验单独统计。

## 未报告点击能力的开屏按钮

`semantic-splash.test.cjs` 使用斗鱼真机布局的最小化样本，覆盖 `clickable=false` 的明确文字按钮、动态数字 ID、倒计时变化，以及禁用、遮挡、购买文字、候选重叠等反例。`worker.test.cjs` 验证待确认 → 启用 → 实时复核 → 点击 → 消失确认全流程。

样本 `tests/fixtures/semantic-splash-0943.json` 来自本机采集，仅保留控件类型、布局和状态，文字仅保留“跳过4”“广告”；不含截图和广告素材。新候选仍需广告或倒计时依据并由用户启用；已启用规则匹配实时语义、类型、位置及遮挡，不重复要求 OCR。此分支用于现代系统的布局快照识别路径。

0.9.43 已在 Pura X / HarmonyOS 7 上验证：仅更新主包，经轻启本机连接自行更新工作模块，斗鱼生成待确认规则；从规则页启用后重新启动斗鱼，发出点击并在两次后续快照中确认目标及广告标记消失。该次前台发现至发起点击 1299 ms，输入调用 108 ms，点击后确认 897 ms；这些是单次真机结果，不代表整体时延或所有厂商的手势控件均可点击。

## 预编译包重签

自动重签的独立离线测试（不读取真实签名材料、不连接手机）：

```sh
python3 tests/resign-hap.test.py
python3 tests/resign-xiaobai.test.py
```

真实签名与设备验证范围见[重签说明](RESIGN.md#验证范围)。
