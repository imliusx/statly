<div align="center">
  <img src="docs/icon.png" width="128" alt="Statly">
  <h1>Statly</h1>
  <p><b>面向 macOS 的轻量系统监控工具</b></p>
  <p>
    <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
    <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
    <img src="https://img.shields.io/badge/体积-0.65%20MB-4c1" alt="体积 0.65 MB">
    <img src="https://img.shields.io/badge/依赖-0-4c1" alt="零依赖">
  </p>
</div>

Statly 是一款面向 macOS 用户的轻量化系统监控工具，使用 Swift 原生开发，常驻菜单栏实时显示 CPU、内存、温度、网络速率与磁盘五项指标，点击任一图标即可展开对应模块的详细数据。

项目以资源占用为首要约束进行设计：菜单栏内容由 AppKit 直接离屏绘制，SwiftUI 仅用于按需打开的详情面板与设置窗口，关闭即释放；全程单进程运行，不依赖任何第三方库，安装包体积 0.65 MB，无后台守护进程，无需申请任何系统权限。

![状态栏与详情弹窗](docs/statusbar.jpg)

## 功能特点

**模块化设计** — 五个指标各占一个独立的菜单栏图标，可单独启用或停用，按住 ⌘ 拖动调整顺序，位置由系统持久化保存。

**菜单栏显示** — 占用类指标以圆环配合百分比呈现，圆环角度与读数严格对应；网络速率以上下行双行展示。数值采用等宽字体并按最大宽度预留空间，避免数值变化引起菜单栏布局抖动。

**样式配置** — 占用样式（圆环+百分比 / 纯文本）与标签样式（图标 / 竖排 / 横排文本 / 隐藏）可自由组合，统一应用于全部模块，并在设置窗口内实时预览。

**详情面板** — 展开后显示该模块的历史曲线。CPU 与内存模块附带占用最高的 5 个进程列表；内存模块显示内存压力状态及 App / 联动 / 已压缩分项；磁盘模块显示容量用量条与读写速率。

**悬停提示** — 圆环模式下将指针停留于图标即可查看精确数值与完整速率，无需展开面板。

**系统适配** — 菜单栏图标以模板图渲染，自动适配深色与浅色外观；设置窗口采用系统分组卡片与毛玻璃材质；界面为简体中文。

**低开销实现** — 全部模块共享一次定时唤醒；渲染结果未发生变化时不触发菜单栏重绘；锁屏或显示器休眠期间暂停采样；进程列表仅在详情面板打开期间采集。

**无残留** — 不显示 Dock 图标，不安装登录项守护进程，除手动检查更新外不产生网络请求。卸载仅需删除应用与一个配置文件。

## 安装

在 [Releases](https://github.com/imliusx/statly/releases) 页面下载 DMG，将 Statly 拖入「应用程序」文件夹。系统要求 **macOS 13 及以上**。

> 当前版本未经 Apple 公证，首次打开需 **右键点击应用 → 打开 → 再次确认**，
> 或在终端执行 `xattr -d com.apple.quarantine /Applications/Statly.app`。

卸载：

```sh
rm -rf /Applications/Statly.app
defaults delete com.statly.app
```

## 使用

| 操作 | 效果 |
|------|------|
| 左键点击某个图标 | 展开**该模块**的详情面板 |
| 悬停在图标上 | 气泡提示精确数值 |
| 右键任一图标 | 设置 / 关于 / 检查更新 / 退出 |
| ⌘ + 拖动 | 调整图标顺序 |

各模块显示内容：

| 模块 | 菜单栏 | 详情面板 |
|------|--------|----------|
| CPU | 总占用率 | 占用曲线、CPU 占用最高的 5 个进程 |
| 内存 | 已用占比 | 占用曲线、App / 联动 / 已压缩分项、内存占用最高的 5 个进程 |
| 温度 | 最高晶粒温度 | 温度曲线、平均值与传感器数量 |
| 网络 | 实时上下行速率 | 上下行速率曲线 |
| 磁盘 | 已用容量占比 | 容量用量条、读写速率 |

## 设置

设置窗口按模块划分侧边栏分区。样式调整可在「预览」区域实时查看效果。采样间隔提供 1 / 2 / 5 秒三档，默认 2 秒，为显示效果与功耗的平衡取值。开机自启基于系统的 `SMAppService` 实现，不安装额外的登录项守护进程。

![设置窗口](docs/settings.jpg)

## 性能

以下均为实测数据（Apple Silicon，五模块全部启用，2 秒采样间隔）：

| 指标 | 目标 | 实测 |
|------|------|------|
| 安装包体积 | < 10 MB | **0.65 MB** |
| 常驻内存（面板关闭时 RSS） | < 35 MB | **32 MB** |
| 每采样周期 timer 唤醒次数 | 1 次 | **1 次**（全模块合并采样） |
| 后台进程 / 权限申请 / root | 0 | **0** |
| 平均 CPU 占用 | < 0.3% | 0.48%（未达标，优化中） |

对应的实现约束：

- **合并唤醒**：全部模块共享一个 `DispatchSourceTimer`，单次唤醒完成所有指标采集。定时器唤醒次数对功耗的影响大于单次唤醒的计算量。
- **差异更新**：格式化结果与上一周期相同时，完全跳过 `NSStatusItem` 调用。
- **不可见时暂停**：锁屏与显示器休眠期间停止采样，恢复后重置基线，避免出现速率尖峰。
- **按需采集**：进程列表仅在详情面板打开期间运行独立定时器，面板关闭即停止并清空状态。
- **温度独立节流**：温度变化缓慢，固定 5 秒采集一次，且仅读取 4 个传感器。实测该子集的最高值与全量读取平均相差 0.01°C，单次成本由 16.7 ms 降至 3.6 ms。

CPU 占用当前超出目标值，瓶颈位于菜单栏图像的离屏绘制，开销随采样频率与启用模块数线性增长，计划通过渲染结果缓存解决。

## 数据来源

除温度外，全部指标均通过用户态公开 API 获取，不需要任何特殊权限：

| 指标 | API |
|------|-----|
| CPU | `host_processor_info`（每核 tick 差值） |
| 内存 | `host_statistics64`；内存压力使用 `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` 事件驱动 |
| 网络速率 | `getifaddrs`（按接口计算差值，处理 32 位计数器回绕） |
| 磁盘 | `URL.resourceValues`（与 Finder 同口径）与 IOKit `IOBlockStorageDriver` |
| 进程列表 | libproc（`proc_listallpids` 与 `proc_pid_rusage`） |
| 温度 | `IOHIDEventSystemClient`（**私有接口**） |

温度在 macOS 上没有公开 API。实现中通过 `dlsym` 动态解析符号，解析失败或读取不到数据时该模块自动降级为「不可用」，不影响其余模块运行。由于使用了私有接口，本项目仅采用直接分发方式，不上架 App Store。

## 构建

环境要求 macOS 13+、Xcode 15+；生成 Xcode 工程需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```sh
make run        # 开发运行（SPM 可执行文件，迭代最快；此模式下开机自启不可用）
make xcodeproj  # 生成 Statly.xcodeproj，用于在 Xcode 中调试完整应用
make app        # Release 构建至 dist/Statly.app
```

`project.yml` 为 Xcode 工程的唯一事实来源，生成的 `.xcodeproj` 不纳入版本控制；`Package.swift` 用于快速开发运行。

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

签名与公证根据本机具备的条件自动选择策略，脚本无需修改：

| 本机条件 | 结果 |
|---|---|
| Developer ID 证书 + notarytool 凭据 | 正式签名、公证并 staple，用户可直接双击打开 |
| 具备 Developer ID 证书，未配置公证凭据 | 正式签名，跳过公证 |
| 仅有开发证书或无证书 | ad-hoc 签名，首次打开需右键 → 打开 |

配置公证凭据（需付费 Apple Developer 账号）：

```sh
xcrun notarytool store-credentials statly-notary \
    --apple-id <AppleID> --team-id <团队ID> --password <应用专用密码>
```

## 路线图

- ✅ 五个模块完整链路：采样 → 菜单栏 → 详情面板 → 设置
- ✅ 进程列表、检查更新、DMG 发布流程
- ⏳ 菜单栏渲染缓存，将 CPU 占用降至 0.3% 目标以内
- ⏳ Developer ID 签名与公证
- 📋 待办：风扇转速、GPU、电池、阈值告警、多语言、Homebrew cask
