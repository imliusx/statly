# Statly

macOS 状态栏系统监控：CPU · 内存 · 网速 · 磁盘。

**主打轻量**——只做四件事，但做到最省。无后台进程、无权限弹窗、无第三方依赖，卸载 = 删除 App + 一个 plist。

## 性能预算（发布门禁）

| 指标 | 预算 |
|------|------|
| 常驻内存 | < 35 MB |
| 平均 CPU（2s 刷新全模块） | < 0.3% |
| 每刷新周期 timer 唤醒 | 1 次（全模块合并采样） |
| 包体积 | < 10 MB |
| 后台进程 / 权限弹窗 / root | 0 |

实现上的对应约束见 [PLAN.md](PLAN.md) 的"轻量化工程规则"。

## 构建

要求 macOS 13+，Xcode 15+。

```sh
make run    # 开发运行（裸二进制，开机自启不可用）
make test   # 单元测试
make app    # 打包 dist/Statly.app（ad-hoc 签名）
```

也可以用 Xcode 直接打开 `Package.swift` 开发调试。

## 使用

- 默认**合并紧凑模式**：全部模块拼在一个状态栏图标里，间距紧凑、刘海屏友好
- 左键点击：展开详情弹窗（历史曲线、内存压力、磁盘读写等）；右键：设置 / 退出菜单
- 设置中可切换为独立图标模式（每模块一个图标，可按住 ⌘ 拖动排序）
- 样式可自由搭配：占用（圆环/文本/迷你图）× 标签（图标/竖排/文本/隐藏）

## 架构

```
Sources/StatlyKit/
├── App/        入口、AppCoordinator（采样循环、状态栏、弹窗、设置窗口的总协调）
├── Core/       调度器（单 timer 合并唤醒）、环形历史缓冲、等宽格式化、设置模型
├── Samplers/   host_processor_info / host_statistics64 / getifaddrs / IOKit
└── UI/         NSStatusItem 渲染（变了才画）、SwiftUI 弹窗与设置
```

全部指标来自用户态公开 API，无需任何特殊权限。

## 路线图

见 [PLAN.md](PLAN.md)。当前完成度：M0 脚手架 ✓ · M1 CPU/内存 ✓ · M2 网络/磁盘/图表 ✓ · M3 发布准备（进行中）。
