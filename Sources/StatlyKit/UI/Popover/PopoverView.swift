import SwiftUI
import Charts

/// 点击状态栏后的单模块详情弹窗。仅在弹窗存在期间参与渲染，关闭即随 hosting controller 释放。
struct PopoverView: View {
    @ObservedObject var store: MetricStore
    @ObservedObject var topStore: TopProcessStore
    let module: ModuleID
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    @ViewBuilder
    private var content: some View {
        switch module {
        case .cpu:
            if let cpu = store.latest.cpu {
                cpuSection(cpu)
                Divider()
                topProcessSection(
                    "CPU 占用最高",
                    rows: topStore.byCPU.map { ($0.id, $0.name, String(format: "%.1f%%", $0.cpu)) }
                )
            } else {
                waitingView
            }
        case .memory:
            if let memory = store.latest.memory {
                memorySection(memory)
                Divider()
                topProcessSection(
                    "内存占用最高",
                    rows: topStore.byMemory.map { ($0.id, $0.name, Format.memoryGB($0.footprint)) }
                )
            } else {
                waitingView
            }
        case .temperature:
            if let temperature = store.latest.temperature {
                temperatureSection(temperature)
            } else if store.isTemperatureAvailable {
                waitingView
            } else {
                unavailableView
            }
        case .network:
            networkSection(store.latest.network)
        case .disk:
            if let disk = store.latest.disk { diskSection(disk) } else { waitingView }
        }
    }

    private func topProcessSection(_ title: String, rows: [(pid_t, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("统计中…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 8) {
                        Text(row.1)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(row.2)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var waitingView: some View {
        Text("等待采样…")
            .foregroundStyle(.secondary)
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("温度不可用")
                .font(.headline)
            Text("本机读不到温度传感器（多见于 Intel 机型，或系统更新改动了传感器接口）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func temperatureSection(_ temperature: TemperatureSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("温度", value: Format.temperature(temperature.celsius))
            valueChart(store.history(.temperature))
            Text("平均 \(Format.temperature(temperature.average)) · 取 \(temperature.sensorCount) 个晶粒传感器的最高值 · 每 5 秒更新")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 各模块区块

    private func cpuSection(_ cpu: CPUSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("CPU", value: Format.percent(cpu.totalUsage, padded: false))
            fractionChart(store.history(.cpuTotal))
            Text("用户 \(Format.percent(cpu.userUsage, padded: false)) · 系统 \(Format.percent(cpu.systemUsage, padded: false)) · \(cpu.perCore.count) 核")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func memorySection(_ memory: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("内存", value: "\(Format.memoryGB(memory.used)) / \(Format.memoryGB(memory.total))")
            fractionChart(store.history(.memoryUsedFraction))
            HStack(spacing: 4) {
                Circle()
                    .fill(pressureColor(memory.pressure))
                    .frame(width: 7, height: 7)
                Text("压力\(memory.pressure.displayName) · App \(Format.memoryGB(memory.app)) · 联动 \(Format.memoryGB(memory.wired)) · 压缩 \(Format.memoryGB(memory.compressed))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func networkSection(_ network: NetworkSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("网络").font(.headline)
                Spacer()
                Text("↓ \(Format.fullRate(network?.rxPerSecond ?? 0))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                Text("↑ \(Format.fullRate(network?.txPerSecond ?? 0))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green)
            }
            rateChart(rx: store.history(.networkRx), tx: store.history(.networkTx))
        }
    }

    private func diskSection(_ disk: DiskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("磁盘", value: "可用 \(Format.diskFull(disk.freeCapacity))")
            usageBar(disk.usedFraction)
            Text("共 \(Format.diskFull(disk.totalCapacity)) · 读 \(Format.fullRate(disk.readPerSecond)) · 写 \(Format.fullRate(disk.writePerSecond))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 自绘用量条（轨道 + 进度），与状态栏圆环同构。
    /// 不用 ProgressView：AppKit 控件在非活跃窗口里会被系统画成灰色，
    /// 弹窗刚弹出时窗口未成为 key，条会先灰后蓝。
    private func usageBar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(3, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Text("Statly")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            FooterIconButton(symbol: "gearshape", help: "设置…", action: onOpenSettings)
            FooterIconButton(symbol: "power", help: "退出 Statly", action: onQuit)
        }
    }

    // MARK: - 复用小件

    private func header(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
    }

    private func fractionChart(_ values: [Double]) -> some View {
        Chart(Array(values.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("时间", point.offset), y: .value("值", point.element))
                .foregroundStyle(Color.accentColor.opacity(0.15))
            LineMark(x: .value("时间", point.offset), y: .value("值", point.element))
                .foregroundStyle(Color.accentColor)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .frame(height: 44)
    }

    /// 纵轴自适应的曲线（温度等非比例数值用）。
    private func valueChart(_ values: [Double]) -> some View {
        let lower = (values.min() ?? 0) - 3
        let upper = (values.max() ?? 1) + 3
        return Chart(Array(values.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("时间", point.offset), y: .value("值", point.element))
                .foregroundStyle(Color.accentColor.opacity(0.15))
            LineMark(x: .value("时间", point.offset), y: .value("值", point.element))
                .foregroundStyle(Color.accentColor)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: lower...max(lower + 1, upper))
        .frame(height: 44)
    }

    private func rateChart(rx: [Double], tx: [Double]) -> some View {
        Chart {
            ForEach(Array(rx.enumerated()), id: \.offset) { point in
                LineMark(
                    x: .value("时间", point.offset),
                    y: .value("值", point.element),
                    series: .value("方向", "下行")
                )
                .foregroundStyle(.blue)
            }
            ForEach(Array(tx.enumerated()), id: \.offset) { point in
                LineMark(
                    x: .value("时间", point.offset),
                    y: .value("值", point.element),
                    series: .value("方向", "上行")
                )
                .foregroundStyle(.green)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 44)
    }

    private func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

/// 弹窗底部的图标按钮：无边框、悬停时显示圆角底色，工具提示补足图标缺失的文字说明。
private struct FooterIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .onHover { isHovering = $0 }
    }
}
