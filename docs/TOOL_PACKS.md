# 工具包制作教程

> 适用范围：本文按轻启 1.2.2-beta（120373）核对。正式版 1.2.0 支持 `schema: 1/2`；合成包 `schema: 3`、入口门控及扩展流程字段需要对应的 1.2.2-beta 预览版。导入前先看轻启首页的版本码。
>
> 本文只讲如何设计、编写、校验和分发 JSON 工具包。所有字段的类型、取值与默认行为见 [能力接口字段手册](CAPABILITY_INTERFACE.md)。

工具包是声明式 JSON：你写出适用应用、触发时机、要找的控件、要执行的动作和成功判据。轻启负责读取当前页面、核对前台应用与已确认规则、发送动作并复核结果。JSON 不能执行任意代码，也不能扩大轻启的权限。

## 1. 先确定一份包要解决什么

写配置前，用普通语言列出四件事：

1. **入口**：用户进入哪个应用、哪个页面？仅打开应用就运行，还是要用户主动点击某个入口？
2. **任务卡片**：同一页是否有多个同名按钮？如果有，记下卡片标题和按钮文字。
3. **流程**：每次点击后页面会出现什么？完成提示、关闭按钮和可选弹窗是否都存在？哪些步骤可能因页面差异而不出现？
4. **结束**：怎样知道这一项已完成？怎样知道应停止重复？完成一项后怎样处理下一项？

先做单步包，确认目标范围和结果判据，再扩成多步。需要一个开关管理多个独立任务时，使用 `schema: 3` 合成包；每个 `tasks[]` 子任务仍是一份完整的 `schema: 2` 文档。

## 2. 写出第一份可导入的单步包

把下例保存为 UTF-8 编码的 `my-confirm.task.json`。把 `com.example.app` 换成真实包名，`提示标题`、`我知道了` 换成实际页面文字。

```json
{
  "schema": 2,
  "id": "example.confirm-dialog",
  "name": "确认提示框",
  "version": 1,
  "appliesTo": ["com.example.app"],
  "when": { "trigger": "app-foreground", "windowMs": 12000 },
  "defaults": {
    "limit": { "maxWidth": 0.5, "maxHeight": 0.16, "maxArea": 0.06 }
  },
  "steps": [
    {
      "find": {
        "by": "text",
        "match": ["我知道了"],
        "sameParentText": ["提示标题"]
      },
      "do": { "capability": "click" },
      "expect": { "result": "gone", "settleMs": 5000, "samples": 2 }
    }
  ]
}
```

这份包的含义：

- `appliesTo` 限定应用。它和轻启里对该应用的启用开关同时生效。
- `when.windowMs` 从应用进入前台开始计时；12 秒内才观察这个目标。
- `find.sameParentText` 要求“我知道了”与“提示标题”是同一父容器的直接子节点，防止点到别的卡片上的同名按钮。页面结构不满足时，删去这一项或改用实际的同级标题。
- `defaults.limit` 限制目标尺寸占窗口的比例。实际按钮太大时应先核对控件范围，再调整到允许范围。
- `expect` 要求点击后目标连续两次从新读取的页面里消失。点击已发出与结果已确认是两件事。

`id` 是稳定身份，后续更新保持不变；`version` 每次发布新内容时递增。同一 `id` 再次导入会更新该包。

## 3. 根据页面选择触发方式

| 场景 | 写法 | 执行范围 |
|---|---|---|
| 只在打开应用后的短时间看 | `{"trigger":"app-foreground","windowMs":12000}` | 观察 1–30 秒 |
| 只在指定页面看 | `{"trigger":"page-foreground","pagePath":["TargetPage"],"windowMs":6000}` | 前台进入后，还要命中页面路径 |
| 每次进入新页面再看 | `{"trigger":"page-visit","windowMs":6000}` | 每页重新计时；读不到页面路径则不执行 |
| 任务出现时间不确定 | `{"trigger":"app-foreground","lifetime":"foreground"}` | 保持前台期间观察；单步发出动作后停止 |

`lifetime` 与 `windowMs` 只能选一个。多步任务即使使用前台常驻，仍受 `defaults.totalMs` 的整轮上限约束。

只想让用户**主动点击进入任务页**后运行时，用 `schema: 3` 的 `entryAfterClick`。它在入口前监听点击；首次读取用于判断页面标识是否原本就存在，之后不持续导出整页。一次点击最多触发有限次新页面读取，只有声明的页面标识从未出现变为出现才激活。新用户先到过渡页时，可由用户继续进入目标页；老用户可直接进入目标页。不要把“打开应用”误当作用户进入目标任务页。

如果用户可能在同一次应用前台会话里离开任务页、再点入口进入，给合成包添加 `entryClickTexts: ["任务入口", "查看更多任务"]`，写实际入口控件的文字。再次运行时轻启要求这些入口出现真实点击，且声明的目标页标识已可见；页面里的其他点击不会重新启动。首次进入仍受 `entryAfterClick` 的页面变化约束。

流程如果由固定入口直接启动，可以在合成包最外层改用 `entryOnTap: ["开始任务", "继续任务"]`。它与 `entryAfterClick` 必须二选一；入口前只监听用户点击，未启动的流程不会持续读取页面。使用 `rewardVideo` 扩展时需要配 `entryOnTap`，字段见[能力接口手册第 11 节](CAPABILITY_INTERFACE.md#11-121-beta-扩展流程字段)。

## 4. 写准目标、依据和反例

| 需求 | 字段 | 写法要点 |
|---|---|---|
| 识别目标文字 | `find.match` | 列出目标控件允许的写法；不要把整页说明文字当目标 |
| 识别描述 | `find.by` | `"desc"` 或 `["text","desc"]` |
| 同名按钮分卡片 | `find.sameParentText` | 填卡片标题，要求目标与标题为直接兄弟节点 |
| 识别时有页面依据 | `need.evidence` | 只帮助发现规则，不能替代每次动作前的页面条件 |
| 每次动作前要求文字 | `need.visibleText` | 当前可见页至少出现列表中一项 |
| 弹窗在场时不点底层 | `need.absentText` | 当前可见页不得出现列表中的任何一项 |
| 排除危险语境 | `deny.context` | 与轻启内置排除表取并集，只能收紧 |
| 控件没有文字 | `find.idHints` / 图像或结构路径 | 需要真实控件依据；不要凭页面截图猜一个文字 |

`find.by: "id"` 目前未接入，写入会被拒绝。`image` 和 `structure` 是现有识别路径，但必须提供它们要求的完整字段与页面依据；先从 [字段手册](CAPABILITY_INTERFACE.md#5-find目标识别) 核对，再使用。

## 5. 多步、可选步骤与重复任务

每个 `steps[]` 都独立识别、动作和复核。前一步未确认成功，后一步不会执行。`defaults.totalMs` 是从第一步发出动作开始计算的整轮上限，范围 1000–120000 毫秒。

例如“点任务 → 关闭结果页 → 有弹窗则确认”：

```json
{
  "schema": 2,
  "id": "example.reward-flow",
  "name": "奖励流程",
  "version": 1,
  "appliesTo": ["com.example.app"],
  "when": { "trigger": "app-foreground", "lifetime": "foreground" },
  "defaults": {
    "totalMs": 60000,
    "limit": { "maxWidth": 0.5, "maxHeight": 0.16, "maxArea": 0.06 }
  },
  "repeat": {
    "maxCycles": 5,
    "cooldownMs": 500,
    "idleMs": 5000,
    "stopWhen": { "text": "已领取", "nearText": "每日奖励" }
  },
  "steps": [
    {
      "find": { "match": ["去完成"], "sameParentText": ["每日奖励"] },
      "need": { "visibleText": ["任务中心"], "absentText": ["恭喜获得"] },
      "do": { "capability": "click" },
      "expect": { "result": "gone" }
    },
    {
      "find": { "match": ["关闭"] },
      "need": { "visibleText": ["恭喜获得奖励"] },
      "do": { "capability": "click" },
      "expect": { "result": "gone" }
    },
    {
      "find": { "match": ["知道了"] },
      "need": { "visibleText": ["恭喜获得"] },
      "skipWhen": {
        "visibleText": ["任务中心"],
        "absentText": ["恭喜获得"],
        "stopRepeat": true
      },
      "do": { "capability": "click" },
      "expect": { "result": "gone" }
    }
  ]
}
```

这里有两个不同的停止条件：

- `repeat.stopWhen` 在下一轮查看**当前卡片**。只有任务标题和“已领取”是同一父容器的直接子节点，才立即转向其他任务；别的卡片已领取不会误伤。状态不明时，最多观察 `idleMs`，之后停止重复。
- `steps[].skipWhen` 只用于后续步骤。若确认弹窗没有出现，并且连续两次新页面都显示“任务中心”而不显示“恭喜获得”，跳过该步骤；`stopRepeat: true` 同时停止这个任务的重复，避免无结果时继续重试。若弹窗出现，仍按该步的 `find`、`do`、`expect` 完成点击与复核。

这些是通用的编排字段；示例文字只用于演示，发布前必须换成目标应用的实际文案。

等待类页面应以**实际可见的完成状态和关闭控件**作为下一步条件。不要从上一步点击时间自行推算页面完成时刻后盲点；`expect.settleMs` 是点击后的复核期限，不是页面等待时间。

## 6. 合成一个可分发的多任务工具包

`schema: 3` 用一个 `id`、一个版本号和一个开关管理 1–8 份 `schema: 2` 子任务。最小结构如下；每个 `tasks[]` 都要有完整的 `when`、`steps` 和独立 `id`，并且 `appliesTo` 必须与外层逐项一致。

```json
{
  "schema": 3,
  "id": "example.daily-suite",
  "name": "每日任务工具包",
  "version": 1,
  "appliesTo": ["com.example.app"],
  "entryAfterClick": "任务中心",
  "tasks": [
    {
      "schema": 2,
      "id": "example.daily-check",
      "name": "每日签到",
      "version": 1,
      "priority": 200,
      "appliesTo": ["com.example.app"],
      "when": { "trigger": "app-foreground", "lifetime": "foreground" },
      "defaults": {
        "limit": { "maxWidth": 0.5, "maxHeight": 0.16, "maxArea": 0.06 }
      },
      "steps": [
        {
          "find": { "match": ["签到"], "sameParentText": ["每日签到"] },
          "need": { "visibleText": ["任务中心"] },
          "do": { "capability": "click" },
          "expect": { "result": "gone" }
        }
      ]
    },
    {
      "schema": 2,
      "id": "example.daily-bonus",
      "name": "领取奖励",
      "version": 1,
      "priority": 210,
      "appliesTo": ["com.example.app"],
      "when": { "trigger": "app-foreground", "lifetime": "foreground" },
      "defaults": {
        "limit": { "maxWidth": 0.5, "maxHeight": 0.16, "maxArea": 0.06 }
      },
      "steps": [
        {
          "find": { "match": ["领取"], "sameParentText": ["每日奖励"] },
          "need": { "visibleText": ["任务中心"] },
          "do": { "capability": "click" },
          "expect": { "result": "gone" }
        }
      ]
    }
  ]
}
```

先给每个子任务分配不同的卡片标题、目标词和优先级。数字小的优先；一个任务执行完仍需在当前页核对下一项。入口字段写在最外层，不能在子任务里重复声明。需要下滑时，用 `need.absentOnScreenText` 确认下方标题尚在屏幕外，滑后用 `expect: {"result":"appeared","match":["下方标题"],"onScreen":true}` 核对它进入屏幕。分发时只需这一份合成 JSON；接收者看到的是一个工具包开关，内部子任务仍独立匹配和复核。

可在最外层加 `"usage": "用户从哪里点击进入，轻启将自动完成什么"`。内容须为 1–400 字符的非空文字；导入成功后会弹出一次说明，工具包详情里也能再次查看。没有 `usage` 就不会弹窗。它不改变运行规则。若流程明确要求打开详情页、停留并返回，可声明 `landingVisit`；提示未出现时不触发访问动作。全部字段和范围见[能力接口手册第 11 节](CAPABILITY_INTERFACE.md#11-121-beta-扩展流程字段)。

### 每天首次打开即签到

若任务要求每天首次打开应用时自动签到，用 `schema: 3` 的 `entryOnForeground: true` 与 `oncePerDay: true`。在 `dailyCheckIn` 中声明首页文字、签到入口相对区域、领取按钮、结果文字、结果弹窗关闭区域，以及已知遮挡弹窗的关闭方式；`tasks` 写空数组。轻启先处理遮挡，再签到领取，完整关闭并回到首页后才记为当天完成。当天再次打开时不会继续扫描该包；次日恢复。

可下载并参考 [酷狗概念版每日签到 V1](https://github.com/thx853068675-dev/quietstart/releases/download/v1.2.2-beta-120373/kugou-concept-daily-checkin-V1.txt)。入口点从实时控件边界取得；图像弹窗只在声明区域识别。普通首页不做 OCR。完整字段和组合限制见[能力接口手册第 12 节](CAPABILITY_INTERFACE.md#12-122-beta-每日签到编排)。

## 7. 校验、导入、更新

1. 保存为 UTF-8 JSON；文件可以用 `.task.json`，也可以把同样的 JSON 内容存为 `.txt`。确保没有注释、尾逗号和重复键。未知字段会使整份文档被拒。
2. 如持有轻启源码仓，运行 `node tools/task-document.cjs 文件名.task.json`。这个校验器会报告字段名、范围、动作与判据组合、子任务应用范围等问题。没有源码仓也可以在轻启的导入页得到同样的拒绝原因。
3. 在轻启「工具包 → 导入」选择 JSON 文件或粘贴全文。导入成功后核对名称、版本、启用状态和任务数量。
4. 在「应用」中启用目标应用；首次发现目标后，在「规则」页确认对应规则。导入工具包和批准规则是不同步骤。
5. 查看「运行记录」中的“发现目标、发送动作、确认生效、未确认/停止”四类结果。修改词表、页面条件或流程后递增版本，重新导入并逐项核对。
6. 分发时提供单份 JSON、适用的轻启版本、适用应用包名、触发入口和版本更新说明。不要把账号、原始页面树、录屏或个人数据写进工具包。

`schema: 2` 的基础单任务包可在正式版 1.2.0 使用；本文展示的 `schema: 3` 与新增流程字段要求支持它们的 1.2.2-beta。具体字段表与兼容限制见 [能力接口字段手册](CAPABILITY_INTERFACE.md)。
