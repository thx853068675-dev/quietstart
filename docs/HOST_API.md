# 宿主 API 手册（签名脚本工具包）

> 核对日期：2026-11-16。文档按轻启 **1.3.0 引擎线**整理；公开安装包是否包含某个方法或 feature，以实际安装包的内部版本号和更新说明为准。
>
> 本文面向要写 `schema: 5` 签名脚本工具包的作者，说明当前已注册、可调用的方法、参数和门禁。声明式 JSON 的字段见[能力接口字段手册](CAPABILITY_INTERFACE.md)，制作流程见[工具包制作教程](TOOL_PACKS.md)。
>
> 签名脚本包要求 **API 26**。宿主只提供受控原语；业务流程、任务顺序、重试、冷却和完成判定由包内脚本决定。

---

## 1. 边界原则

| 引擎保留 | 工具包提供 |
| --- | --- |
| 读取真实页面、解析目标、签发不透明引用 | 页面特征、目标词表、选择条件 |
| 核验窗口、前台、授权、几何、遮挡、可见和可输入状态 | 什么时候读、读哪一块、先做哪个任务 |
| 提交一次受控输入，写动作账本，返回回执 | 下一步做什么、失败后重试几次、等待多久 |
| 保存检查点、绝对到期事件、取消和资源上限 | 任务顺序、分支、循环、冷却、完成判定 |
| 渲染包提交的通用视图、胶囊和列表模型 | 业务字段、文案、布局、图标和状态 |
| 校验签名、发布者、能力、版本、来源和导入事务 | 订阅地址、包版本、迁移映射和发布节奏 |

- 包不能扩大引擎权限；签名声明只是申请，实际许可是“实现支持 ∩ 平台可用 ∩ profile 可用 ∩ 签名能力 ∩ 发布者授权 ∩ 当前会话条件”的交集。
- 引擎不替包决定业务；没有隐藏的专用业务 Worker 在脚本失败时接手。
- 现代 task-intent／task-actor 包缺入口、未匹配、暂停或脚本出错时，不会回退到旧原生业务流程。

---

## 2. 包形态与准入

签名包是一份 UTF-8 JSON 文本信封，不是 ZIP：

```json
{ "schema": 5, "kind": "quietstart-toolkit-text", "files": [ { "path": "manifest.json", "text": "…" } ] }
```

- 载荷文件名固定：`LICENSES.txt`、`manifest.json`、`rules.json`、`main.mjs`、`migrate.mjs`、`policy.json`，可选 `config.json`；另有 `files.json` 与 `signature.json`。
- 签名算法固定 `ECDSA-P256-SHA256`；签名覆盖 `quietstart-toolkit/v1\n` 加 `files.json` 原文，`files.json` 逐文件记录字节数和 SHA-256。
- 整份文本上限 1 MiB，`manifest.json` 上限 64 KiB；未知文件、重复字段、重复路径、文件顺序不符、摘要不符、签名不符都会整包拒绝。
- `migrate.mjs` 是必需文件；没有迁移需求时写一个返回原状态的空迁移，不要删除文件。

### 2.1 五种 profile

| profile | 是否执行 JS | 用途 | 触发 |
| --- | --- | --- | --- |
| `declarative-task/1` | 否 | schema 2／3 声明式规则 | 由原规则引擎调度 |
| `legacy-task-policy/1` | 是 | 旧策略脚本 | `page-search`、`task-completed`、`landing-recovery`、`app-launch` |
| `task-intent/1` | 是 | 事件驱动的分步任务 | `app-foreground`、`user-entry`、`entry-recovery`、`entry-touch-proof`；声明 `events.ui.v1` 后可用原生 UI 事件 |
| `task-actor/1` | 是 | 前台会话内持续观察、长驻编排 | 唯一 `app-foreground`／`start` |
| `companion/1` | 是 | 独立助手服务、双窗口、图片与网络端口 | `manual-panel` 或 `app-foreground` |

新任务包默认使用 `task-intent/1`；需要长驻看板和自有定时器时使用 `task-actor/1`；`companion/1` 是独立端口，不能把普通任务包为了网络或文件能力改声明成 companion。

### 2.2 manifest 字段

```json
{
  "schema": 5,
  "kind": "quietstart-toolkit",
  "id": "example.page-check",
  "name": "示例页面核对",
  "version": 1,
  "publisher": { "id": "example.publisher", "keyId": "example-key-1" },
  "requires": {
    "hostApi": { "major": 1, "minMinor": 0 },
    "minPlatformApi": 26,
    "features": ["task-intent.v1"]
  },
  "targets": { "bundles": ["com.example.app"], "contentScope": "app-content" },
  "entries": {
    "rules": "rules.json",
    "script": "main.mjs",
    "migrate": "migrate.mjs",
    "policy": "policy.json"
  },
  "capabilities": ["query.snapshot", "query.resolve", "input.tap", "ui.status"],
  "stateVersion": 1,
  "profile": "task-intent/1",
  "migrationFrom": "legacy-example/1",
  "minAppVersionCode": 130001,
  "limits": { "heapMiB": 8, "cpuMsPerEvent": 500, "wallMsPerEvent": 0 },
  "triggers": [
    { "id": "foreground", "type": "app-foreground", "handler": "onEvent", "event": "tick",
      "when": { "sequenceIdle": true } }
  ],
  "replaces": ["example.page-check"]
}
```

| 字段 | 约束 |
| --- | --- |
| `schema` / `kind` | 固定 `5` / `quietstart-toolkit` |
| `id` | 字母数字开头，可含 `._-`，≤64 字符；与 `rules.json` 一致 |
| `name` | 非空、≤120 字符，与规则文档一致 |
| `version` | ≥1 的整数；同内容不能覆盖同版本正文 |
| `publisher.id` / `publisher.keyId` | 与签名 `keyId` 一致；发布者身份由公钥指纹确定 |
| `requires.hostApi.major` | 必须为 `1`；`minMinor` 不能高于当前宿主 minor |
| `requires.minPlatformApi` | ≥26，且 ≤ 设备 API |
| `requires.features` | **精确集合**：由 profile、entries、config 和 feature 声明推导；多一项、少一项或顺序不同都会被拒 |
| `targets.bundles` | 1–8 个精确 bundle 名；`task-actor/1` 与 `companion/1` 必须恰好 1 个；事件包可用空数组 |
| `targets.contentScope` | 固定 `app-content` |
| `entries` | 固定文件名；声明式包可只有 `rules`，可选 `config` |
| `capabilities` | 只能取该 profile 允许的集合 |
| `stateVersion` | 固定 `1` |
| `minAppVersionCode` | 必须 ≤ 当前宿主构建号；低于 profile 下限会被拒 |
| `limits` | task-intent／legacy：8 MiB；task-actor／companion：16 MiB；稳定 task 预算为 500 ms／0 wall |
| `triggers` | 1–8 项，类型不可重复，`handler` 固定 `onEvent` |
| `replaces` | task-intent：1–64 个合法 ID（必填且非空，没有旧包时可写自己的 ID）；task-actor：只能是自己；companion／declarative：空数组 |

`requires.features` 不是自由能力清单。新增能力时，必须同时补齐 `capabilities`、对应 feature 和 `minAppVersionCode`；不要在没有 Codec 支持时手工塞入未知 feature。最稳妥的做法是从最接近的现有签名包复制 manifest，只改身份、版本、bundle、能力、触发和最低版本，再用官方校验器验证。

### 2.3 触发入口

| trigger.type | 适用 profile | 说明 |
| --- | --- | --- |
| `app-foreground` | task-intent、task-actor、companion | task-intent 可带 `sequenceIdle`；task-actor 必须 `event: "start"` 且 `when.entryActive/sequenceIdle` 都为 `true` |
| `user-entry` | task-intent | 真实用户点击入口；可配 `entry-touch-proof` 做触点后首次核对 |
| `entry-recovery` | task-intent | 入口恢复；事件名为 `entry-probe` |
| `entry-touch-proof` | task-intent | 需同时声明 `user-entry`；`when.entryActive=false`、`sequenceIdle=true` |
| `page-search`／`task-completed`／`landing-recovery`／`app-launch` | legacy-task-policy | 旧兼容入口 |
| `dialog-show`／`toast-show`／`foreground-change`／`page-change` | task-intent + `events.ui.v1` | 真实原生事件；不自动 tick、不接续 `next` |

---

## 3. task-intent/1

### 3.1 执行模型

```text
安装 → 验签/授权 → 入口触发 → onEvent(ctx, event)
  → 读页面（至多一次 snapshot）
  → 包内计算
  → 至多一次物理输入
  → 返回 waiting 或 complete
  → 宿主原子提交 checkpoint + next，输入另记宿主账本
```

- 每个事件重新加载授权、窗口和设置；脚本不能跨事件保留 Promise、定时器或内存状态。长期等待用返回 `next.at` 实现。
- 一个事件最多一次 `observe.snapshot`、一次物理输入；`actions.select` 也必须遵守同一上限。
- 输入前宿主重新核验当前窗口、前台、目标身份、几何、可见/可点击和代次；目标失效返回 `not-dispatched`，不发送输入。
- 同一幂等键只对应同一动作。已存在回执返回账本状态，不重复发送；同键不同参数拒绝。
- 未知输入会暂停任务并保留账本，不允许用新键重放；包必须通过 `actions.lookup` 或恢复事件先核对结果。
- `checkpoint`、`next` 和状态作为一组提交；已发生的设备输入独立记账。

### 3.2 入口与事件

`main.mjs` 必须导出：

```js
export async function onEvent(ctx, event) { /* 返回 RunResult */ }
```

| 事件字段 | 说明 |
| --- | --- |
| `kind` | 正常调度为 `"tick"`；只读入口核对为 `"entry-probe"` |
| `actionSequence` | 本事件的动作序号，从 0 起；用于拼幂等键 |
| `enabledTaskIds` | 当前同一个包内可执行的任务 ID 数组 |
| `uiEvent` | 声明 `events.ui.v1` 时出现；含 `kind`、`bundle`、`sourceBundle`、`windowId`、`componentId`、`componentType`、`text`、`sequence`、`at` |
| `visitOwnerSelection` | 本次事件允许同一应用内的已声明选择 |
| `visualRowSelection` | 本次事件允许视觉列表行选择 |
| `chooserArrivalOnly` / `chooserTargetArrival` | 仅做到达确认，不解锁其他输入 |

`uiEvent.kind` 只取 `dialog-show`、`toast-show`、`foreground-change`、`page-change`；事件来源文本只作提示，输入仍核验当前原生窗口、授权和包代次。

### 3.3 ctx

| 字段／方法 | 说明 |
| --- | --- |
| `ctx.run.id` | 本次持久任务的 run ID；用于幂等键前缀 |
| `ctx.run.resumed` | 是否从已提交检查点恢复 |
| `ctx.run.revision` / `ctx.run.committedAt` | 已提交检查点修订号 / 上次提交墙钟时刻 |
| `ctx.run.recoveryActionKey` | 恢复事件中指向待核对的动作键；仅恢复时出现 |
| `ctx.checkpoint` | 上次成功提交的检查点对象（不透明 JSON） |
| `ctx.config.read()` | 读取本次调用固定的用户参数快照；参数只能读，不能写 |

`ctx.checkpoint` 限制：≤64 KiB，深度 ≤16，节点 ≤4096，单层数组/对象键 ≤256；只接受 JSON 值。宿主不解释其业务含义。

### 3.4 返回值

```ts
interface RunResult {
  status: 'waiting' | 'complete';
  checkpoint: object;                 // 必填，下一事件的进度
  next?: { at: number; };             // waiting 必填，complete 不得带
  successProof?: string;              // 宿主签发的完成证明引用
  outcome?: string;                   // ≤80 字符
  message?: string;                   // ≤240 字符
}
```

- `status` 只接受 `waiting` 和 `complete`。业务失败不要返回 `paused`／`failed`；用 `waiting` 保留检查点继续核对，或抛出明确错误让宿主暂停并记录。
- `waiting` 必须带 `next.at`（绝对墙钟毫秒）；`complete` 不得带 `next`。
- `next` 还可带宿主已实现的可选等待提示：`foregroundTicket`／`foregroundUntil`／`foregroundBundle`（外部前台等待），或 `chooserTicket`／`chooserQuery`／`chooserUntil`／`chooserStableScene`（同一原生页面等待）。它们需要对应的 feature 和最低版本。
- `successProof` 只能来自同一次事件中 `observe.snapshot()` 返回的 `completionProof`。只有“`status:'complete'` ∧ 当前 owner 有效 ∧ 证明属于本宿主注册表”才记为成功；否则只是完成、不计成功。
- 伪造字符串、复制别包引用或持久化旧引用都不会被接受。

### 3.5 方法

| 方法 | 参数 | 返回 / 说明 |
| --- | --- | --- |
| `ctx.clock.now()` | 无 | 宿主墙钟毫秒 |
| `ctx.config.read()` | 无 | 参数快照；只有声明 `config.json` 的包可用 |
| `ctx.observe.snapshot(request)` | `{ fields: ['queries'], reason, queryRefs? }` | 读取一帧；每事件最多一次；`reason` 1–160 字符；`queryRefs` 1–32 个已声明普通查询 |
| `ctx.rules.resolve(queryRef, rowRef?, mode?)` | 查询 ID；可选行/访问绑定；`mode` 仅 `'arrival-only'` | 返回已声明查询结果 |
| `ctx.vision.ocr({ ruleRef })` | 已声明的 OCR 规则 | 区域 OCR；需 `query.ocr`，受 `maxOcrReads` 1–3 限制 |
| `ctx.catalog.read(request)` | 系统安装/清理声明 | 应用清单票据；需 `apps.catalog` |
| `ctx.actions.lookup({ idempotencyKey })` | 以 run ID 开头的键 | 只读动作账本，不读屏 |
| `ctx.actions.perform(action)` | 单个动作对象 | 提交一次受控输入；每事件最多一次 |
| `ctx.actions.select(request)` | 同帧选择请求 | 读一次页面 → 包内纯计算选择 → 至多一次输入 |
| `ctx.ui.publish(item)` | `state` 或 `capsule` | 状态/胶囊；每事件最多 8 项 |
| `ctx.log.write({ message })` | ≤500 字符 | 包级诊断；计入 8 项上限 |

`observe.snapshot` 返回：

```ts
interface Observation {
  ownerValid: boolean;
  queries: Record<string, QueryResult>;
  completionProof?: string;
  window?: Rect;
}
```

`QueryResult` 可能含 `matched`、`targetRef`、`ownerValid`、`text`、`lines`、`frameRef`、`rows`、`texts`、`complete`、`completeRowRefs`、`bounds`。`ownerValid=false` 或 `complete=false` 时，不能把“没看到”当成“已消失”。

`rules.match` 只作旧策略兼容，只接受 `kind: "current-task-earned"` 的规则；新包用 `observe.snapshot()` 的完成证明。

#### 动作

| `kind` | 参数 | 说明 |
| --- | --- | --- |
| `tap` | `targetRef`、`idempotencyKey`、可选 `evidenceRefs` | 普通点击；目标必须来自当前事件有效引用 |
| `tap-query` | `ruleRef`、`idempotencyKey`、可选 `expectedBounds` | 声明查询单次点击；需 `input.query-tap.v1` |
| `input-text` | `ruleRef`、`targetRef`、`idempotencyKey` | 向已声明文本目标输入；需 `input.text` |
| `relative-swipe` | `ruleRef`、`frameRef`、`from`、`to`、`speed`、`idempotencyKey` | 相对当前窗口滑动；需 `input.swipe` 和节点投影声明 |
| `swipe` | `ruleRef`、`idempotencyKey` | 声明的系统滑动；需 `system.operations` 和 `input.swipe` |
| `dismiss-keyboard` | `ruleRef`、`afterSequence`、`idempotencyKey` | 收起当前应用键盘；需 `input.keyboard-dismiss` 和对应 feature |
| `back` | `ruleRef`、`idempotencyKey` | 受控返回；需 `navigation.back` |
| `launch-owner` | `ruleRef`、`idempotencyKey` | 启动已声明的所属应用入口；需 `apps.launch-owner` |
| `uninstall-new` | `ruleRef`、`idempotencyKey` | 只清理本次安装新增且已核对的包；需 `apps.uninstall-new` 与 `apps.catalog` |

回执：

```ts
interface Receipt {
  status: 'applied' | 'already-applied' | 'unknown' | 'not-dispatched' | 'no-input' | 'failed';
  sequence?: number;
  at?: number;
  consumed: boolean;
  reason?: string;
  visitTickets?: Record<string, string>;
}
```

- `consumed=true` 表示账本已预留序号，**不等于**物理输入一定成功。
- `not-dispatched`／`consumed:false` 表示没有输入、没有账本占用；同一个键可以在重新读取页面后再次提交，但必须重新核验当前目标。
- `unknown` 表示输入可能已发出或结果不足；任务会暂停，包不能换新键重试。
- 同键同参数返回原回执；同键不同参数是冲突，不是重试。

`actions.select` 用于“读一次页面 → 包内选择 → 一次输入”。基础参数为 `queryRefs`、`input`、`idempotencyKey`；`boundRowRef`、`visit`、`visualRefs`、`visualWhen`、`visualUnless`、`targetQueryRef`、`confirmationTicket`、`visualRowSelection` 需要对应的 `input.select-*` feature。`value` 是本次选择计算出的输入值，`receipt` 与 `perform` 同语义。

### 3.6 `policy.json`

`policy.json` 是严格校验的查询程序（≤64 KiB，1–40 个查询）。顶层键：`schema`、`contentScopeRef`、`queries`、`completion`、`maxOcrReads`、`system`、`scopes`、`projectionActions`、`containers`、`pixelProgress`、`visits`、`launchConfirmations`、`systemReturns`。未知键拒绝。

查询类型包括 `text`、`exists`、`target`、`ocr-target`、`ocr-lines`、`rows`、`labels`、`bound-scope`、`nodes`、`chooser`、`container`、`pixel-progress`、`visit`、`launch-confirmation`、`system-return`。`completion` 用 `all` / `any` / `absent` / `afterAction` / `seenAfter` 描述完成证明；只有当前 owner 有效、证明来自本轮真实观测时才签发 `completionProof`。

`system` 声明受控系统操作（`back`、`swipe`、`launch-owner`、`uninstall-new`）；`visits` 声明跳转、停留、返回和奖励核对；`containers` 声明容器边界；`projectionActions` 声明节点投影上的输入。具体字段和校验以官方校验器与现有签名包为准。

---

## 4. task-actor/1

`task-actor/1` 用于需要在一次前台会话内持续观察、长驻编排的助手。它和 task-intent 共用签名、授权和资源约束，但使用独立的 transport、事件队列、状态文件和输入账本。

### 4.1 包结构

- `manifest.json`：profile 为 `task-actor/1`，恰好 1 个 bundle、1 个 `app-foreground` 触发；`event` 必须是 `start`，`when` 为 `{ "entryActive": true, "sequenceIdle": true }`。
- `policy.json`：actor 程序，声明状态文件、截图上限、输入上限和后台策略。
- `rules.json`：actor 元数据 `{ schema:1, kind:"task-actor", id, name, version, bundles, description, priority? }`，身份必须与 manifest 一致。
- `main.mjs`：导出 `export async function onEvent(ctx)`，内部用 `ctx.actor.next()`／`reply()`／`call()` 驱动。
- `config.json`：可选参数；`migrate.mjs`：必需文件。

```json
{
  "schema": 1,
  "files": [{ "id": "state", "maxBytes": 65536 }],
  "capture": { "maxRgbaBytes": 8388608, "maxHeight": 1680, "pixelOnlyMaxHeight": 840,
               "minIntervalMs": 0, "pixelOnlyMinIntervalMs": 0 },
  "input": { "region": [0, 0, 1, 1], "maxFrameAgeMs": 4000, "maxCallsPerTurn": 16,
             "maxPathPoints": 1000, "minSpeed": 200, "maxSpeed": 15000 },
  "background": { "enabled": false }
}
```

`files[].id` 只能由作者声明，宿主为每个包分配独立目录；不能写任意路径，不能读写其他包或宿主账本。`legacyName`／`legacyPackName` 只用于迁移旧数据。

### 4.2 事件与方法

```js
export async function onEvent(ctx) {
  for (;;) {
    const event = await ctx.actor.next();       // 等真实事件
    const result = await ctx.actor.call({ operation: 'clock.now', args: {} });
    await ctx.actor.reply(event.id, true, result.value);
  }
}
```

| 事件 type | payload | 说明 |
| --- | --- | --- |
| `foreground` | `{ ownerValid }` | 前台变化；`ownerValid=false` 时不得输入 |
| `screen-change` | `{}` | 屏幕可用/锁屏变化 |
| `user-takeover` | `{}` | 用户接管；宿主已暂停输入 |
| `timer`／`prepare` | `{ timerId }` | 自有绝对定时事件；`prepare` 仅用于原生 UI 准备 |
| `ui-action`／`stop`／`presentation-shown`／`settings-*`／`paused-changed` | 展示事件 | 来自包提交的视图和胶囊；必须核对 revision，旧事件不能覆盖新视图 |

| 方法 | 参数 | 返回 |
| --- | --- | --- |
| `clock.now` | 无 | `{ now }` |
| `scheduler.schedule` / `scheduler.cancel` | `{ id, at, prepareAt? }` / `{ id }` | `null`；最多 32 个定时器 |
| `state.read` / `state.write` | `{ fileId }` / `{ fileId, text }` | `{ text? }` / `null`；需 `state.read`／`state.write` |
| `settings.read` | 无 | 参数对象；需 `config.read` |
| `context.read` | 无 | `{ schema, config, presentation, foreground }`；需 `task-actor-context.v1` 及三项能力 |
| `owner.snapshot` / `owner.layout` | 无 | 窗口 / 内容布局；需 `query.snapshot` |
| `capture.read` | `{ height?, pixelsOnly? }` | 帧引用；需 `query.pixels` |
| `vision.observe` | `{ height?, pixelsOnly?, includeLayout?, ocr? }` | 观察结果；需 `task-actor-vision.v1` |
| `capture.readChunk` / `capture.ocr` / `capture.release` | 帧与分片参数 | 分片 / OCR / 释放 |
| `input.sequence` / `input.lookup` | 无 / `{ idempotencyKey }` | 序号 / 账本回执 |
| `input.tap` / `input.swipe` / `input.path` | `{ frameRef, idempotencyKey, ... }` | 输入回执；每回合受 `maxCallsPerTurn` 限制 |
| `apps.launch-owner` / `apps.restart-owner` / `apps.return-previous` / `apps.home` | 启动返回参数 | 受控所属应用导航 |
| `touch.start` / `touch.read` / `touch.stop` | 无 | 被动触点事实；需 `touch.observe` |
| `presentation.read` / `publish` / `clear` / `pause` | 展示模型 | 展示状态/视图；需 `ui.status` |
| `log.write` | `{ message }` | 包级诊断 |

观察帧有 15 秒只读租约；租约到期后引用失效。所有观察和输入都绑定当前窗口、会话、授权和帧；`ownerValid=false`、帧过期、用户接管、屏幕不可用或前台不是所属应用时，宿主拒绝返回可输入引用。未知输入暂停，不自动重放。

`presentation.publish` 接受通用视图模型，节点包括 `column`、`row`、`text`、`image`、`button`、`input`、`secret`、`choice`、`list`、`grid`、`diagram`、`annotation`；上限 2048 个节点、深度 24、序列化 ≤256 KiB。`background.enabled` 只允许所属应用离开前台后保留展示/唤回能力，不是无限后台保活。

---

## 5. 能力与版本门禁

### 5.1 profile 能力

| profile | capabilities |
| --- | --- |
| `legacy-task-policy/1` | `query.snapshot`、`query.resolve`、`input.swipe`、`input.tap`、`navigation.back`、`ui.status`、`log.write` |
| `task-intent/1` | 上述 + `navigation.system-return`、`query.pixels`、`input.text`、`input.keyboard-dismiss`、`query.ocr`、`apps.catalog`、`apps.launch-owner`、`apps.uninstall-new` |
| `task-actor/1` | `query.snapshot`、`query.pixels`、`query.ocr`、`input.tap`、`input.swipe`、`input.pointer-path`、`apps.launch-owner`、`apps.restart-owner`、`apps.return-previous`、`ui.status`、`config.read`、`state.read`、`state.write`、`touch.observe`、`log.write` |
| `companion/1` | `companion.ui`、`companion.storage`、`companion.vision`、`companion.overlay`、`companion.http`、`companion.credentials`、`companion.background` |

capability 是“申请权限”，不是“实现存在”。最终可调用集合还要过方法注册表、feature gate、发布者授权和当前会话条件。

### 5.2 常用 feature

| feature | 作用 |
| --- | --- |
| `config.v1` / `config-layout.v1` / `config.range.v1` | 参数声明 / 分组 / 双端范围 |
| `action-receipts.v1` | 动作回执查询 |
| `query.snapshot-refs.v1` / `v2` | 同帧批量读取 / 节点批读 |
| `query.nodes-observation.v1` | 只读节点投影 |
| `query.row-completeness.v1` | 按行完整性证明 |
| `input.keyboard-dismiss.v1` | 收起当前应用键盘 |
| `input.query-tap.v1` | 声明查询单次点击 |
| `input.select.v1` 及 `select-*` | 同帧选择 + 单次输入及其绑定/访问/视觉/确认变体 |
| `query.chooser-arrival.v1` / `query.chooser-target-arrival.v1` | 目标应用到达查询 |
| `task.wait-visit-foreground.v1` / `task.watch-visit-chooser.v1` | 外部前台等待 / 同窗选择窗观察 |
| `events.ui.v1` | 原生 UI 事件入口 |
| `entry.control-targets.v1` | 控件入口声明 |
| `task-actor-vision.v1` / `task-actor-context.v1` | actor 原生视觉 / 原生上下文 |
| `presentation-styles.v1` / `ui.task-capsule.v1` | 展示样式 / 执行胶囊开关 |
| `companion-settings.v1` / `companion-stable-controls.v1` | 助手配置页 / 常驻控制浮层 |

`input.select.v1` 需要 `query.snapshot-refs.v2`，capabilities 至少含 `query.snapshot` 和一种输入能力；`events.ui.v1` 需要 `query.snapshot`、`query.resolve`、`input.tap`；`task-actor-context.v1` 需要 `config.read`、`ui.status`、`query.snapshot`。完整集合和最低版本以官方校验器与安装包为准。

### 5.3 预算

| 项目 | task-intent／legacy | task-actor／companion |
| --- | --- | --- |
| JS 堆 | 8 MiB | 16 MiB |
| 单事件／回合 CPU | 500 ms（旧预算 100 ms） | 5000 ms |
| 宿主墙钟硬截止 | 0（不设） | 0（不设） |
| 单条桥接消息 | ≤256 KiB | ≤256 KiB |
| 同时活跃运行时 | 最多 2 个 | 最多 2 个 |
| 事件队列 | 64 | 64 |
| 定时器 | 用 `next.at` | 32 |
| 输入 | 每事件 ≤1 次物理输入 | 每回合 ≤`maxCallsPerTurn`（默认 16） |

超预算会终止本次回合并记录；不会把“没报错”当成功，也不会用新的动作键重放未知输入。

---

## 6. 当前不可用

以下名字即使出现在历史设计稿或兼容白名单中，也不等于当前可调用：

- `ctx.actions.recheck`、`ctx.navigation.back`、`ctx.apps.requestOpen`、`ctx.kv.get/set`、`ctx.data.enqueue`、`ctx.overlay.publish`、`ctx.vision.capture/match/sample/geometry`、`ctx.targets.fromEvidence` 等旧草案方法。
- 任意 `fetch`、任意文件路径、进程、shell、动态 import、原生模块加载、直接 Driver／Window／UiTest 调用。
- 由脚本自行声明的目标、窗口、票据、完成证明、输入回执或权限。
- 按应用名、包 ID、任务名或业务字段分支的“通用”接口；旧业务 Worker 不是新包后门。

需要新原语时，先说明缺口、通用输入输出和边界，再补通用引擎接口；不要为新应用增加包名分支或专用页面。

---

## 7. 作者验证

1. **静态校验**：用官方签名与 Codec 校验器检查签名、manifest、`policy.json`、`rules.json` 和文件摘要；校验器不执行包内 JS。
2. **注册表核对**：确认方法、profile、feature 与本文一致；未注册的方法在设备上会以“脚本没有此能力”拒绝。
3. **纯计算回放**：对作者 Kit 的决策函数固定时间、事实和回执，比较状态、意图和读取请求。
4. **真实 Codec／Store**：验签、身份、能力、授权撤销、配置、升级事务和存储长度。
5. **真实 QuickJS + Host**：跑完整 `onEvent`／actor 回合，统计宿主调用、pending、取消、unknown 和恢复；错误 provider 等阴性样本不得发输入。
6. **release／实机**：真实窗口、冷启动、后台、保数据升级和代表链。Node mock 和编译通过不算实机通过。

记录版本、源提交、包 SHA-256、实际读取/OCR/输入次数、失败阶段和恢复结果；不要把历史草案或模拟结果写成已支持 API。

---

## 8. 最小示例

以下只演示结构，不是可直接发布的完整业务包。它读取一帧、确认声明目标、点击一次，并在下一个事件用宿主完成证明结束。

`policy.json`：

```json
{
  "schema": 1,
  "queries": {
    "page": { "kind": "text", "allText": ["任务中心"] },
    "entry": { "kind": "target", "text": "领取" },
    "done": { "kind": "text", "anyText": ["已领取"] }
  },
  "completion": [{ "all": ["done"], "afterAction": "entry" }]
}
```

`main.mjs`：

```js
export async function onEvent(ctx, event) {
  if (event?.kind !== 'tick') throw Error('unexpected-event');
  const now = await ctx.clock.now();
  const frame = await ctx.observe.snapshot({ fields: ['queries'], reason: '核对任务页与领取入口' });
  if (!frame.ownerValid) {
    return { status: 'waiting', checkpoint: ctx.checkpoint ?? {}, next: { at: now + 1000 } };
  }
  if (frame.completionProof) {
    return { status: 'complete', checkpoint: { done: true }, successProof: frame.completionProof };
  }
  const entry = frame.queries?.entry;
  if (!entry?.matched) {
    return { status: 'waiting', checkpoint: ctx.checkpoint ?? {}, next: { at: now + 1000 } };
  }
  const receipt = await ctx.actions.perform({
    kind: 'tap', targetRef: entry.targetRef, idempotencyKey: ctx.run.id + '/claim'
  });
  if (receipt.status !== 'applied' && receipt.status !== 'already-applied') {
    return { status: 'waiting', checkpoint: ctx.checkpoint ?? {}, next: { at: now + 1500 } };
  }
  return { status: 'waiting', checkpoint: { clicked: true }, next: { at: now + 1000 } };
}
```

每个事件只读一次、只输入一次；点击后的结果由下一个事件重新读取，`completion` 中的 `afterAction` 只在该动作已记录后成立。

---

## 9. 相关文档

- [工具包制作教程](TOOL_PACKS.md)
- [能力接口字段手册](CAPABILITY_INTERFACE.md)
- [安装与升级说明](INSTALL.md)
- 发布、签名与订阅：以官方发布页和工具包订阅说明为准。
