import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("显示模块") {
                ForEach(ModuleID.allCases, id: \.self) { module in
                    Toggle(module.displayName, isOn: moduleBinding(module))
                }
                Text("至少保留一个模块。模块图标可按住 ⌘ 拖动排序。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("刷新频率") {
                Picker("采样间隔", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.allowedIntervals, id: \.self) { interval in
                        Text("\(Int(interval)) 秒").tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                Text("2 秒是显示效果与功耗的平衡点。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("状态栏样式") {
                Toggle("合并为单个图标", isOn: $settings.mergeModules)
                Picker("占用样式", selection: $settings.statusStyle) {
                    ForEach(StatusStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Picker("标签", selection: $settings.labelStyle) {
                    ForEach(LabelStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text("合并模式间距更紧凑（推荐，刘海屏友好）；关闭后每个模块是独立图标，可 ⌘ 拖动单独排序。精确数值可悬停或点击图标查看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("通用") {
                Toggle("随系统启动", isOn: launchAtLoginBinding)
                    .disabled(!settings.canToggleLaunchAtLogin)
                if !settings.canToggleLaunchAtLogin {
                    Text("以 .app 方式运行时可用（make app）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

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
