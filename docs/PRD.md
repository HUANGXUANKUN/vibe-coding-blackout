# Blackout — 产品需求文档 (PRD)

> 一键让所有屏幕彻底变黑，Mac 继续跑。再一键恢复。
>
> 版本：v1.0 · 平台：macOS 13+ (Apple Silicon & Intel) · 形态：菜单栏常驻小工具

---

## 1. 背景与真实场景

用户在开放式办公位上让 AI Agent 长时间自主运行（终端里跑任务、跑构建、跑爬取）。此时：

- **不能锁屏** —— 锁屏在部分场景会挂起交互、断开某些会话、并且解锁成本高；用户要的是「机器继续干活」。
- **不能被别人看见** —— 屏幕上是代码、内部文档、聊天记录。有人经过工位就能一眼扫到 3 块大屏。
- **需要瞬时、单手、不看屏幕就能完成** —— 有人走近时反应窗口只有一两秒，不可能去点菜单栏。

现有方案都不合格：

| 方案 | 为什么不行 |
| --- | --- |
| 锁屏 (⌃⌘Q) | 会中断部分工作流；解锁要输密码/Touch ID；用户明确排除 |
| 屏保 | 同样接管输入；且不保证多屏同步；唤醒即泄露 |
| 手动调亮度 | 3 块屏要调 3 次；外接屏亮度键不生效；最低亮度仍然看得清 |
| 关显示器电源 | 物理按钮，3 台来不及；且不省事 |
| `pmset displaysleepnow` | 任何鼠标微动就唤醒并立刻暴露桌面 |

**核心洞察：用户要的不是「调暗」，是「屏幕在视觉上等于关机，但机器没有停」。**

## 2. 目标 / 非目标

### 目标 (v1.0)

1. **G1** 一个可单手完成、无需看屏幕的手势 → 全部显示器瞬间变成纯黑，不泄露任何像素。
2. **G2** 同一手势 → 完全恢复到操作前的状态（含每块屏各自原本的亮度）。
3. **G3** 期间前台 App 不失焦、不被打断，Agent 继续跑。
4. **G4** 期间路人无法用键鼠操作这台 Mac。
5. **G5** 任何情况下用户都能出来（≥3 条独立退出路径），绝不出现「被自己锁在黑屏里」。
6. **G6** 零配置可用；默认值就是正确答案。

### 非目标 (v1.0)

- 不做 DDC/CI 硬件调光外接显示器（见 §6.2 决策记录）。
- 不做锁屏/密码/鉴权 —— 这是隐私遮挡工具，不是安全边界。
- 不做静音、不做暂停音视频播放（v1.1 候选）。
- 不做 iOS/iPadOS 联动、不做远程触发。
- 不做多语言 UI（README 双语，UI 英文）。

## 3. 用户故事

- **US1** 作为工位上的工程师，我双击右 Control，3 块屏立刻全黑，路人只看到 3 块「关着的」屏幕。
- **US2** 我再双击右 Control，一切回到原样，包括我原来 47% 的内置屏亮度和 80% 的外接屏亮度。
- **US3** 我黑屏 40 分钟去开会，回来 Agent 还在跑 —— 因为 Blackout 期间阻止了系统空闲休眠。
- **US4** 我忘了手势是什么，第一次黑屏时屏幕中央淡出一行灰字告诉我怎么出来。
- **US5** 我黑屏时同事按了我的键盘，什么都没发生。
- **US6** App 崩了/被强杀，我的亮度不会永远停在 0 —— 下次启动自动复原。

## 4. 交互设计

### 4.1 触发手势

**默认：双击右 Control（⌃）。**

为什么是这个键：

- 右 Control 在 Apple 键盘上单独存在、位置固定、单手可达，且**几乎没有任何 App 单独使用它**。
- 「双击修饰键」是 macOS 用户熟悉的语汇（双击 ⌘ 呼出词典、双击 ⇧ 大写锁定等）。
- 修饰键不产生字符，误触零成本。

判定规则（严格，避免误触发）：

| 规则 | 值 | 理由 |
| --- | --- | --- |
| 两次「按下-抬起」的间隔上限 | 400 ms（可调 250/400/600） | 太长会和正常按 Ctrl 混淆 |
| 单次按住时长上限 | 450 ms | 长按 Ctrl 不算「点」 |
| 序列污染 | 期间按下任何其它按键即作废 | `⌃C`、`⌃⌥Tab` 等组合键绝不误触发 |
| 触发后冷却 | 350 ms | 防止一次手势被判成两次、来回闪烁 |
| 触发时机 | **第二次抬起**时 | 若判在「按下」，`⌃ ⌃C` 会误触发 |

可选触发键：右 Control（默认）/ 左 Control / 右 Command / 右 Option / 右 Shift。

### 4.2 黑屏时的画面

- 全部显示器铺满**纯黑不透明**窗口，层级在菜单栏、Dock、通知横幅之上。
- 0.22s 淡入（可关）。淡入让「有人走近」这件事看起来不像故障。
- 首次黑屏 / 开启提示后：鼠标所在的那块屏中央淡出一枚提示丸
  `Screens blacked out · double-tap ⌃ or press esc to restore`
  0.9s 停留 + 1.3s 淡出 → 归于全黑。灰度 35%，不刺眼，不构成信息泄露。
- 恢复时：0.18s 淡出，无提示（用户已经在看屏幕了）。

### 4.3 菜单栏

图标是代码绘制的 template image（自动适配浅/深色菜单栏、自动适配 Reduce Transparency）：

- 未激活：显示器外框线稿。
- 已激活：同一外框，屏幕区域**实心填充** —— 一眼读出「屏是关着的」。

菜单结构（扁平优先，二级只放低频项）：

```
● Screens visible                     ← 状态行，disabled
  Black Out Now            ⌃⌃         ← 主操作，随状态变 Restore Screens
─────────────────────────────
  Trigger                        ▸     Right Control ✓ / Left Control / Right ⌘ / Right ⌥ / Right ⇧
                                       ── Double-tap speed: Fast / Normal ✓ / Relaxed
  Behavior                       ▸     Dim display backlight ✓
                                       Keep Mac awake while blacked out ✓
                                       Block keyboard & mouse ✓
                                       esc restores ✓
                                       Fade animation ✓
                                       Show hint on blackout ✓
─────────────────────────────
  ⚠︎ Accessibility access needed…      ← 仅未授权时出现，点击直达系统设置
  Launch at Login                ✓
─────────────────────────────
  How it works…
  Blackout 1.0.0 · GitHub
  Quit Blackout                  ⌘Q
```

设计原则：**没有偏好设置窗口**。一个菜单栏小工具的全部设置能塞进菜单，就不该开窗。

### 4.4 首次运行引导

一个 480pt 宽的小窗（只出现一次）：产品名 + 一句话 + 手势示意 + 「授权辅助功能」按钮（实时反映授权状态）+ 「Try it now」按钮（黑屏 1.5s 自动恢复，让用户在安全环境里体验一次）+ 「Done」。

### 4.5 退出黑屏的三条独立路径

1. 再次双击触发键（主路径）。
2. 按 `esc`（默认开启；被吞掉，不会漏给前台 App）。
3. 杀掉进程 —— 遮罩窗口随进程消失，亮度由下次启动的崩溃恢复逻辑复原。

## 5. 功能需求

| ID | 需求 | 优先级 |
| --- | --- | --- |
| F1 | 双击触发键切换黑屏状态 | P0 |
| F2 | 每块显示器一个纯黑遮罩，层级 `CGShieldingWindowLevel()` | P0 |
| F3 | 遮罩为 non-activating panel，不抢焦点 | P0 |
| F4 | 显示器热插拔 / 分辨率变化 / 切换 Space 时遮罩自动跟上，不露缝 | P0 |
| F5 | 支持硬件调光的显示器背光降到最低，恢复时按屏还原原值 | P1 |
| F6 | 黑屏期间持有 `PreventUserIdleSystemSleep` 电源断言 | P1 |
| F7 | 黑屏期间吞掉键盘按键与鼠标点击/滚动（不吞鼠标移动） | P1 |
| F8 | 崩溃/强杀后下次启动自动复原亮度并释放脏状态 | P0 |
| F9 | 唤醒 / 解锁 / 快速用户切换后重新压住遮罩并重申亮度 | P1 |
| F10 | 菜单栏状态、设置、权限入口、登录启动 | P1 |
| F11 | 事件 tap 被系统禁用后自动重新启用 | P0 |
| F12 | 未授权辅助功能时给出明确指引，且菜单栏手动触发仍可用 | P1 |

## 6. 技术方案

### 6.1 三层机制

```
                ┌─────────────────────────────────────────┐
   手势  ──────▶│ CGEventTap (.defaultTap, session)        │
                │  └ TapDetector（纯函数状态机，可单测）    │
                └───────────────┬─────────────────────────┘
                                ▼
                     ┌──────────────────────┐
                     │ BlackoutController   │  单一状态源 isActive
                     └──┬────────┬────────┬─┘
       ┌────────────────┘        │        └────────────────┐
       ▼                         ▼                         ▼
 OverlayManager           BrightnessController        PowerAssertion
 每屏一个纯黑 NSPanel      DisplayServices 私有 API     阻止空闲休眠
 = 视觉保证（必成功）      = 观感加成（可失败）          = 让 Agent 活着
```

**关键取舍：视觉保证必须来自遮罩窗口，不能依赖亮度 API。** 遮罩是 WindowServer 合成的，100% 可控、瞬时、任意显示器都有效；亮度 API 在外接屏上大概率失败。把「看不见」押在遮罩上，把亮度当作让屏幕「看起来像关机」的加分项。

### 6.2 决策记录

| 决策 | 选择 | 被否方案及原因 |
| --- | --- | --- |
| 变黑手段 | 每屏纯黑 shielding-level 窗口 | ① 纯降硬件亮度：最低亮度在暗办公室仍可读，外接屏根本调不动 ② `CGDisplayCapture`：独占显示器，会打断其它 App 和视频会议 ③ Gamma 表清零：某些 App/录屏会绕过，且恢复时偶发残留 |
| 外接屏背光 | 不做 | DDC/CI over I2C 需按厂商 hack，单次写入 30–200ms，可能挂住 I2C 总线导致系统卡顿；收益仅是「背光更暗」，而遮罩已经保证看不见 |
| 事件监听 | `.defaultTap` + 辅助功能权限 | `.listenOnly` 只需输入监控权限，但**无法吞事件** → 做不到 F7，且 `esc` 会漏进前台终端 |
| 遮罩层级 | `CGShieldingWindowLevel()` | 更低的层级挡不住通知横幅 —— 一条微信预览就等于全泄露。代价：黑屏时自己的菜单栏也被挡住（见 §7 已知限制） |
| 遮罩窗口类型 | `NSPanel` + `.nonactivatingPanel`，`canBecomeKey = false` | 普通 NSWindow 会激活本 App，抢走终端焦点 |
| 恢复亮度 | 恢复到**操作前每屏各自的值** | 用户口述是「调回最亮」，但那会破坏他原本的亮度设置；「还原」才是正确语义 |
| 关屏睡眠 | 不做 | `displaysleepnow` 后任何鼠标微动即唤醒，唤醒瞬间的合成竞态有泄露风险 |
| 测试框架 | 独立可执行测试体 | 本机只有 CLT，无 XCTest（已实测 `no such module 'XCTest'`）。纯断言 harness 在任何环境都能跑，CI 也一样 |
| 构建 | SwiftPM + `scripts/bundle.sh` 组装 .app | 不需要 Xcode；`Package.swift` 可读可 review，胜过 pbxproj |

### 6.3 亮度 API

`dlopen` 私有框架 `DisplayServices`，取三个符号：

```c
int  DisplayServicesGetBrightness(CGDirectDisplayID, float *out);
int  DisplayServicesSetBrightness(CGDirectDisplayID, float);
bool DisplayServicesCanChangeBrightness(CGDirectDisplayID);
```

用 `dlsym` 而非链接：Apple 哪天挪走它，App 只是失去调光加分项，不会启动失败。任一显示器读取失败就**不记录**该屏，恢复时跳过 —— 绝不拍脑袋写回 1.0。

### 6.4 崩溃一致性

亮度是**进程外的全局系统状态**，会活过进程死亡。所以：

1. 调暗**之前**先把 `{displayKey: previousBrightness}` 写进 `UserDefaults` 并 `synchronize()`。
2. 恢复成功后清除该记录。
3. 每次启动先检查该记录：存在 → 立刻还原 + 清除，并在日志里记一笔。
4. 另加 `atexit` 与 `SIGINT/SIGTERM` 的 dispatch signal source 做优雅收尾。

`displayKey` 用 `vendor-model-serial-unit` 组合而非 `CGDirectDisplayID`（后者重新插拔就变）。

### 6.5 状态机

```
        ┌──────────┐   toggle()   ┌──────────┐
        │  Visible │─────────────▶│ BlackedOut│
        │          │◀─────────────│           │
        └──────────┘   toggle()   └──────────┘
             ▲                          │
             └──── 启动时崩溃恢复 ────────┘
```

`BlackoutController.isActive` 是唯一状态源。遮罩、亮度、电源断言、输入拦截全部是它的派生输出。UI 只读它。

## 7. 已知限制（写进 README，不藏）

1. **黑屏时菜单栏被自己挡住** —— 遮罩在 shielding level。所以退出只能靠手势或 `esc`。这是为了挡住通知横幅必须付的代价。
2. **Secure Event Input** —— 当前台是密码输入框（或开了 secure keyboard entry 的终端）时，macOS 会禁用所有事件 tap，手势失效。菜单里实时提示该状态。
3. **外接显示器背光不变** —— 见 §6.2。遮罩仍然保证看不见。
4. **屏幕共享 / 录屏** —— 遮罩是本机窗口，会被一起录进去（这通常正是你想要的），但不阻止已在进行的远程控制。Blackout 不是安全边界。
5. **Ad-hoc 签名重建后权限会重置** —— TCC 认签名。重新 `make install` 后可能需要重新勾一次辅助功能。

## 8. 验收标准

- [ ] A1 三屏全部变黑，耗时 < 250ms，无一块屏出现残留可读内容。
- [ ] A2 恢复后每块屏亮度等于操作前的值（±0.01）。
- [ ] A3 黑屏前后前台 App 不变（终端仍持有键盘焦点）。
- [ ] A4 `⌃C`、`⌃⌥←`、长按 `⌃` 均不触发。
- [ ] A5 黑屏期间按 20 个随机键，前台 App 收到 0 个。
- [ ] A6 黑屏中热插拔一台显示器，新屏不出现可读桌面。
- [ ] A7 黑屏中 `kill -9`，重启 App 后亮度自动复原。
- [ ] A8 TapDetector 单测全绿（含污染、长按、超时、冷却）。
- [ ] A9 `swift build -c release` 零 error。

---

# 自审记录

按要求对功能设计 / UI / 架构 / bug 做了三轮自我评审。每轮都产生了对上面设计的实际修改，修改已合并进正文。

## 第一轮 —— 产品与交互

| # | 问题 | 处置 |
| --- | --- | --- |
| 1.1 | 用户原话「调回**最亮**」。照做会破坏他原本的亮度偏好（内置屏 47% 的人不想变 100%）。 | 改为**还原每屏原值**。§6.2 记录该偏离并说明理由。 |
| 1.2 | 「亮度调到最低就看不到」是错的。P3225QE 最低亮度在暗办公室仍能读代码；且外接屏根本不响应亮度 API。**照原话实现会直接达不到用户真实目的。** | 引入纯黑遮罩作为**主机制**，亮度降为**辅助**。这是本 PRD 最重要的一次修正。 |
| 1.3 | 用户真实目的是「Agent 继续跑」。但人不碰电脑 20 分钟后 Mac 可能空闲休眠，Agent 就停了 —— 黑屏反而害了他。 | 新增 F6：黑屏期间持 `PreventUserIdleSystemSleep` 断言。用户没提，但这是需求的必要条件。 |
| 1.4 | 屏幕黑了不等于别人不能用。路人可以直接敲键盘、点鼠标。 | 新增 F7：黑屏期间吞键鼠。 |
| 1.5 | 「被锁在黑屏里」是本产品唯一的灾难性失败。 | 定为 G5，明确三条独立退出路径（§4.5），并把 `esc` 设为默认开启。 |
| 1.6 | 用户记不住手势，第一次黑屏会慌。 | 新增淡出提示丸（§4.2）+ 首次运行引导（§4.4）里的「Try it now」安全体验。 |
| 1.7 | 通知横幅。黑屏了但微信弹窗浮在最上面 = 全泄露。 | 遮罩层级定为 `CGShieldingWindowLevel()`，并接受菜单栏被挡的代价（§7.1）。 |
| 1.8 | 没有产品名和状态可视化。 | 定名 Blackout；菜单栏图标用「线稿 / 实心」两态直接表达屏幕开关。 |

## 第二轮 —— 架构与 API 可行性

| # | 问题 | 处置 |
| --- | --- | --- |
| 2.1 | `.listenOnly` tap 只需输入监控权限，看起来更"轻"，但**不能吞事件** → F7 做不到，而且 `esc` 会同时漏进前台终端（在跑 Agent 的终端里按 esc 后果不可控）。 | 改用 `.defaultTap` + 辅助功能权限。代价是更重的授权，收益是 F7 与可控的 `esc`。 |
| 2.2 | 事件 tap 回调里做重活会被系统以 `tapDisabledByTimeout` 掐掉。 | 回调只做状态机 + 一次同步 toggle；显式处理两种 disable 事件并重新启用（F11）。 |
| 2.3 | 双击检测依赖真实键盘，天然不可测。 | 抽出 `TapDetector` 纯值类型：输入是 `(事件, 时间戳)`，输出是 `Bool`，时钟由外部注入。逻辑与 AppKit 完全解耦，可全量单测。 |
| 2.4 | 亮度是进程外全局状态，进程死了它不会恢复 —— 这是唯一会「弄坏用户机器状态」的地方。 | 设计 §6.4 崩溃一致性协议：先持久化再改，启动即自愈。 |
| 2.5 | 硬链接私有框架会让 App 在未来 macOS 上直接启动失败。 | 全部走 `dlopen` + `dlsym`，失败即降级。 |
| 2.6 | 普通 `NSWindow` 置前会激活本 App，抢走终端焦点，违反 G3。 | 用 `NSPanel` + `.nonactivatingPanel` + `canBecomeKey=false` + `orderFrontRegardless()`。 |
| 2.7 | 本机无 XCTest，`swift test` 直接失败（已实测）。若坚持写 XCTest，仓库在作者机器上就跑不了测试。 | 改为 `BlackoutTests` 独立可执行 target + 极简断言 harness，`make test` 与 CI 都能跑。 |
| 2.8 | 想过做偏好窗口，会引入 SwiftUI/nib、布局无法在无 Xcode 环境目视验证。 | 全部设置塞进菜单；仅首次引导用一个纯代码 AppKit 小窗。UI 代码量与风险都降一个数量级。 |
| 2.9 | 权限、登录项、亮度、电源、遮罩混在 AppDelegate 里会烂成一团。 | 分层：`Core/`（无 UI 依赖的机制）、`UI/`（只读状态、只发命令）、`Support/`（日志、进程收尾）。`BlackoutController` 是唯一状态源。 |

## 第三轮 —— Bug 与边界红队

| # | 潜在 bug | 处置 |
| --- | --- | --- |
| 3.1 | 显示器热插拔：黑屏中接上第三块屏 → 新屏没有遮罩，直接露出桌面。 | 监听 `didChangeScreenParameters`，按 `NSScreen.screens` 差量增删遮罩；**激活状态下新建的遮罩直接 alpha=1 不淡入**，避免露一帧桌面。 |
| 3.2 | 快速连按导致淡入淡出动画交叉，最终 alpha 停在中间值 → 屏幕半透明，泄露。 | 引入 generation 计数器；每次 toggle 自增，动画完成回调里校验 generation，过期回调不执行 `orderOut`。目标 alpha 永远由最新一次 toggle 决定。 |
| 3.3 | `DisplayServicesGetBrightness` 失败时若默认按 1.0 记录，恢复会把用户亮度顶到 100%。 | 读取失败 → 该屏不入表、也不调暗。宁可不做，不可做错。 |
| 3.4 | 吞掉 `mouseMoved` 会让光标冻住，用户会以为死机（而且没有任何好处）。 | 事件 mask 里**不包含** `mouseMoved`，只吞按下/抬起/拖拽/滚轮。 |
| 3.5 | 吞掉 `flagsChanged` 会让前台 App 的修饰键状态错乱（卡住 Shift）。 | 拦截时**放行所有 flagsChanged**。修饰键单独按下不产生字符，放行无害。 |
| 3.6 | `esc` 触发恢复后若不吞掉，会同时漏给前台终端（可能中断 Agent 的交互）。 | 触发恢复的那次 `esc` 返回 `nil` 吞掉。 |
| 3.7 | 触发键自身的 `flagsChanged` 若被吞，OS 侧修饰键状态会与真实按键不同步。 | 触发键事件永远放行，只读不改。 |
| 3.8 | 电源断言忘了释放 → Mac 从此再也不休眠，电池狂掉。 | 断言的创建/释放与 `isActive` 严格配对，并在 `applicationWillTerminate`、`atexit`、信号处理里兜底释放。 |
| 3.9 | 睡眠唤醒 / 锁屏解锁 / 快速用户切换后，遮罩可能被压到 loginwindow 之下，或系统重置了亮度。 | 监听 `NSWorkspace.didWake`、`sessionDidBecomeActive`、`com.apple.screenIsUnlocked`；激活态下重新 `orderFrontRegardless()` 并重申目标亮度（F9）。 |
| 3.10 | `UserDefaults` 里存的枚举原始值被手改成非法值 → 崩溃或行为诡异。 | 所有偏好读取都过一层校验，非法值回落默认值。 |
| 3.11 | Secure Event Input 开启时 tap 静默失效，用户以为 App 坏了。 | 定时 `IsSecureEventInputEnabled()`，菜单里显示「Hotkey blocked by secure input」。 |
| 3.12 | 未授权辅助功能时 App 变成完全没用的图标。 | 未授权也能从菜单手动黑屏（F12）；菜单顶部常驻授权入口；2s 轮询授权状态，一授权立刻装 tap，无需重启。 |
| 3.13 | 遮罩不设 `collectionBehavior` → 切 Space 后遮罩留在原 Space，新 Space 全裸。 | `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]`。 |
| 3.14 | `alphaValue` 淡出结束才 `orderOut`，但期间用户又激活了 → 窗口被 orderOut 掉。 | 同 3.2 的 generation 校验。 |
| 3.15 | 自测会真的把开发者的屏幕弄黑，若逻辑有 bug 就出不来了。 | 提供 `blackout --self-test`：不装事件 tap、不阻塞，黑屏固定 1.2s 后无条件恢复并打印每屏亮度前后值，可在任何状态下安全验证核心链路。 |
| 3.16 | 仓库卫生：构建产物、dist 混进 git；无 license；无 CI。 | `.gitignore` + MIT + GitHub Actions（macos-latest 上 `swift build -c release` + `make test`）。 |
