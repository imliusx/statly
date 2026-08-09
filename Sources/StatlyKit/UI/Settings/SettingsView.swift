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
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .about: return "info.circle"
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
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 165, max: 220)
        } detail: {
            ScrollView {
                SettingsDetailView(section: selection, settings: settings, store: store)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            }
            .navigationTitle(selection.title)
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 400, idealHeight: 430)
    }
}

/// 右侧内容页。
struct SettingsDetailView: View {
    let section: SettingsSection
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: MetricStore

    @State private var updateOutcome: UpdateChecker.Outcome?
    @State private var isCheckingUpdate = false

    var body: some View {
        detail
    }

    @ViewBuilder
    private var detail: some View {
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

    // MARK: - 通用

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingGroup("采样") {
                Picker("刷新间隔", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.allowedIntervals, id: \.self) { interval in
                        Text("\(Int(interval)) 秒").tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                caption("2 秒是显示效果与功耗的平衡点。所有模块共用一次采样唤醒，锁屏或息屏时自动暂停。")
            }

            settingGroup("启动") {
                Toggle("随系统启动", isOn: launchAtLoginBinding)
                    .disabled(!settings.canToggleLaunchAtLogin)
                if !settings.canToggleLaunchAtLogin {
                    caption("以 .app 方式运行时可用（make app）。")
                }
            }
        }
    }

    // MARK: - 外观

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingGroup("占用样式") {
                Picker("占用样式", selection: $settings.statusStyle) {
                    ForEach(StatusStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                caption("迷你图适用于 CPU 与内存；磁盘占用几乎不变，会显示为圆环。")
            }

            settingGroup("标签") {
                Picker("标签", selection: $settings.labelStyle) {
                    ForEach(LabelStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                caption("样式统一应用到所有模块。精确数值可悬停图标查看。")
            }

            settingGroup("状态栏预览") {
                previewStrip(ModuleID.allCases.filter(settings.enabledModules.contains))
            }
        }
    }

    // MARK: - 模块

    private func modulePage(_ module: ModuleID) -> some View {
        let isLastEnabled = settings.enabledModules == [module]
        return VStack(alignment: .leading, spacing: 20) {
            settingGroup("显示") {
                Toggle("在状态栏显示", isOn: moduleBinding(module))
                    .disabled(isLastEnabled)
                if isLastEnabled {
                    caption("至少需要保留一个模块。")
                }
            }

            if settings.enabledModules.contains(module) {
                settingGroup("状态栏预览") {
                    previewStrip([module])
                }
            }

            settingGroup("显示内容") {
                ForEach(Array(moduleFacts(module).enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(fact.0)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .leading)
                        Text(fact.1)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
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

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                // 用 NSApplication.shared 而非 NSApp：后者在未初始化 NSApplication 的
                // 进程里是 nil，取图标会崩
                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
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
            }

            settingGroup("更新") {
                HStack(spacing: 10) {
                    Button("检查更新…", action: checkForUpdates)
                        .disabled(isCheckingUpdate)
                    if isCheckingUpdate {
                        ProgressView().controlSize(.small)
                    }
                }
                Link("GitHub 仓库", destination: UpdateChecker.repositoryURL)
                    .font(.callout)
            }

            settingGroup("资源占用") {
                caption("无后台进程、无权限申请、零第三方依赖。全部指标取自用户态公开 API。")
            }
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

    private func settingGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 用真实渲染器画出的状态栏预览，样式改动即时可见。
    private func previewStrip(_ modules: [ModuleID]) -> some View {
        HStack(spacing: 16) {
            ForEach(modules, id: \.self) { module in
                statusPreview(module)
            }
            if modules.isEmpty {
                Text("未启用任何模块")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.06))
        )
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
