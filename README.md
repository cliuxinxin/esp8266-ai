<p align="center">
  <img src="docs/images/logo.svg" width="72" alt="logo">
</p>

<h1 align="center">AI Mac 小屏幕</h1>

<p align="center">桌上的一台 AI 状态小电脑 —— ESP8266 · 开源硬件 · 桌面伴侣</p>

<p align="center">
  中文 ·
  <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="https://mac.qust.me">官网</a> ·
  <a href="https://mac.qust.me/#flash">网页刷机</a> ·
  <a href="https://github.com/pengchujin/esp8266-ai/releases/latest">下载</a>
</p>

<p align="center">
  <img src="docs/images/hero.jpg" width="640" alt="AI Mac 小屏幕">
</p>

一块 240×240 的复古小电视，放在桌上实时显示 **Claude Code / Codex CLI 在干什么、额度还剩多少**。不需要任何 API key：数据来自本机已有的 CLI 登录凭据和会话日志，由配套的 Mac / Windows 桥接程序在局域网内提供给设备。

## 功能

| | |
|---|---|
| <img src="docs/images/feature1.jpg" width="360" alt="AI 工作状态"> | **AI 工作状态与额度**<br>桌宠动起来 = AI 正在干活。方形进度环 + 大字显示 5 小时 / 周额度的真实用量；额度用满自动换成重置倒计时，等你审批时整圈边框红闪提醒。 |
| <img src="docs/images/feature2.jpg" width="360" alt="网速监视"> | **网速实时监视**<br>任务管理器风格的上下行曲线，56 秒滚动窗口，量程自动调整。 |
| <img src="docs/images/music.jpg" width="360" alt="音乐播放"> | **音乐播放显示**<br>专辑封面、歌名、歌手、进度条实时同步；音乐响起自动切入，停止自动切回。 |
| <img src="docs/images/feature3.jpg" width="360" alt="桌宠可换"> | **可换桌宠**<br>内置 [petdex.dev](https://petdex.dev) 画廊 3300+ 开源桌宠，也可上传任意 GIF，设备板上直接解码，无需重烧固件。 |

此外还支持**增强天气页**和**名人名言页**。天气页包含当前/体感/最高/最低温、湿度、风力、空气质量、降水概率和未来三天预报；名言页轮换展示中文一言和英文 ZenQuotes，并在断网时沿用最近一次成功缓存。

## 快速上手

需要的东西：一台「SD2 小电视」开发板（[开源硬件](https://oshwhub.com/q21182889/sd2)，也可[直接购买成品](https://mobile.yangkeduo.com/goods.html?ps=OuBjGMWE82)）、一根 USB **数据**线。

### 第 1 步 · 刷固件（约 30 秒）

用 Chrome / Edge 打开 **[mac.qust.me/#flash](https://mac.qust.me/#flash)**，USB 连接设备，点「连接设备并烧录」，选择串口等待完成即可，无需安装任何工具。

> 弹窗里看不到串口？Windows 需要装 [CH340 驱动](https://www.wch.cn/downloads/CH341SER_EXE.html)，Mac 系统自带无需安装；换根 USB 线（很多线只能充电）；更多排查见[官网 FAQ](https://mac.qust.me/#flash-faq)。
>
> 命令行党也可以用 esptool 把 [Releases](https://github.com/pengchujin/esp8266-ai/releases/latest) 里的 `esp8266-ai-firmware-*.bin` 刷到 `0x0`。

### 第 2 步 · 配 WiFi

设备首次开机会开热点 **`AI-Clock-Setup`**：手机连上后自动弹出配网页（没弹就用浏览器打开 `192.168.4.1`），选择家里 WiFi、输入密码，完成。

### 第 3 步 · 装桥接程序

从 [Releases](https://github.com/pengchujin/esp8266-ai/releases/latest) 下载并打开：

- **macOS**：`AIClockBridge-*-macOS.dmg`，拖入 Applications（ad-hoc 签名，首次启动需在「系统设置 → 隐私与安全性」允许，并同意本地网络权限）
- **Windows**：`AIClockBridge-*-Windows-x64.exe`，双击即用

桥接程序常驻菜单栏 / 托盘，会**自动发现并配对**同一局域网内的设备——到这里屏幕就活了。

<p align="center">
  <img src="docs/images/working.jpg" width="640" alt="工作演示">
</p>

日常使用都在托盘图标上：**左键**打开设备画面的实时镜像（底部有屏幕亮度滑条），**右键**是完整菜单（额度详情、屏幕切换、天气城市、更换桌宠、音乐/网速页等）。

### 自动显示与名人名言

Mac 菜单栏右键 →「自动显示设置…」可以分别控制两类内容：**事件触发**项在事件发生时立即切入；**定时显示**项按设定间隔到期后展示一段时间。默认设置如下：

| 类型 | 内容 | 默认 | 间隔 | 显示时长 |
|---|---|---:|---:|---:|
| 事件 | Claude 工作状态 | 关 | — | 事件期间 |
| 事件 | Codex 工作状态 | 开 | — | 事件期间 |
| 事件 | 等待确认 | 开 | — | 事件期间 |
| 事件 | 音乐播放 | 开 | — | 播放期间 |
| 定时 | 天气 | 开 | 15 分钟 | 10 秒 |
| 定时 | 名人名言 | 开 | 30 分钟 | 12 秒 |
| 定时 | 股票 | 关 | 15 分钟 | 10 秒 |
| 定时 | 网速 | 关 | 10 分钟 | 10 秒 |

定时间隔可设为 1–240 分钟，显示时长可设为 5–60 秒。自动模式优先级为：**等待确认 > Codex 工作 > Claude 工作 > 音乐 > 已到期的定时内容 > 空闲桌宠**；多个定时项同时到期时优先显示最久未展示的一项。事件会打断定时内容，事件结束后该内容恢复并重新获得完整显示时长。

关闭某一项**只影响自动模式**，仍可从「屏幕显示」或镜像底部手动固定到对应页面。选择「屏幕显示 → 名人名言」会持续显示名言；点「换一句」会立即请求新内容，当前正固定显示名言时设备也会随即刷新。

名言由 Mac 桥接程序从一言（中文）和 ZenQuotes（英文）轮换获取，无需 API Key，约每 30 分钟自动换一句并避免近期重复。成功内容缓存到本机；网络失败时保留上次结果，超过 30 分钟会标记为陈旧，但仍可继续显示。名言功能需要同时更新 Mac 桥接程序与 ESP8266 固件。

### 天气功能

天气功能需要同时更新 **Mac 桥接程序**和 **ESP8266 固件**，并确保两台设备处于同一局域网。

- 右键菜单栏图标 →「屏幕显示」→「天气」：固定显示天气页。
- 右键菜单栏图标 →「设置天气城市…」：搜索并选择城市，默认为成都。
- 右键菜单栏图标 →「屏幕显示」→「自动（谁在干活显示谁）」：每 15 分钟自动展示天气约 10 秒。
- 左键菜单栏图标：打开实时屏幕镜像，也可以从镜像底部切换到天气页。

天气页显示当前温度、体感温度、最高/最低温、湿度、风向风速、降水概率、AQI 和未来三天预报。数据约每 10 分钟更新一次；网络暂时中断时会保留最近一次成功获取的数据。自动模式采用上面的统一事件优先级，天气与其他定时项则按最久未显示者公平选择。

### 从源码更新最新版（macOS）

先拉取最新代码：

```bash
git switch main
git pull --ff-only origin main
```

从菜单栏退出正在运行的旧版 AIClockBridge，防止本地服务端口冲突，然后启动新版 Mac 桥接程序：

```bash
cd mac-app
swift run
```

也可以编译并运行优化版：

```bash
cd mac-app
swift build -c release
.build/release/AIClockBridge
```

首次运行时，请允许 macOS 的本地网络访问权限。天气和名言数据都由 Mac 桥接程序获取，不需要单独申请 API Key。

使用 USB 数据线连接 ESP8266，确认串口后编译并刷写固件：

```bash
cd firmware
pio device list
pio run -t upload
```

项目默认串口是 `/dev/cu.usbserial-130`。如果你的串口名称不同，可显式指定：

```bash
pio run -t upload --upload-port /dev/cu.usbserial-你的串口
```

刷写完成后设备会自动重启。如果设备尚未配网，请连接它创建的 `AI-Clock-Setup` 热点完成 WiFi 配置。

## 常见问题

- **屏幕边框红色闪烁**：设备连不上桥接程序——确认电脑端程序在运行、和设备在同一 WiFi。
- **额度一直显示 `-`**：本机没有登录过 Claude Code / Codex CLI，桥接程序读不到凭据。
- **想换桌宠**：右键托盘图标 → 「更换桌宠动画…」，挑一个点上传就行。

## 开发

```
firmware/     ESP8266 固件（PlatformIO + Arduino，含板上 GIF 解码）
mac-app/      macOS 菜单栏桥接（Swift/SPM，零第三方依赖）
windows-app/  Windows 托盘桥接（C# / .NET 8 WinForms）
tools/        GIF → RGB565 内置精灵图转换脚本
docs/         开发文档（硬件引脚、HTTP API、架构细节）
```

```bash
(cd firmware && pio run)            # 固件：仅编译
(cd mac-app && swift test)           # Mac 桥接：运行测试
(cd mac-app && swift run)            # Mac 桥接：本地运行
```

硬件引脚表、屏幕驱动的坑、设备 HTTP API、GIF 板上解码架构等细节见 **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)**。

硬件、固件、软件全部开源，拿去改、拿去做、拿去卖都行。
