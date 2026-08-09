import XCTest
@testable import StatlyKit

final class TopProcessStoreTests: XCTestCase {
    /// 这个用例直接执行崩溃过的 libproc 互操作：若 proc_pid_rusage 的缓冲区
    /// 传法再次写错，内核会写坏栈并让测试进程 SIGABRT，测试即失败。
    func testReadProcessesDoesNotSmashStack() {
        let samples = TopProcessStore.readProcesses()
        XCTAssertFalse(samples.isEmpty, "至少应能读到当前进程")

        guard let mine = samples.first(where: { $0.pid == getpid() }) else {
            return XCTFail("结果里应包含测试进程自身")
        }
        // 自身足迹是个合理的正值（>1MB、<64GB），说明结构体确实被正确填充
        XCTAssertGreaterThan(mine.footprint, 1_000_000)
        XCTAssertLessThan(mine.footprint, 64_000_000_000)
        XCTAssertGreaterThan(mine.cpuTimeNs, 0)
    }

    /// 连续两次读取：累计 CPU 时间单调不减，可用于差值计算。
    func testCPUTimeIsMonotonic() {
        let first = TopProcessStore.readProcesses().first { $0.pid == getpid() }
        var sink: Double = 0
        for i in 0..<200_000 { sink += Double(i).squareRoot() }
        XCTAssertGreaterThan(sink, 0)
        let second = TopProcessStore.readProcesses().first { $0.pid == getpid() }

        guard let first, let second else { return XCTFail("未读到自身进程") }
        XCTAssertGreaterThanOrEqual(second.cpuTimeNs, first.cpuTimeNs)
    }

    /// 走完整的定时采样链路（start → 后台采样 → 主线程发布 → stop）。
    func testLiveSamplingPublishesTopLists() {
        let store = TopProcessStore()
        let expectation = expectation(description: "收到 Top 进程数据")
        store.start(interval: 0.3)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            XCTAssertFalse(store.byMemory.isEmpty, "内存榜应有数据")
            XCTAssertFalse(store.byCPU.isEmpty, "第二次采样后 CPU 榜应有数据")
            XCTAssertLessThanOrEqual(store.byMemory.count, 5)
            store.stop()
            XCTAssertTrue(store.byCPU.isEmpty, "停止后应清空状态")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
