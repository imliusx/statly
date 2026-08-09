import XCTest
@testable import StatlyKit

final class SamplerMathTests: XCTestCase {
    func testDelta32Normal() {
        XCTAssertEqual(SamplerMath.delta32(current: 150, previous: 100), 50)
    }

    func testDelta32WrapAround() {
        // 计数器从 UInt32.max - 9 回绕到 10：实际走了 20
        XCTAssertEqual(SamplerMath.delta32(current: 10, previous: UInt32.max - 9), 20)
    }

    func testDelta64CounterResetReturnsZero() {
        XCTAssertEqual(SamplerMath.delta64(current: 5, previous: 100), 0)
    }

    func testCPUUsage() {
        let previous = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [CPUTicks(user: 25, system: 25, idle: 50, nice: 0)]
        let usage = SamplerMath.cpuUsage(previous: previous, current: current)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage!.total, 0.5, accuracy: 0.0001)
        XCTAssertEqual(usage!.user, 0.25, accuracy: 0.0001)
        XCTAssertEqual(usage!.system, 0.25, accuracy: 0.0001)
        XCTAssertEqual(usage!.perCore, [0.5])
    }

    func testCPUUsageFirstSampleReturnsNil() {
        let current = [CPUTicks(user: 10, system: 10, idle: 10, nice: 0)]
        XCTAssertNil(SamplerMath.cpuUsage(previous: [], current: current))
    }

    func testCPUUsageCoreCountMismatchReturnsNil() {
        let previous = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [
            CPUTicks(user: 1, system: 1, idle: 1, nice: 0),
            CPUTicks(user: 1, system: 1, idle: 1, nice: 0),
        ]
        XCTAssertNil(SamplerMath.cpuUsage(previous: previous, current: current))
    }

    func testCPUUsageWithTickWrapAround() {
        let previous = [CPUTicks(user: UInt32.max - 49, system: 0, idle: 0, nice: 0)]
        let current = [CPUTicks(user: 50, system: 0, idle: 100, nice: 0)]
        let usage = SamplerMath.cpuUsage(previous: previous, current: current)
        XCTAssertNotNil(usage)
        // user 走了 100，idle 走了 100
        XCTAssertEqual(usage!.total, 0.5, accuracy: 0.0001)
    }
}
