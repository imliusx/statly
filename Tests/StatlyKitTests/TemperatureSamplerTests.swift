import XCTest
@testable import StatlyKit

final class TemperatureSamplerTests: XCTestCase {

    // MARK: - 传感器筛选（纯函数，可脱离硬件测试）

    private func select(_ names: [String]) -> [String] {
        let services = names.map { $0 as NSString as AnyObject }
        let selected = HIDTemperatureSensors.selectSensors(services) { service in
            (service as? NSString) as String? ?? ""
        }
        return selected.map { ($0 as? NSString) as String? ?? "" }
    }

    /// tcal 是校准参考（读数恒定偏高），电池与闪存温度属于别的部件，都不该混进 CPU 温度。
    func testExcludesCalibrationBatteryAndStorageSensors() {
        let picked = select([
            "PMU tcal", "PMU2 tcal", "gas gauge battery", "NAND CH0 temp",
            "PMU tdie1", "PMU tdie2",
        ])
        XCTAssertEqual(Set(picked), ["PMU tdie1", "PMU tdie2"])
    }

    /// 有晶粒传感器时只取晶粒温度，忽略 tdev 这类器件温度。
    func testPrefersDieSensorsOverDeviceSensors() {
        let picked = select(["PMU tdev1", "PMU tdev2", "PMU tdie1"])
        XCTAssertEqual(picked, ["PMU tdie1"])
    }

    /// 传感器很多时要抽样封顶，否则单次采样开销会超出性能预算。
    func testCapsSensorCountAndSpreadsAcrossPool() {
        let picked = select((1...16).map { "PMU tdie\($0)" })
        XCTAssertEqual(picked.count, 4, "应封顶到 4 个")
        XCTAssertEqual(Set(picked).count, 4, "不应重复取同一个")
    }

    /// 没有晶粒传感器的机型（如 Intel）回落到其余可用传感器。
    func testFallsBackWhenNoDieSensors() {
        let picked = select(["TC0P", "TC1P", "PMU tcal"])
        XCTAssertEqual(Set(picked), ["TC0P", "TC1P"])
    }

    func testReturnsEmptyWhenEverythingExcluded() {
        XCTAssertTrue(select(["PMU tcal", "gas gauge battery"]).isEmpty)
    }

    // MARK: - 温度到圆环比例

    func testHeatFractionMapping() {
        XCTAssertEqual(TemperatureSnapshot(celsius: 30, average: 30, sensorCount: 1).heatFraction, 0, accuracy: 0.001)
        XCTAssertEqual(TemperatureSnapshot(celsius: 65, average: 65, sensorCount: 1).heatFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(TemperatureSnapshot(celsius: 100, average: 100, sensorCount: 1).heatFraction, 1, accuracy: 0.001)
        // 超出范围要夹紧，圆环不能画过头或为负
        XCTAssertEqual(TemperatureSnapshot(celsius: 5, average: 5, sensorCount: 1).heatFraction, 0)
        XCTAssertEqual(TemperatureSnapshot(celsius: 130, average: 130, sensorCount: 1).heatFraction, 1)
    }

    // MARK: - 真机读取

    func testLiveReadingIsPlausible() throws {
        let sampler = TemperatureSampler()
        try XCTSkipUnless(sampler.isAvailable, "本机读不到温度传感器")

        guard let snapshot = sampler.sample() else {
            return XCTFail("传感器可用却读不出数值")
        }
        XCTAssertGreaterThan(snapshot.celsius, 10, "读数低得不合常理")
        XCTAssertLessThan(snapshot.celsius, 120, "读数高得不合常理")
        XCTAssertGreaterThan(snapshot.sensorCount, 0)
        XCTAssertLessThanOrEqual(snapshot.average, snapshot.celsius + 0.001, "平均值不应高于最高值")
    }

    /// 温度是慢变量，5 秒内的重复调用必须走缓存 —— 否则常驻 CPU 开销会翻数倍。
    func testRepeatedSamplesAreThrottled() throws {
        let sampler = TemperatureSampler()
        try XCTSkipUnless(sampler.isAvailable, "本机读不到温度传感器")
        _ = sampler.sample()

        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<20 { _ = sampler.sample() }
        let perCall = (ProcessInfo.processInfo.systemUptime - start) / 20 * 1000
        XCTAssertLessThan(perCall, 0.1, "缓存期内的调用应几乎零成本，实测 \(perCall) ms")
    }

    /// 单次真实读取的耗时上限：守住"只采样少量传感器"这个前提。
    func testSingleReadStaysWithinBudget() throws {
        let sampler = TemperatureSampler()
        try XCTSkipUnless(sampler.isAvailable, "本机读不到温度传感器")

        var slowest: Double = 0
        for _ in 0..<3 {
            sampler.resetBaseline()
            let start = ProcessInfo.processInfo.systemUptime
            _ = sampler.sample()
            slowest = max(slowest, (ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        // 实测 4 个传感器约 3.6ms；放宽到 15ms 以容忍机器差异，
        // 但足以拦住"退回全量采样"（16 个传感器约 17ms）这类回归
        XCTAssertLessThan(slowest, 15, "单次读取 \(slowest) ms，超出预算")
    }
}
