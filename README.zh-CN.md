<div align="center">
  <img src="docs/icon.png" width="128" alt="Statly">
  <h1>Statly</h1>
  <p><b>面向 macOS 的轻量系统监控工具</b></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
    <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
    <img src="https://img.shields.io/badge/Size-0.71%20MB-4c1" alt="Size 0.71 MB">
    <img src="https://img.shields.io/badge/Dependencies-0-4c1" alt="Zero dependencies">
    <img src="https://img.shields.io/badge/License-MIT-4c1" alt="MIT License">
  </p>
  <p><a href="README.md">English</a> · <b>简体中文</b></p>
</div>

Statly 是一款面向 macOS 的轻量系统监控工具，常驻菜单栏实时显示 CPU、内存、温度、网络速率与磁盘五项指标，点击图标展开对应模块的详情。

以资源占用为首要约束：菜单栏内容由 AppKit 离屏绘制，SwiftUI 仅用于按需打开的详情面板与设置窗口；单进程运行，零第三方依赖，安装包 0.71 MB，无后台守护进程，无需任何系统权限。

![状态栏与详情弹窗](docs/statusbar.jpg)

## 功能

- **模块化** — 五个指标各自独立，可单独启用/停用，按住 ⌘ 拖动排序，位置持久保存。
- **菜单栏显示** — 占用类指标以圆环+百分比呈现；网络上下行双行显示；数值用等宽字体预留宽度，避免布局抖动。
- **样式配置** — 占用样式（圆环+百分比 / 纯文本）与标签样式（图标 / 竖排 / 横排 / 隐藏）自由组合，设置窗口实时预览。
- **温度双重呈现** — 图标水银柱按 <50°C / 50–80°C / ≥80°C 三档变化；圆环按读数直接填充，口径与其他模块一致。
- **温度来源可选** — 可在 CPU（取晶粒传感器最高值）与电池之间切换，台式机无电池传感器时自动禁用。
- **详情面板** — 各模块历史曲线；CPU/内存附占用最高的 5 个进程，内存附压力状态与分项，网络附本机 IP / 网关 / DNS / 公网 IP，磁盘附容量条与读写速率。
- **悬停提示** — 圆环模式下悬停图标即可查看精确数值。
- **系统适配** — 模板图自动适配深浅色；设置窗口为系统分组卡片与毛玻璃；界面简体中文。
- **低开销** — 全模块共享一次定时唤醒；结果无变化不重绘；锁屏/休眠暂停采样；进程列表仅面板打开时采集。
- **无残留** — 无 Dock 图标，无登录项守护进程，卸载仅需删除应用与一个配置文件。

## 安装

在 [Releases](https://github.com/imliusx/statly/releases) 下载 DMG，拖入「应用程序」。要求 **macOS 13 及以上**。

> 当前版本未经 Apple 公证，首次打开需右键点击应用 → 打开，或执行 `xattr -d com.apple.quarantine /Applications/Statly.app`。

卸载：

```sh
rm -rf /Applications/Statly.app
defaults delete com.statly.app
```

## 使用

| 操作 | 效果 |
|------|------|
| 左键点击图标 | 展开该模块的详情面板 |
| 悬停图标 | 气泡提示精确数值 |
| 右键任一图标 | 设置 / 关于 / 检查更新 / 退出 |
| ⌘ + 拖动 | 调整图标顺序 |

| 模块 | 菜单栏 | 详情面板 |
|------|--------|----------|
| CPU | 总占用率 | 占用曲线、占用最高的 5 个进程 |
| 内存 | 已用占比 | 占用曲线、App / 联动 / 已压缩分项、占用最高的 5 个进程 |
| 温度 | 所选来源的最高温度 | 温度曲线、平均值与传感器数量 |
| 网络 | 实时上下行速率 | 速率曲线、本机 IP / 网关 / DNS、公网 IP 与归属地 |
| 磁盘 | 已用容量占比 | 容量用量条、读写速率 |

## 设置

按模块分区，样式调整实时预览。采样间隔 1 / 2 / 5 秒，默认 2 秒。开机自启基于 `SMAppService`；公网 IP 查询可在设置中关闭，关闭后无任何对外请求。

![设置窗口](docs/settings.jpg)

## 性能

实测数据（Apple Silicon，五模块，2 秒采样间隔）：

| 指标 | 目标 | 实测 |
|------|------|------|
| 安装包体积 | < 10 MB | **0.71 MB** |
| 常驻内存（面板关闭时 RSS） | < 35 MB | **32 MB** |
| 每采样周期 timer 唤醒 | 1 次 | **1 次**（全模块合并） |
| 后台进程 / 权限 / root | 0 | **0** |
| 平均 CPU 占用 | < 0.5% | **0.42%** |

实现约束：

- **合并唤醒** — 全部模块共享一个 `DispatchSourceTimer`。
- **差异更新** — 结果与上一周期相同时跳过 `NSStatusItem` 调用。
- **不可见时暂停** — 锁屏/休眠时停止采样，恢复后重置基线防速率尖峰。
- **按需采集** — 进程列表与网络环境信息仅面板打开时采集，面板关闭即停止。
- **温度独立节流** — 固定 5 秒采样一次，仅读少量传感器（CPU 4 个、电池 2 个），单次成本由 16.7 ms 降至 3.6 ms，与全量读取最高值平均相差 0.01°C。

CPU 占用构成（采样分析器与受控基准实测）：

| 来源 | 占比 |
|------|------|
| AppKit 更新菜单栏项的固有成本 | 约 0.23% |
| Statly 自身的采样与渲染 | 约 0.06% |
| 其余（定时器、事件循环等） | 约 0.13% |

0.23% 是最小对照程序的实测下限（仅每 2 秒更换两个菜单栏项图像，仍需 0.21–0.25%），即 0.3% 在 2 秒间隔下不可达。原定 < 0.3% 目标据此修订为 < 0.5%；5 秒间隔时约 0.2%。

## 数据来源

全部数据通过用户态公开 API 在本机获取，无需特殊权限：

| 指标 | API |
|------|-----|
| CPU | `host_processor_info`（每核 tick 差值） |
| 内存 | `host_statistics64`；内存压力用 `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` 事件驱动 |
| 网络速率 | `getifaddrs`（按接口差值，处理 32 位计数器回绕） |
| 网络环境 | `SCDynamicStore`、`getifaddrs` |
| 磁盘 | `URL.resourceValues`、IOKit `IOBlockStorageDriver` |
| 进程列表 | libproc（`proc_listallpids` / `proc_pid_rusage`） |
| 温度 | `IOHIDEventSystemClient`（**私有接口**） |
| 公网 IP | `ipinfo.io`（**唯一对外请求**，可关闭） |

温度在 macOS 上没有公开 API，通过 `dlsym` 动态解析符号，失败时该模块降级为「不可用」，不影响其余模块；因使用私有接口，本项目仅直接分发，不上架 App Store。Wi-Fi SSID 自 10.15 起需位置授权，本项目不申请权限，故不显示。公网 IP 仅在网络面板打开时查询一次，结果缓存至本机 IP / 网关变化，可随时关闭。

## 构建

需要 macOS 13+、Xcode 15+ 与 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）：

```sh
make run        # 开发运行（SPM，迭代最快；此模式下开机自启不可用）
make xcodeproj  # 生成 Statly.xcodeproj，用于 Xcode 调试完整应用
make app        # Release 构建至 dist/Statly.app
```

`project.yml` 是 Xcode 工程的唯一事实来源，`.xcodeproj` 不入版本控制。

```
Sources/StatlyKit/
├── App/        程序入口、AppCoordinator（采样循环、菜单栏、面板与设置的总协调）
├── Core/       定时调度器、环形历史缓冲、等宽格式化、设置模型、更新检查
├── Samplers/   五个指标采样器与进程列表采集
└── UI/         NSStatusItem 渲染、SwiftUI 详情面板与设置窗口
```

## 发布

```sh
scripts/release.sh 0.1.0             # 构建、签名并生成 DMG 至 dist/
scripts/release.sh 0.1.0 --publish   # 同上，并创建 tag 与 GitHub Release
```

签名策略按本机条件自动选择：Developer ID + 公证凭据 → 签名、公证并 staple；仅有 Developer ID → 签名跳过公证；仅有开发证书或无证书 → ad-hoc 签名。

配置公证凭据（需付费 Apple Developer 账号）：

```sh
xcrun notarytool store-credentials statly-notary \
    --apple-id <AppleID> --team-id <团队ID> --password <应用专用密码>
```

## 路线图

- ✅ 五个模块完整链路、进程列表、检查更新、DMG 发布流程
- ⏳ 菜单栏渲染缓存、Developer ID 签名与公证
- 📋 待办：风扇转速、GPU、电池、阈值告警、多语言、Homebrew cask

## 许可证

[MIT](LICENSE) © 2026 liusx
