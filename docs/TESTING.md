# 测试

开源整理回归：当前离线套件共 400 项通过，包含源码导出过滤、凭据检测、安装目标选择和安装失败处理。Windows 批处理仅做静态审阅，未在 Windows 真机运行。

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

## 预编译包重签

自动重签的独立离线测试（不读取真实签名材料、不连接手机）：

```sh
python3 tests/resign-hap.test.py
```

真实签名与设备验证范围见[重签说明](RESIGN.md#验证范围)。
