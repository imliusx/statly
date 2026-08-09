import SwiftUI
import AppKit

/// 设置窗口的侧边栏分区。
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case cpu
    case memory
    case network
    case disk
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .appearance: return "外观"
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .network: return "网络"
        case .disk: return "磁盘"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .cpu: return "cpu.fill"
        case .memory: return "memorychip.fill"
        case .network: return "network"
        case .disk: return "internaldrive.fill"
        case .about: return "info"
        }
    }

    /// 侧边栏图标块底色，沿用系统设置的彩色图标语汇
    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .indigo
        case .cpu: return .blue
        case .memory: return .green
        case .network: return .purple
        case .disk: return .orange
        case .about: return .secondary
        }
    }

    /// 对应的指标模块（非模块分区为 nil）
    var module: ModuleID? {
        switch self {
        case .cpu: return .cpu
        case .memory: return .memory
        case .network: return .network
        case .disk: return .disk
        default: return nil
        }
    }
}

/// 设置窗口外壳：左侧分区列表 + 右侧内容。内容本身在 SettingsDetailView，
/// 拆开是因为 NavigationSplitView 无法被 ImageRenderer 渲染，页面内容单独出来才能测。
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: MetricStore

    @State private var selection: SettingsSection

    init(settings: AppSettings, store: MetricStore, initialSection: SettingsSection = .general) {
        self.settings = settings
        self.store = store
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, id: \.self, selection: $selection) { section in
                SidebarRow(section: section)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 182, max: 230)
        } detail: {
            SettingsDetailView(section: selection, settings: settings, store: store)
                .navigationTitle(selection.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, idealWidth: 700, minHeight: 420, idealHeight: 460)
    }
}

/// 侧边栏行：彩色圆角图标块 + 标题（系统设置的视觉语汇）。
private struct SidebarRow: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(section.tint.gradient)
                .frame(width: 21, height: 21)
                .overlay(
                    Image(systemName: section.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Text(section.title)
        }
        .padding(.vertical, 1)
    }
}

/// 右侧内容页。用 .formStyle(.grouped) 得到系统设置的分组卡片外观。
struct SettingsDetailView: View {
    let section: SettingsSection
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: MetricStore

    @State private var updateOutcome: UpdateChecker.Outcome?
    @State private var isCheckingUpdate = false

    var body: some View {
        Form {
            switch section {
            case .general: generalPage
            case .appearance: appearancePage
            case .about: aboutPage
            default:
                if let module = section.module {
                    modulePage(module)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 通用

    @ViewBuilder
    private var generalPage: some View {
        Section {
            Picker("刷新间隔", selection: $settings.refreshInterval) {
                ForEach(AppSettings.allowedIntervals, id: \.self) { interval in
                    Text("\(Int(interval)) 秒").tag(interval)
                }
            }
        } header: {
            Text("采样")
        } footer: {
            footnote("2 秒是显示效果与功耗的平衡点。所有模块共用一次采样唤醒，锁屏或息屏时自动暂停。")
        }

        Section {
            Toggle("随系统启动", isOn: launchAtLoginBinding)
                .disabled(!settings.canToggleLaunchAtLogin)
        } header: {
            Text("启动")
        } footer: {
            if !settings.canToggleLaunchAtLogin {
                footnote("以 .app 方式运行时可用（make app）。")
            }
        }
    }

    // MARK: - 外观

    @ViewBuilder
    private var appearancePage: some View {
        Section {
            Picker("占用样式", selection: $settings.statusStyle) {
                ForEach(StatusStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            Picker("标签", selection: $settings.labelStyle) {
                ForEach(LabelStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } header: {
            Text("状态栏")
        } footer: {
            footnote("样式统一应用到所有模块。迷你图适用于 CPU 与内存，磁盘占用几乎不变会显示为圆环。")
        }

        Section {
            previewStrip(ModuleID.allCases.filter(settings.enabledModules.contains))
        } header: {
            Text("预览")
        } footer: {
            footnote("精确数值可悬停图标查看，或点击图标打开详情。")
        }
    }

    // MARK: - 模块

    @ViewBuilder
    private func modulePage(_ module: ModuleID) -> some View {
        let isLastEnabled = settings.enabledModules == [module]

        Section {
            Toggle("在状态栏显示", isOn: moduleBinding(module))
                .disabled(isLastEnabled)
        } footer: {
            if isLastEnabled {
                footnote("至少需要保留一个模块。")
            }
        }

        if settings.enabledModules.contains(module) {
            Section {
                previewStrip([module])
            } header: {
                Text("预览")
            }
        }

        Section {
            ForEach(Array(moduleFacts(module).enumerated()), id: \.offset) { _, fact in
                LabeledContent(fact.0) {
                    Text(fact.1)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("显示内容")
        }
    }

    /// (位置, 内容说明)
    private func moduleFacts(_ module: ModuleID) -> [(String, String)] {
        switch module {
        case .cpu:
            return [
                ("状态栏", "总占用率"),
                ("悬停", "用户态 / 系统态占比与核心数"),
                ("详情", "占用曲线、CPU 占用最高的 5 个进程"),
            ]
        case .memory:
            return [
                ("状态栏", "已用内存占比"),
                ("悬停", "已用 / 总量与内存压力"),
                ("详情", "占用曲线、App / 联动 / 已压缩明细、内存占用最高的 5 个进程"),
            ]
        case .network:
            return [
                ("状态栏", "实时上行、下行速率（两行）"),
                ("悬停", "完整速率"),
                ("详情", "上下行速率曲线"),
            ]
        case .disk:
            return [
                ("状态栏", "已用容量占比"),
                ("悬停", "已用占比与可用容量"),
                ("详情", "容量用量条、读写速率"),
            ]
        }
    }

    // MARK: - 关于

    @ViewBuilder
    private var aboutPage: some View {
        Section {
            HStack(spacing: 14) {
                // 用 NSApplication.shared 而非 NSApp：后者在未初始化 NSApplication 的
                // 进程里是 nil，取图标会崩
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 60, height: 60)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Statly").font(.title2).bold()
                    Text("版本 \(UpdateChecker.currentVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("菜单栏系统监控：只做四件事，但做到最省。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }

        Section {
            LabeledContent("检查更新") {
                HStack(spacing: 8) {
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                    }
                    Button("检查", action: checkForUpdates)
                        .disabled(isCheckingUpdate)
                }
            }
            LabeledContent("项目主页") {
                Link("GitHub", destination: UpdateChecker.repositoryURL)
            }
        } footer: {
            footnote("无后台进程、无权限申请、零第三方依赖。全部指标取自用户态公开 API。")
        }
        .alert("检查更新", isPresented: updateAlertBinding) {
            if case .newVersion = updateOutcome {
                Button("前往下载") { NSWorkspace.shared.open(UpdateChecker.releasesPageURL) }
                Button("稍后", role: .cancel) {}
            } else {
                Button("好", role: .cancel) {}
            }
        } message: {
            Text(updateMessage)
        }
    }

    private func checkForUpdates() {
        isCheckingUpdate = true
        UpdateChecker.check { outcome in
            isCheckingUpdate = false
            updateOutcome = outcome
        }
    }

    private var updateAlertBinding: Binding<Bool> {
        Binding(
            get: { updateOutcome != nil },
            set: { if !$0 { updateOutcome = nil } }
        )
    }

    private var updateMessage: String {
        switch updateOutcome {
        case .upToDate(let current): return "已是最新版本（\(current)）。"
        case .newVersion(let version): return "发现新版本 \(version)，当前 \(UpdateChecker.currentVersion)。"
        case .noReleases: return "仓库还没有发布过 Release。"
        case .failed(let reason): return "检查失败：\(reason)"
        case .none: return ""
        }
    }

    // MARK: - 复用小件

    /// 分组脚注。macOS 的 grouped Form 默认让 footer 靠右且多行右对齐，
    /// 这里同时拉回块对齐与行内对齐，以对齐系统设置的观感。
    private func footnote(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 用真实渲染器画出的状态栏预览，样式改动即时可见。
    private func previewStrip(_ modules: [ModuleID]) -> some View {
        HStack(spacing: 18) {
            ForEach(modules, id: \.self) { module in
                statusPreview(module)
            }
            if modules.isEmpty {
                Text("未启用任何模块")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 26)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusPreview(_ module: ModuleID) -> some View {
        let output = StatusRenderer.render(
            module: module,
            snapshot: store.latest,
            style: settings.statusStyle,
            labelStyle: settings.labelStyle,
            history: previewHistory(module)
        )
        switch output.content {
        case .text(let text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
        case .image(let image):
            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundStyle(.primary)
        }
    }

    private func previewHistory(_ module: ModuleID) -> [Double] {
        guard settings.statusStyle == .graph else { return [] }
        switch module {
        case .cpu: return store.history(.cpuTotal)
        case .memory: return store.history(.memoryUsedFraction)
        default: return []
        }
    }

    // MARK: - 绑定

    private func moduleBinding(_ module: ModuleID) -> Binding<Bool> {
        Binding(
            get: { settings.enabledModules.contains(module) },
            set: { enabled in
                var modules = settings.enabledModules
                if enabled {
                    modules.insert(module)
                } else {
                    modules.remove(module)
                }
                guard !modules.isEmpty else { return }
                settings.enabledModules = modules
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { settings.launchAtLogin = $0 }
        )
    }
}
