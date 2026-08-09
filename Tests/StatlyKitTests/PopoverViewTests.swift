import XCTest
import SwiftUI
@testable import StatlyKit

/// 把四个模块的弹窗真实渲染一遍（含 Swift Charts），覆盖"点击某模块弹窗崩溃"这一类问题。
/// 分别测空数据（刚启动、尚无采样）与有数据两种状态。
@MainActor
final class PopoverViewTests: XCTestCase {
    private func render(module: ModuleID, store: MetricStore, top: TopProcessStore) {
        XCTAssertNotNil(image(module: module, store: store, top: top), "\(module.rawValue) 弹窗渲染失败")
    }

    private func image(module: ModuleID, store: MetricStore, top: TopProcessStore) -> Data? {
        let view = PopoverView(
            store: store,
            topStore: top,
            module: module,
            onOpenSettings: {},
            onQuit: {}
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage?.tiffRepresentation
    }

    /// 磁盘用量条必须真的画出来：早前用的 ProgressView 是 AppKit 控件包装，
    /// 在非活跃窗口里会变灰、且完全不参与 SwiftUI 渲染，占用高低画出来一模一样。
    func testDiskUsageBarReflectsUsage() {
        func snapshot(free: UInt64) -> SystemSnapshot {
            SystemSnapshot(disk: DiskSnapshot(
                totalCapacity: 1_000_000_000_000,
                freeCapacity: free,
                readPerSecond: 0,
                writePerSecond: 0
            ))
        }
        let top = TopProcessStore()

        let nearlyFull = MetricStore()
        nearlyFull.apply(snapshot(free: 50_000_000_000))
        let nearlyEmpty = MetricStore()
        nearlyEmpty.apply(snapshot(free: 950_000_000_000))

        guard let a = image(module: .disk, store: nearlyFull, top: top),
              let b = image(module: .disk, store: nearlyEmpty, top: top) else {
            return XCTFail("磁盘弹窗渲染失败")
        }
        XCTAssertNotEqual(a, b, "占用 95% 与 5% 应渲染出不同的用量条")
    }

    func testRendersAllModulesWithoutData() {
        let store = MetricStore()
        let top = TopProcessStore()
        for module in ModuleID.allCases {
            render(module: module, store: store, top: top)
        }
    }

    func testRendersAllModulesWithData() {
        let store = MetricStore()
        let top = TopProcessStore()
        // 多灌几轮，让历史曲线有内容
        for index in 0..<5 {
            store.apply(SystemSnapshot(
                cpu: CPUSnapshot(
                    totalUsage: 0.1 * Double(index),
                    userUsage: 0.05 * Double(index),
                    systemUsage: 0.05 * Double(index),
                    perCore: [0.2, 0.3]
                ),
                memory: MemorySnapshot(
                    total: 17_179_869_184,
                    used: 8_589_934_592,
                    app: 4_294_967_296,
                    wired: 2_147_483_648,
                    compressed: 2_147_483_648,
                    pressure: .normal
                ),
                network: NetworkSnapshot(rxPerSecond: 1024 * Double(index), txPerSecond: 512),
                disk: DiskSnapshot(
                    totalCapacity: 500_000_000_000,
                    freeCapacity: 250_000_000_000,
                    readPerSecond: 1_048_576,
                    writePerSecond: 524_288
                )
            ))
        }
        for module in ModuleID.allCases {
            render(module: module, store: store, top: top)
        }
    }

    /// 全零数据（网速静止时的常见情形）也不能让图表崩溃。
    func testRendersWithAllZeroSeries() {
        let store = MetricStore()
        let top = TopProcessStore()
        for _ in 0..<3 {
            store.apply(SystemSnapshot(
                cpu: CPUSnapshot(totalUsage: 0, userUsage: 0, systemUsage: 0, perCore: [0]),
                memory: MemorySnapshot(total: 1, used: 0, app: 0, wired: 0, compressed: 0, pressure: .critical),
                network: NetworkSnapshot(rxPerSecond: 0, txPerSecond: 0),
                disk: DiskSnapshot(totalCapacity: 0, freeCapacity: 0, readPerSecond: 0, writePerSecond: 0)
            ))
        }
        for module in ModuleID.allCases {
            render(module: module, store: store, top: top)
        }
    }
}
