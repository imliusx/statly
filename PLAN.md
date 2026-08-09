# Statly 开发规划

> macOS 状态栏系统监控工具。核心卖点：**轻量**——比所有同类产品更省 CPU、更省内存、更省电、体积更小。

## 1. 产品定位

菜单栏常驻显示 CPU / 内存 / 网速 / 磁盘实时指标，点击展开详情。

一句话定位：**"只做四件事，但做到最省。"**

| 竞品 | 特点 | Statly 的差异 |
|------|------|---------------|
| iStat Menus | 功能最全，付费，常驻 ~100MB | 只保留高频指标，资源占用为卖点 |
| Stats | 免费开源，模块多，包体较大 | 更克制的功能面 + 硬性能预算 |
| MenuMeters | 极轻但陈旧，无详情面板 | 现代 UI + 同级别的轻 |

## 2. 性能预算（硬性验收标准，写进 CI 检查清单）

| 指标 | 预算 |
|------|------|
| 常驻内存（弹窗关闭时 RSS） | < 35 MB |
| 平均 CPU（2s 刷新，4 模块全开，Apple Silicon） | < 0.3% |
| 能耗 | 活动监视器 Energy Impact ≈ 0；powermetrics 实测对比空载基线 |
| 每个刷新周期的 timer 唤醒次数 | 1 次（所有模块合并采样） |
| App 包体积 | < 10 MB |
| 冷启动到状态栏图标出现 | < 200 ms |
| 后台进程 / helper / 内核扩展 | 0 个，单进程 |
| 权限弹窗（TCC）、root | 0 |

任何新功能如果破坏预算，功能让步，预算不让步。

## 3. 技术选型

- **Swift，AppKit + SwiftUI 混合**：常驻路径（状态栏渲染、采样）全 AppKit/C API 手写；SwiftUI 只用于按需打开的弹窗和设置窗口，关闭即销毁。
- 不用 `MenuBarExtra`（宽度控制与高频刷新性能不足），用 `NSStatusItem`。
- **零第三方依赖**：1.0 不引入 Sparkle，更新用"检查更新"菜单项请求 GitHub Releases API 提示下载；主更新渠道推 Homebrew cask。
- 最低系统版本 **macOS 13**（可用 SMAppService、Swift Charts）。
- `LSUIElement = YES`，无 Dock 图标。
- 分发：Developer ID 签名 + 公证 + DMG，不上 App Store（沙盒会限制进程信息与后续传感器功能）。

## 4. 数据采集

全部为用户态 API，无权限弹窗、无 root：

| 指标 | API | 备注 |
|------|-----|------|
| CPU 使用率 | `host_processor_info`（Mach） | 每核 tick 差值；分 user/system/idle |
| 内存 | `host_statistics64` → `vm_statistics64` | used ≈ active + wired + compressed，对齐活动监视器口径 |
| 内存压力 | `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` | 事件驱动，零轮询成本 |
| 网速 | `getifaddrs` | 非回环接口收发字节差值 ÷ 间隔 |
| 磁盘容量 | `URL.resourceValues`（`volumeAvailableCapacityForImportantUsage`） | 与 Finder 显示一致 |
| 磁盘 I/O 速度 | IOKit `IOBlockStorageDriver` → `Statistics` | 累计读写字节差值 |
| Top 进程 | libproc（`proc_listallpids` + `proc_pidinfo`） | **仅弹窗打开时采样**，不进常驻路径 |

## 5. 架构

```
Statly/
├─ App/            入口、AppDelegate、生命周期
├─ Core/
│   ├─ MetricModule 协议    指标 = 模块（采样器 + 状态栏渲染 + 详情视图）
│   ├─ Scheduler            单一 DispatchSourceTimer，后台队列，leeway ≥ 500ms
│   ├─ HistoryBuffer        定长环形数组，只存原始 Double，不存对象
│   └─ Formatters           字节/速率/百分比，等宽数字
├─ Samplers/       CPUSampler / MemorySampler / NetworkSampler / DiskSampler
├─ UI/
│   ├─ StatusBar/           每模块一个 NSStatusItem；文本 / 迷你图两种样式
│   ├─ Popover/             SwiftUI：历史曲线（Swift Charts）、分项、Top 进程
│   └─ Settings/            单页：模块开关、刷新率、样式、开机自启
└─ Resources/
```

## 6. 轻量化工程规则（常驻路径守则）

1. **单 timer 合并唤醒**：所有模块共享一个 `DispatchSourceTimer`，一次唤醒采完全部指标。绝不允许每模块各建 timer。
2. **变了才画**：格式化结果与上次相同就不碰 `NSStatusItem`，字符串 diff 后再 set。
3. **看不见就停**：锁屏 / 显示器休眠（`NSWorkspace` 通知）暂停采样，唤醒恢复。
4. **按需分级**：Top 进程、提高刷新率等重操作只在弹窗打开期间生效；弹窗和设置窗口关闭即释放。
5. **等宽数字 + 固定 item 宽度**：`monospacedDigit`，避免数字跳动引起整条菜单栏重排。
6. **迷你图用离屏 CGContext 画成小图**，无 CALayer 动画、无过渡效果。
7. 刷新率可配 1s / 2s / 5s，**默认 2s**。
8. 每个 PR 自问：这段代码在常驻路径上吗？在的话，它每 2 秒的成本是多少？

## 7. 功能克制（scope 上的轻量）

- 1.0 只有 4 个模块：CPU、内存、网速、磁盘。
- 状态栏格式全局统一为「短标签 + 图形」：圆环（默认）/ 文本 / 迷你图（CPU·内存），网速为双行速率。
- 设置一页放完。
- 卸载 = 删除 app + 一个 plist，宣传页明说。
- 刘海屏应对：模块可单独开关；模块间距为系统默认行为（曾试验合并单图标模式，因交互不如独立图标自然而放弃）。

## 8. 里程碑

- **M0 脚手架**（1–2 天）：Xcode 工程、菜单栏应用骨架、空 NSStatusItem、设置窗壳、SMAppService 自启。
- **M1 MVP**（约 1 周）：CPU + 内存全链路（采样 → 状态栏 → 弹窗 → 设置开关），验证架构与预算可行性——**M1 结束即做第一次能耗实测**。
- **M2 补齐**（约 1 周）：网速、磁盘、迷你图样式、Swift Charts 历史曲线、配置持久化。
- **M3 发布 1.0**（约 1 周）：Top 进程（按需）、深浅色、性能预算逐项验收（Instruments + powermetrics）、签名公证、DMG、检查更新、Homebrew cask。
- **V2 待办池**：温度/风扇（SMC / IOHIDEventSystemClient）、GPU、电池、阈值告警、多语言、Sparkle、App Store 版评估。

## 9. 风险

| 风险 | 应对 |
|------|------|
| 自身能耗口碑翻车 | 性能预算作为发布门禁；M1 起每里程碑实测 |
| 刘海屏挤掉图标 | 模块开关 + 合并紧凑模式 |
| SwiftUI 弹窗内存驻留 | 关闭即销毁 hosting controller，实测 RSS 回落 |
| 与 Bartender/Ice 共存 | 标准多 item 设计天然兼容，发布前实测 |
| V2 传感器用私有接口 | 只进直接分发版，不进 App Store 版 |
