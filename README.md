<div align="center">

# Blackout

**双击右 Control，所有屏幕瞬间全黑。Mac 继续跑。**
*Double-tap Right Control. Every screen goes black. Your Mac keeps working.*

macOS 13+ · Apple Silicon & Intel · 菜单栏常驻 · MIT

</div>

---

## 这是干什么的

你在开放式工位上让 AI Agent 长时间跑任务。屏幕上是代码、内部文档、聊天记录，三块大屏谁走过都能一眼扫到。

你**不想锁屏**（会打断工作流、解锁麻烦），但你需要**别人看不到**。

双击右 Control：

- 所有显示器变成**纯黑**，层级在菜单栏、Dock 和通知横幅之上 —— 不漏一个像素
- 前台 App **不失焦**，Agent 一秒都没停
- 键盘鼠标被**吞掉**，路人碰不了你的机器
- Mac 被**保持唤醒**，你去开会 40 分钟回来任务还在跑
- 支持硬件调光的屏背光降到最低，看起来就像关机了

再双击一次：一切回到原样，**每块屏各自恢复到它原本的亮度**。

出不来怎么办？退路按**依赖**分层，不是按数量堆：再双击一次 / 按 `esc` / 手势不可用时遮罩自己接管键盘和鼠标（纯 AppKit，不依赖任何权限）/ 杀进程（遮罩随进程消失，亮度下次启动自动复原）。

## 安装

```bash
git clone https://github.com/HUANGXUANKUN/vibe-coding-blackout.git && cd vibe-coding-blackout && make install
```

只需要 Xcode Command Line Tools（`xcode-select --install`），**不需要装 Xcode**。

装完会自动启动，菜单栏出现一个显示器图标。然后授权一次：

**系统设置 ▸ 隐私与安全性 ▸ 辅助功能 ▸ 打开 Blackout**

辅助功能权限是键盘手势必需的（macOS 只允许拿到该权限的进程读写事件流）。没授权也能用 —— 从菜单栏手动黑屏，只是没有快捷手势。

想先看看它长什么样、又不想授权？

```bash
make self-test    # 全屏黑 1.2 秒，自动恢复，并校验每块屏亮度确实回来了
```

## 用法

| 操作 | 结果 |
| --- | --- |
| 双击右 Control | 全部屏幕变黑 / 恢复 |
| `esc` | 恢复（安全退路，永远不依赖手势判定准不准） |
| 未授权时点一下屏幕 | 恢复（此时遮罩自己接管键鼠，不依赖权限） |
| 菜单栏图标 | 线稿 = 屏幕可见，实心 = 已黑屏 |
| 菜单 ▸ Black Out Now | 不用手势也能黑屏（未授权时的备用路径） |

### 设置（全在菜单里，没有偏好窗口）

**Trigger** —— 触发键可换成 左 Control / 右 ⌘ / 右 ⌥ / 右 ⇧；双击间隔可选 Fast (250ms) / Normal (400ms) / Relaxed (600ms)。

**Behavior**

| 选项 | 默认 | 说明 |
| --- | --- | --- |
| Dim display backlight | 开 | 降低支持调光的屏背光，恢复时按屏还原原值 |
| Keep Mac awake while blacked out | 开 | 持有 `PreventUserIdleSystemSleep`，你不碰电脑也不会空闲休眠 |
| Block keyboard & mouse | 开 | 黑屏期间吞掉按键和点击（鼠标移动不吞，否则像死机） |
| esc restores | 开 | 安全退路 |
| Fade animation | 开 | 0.22s 淡入 / 0.18s 淡出 |
| Show hint on blackout | 开 | 黑屏后在鼠标所在屏中央淡出一行提示 |

误触发防护：单击不算、长按不算、`⌃C` 这类组合键不算、触发后 350ms 冷却防止来回闪。判定发生在**第二次抬起**，所以 `⌃` 然后 `⌃C` 也不会误触发。

## 已知限制

1. **黑屏时看不到自己的菜单栏** —— 遮罩在 `CGShieldingWindowLevel()`，这是挡住通知横幅必须付的代价（一条微信预览浮在最上面就等于全泄露）。所以菜单里的 Restore 在黑屏时点不到，退出走上面那几条路。
2. **外接显示器背光不变** —— DDC/CI 调外接屏需要按厂商 hack、单次写入几十到几百毫秒、还可能挂住 I2C 总线，收益只是「背光更暗」。遮罩已经保证看不见，不值得。实测本机两台 DELL P3225QE 不响应亮度 API，内置 XDR 正常。
3. **密码框获得焦点时手势失效** —— macOS 的 Secure Event Input 会禁用所有事件 tap。菜单里会实时提示 `⚠︎ Hotkey paused by secure input`；这种情况下遮罩会自动接管键盘，`esc` 仍然管用。
4. **Blackout 不是安全边界** —— 它是隐私遮挡工具。不阻止已在进行的远程控制，也不做鉴权。真要防人动你的机器，请锁屏。
5. **每次 `make install` 之后必须重新授权** —— macOS 的 TCC 按代码签名认 App，而 ad-hoc 签名的 cdhash 随二进制内容变。重装后**复选框看着还是勾上的，但手势已经死了** —— 这是最容易被误当成 App bug 的现象。修法：在辅助功能列表里把 Blackout 关掉再打开；或者

   ```bash
   tccutil reset Accessibility com.huangxuankun.blackout
   ```

   然后重新勾一次。想彻底免除这个来回，只能用一个固定的签名身份（自签名证书或 Developer ID）替代 ad-hoc 签名 —— 那需要往钥匙串里装证书并设置信任，不在本仓库的默认流程里。

## 架构

```
   手势  ──▶ CGEventTap (.defaultTap)
              └ TapDetector  纯值类型状态机，注入时钟，全量单测
                    │
                    ▼
            BlackoutController        ← isActive 是唯一状态源
             ├── OverlayManager       每屏一个纯黑 NSPanel  = 视觉保证（必成功）
             ├── BrightnessController DisplayServices 私有 API = 观感加成（可失败）
             └── PowerAssertion       阻止空闲休眠 = 让 Agent 活着
                    │
                    ▼
            StatusItemController      只读状态、只发命令
```

关键取舍：**「看不见」押在遮罩窗口上，不押在亮度 API 上。** 遮罩由 WindowServer 合成，瞬时、精确、任意显示器都有效；亮度 API 在外接屏上大概率失败。

其它设计要点：

- `.defaultTap` 而非 `.listenOnly` —— 后者不能吞事件，做不到输入拦截，且 `esc` 会漏进前台终端。
- 遮罩是 `.nonactivatingPanel` 且 `canBecomeKey = false` —— 置前不抢焦点，跑 Agent 的终端仍然持有键盘。
- 亮度是**进程外全局状态**，会活过进程死亡。所以调暗**之前**先把每屏原值写进 `UserDefaults` 并 flush；下次启动检测到记录就自动复原。`kill -9` 也不会把你的亮度永远留在 0。
- 显示器热插拔时，激活态下新建的遮罩**直接 alpha=1**，不淡入 —— 否则会露一帧桌面。
- 淡入淡出用 generation 计数器防竞态，快速连按不会把窗口停在半透明。

完整的功能设计、三轮自审记录（产品 / 架构 / bug 红队）和决策理由见 **[docs/PRD.md](docs/PRD.md)**。

## 开发

```bash
make build       # swift build -c release
make test        # 48 项断言：双击判定、组合键防误触、冷却、偏好校验、崩溃恢复记录
make self-test   # 真的黑屏 1.2 秒并校验恢复
make bundle      # 组装 dist/Blackout.app（含代码生成的 .icns + ad-hoc 签名）
make install     # 装到 /Applications 并重启
```

没有 `.xcodeproj`，没有 asset catalog，图标是代码画的。测试用独立可执行体而不是 XCTest —— XCTest 随 Xcode 分发，CLT-only 的机器上 `swift test` 直接失败。

日志：

```bash
log stream --predicate 'subsystem == "com.huangxuankun.blackout"' --level info
```

---

<details>
<summary><b>English</b></summary>

### What it is

A menu-bar utility for the moment someone walks up to your desk while an agent is running.

Double-tap Right Control and every display goes fully black — above the menu bar, the Dock and notification banners. Your Mac is not locked and nothing loses focus, so long-running work continues. Keyboard and mouse are swallowed while hidden, an idle-sleep assertion keeps the machine awake, and backlights drop to minimum on displays that support it. Double-tap again and every display returns to its own previous brightness.

Ways out are grouped by *dependency*, not counted: the gesture and the tap-level `esc` both need the event tap, so when the tap is unavailable the overlay takes key focus and handles `esc` and clicks itself through plain AppKit — no permission involved. Killing the process always works too (overlays die with it; brightness is restored on the next launch from a record written before dimming).

### Install

```bash
git clone https://github.com/HUANGXUANKUN/vibe-coding-blackout.git && cd vibe-coding-blackout && make install
```

Needs only the Xcode Command Line Tools. Then grant **System Settings ▸ Privacy & Security ▸ Accessibility ▸ Blackout** — required for the keyboard gesture. Without it you can still black out from the menu.

`make self-test` blacks out for 1.2s, restores, and verifies every display came back — safe to run any time, no permissions needed.

### Design notes

The overlay window, not the brightness API, is what guarantees nothing is visible: it is composited by WindowServer, so it is instant and works on every display, whereas `DisplayServices` typically cannot reach external monitors (on the author's machine it drives the built-in XDR but neither DELL P3225QE). Brightness is treated as a cosmetic bonus that is allowed to fail.

Full requirements, the three self-review rounds, and the reasoning behind each trade-off are in [docs/PRD.md](docs/PRD.md).

### Known limits

The overlay sits at `CGShieldingWindowLevel()` so it also covers our own menu bar — exit via the gesture or `esc`. External-monitor backlights are untouched by design (no DDC/CI). The gesture is disabled by macOS whenever a secure input field is focused; the menu says so when that happens. Blackout is a privacy screen, not a security boundary — lock your Mac if you need one.

</details>

## License

MIT © Xuankun Huang
