# 工具包制作教程

> 核对日期：2026-10-21。基础格式支持 `schema: 1/2/3`；新增能力须核对内部构建号。最低版本声明、随机滑动间隔及整行排除的增强已实现，待正式集成，不能据此认为现有公开安装包已经支持。
>
> 本文只讲如何设计、编写、校验和分发 JSON 工具包。所有字段的类型、取值与默认行为见 [能力接口字段手册](CAPABILITY_INTERFACE.md)。

工具包是声明式 JSON：你写出适用应用、触发时机、要找的控件、要执行的动作和成功判据。轻启负责读取当前页面、核对前台应用与已确认规则、发送动作并复核结果。JSON 不能执行任意代码，也不能扩大轻启的权限。

本文只用示例应用与通用页面文案介绍配置方法，不提供具体应用的配置合集。近期变化集中在入口确认、页面就绪调度、通用交互参数和版本兼容性；字段状态见[接口手册的版本边界](CAPABILITY_INTERFACE.md#近期变化与版本边界)。

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

入口卡片与目标页恰好同名时，可再声明目标页唯一控件的 `entryAfterClickId`；不同路径进入的目标页，可用 `entryAfterClickAny` 列出额外页面文字。参数片段如下，需合并到完整的 `schema: 3` 文档：

```json
{
  "entryAfterClick": "资料中心",
  "entryAfterClickAny": ["我的资料"],
  "entryAfterClickId": "example-content-title",
  "entryClickTexts": ["打开资料", "更多资料"]
}
```

轻启会核对真实点击后的目标页标识、已声明的控件 ID 和就绪条件。先看到首页同名卡片不应开始执行。`entryAfterClickId` 只用于入口确认，不是新增的 `find.by` 识别路径。

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

每个 `steps[]` 都独立识别、动作和复核。前一步未确认成功，后一步不会执行。`defaults.totalMs` 是从第一步发出动作开始计算的整轮上限，最新实现范围为 1000–240000 毫秒，默认仍为 30000；旧版本可能只接受较小范围。

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

以「首页 → 每日记录 → 已记录 → 关闭结果页」为通用案例：入口点从实时控件边界取得；图像弹窗只在声明区域识别。普通首页不做 OCR。完整字段和组合限制见[能力接口手册第 12 节](CAPABILITY_INTERFACE.md#12-122-beta-每日签到编排)。

## 7. 校验、导入、更新

1. 保存为 UTF-8 JSON；文件可以用 `.task.json`，也可以把同样的 JSON 内容存为 `.txt`。确保没有注释、尾逗号和重复键。未知字段会使整份文档被拒。
2. 如持有轻启源码仓，运行 `node tools/task-document.cjs 文件名.task.json`。这个校验器会报告字段名、范围、动作与判据组合、子任务应用范围等问题。没有源码仓也可以在轻启的导入页得到同样的拒绝原因。
3. 在轻启「工具包 → 导入」选择 JSON 文件或粘贴全文。导入成功后核对名称、版本、启用状态和任务数量。
4. 在「应用」中启用目标应用；首次发现目标后，在「规则」页确认对应规则。导入工具包和批准规则是不同步骤。
5. 查看「运行记录」中的“发现目标、发送动作、确认生效、未确认/停止”四类结果。修改词表、页面条件或流程后递增版本，重新导入并逐项核对。
6. 分发时提供单份 JSON、适用的轻启版本、适用应用包名、触发入口和版本更新说明。不要把账号、原始页面树、录屏或个人数据写进工具包。

三种格式相同，不代表所有内部版本接受相同的新字段或数值上限。版本不足时的处理、新字段默认值与组合限制见 [能力接口字段手册](CAPABILITY_INTERFACE.md)。

## 8. 近期能力的通用案例

下面只选配置方法作说明。JSON 块均为参数片段，应合并到对应的完整文档，不能单独导入；具体应用、页面名称和入口由作者自行记录。

### 案例一：页面准备好后再交接

同一示例应用先出现提示页，关闭后进入资料页。资料页的配置可声明：

```json
{
  "priority": 600,
  "readyWhen": {
    "allText": ["资料中心"],
    "anyText": ["全部资料", "我的资料"],
    "absentText": ["正在加载"]
  }
}
```

这表示当前页面必须包含「资料中心」，还要包含两种分类文字中的至少一种，并且没有「正在加载」。前序流程仍有明确目标时按优先级处理；页面确认就绪后才允许后续配置接手，不靠猜一个固定等待时间。该条件也不抢占正在运行的多步流程。

多个浏览入口可分别声明自己的入口文字和就绪页，同时启用。当前页面必须唯一对应其中一个；访问期间保持当前配置，结束后才能切换到另一个入口。入口、就绪与步骤条件须共同满足。

### 案例二：复用浏览节奏和排除参数

在已定义的浏览面板流程中，可以只调整 `coinBrowse` 内的这些参数：

```json
{
  "browseDwellMs": 25000,
  "swipeSpeed": 300,
  "swipeSpeedRange": [200, 800],
  "swipeIntervalMs": 450,
  "swipeIntervalRangeMs": [200, 800],
  "excludeWords": ["下单", "购买", "付款", "支付", "提交订单", "确认订单", "邀请"],
  "backFrom": [0.015, 0.5],
  "backTo": [0.3, 0.5],
  "backSpeed": 2600,
  "maxBackAttempts": 3,
  "rewardUnit": "积分",
  "panelProgressText": "当前进度"
}
```

随机间隔和整行排除增强**待正式集成**。其余参数也应先核对所用构建是否支持。省略随机范围时，仍使用原固定速度或固定间隔；每次滑动的速度和等待分别取值，不会每读一次页面就重算等待。

能读到页面要求的时长就按它执行，读不到才用示例中的 25 秒兜底。完成状态或截止时间优先于下一次滑动的等待。到时返回列表后继续找其他项目，未确认完成不计入显示结果。新的整行过滤会处理同一项目里拆开的说明，正常的相邻项目仍可继续；`excludeWords` 是替换本项默认词表，写配置时保留仍需排除的词。

嵌套列表与系统打开方式选择的参数属于另一种已定义的分段流程：内层、外层滚动使用不同位置，打开方式选择可按标题识别并选一个候选项。它们不是给普通 `do.swipe` 新增的属性；参数所在对象与范围见[接口摘录](CAPABILITY_INTERFACE.md#15-通用交互参数摘录)。改变文案、等待范围或可见区域时，优先复用已有配置项。

### 案例三：发布时声明最低版本

支持最低版本检查的新本体发布后，可在最外层写：

```json
{
  "minAppVersionCode": 127080,
  "minAppVersionName": "1.2.7"
}
```

数字仅演示内部版本比较，不表示此构建已公开发布。版本不足时，新引擎会提示升级；替换或订阅更新不兼容时，原正文、更新时间和启用状态保留。旧客户端无法通过配置自行补上该提示。版本名用于展示，比较只看内部版本码；复合文档按各部分要求的最高值处理。

发布前依次检查：所需接口是否已随目标本体提供、完整文档是否可导入、入口是否真实触发、结果是否得到确认、暂停后是否仍有输入。关闭执行开关、暂停当前应用或结束会话后，浏览流程在输入前重新核对权限；配置不能绕过这些检查。
