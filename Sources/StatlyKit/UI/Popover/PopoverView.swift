import SwiftUI
import Charts

/// 点击状态栏后的单模块详情弹窗。仅在弹窗存在期间参与渲染，关闭即随 hosting controller 释放。
struct PopoverView: View {
    @ObservedObject var store: MetricStore
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
            if let cpu = store.latest.cpu { cpuSection(cpu) } else { waitingView }
        case .memory:
            if let memory = store.latest.memory { memorySection(memory) } else { waitingView }
        case .network:
            networkSection(store.latest.network)
        case .disk:
            if let disk = store.latest.disk { diskSection(disk) } else { waitingView }
        }
    }

    private var waitingView: some View {
        Text("等待采样…")
            .foregroundStyle(.secondary)
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
            ProgressView(value: disk.usedFraction)
            Text("共 \(Format.diskFull(disk.totalCapacity)) · 读 \(Format.fullRate(disk.readPerSecond)) · 写 \(Format.fullRate(disk.writePerSecond))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("Statly")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("设置…", action: onOpenSettings)
            Button("退出", action: onQuit)
        }
        .controlSize(.small)
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
