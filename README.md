# Statly

macOS 菜单栏系统监控：**CPU · 内存 · 温度 · 网速 · 磁盘**。

只做五件事，但做到最省——单进程、无后台守护、无权限弹窗、零第三方依赖，整个 App 不到 1 MB。

![状态栏与详情弹窗](docs/statusbar.jpg)

## 安装

到 [Releases](https://github.com/imliusx/statly/releases) 下载 DMG，把 Statly 拖进「应用程序」。要求 **macOS 13 及以上**。

> 当前版本未经 Apple 公证，首次打开需 **右键点击 App → 打开 → 再次确认**，
> 或在终端执行 `xattr -d com.apple.quarantine /Applications/Statly.app`。

卸载就是删掉 App，外加一个配置文件：

```sh
rm -rf /Applications/Statly.app
defaults delete com.statly.app
```

## 使用

每个模块占一个状态栏图标，按住 ⌘ 可拖动排序，位置由系统记住。

| 操作 | 效果 |
|------|------|
| 左键点击某个图标 | 展开**该模块**的详情：历史曲线、分项明细、占用最高的进程 |
| 悬停 | 气泡显示精确数值 |
| 右键任一图标 | 设置 / 关于 / 检查更新 / 退出 |

各模块显示的内容：

| 模块 | 状态栏 | 详情弹窗 |
|------|--------|----------|
| CPU | 总占用率 | 占用曲线、CPU 占用最高的 5 个进程 |
| 内存 | 已用占比 | 占用曲线、App / 联动 / 已压缩明细、内存占用最高的 5 个进程 |
| 温度 | 最高晶粒温度 | 温度曲线、平均值与传感器数 |
| 网络 | 实时上下行速率 | 上下行速率曲线 |
| 磁盘 | 已用容量占比 | 容量用量条、读写速率 |

## 设置

侧边栏按模块分区，样式改动在「预览」里即时可见。占用样式（圆环+百分比 / 纯文本）与标签样式（图标 / 竖排 / 文本 / 隐藏）可自由搭配，统一应用到所有模块。

![设置窗口](docs/settings.jpg)

## 性能

轻量是这个项目的第一原则，不是顺带的宣传语。所有数字都是实测值（Apple Silicon，五模块全开，2 秒刷新）：

| 指标 | 目标 | 实测 |
|------|------|------|
| 包体积 | < 10 MB | **0.65 MB** |
| 常驻内存（弹窗关闭时 RSS） | < 35 MB | **32 MB** |
| 每刷新周期 timer 唤醒 | 1 次 | **1 次**（全模块合并采样） |
| 后台进程 / 权限弹窗 / root | 0 | **0** |
| 平均 CPU | < 0.3% | 0.48%（未达标，优化中） |

支撑这些数字的工程约束（详见 [PLAN.md](PLAN.md)）：

- **单 timer 合并唤醒**：所有模块共享一个 `DispatchSourceTimer`，一次唤醒采完全部指标
- **变了才画**：渲染结果与上次相同就完全不碰 `NSStatusItem`
- **看不见就停**：锁屏、显示器休眠时暂停采样，唤醒后重置基线避免速率尖峰
- **按需分级**：进程排行只在弹窗打开期间采样，关闭即停止并释放
- **温度独立节流**：温度是慢变量，固定 5 秒采一次，且只读 4 个传感器（实测与全量读取的最高值平均只差 0.01°C，成本从 16.7 ms 降到 3.6 ms）

CPU 一项目前超出目标，瓶颈在状态栏图像的离屏绘制（开销随刷新频率与模块数线性增长），计划用渲染结果缓存解决。

## 数据来源

除温度外，全部指标来自用户态公开 API，不需要任何特殊权限：

| 指标 | API |
|------|-----|
| CPU | `host_processor_info`（每核 tick 差值） |
| 内存 | `host_statistics64`，内存压力用 `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` 事件驱动 |
| 网速 | `getifaddrs`（按接口差值，处理 32 位计数器回绕） |
| 磁盘 | `URL.resourceValues`（与 Finder 同口径）+ IOKit `IOBlockStorageDriver` |
| 进程排行 | libproc（`proc_listallpids` + `proc_pid_rusage`） |
| 温度 | `IOHIDEventSystemClient`（**私有接口**） |

温度没有公开 API。这里用 `dlsym` 动态取符号，读不到时该模块自动降级为「不可用」，不影响其余模块。也正因为用了私有接口，本项目只做直接分发，不上 App Store。

## 构建

要求 macOS 13+、Xcode 15+；生成 Xcode 工程需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
make run        # 开发运行（SPM 裸二进制，改-看循环最快；开机自启不可用）
make test       # 单元测试
make xcodeproj  # 生成 Statly.xcodeproj，用 Xcode 调试真 .app
make app        # Release 构建到 dist/Statly.app
```

`project.yml` 是 Xcode 工程的唯一事实来源（生成的 `.xcodeproj` 不入库）；`Package.swift` 负责单元测试与快速开发运行。

```
Sources/StatlyKit/
├── App/        入口、AppCoordinator（采样循环、状态栏、弹窗、设置的总协调）
├── Core/       单 timer 调度器、环形历史缓冲、等宽格式化、设置模型、更新检查
├── Samplers/   五个指标采样器 + 进程排行
└── UI/         NSStatusItem 渲染（变了才画）、SwiftUI 弹窗与设置窗口
```

## 发布

```sh
scripts/release.sh 0.1.0             # 构建 + 签名 + 出 DMG 到 dist/
scripts/release.sh 0.1.0 --publish   # 同上，并打 tag、创建 GitHub Release
```

签名与公证按本机能力自动降级，脚本本身不用改：

| 本机条件 | 结果 |
|---|---|
| Developer ID 证书 + notarytool 凭据 | 正式签名 + 公证 + staple，用户双击即开 |
| 有 Developer ID 证书，未配公证凭据 | 正式签名，跳过公证 |
| 只有开发证书或没有证书 | ad-hoc 签名，首次打开需右键 → 打开 |

配置公证凭据（需付费 Apple Developer 账号）：

```sh
xcrun notarytool store-credentials statly-notary \
    --apple-id <AppleID> --team-id <团队ID> --password <应用专用密码>
```

## 路线图

完整规划见 [PLAN.md](PLAN.md)。

- ✅ 五个模块全链路：采样 → 状态栏 → 详情弹窗 → 设置
- ✅ 进程排行、检查更新、DMG 发布流程
- ⏳ 状态栏渲染缓存（把 CPU 拉回 0.3% 目标以内）
- ⏳ Developer ID 签名与公证
- 📋 待办池：风扇转速、GPU、电池、阈值告警、多语言、Homebrew cask
