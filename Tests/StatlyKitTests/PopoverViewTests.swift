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

    /// 温度曲线的填充不能溢出图表边界盖住下方内容。
    ///
    /// 做法：两个仓库的最新读数完全相同、只有历史曲线不同，那么除图表以外的
    /// 一切（说明文字、页脚）都应逐像素一致。若面积图溢出，改变历史就会污染下方区域。
    func testTemperatureChartDoesNotBleedOverContentBelow() {
        func snapshot(_ celsius: Double) -> SystemSnapshot {
            SystemSnapshot(temperature: TemperatureSnapshot(celsius: celsius, average: 40, sensorCount: 4))
        }
        let flat = MetricStore()
        for _ in 0..<12 { flat.apply(snapshot(40)) }

        let varying = MetricStore()
        for step in 0..<11 { varying.apply(snapshot(30 + Double(step) * 3)) }
        varying.apply(snapshot(40))   // 收尾于同一读数，头部与文字因此完全一致

        let top = TopProcessStore()
        guard let a = image(module: .temperature, store: flat, top: top),
              let b = image(module: .temperature, store: varying, top: top) else {
            return XCTFail("温度弹窗渲染失败")
        }
        XCTAssertNotEqual(a, b, "历史不同，曲线本身应当不同（否则本用例失去意义）")

        guard let repA = NSBitmapImageRep(data: a), let repB = NSBitmapImageRep(data: b) else {
            return XCTFail("位图解析失败")
        }
        XCTAssertEqual(repA.pixelsHigh, repB.pixelsHigh)
        // 图表下方（下半部）必须逐像素一致
        var mismatches = 0
        let start = repA.pixelsHigh / 2
        for y in start..<repA.pixelsHigh {
            for x in stride(from: 0, to: repA.pixelsWide, by: 3) {
                var pa = [Int](repeating: 0, count: 5), pb = [Int](repeating: 0, count: 5)
                repA.getPixel(&pa, atX: x, y: y)
                repB.getPixel(&pb, atX: x, y: y)
                if pa != pb { mismatches += 1 }
            }
        }
        XCTAssertEqual(mismatches, 0, "图表下方有 \(mismatches) 个像素被曲线填充污染")
    }
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
