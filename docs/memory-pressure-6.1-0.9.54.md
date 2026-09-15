# HarmonyOS 6.1：真实内存压力与系统回收验证

2026-09-16，Pura 70 Pro（HBN-AL00），OpenHarmony-6.1.1.120 / API 24，
轻启 0.9.54-test。USB 连接，轻启切回系统桌面后处于 background 调度组。
本轮没有调用结束轻启的命令、测试版故障钩子，也没有修改 OOM 分数或系统回收策略。

## 结果

**复现了系统低内存杀进程；监督进程存活，约 22 秒后自动恢复。**

| 观测 | 结果 |
| --- | --- |
| 施压方式 | 12 个系统 dd 进程各申请 512 MiB，缓冲区填入随机数据后阻塞在匿名管道 |
| 实际压力峰值 | RSS 合计约 5.96 GiB；非仅申请虚拟地址、非磁盘填充 |
| 最低采样可用内存 | 517 MiB |
| 旧工作进程 | PID 60846，后台 oom_score_adj=380 |
| 系统终止时间 | 00:24:41.137（UTC+8） |
| 系统退出原因 | reason=7，message / killReason=LowMemoryKill，系统详情包含旧 PID 和退出时间 |
| 监督进程 | PID 60921 保持不变，检测 process-exited，执行第一次自动恢复 |
| 新工作进程 | PID 3907，同一个本机连接 token；新 UiTest PID 4313 |
| 恢复就绪 | 00:25:03 监督状态 healthy，新工作心跳与 RPC 均已刷新，约 21.9 秒 |
| 人为重新连接 | 无 |
| 释放后观察 | 120 秒，工作 PID 始终 3907，RPC 距采样最多 5 秒，未再恢复重启 |
| 温度和清理 | 电池温度最高 35°C；所有压力进程退出，RSS 为 0，临时设备文件已清理 |

系统原始日志中的直接证据（仅保留轻启相关行）：

```text
1789489481.136 memmgrservice/MM: KillOneProcessByPid LowMemoryKill: pid=60846
1789489481.138 memmgrservice/MM: ExecuteKillAction LowMemoryKill:killing proc[pid=60846,uid=20020227,pname=com.tonghongxiang.quietstart, prio=380,type=3]
1789489481.298 foundation/AppMS: PROCESS_KILL, pid=60846, processName=com.tonghongxiang.quietstart, reason=LowMemoryKill, FOREGROUND=0
```

监督在压力释放前已经恢复。内存负载仍在时，系统也进行了换页，所以恢复时压力进程的 RSS
已经低于峰值；不能解读为全程维持了 5.96 GiB 常驻内存。随后主动释放全部压力并继续观察
120 秒，工作 PID 未变、监督保持正常，压力进程无残留。完整原始记录保存在本地忽略目录，
不将包含其他应用信息的系统日志提交到开源仓库。

## 观察窗口结束后的另一次异常

本轮压力测试及释放后的 120 秒观察于 00:27:26 结束。00:29:24 左右，工作进程
3907 又结束了一次；用户确认期间没有操作手机。此次不能归为上述低内存回收：

- 工作状态先写入 `sessionState=error`、`operation=ended`，`sessionError=undefined`。
- 系统记录仅给出 `reason=2`，没有有效的旧 PID、退出时间和具体消息，不能据此判为
  用户清理，也不能证明又发生了 `LowMemoryKill`。
- 原监督进程 60921 保持存活，00:29:33 开始第二次恢复，00:30:01 恢复为
  `healthy`；新工作 PID 16525、UiTest PID 16612，连接 token 未变，无人工重新激活。
- 截至 00:36 左右的再次读取，新工作心跳和 RPC 正常，监督仍为第二次恢复后的
  `healthy`。这是一次额外的短时观测，不是长时间稳定性结论。

已确认诊断存在信息保留缺口：`reportError()` 将不存在的错误码转为字符串
`undefined`；具体消息只写入当前工作日志和当前状态中的历史记录，`SystemExitStore`
只保存 `errorCode`。重启后的新状态替换旧历史，且旧 PID 的 hilog 已无法读取，
因此本次具体异常内容未能追回。后续需持久化终止时的异常消息及发生阶段，才能继续
定位这类会话自行结束的问题。此轮未改动应用代码来猜测修复。

结论应分别表述为：**真实低内存回收后的恢复通过；随后另一次工作会话错误也恢复了，
但其根因尚未确定，不能认定后台长期稳定性问题已经全部解决。**

## 可复测方法

先在手机正常连接轻启，确认在线，再执行：

```sh
python3 scripts/pressure/run-memory-pressure.py \
  --serial 手机序列号 \
  --max-mib 6144 \
  --out /绝对路径/本轮结果目录
```

脚本会传入独立的 shell 压力工具，不改动或重新安装轻启。以 512 MiB 为一档逐步增加负载，
持续监控内存、温度、工作进程、监督进程、OOM 优先级、心跳与 RPC。进程变化后不再增加
压力。施压最长约 230 秒，释放后观察 120 秒；单个压力槽在手机端有 300 秒超时，USB
断开也会结束。温度达到 43°C 或可用内存低于 384 MiB 时提前释放；分配新槽之前另留余量。
读取系统退出记录和日志，不清除系统日志、不伪造退出原因。

压力工具继承调试 shell 的 OOM 优先级，与普通第三方前台应用不同；这是一项真实的合成
内存负载实验。观察到监督进程 oom_score_adj=-1000，但这并不是对所有系统回收策略的豁免。
Linux 内核对该字段的定义见[官方文档](https://github.com/torvalds/linux/blob/master/include/uapi/linux/oom.h)。

本轮只证明此设备、此版本的低内存回收场景可以自恢复，不能代替断开 USB、锁屏长时间
待机、CPU/温控回收或系统同时结束监督进程的验证。
