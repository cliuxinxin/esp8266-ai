# Mac 磁盘清理扫描报告

**扫描时间**：2026-08-30 16:40
**扫描方式**：只读扫描（未删除、未移动任何文件）

---

## 一、磁盘现状（危险）

| 项目 | 数值 |
|---|---|
| 磁盘总容量 | 228 GiB（APFS 容器） |
| 数据卷 `/System/Volumes/Data` 已用 | **181 GiB（99%）** |
| **当前可用空间** | **2.3 GiB** |

> macOS 建议至少保留 10–15% 可用空间用于 swap、系统更新和快照。2.3 GiB 已属**危险水位**，会出现卡死、无法更新、应用写入失败等问题。**建议优先处理，目标回收 40 GB 以上。**

---

## 一·补、执行记录（2026-08-30 17:05 已完成）

用户确认后已实际执行以下删除，**共回收约 31 GiB**：

| 项目 | 执行动作 | 结果 |
|---|---|---|
| Ollama 模型 | `ollama rm huihui_ai/qwen3.5-abliterated:9b` | ✅ 已删，`gemma4:e4b-mlx` 保留 |
| VSCode 升级残留 | `rm -rf ~/Library/Caches/com.microsoft.VSCode.ShipIt` | ✅ 已删（1.5 GB） |
| Codex 升级残留 | `rm -rf ~/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle` | ✅ 已删（1.9 GB） |
| 抖音升级残留 | `rm -rf ~/Library/Caches/com.bytedance.douyin.desktop.ShipIt` | ✅ 已删（688 MB） |
| GitHub Desktop 升级残留 | `rm -rf ~/Library/Caches/com.github.GitHubClient.ShipIt` | ✅ 已删（681 MB） |
| 模拟器设备 | `xcrun simctl delete all` | ✅ 37 台全部删除（6.6 GB） |
| iOS 18.3.1 运行时 | `xcrun simctl runtime delete 5C6F3EAC-…` | ✅ 已删 |
| iOS 18.6 运行时 | `xcrun simctl runtime delete C5907C27-…` | ✅ 已删 |
| iOS 26.5 运行时 | `xcrun simctl runtime delete 0851B1DF-…` | ✅ 已删 |
| dyld 共享缓存 | — | ✅ 随运行时一并清空，仅剩 6 个 0 字节日志，无需 sudo |

**执行后状态**

| 指标 | 清理前 | 清理后 |
|---|---|---|
| 已用 | 181 GiB (99%) | **150 GiB (82%)** |
| 可用 | 2.3 GiB | **35 GiB** |
| 模拟器运行时 | 3 个 / 24.3 GB | **0 个** |
| 模拟器设备 | 37 台 | **0 台** |
| CoreSimulator 总计 | 79 GB | **5.1 MB** |
| Ollama 模型 | 2 个 / 14 GB | **1 个 / 8.2 GB** |
| 用户缓存目录 | 9.3 GB | **4.6 GB** |

> 上表 `~/Library/Caches` 剩余 4.6 GB 中，仍有 Arc 977M、Google 806M、Playwright 1.0G、WorkBuddy 迁移残留 1.3G 等可继续清理项，详见第三节。

---

## 二、占用分布（按可回收性排序）

| 占用项 | 大小 | 路径 |
|---|---|---|
| iOS 模拟器 CoreSimulator | **79 GB** | `/Library/Developer/CoreSimulator` |
| 系统级 /Library 其他 | 10 GB | `/Library/Frameworks` 3.9G、`Application Support` 2.7G 等 |
| 用户 Library 缓存 | 9.3 GB | `~/Library/Caches` |
| Ollama 本地大模型 | 14 GB | `~/.ollama/models` |
| 用户 Library 应用支持 | 16 GB | `~/Library/Application Support` |
| 应用容器（QQ/微信等） | 14 GB | `~/Library/Containers` |
| 应用程序 | 21 GB | `/Applications` |
| 其他 dotfiles 工具链 | ~10 GB | `.hermes` `.local` `.codex` `.npm-cache` `.rustup` 等 |

---

## 三、重点清理项（按收益排序）

### 🥇 1. iOS 模拟器 —— 可回收 **35–55 GB**

这是最大的一块，占整机 1/3。

```
/Library/Developer/CoreSimulator/Volumes/iOS_22G86     19 GB   (iOS 18.6)
/Library/Developer/CoreSimulator/Volumes/iOS_22D8075   18 GB   (iOS 18.3)
/Library/Developer/CoreSimulator/Volumes/iOS_23F77     16 GB   (iOS 26.5)
/Library/Developer/CoreSimulator/Cryptex/Images/bundle 16 GB   (运行时镜像包)
/Library/Developer/CoreSimulator/Caches/dyld           10 GB   (动态库缓存，纯缓存)
~/Library/Developer/CoreSimulator/Devices              6.6 GB  (模拟器设备数据)
```

当前装有 3 个运行时 + 大量模拟器设备（iOS 18.3 下 15 台、18.6 下 7 台，全部 Shutdown）。

**建议动作（风险从低到高）**

```bash
# ① 清 dyld 共享缓存 —— 最安全，纯缓存，系统会自动重建
sudo rm -rf /Library/Developer/CoreSimulator/Caches/dyld
# 预计回收 ~10 GB，风险：无

# ② 查看并删除不用的模拟器设备
xcrun simctl list devices
xcrun simctl delete <设备UUID>
xcrun simctl delete unavailable          # 一次性删掉所有不可用设备
# 预计回收 0–6 GB，风险：低（设备里的数据会丢，模拟器可重建）

# ③ 删除不用的 iOS 运行时（推荐只保留 iOS 26.5）
xcrun simctl runtime list                          # 查看
sudo xcrun simctl runtime delete iOS-18-3          # 删 iOS 18.3
sudo xcrun simctl runtime delete iOS-18-6          # 删 iOS 18.6
# 预计回收 35–40 GB，风险：中（删后需联网重新下载才能用该版本模拟器）
```

> ⚠️ 注意：`Volumes/` 是挂载点，`Cryptex/Images/bundle/` 是镜像实体，两者有重叠计算，**不要重复相加**。实际回收以删除运行时后的 `df -h` 为准。

---

### 🥈 2. Ollama 本地大模型 —— 可回收 **6.6–14 GB**

```
~/.ollama/models                     14 GB
  ├─ gemma4:e4b-mlx                  8.8 GB   (4 周前使用)
  └─ huihui_ai/qwen3.5-abliterated:9b  6.6 GB  (2 周前使用)
```

```bash
ollama list                    # 查看
ollama rm gemma4:e4b-mlx       # 删单个（保留另一个）
# 风险：低。删掉后需重新 pull（耗时，取决于网络）
```

---

### 🥉 3. 用户缓存目录 —— 可回收 **~8 GB（几乎零风险）**

| 路径 | 大小 | 说明 |
|---|---|---|
| `~/Library/Caches/com.openai.codex` | 1.9 GB | Codex 缓存 |
| `~/Library/Caches/com.microsoft.VSCode.ShipIt` | 1.5 GB | VSCode **升级残留包**，可全删 |
| `~/Library/Caches/com.workbuddy.workbuddy.BundleMigration` | 1.3 GB | WorkBuddy 迁移残留 |
| `~/Library/Caches/ms-playwright` | 1.0 GB | Playwright 浏览器内核（重装会再下载） |
| `~/Library/Caches/Arc` | 977 MB | Arc 浏览器缓存 |
| `~/Library/Caches/Google` | 806 MB | Chrome 缓存 |
| `~/Library/Caches/com.bytedance.douyin.desktop.ShipIt` | 688 MB | 抖音升级残留 |
| `~/Library/Caches/com.github.GitHubClient.ShipIt` | 681 MB | GitHub Desktop 升级残留 |
| `~/Library/Caches/Homebrew` | 108 MB | 可用 `brew cleanup` |
| `~/Library/Caches/node-gyp` | 62 MB | node-gyp 编译缓存 |

```bash
# 安全清理（建议先删 ShipIt 类和迁移残留）
rm -rf ~/Library/Caches/com.microsoft.VSCode.ShipIt
rm -rf ~/Library/Caches/com.workbuddy.workbuddy.BundleMigration
rm -rf ~/Library/Caches/com.bytedance.douyin.desktop.ShipIt
rm -rf ~/Library/Caches/com.github.GitHubClient.ShipIt
brew cleanup --prune=all        # Homebrew 旧版本包
npm cache clean --force         # npm 缓存
```

> 浏览器缓存（Arc / Chrome / Edge）建议**在浏览器设置里清**，直接删目录可能导致插件数据异常。

---

### 4. 聊天软件数据 —— 可回收 **5–9 GB（需在应用内操作）**

```
~/Library/Containers/com.tencent.qq           5.2 GB
~/Library/Containers/com.tencent.xinWeChat    3.3 GB
~/Library/Containers/com.tencent.xWeChat      1.1 GB
```

⚠️ **不要直接删目录**，会丢聊天记录。正确做法：
- 微信：设置 → 通用 → 存储空间 → 管理，清理缓存 + 选择性删除聊天文件
- QQ：设置 → 基本设置 → 文件管理 → 前去清理

---

### 5. 应用支持目录 —— 可回收 **3–6 GB**

```
~/Library/Application Support/Arc                    3.3 GB
~/Library/Application Support/抖音                    2.0 GB
~/Library/Application Support/lzc-client-desktop     1.9 GB  (懒猫微服，其中 Cache 563MB)
~/Library/Application Support/Microsoft              1.4 GB
~/Library/Application Support/Steam                  1.2 GB  (含 Steam.AppBundle 1.0G，是 Steam 自更新包)
~/Library/Application Support/Google                 1.1 GB
~/Library/Application Support/Shandianshuo           903 MB
~/Library/Application Support/Microsoft Edge         789 MB
~/Library/Application Support/com.apple.wallpaper    457 MB  (系统壁纸，不建议动)
```

建议：抖音 2.0 GB 若不常使用可直接卸载；懒猫微服的 `Cache` 563 MB 可删。

---

### 6. 其他工具链 —— 可回收 **2–4 GB**

| 路径 | 大小 | 说明 |
|---|---|---|
| `~/.hermes` | 3.2 GB | 其中 `hermes-agent` 2.3G、`state.db` 282M、`state-snapshots` 191M |
| `~/.local` | 1.9 GB | |
| `~/.codex` | 1.6 GB | |
| `~/.npm-cache` | 1.3 GB | |
| `~/.rustup` | 1.2 GB | 可用 `rustup toolchain list` 删旧工具链 |
| `~/.platformio` | 409 MB | 嵌入式开发平台包 |
| `~/.lmstudio` | 299 MB | |

---

### 7. Time Machine 本地快照 —— 系统自动管理

系统中存在 3 个本地快照（`com.apple.os.update-*`）。这些是系统更新前的恢复点，通常会自行清理。若急需空间：

```bash
tmutil listlocalsnapshots /
sudo tmutil deletelocalsnapshots <快照日期>
```

---

### 8. 非本机占用（不影响本机磁盘，仅提示）

以下为**已挂载的局域网共享盘**，占的是 NAS/Windows 机器的空间，不是本机：
- `/Volumes/downloads` — 14 TB，已用 13 TB（97%）
- `/Volumes/SE` — 同上
- `/Volumes/noen` — 同上

---

## 四、推荐执行顺序

| 步骤 | 动作 | 预计回收 | 风险 |
|---|---|---|---|
| 1 | 删 ShipIt / 迁移残留 / brew cleanup | ~4 GB | 无 |
| 2 | 删 CoreSimulator dyld 缓存 | ~10 GB | 无 |
| 3 | 删 1–2 个不用的 iOS 运行时 | 35–40 GB | 低 |
| 4 | 微信/QQ 应用内清理 | 5–9 GB | 低 |
| 5 | 删不用的 Ollama 模型 | 6.6–8.8 GB | 低 |
| 6 | 卸载不用的大应用（抖音、Steam 等） | 3–5 GB | 低 |
| **合计** | | **60–80 GB** | |

做完第 1–3 步就能回收约 50 GB，磁盘立刻脱离危险区。

---

## 五、后续维护建议

1. **不要手动删 `~/Library/Containers` 下的应用数据目录**，聊天记录会丢。
2. iOS 模拟器用完记得 `xcrun simctl delete unavailable`，这是空间黑洞。
3. 定期跑：`brew cleanup --prune=all` + `npm cache clean --force` + `ollama list`。
4. 用系统自带的 **「关于本机 → 存储空间 → 推荐」** 做二次确认，它识别更准（尤其是「文稿」和「系统数据」分类）。
