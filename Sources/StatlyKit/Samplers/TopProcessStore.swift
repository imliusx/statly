import Foundation
import Darwin

public struct TopProcess: Identifiable, Sendable {
    public let id: pid_t
    public let name: String
    /// CPU 占用百分比（0–100×核数）
    public let cpu: Double
    /// 物理内存足迹（字节，与活动监视器"内存"列同口径）
    public let footprint: UInt64
}

/// Top 进程采样（轻量化守则"按需分级"：只在弹窗打开期间运行自己的定时器，
/// 关闭即停止并清空全部状态，不进常驻路径）。
public final class TopProcessStore: ObservableObject {
    @Published public private(set) var byCPU: [TopProcess] = []
    @Published public private(set) var byMemory: [TopProcess] = []

    private let queue = DispatchQueue(label: "statly.top-processes", qos: .utility)
    private var timer: DispatchSourceTimer?
    /// 仅在采样队列上访问
    private var previousTimes: [pid_t: UInt64] = [:]
    private var previousStamp: TimeInterval = 0
    private var nameCache: [pid_t: String] = [:]

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init() {}

    public func start(interval: TimeInterval) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.previousTimes = [:]
            self?.previousStamp = 0
            self?.nameCache = [:]
        }
        byCPU = []
        byMemory = []
    }

    // MARK: - 采样（libproc，无需任何权限）

    private func sample() {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard filled > 0 else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousStamp > 0 ? now - previousStamp : 0

        var entries: [(pid: pid_t, cpu: Double, footprint: UInt64)] = []
        var currentTimes: [pid_t: UInt64] = [:]
        currentTimes.reserveCapacity(Int(filled))

        for index in 0..<Int(min(filled, Int32(pids.count))) {
            let pid = pids[index]
            guard pid > 0 else { continue }

            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
                var raw: rusage_info_t? = UnsafeMutableRawPointer(pointer)
                return proc_pid_rusage(pid, RUSAGE_INFO_V4, &raw)
            }
            guard result == 0 else { continue }

            let totalNs = Self.machToNs(info.ri_user_time &+ info.ri_system_time)
            currentTimes[pid] = totalNs

            var cpu: Double = 0
            if elapsed > 0, let previous = previousTimes[pid], totalNs >= previous {
                cpu = Double(totalNs - previous) / (elapsed * 1_000_000_000) * 100
            }
            entries.append((pid, cpu, info.ri_phys_footprint))
        }

        let hasBaseline = previousStamp > 0
        previousTimes = currentTimes
        previousStamp = now

        let topCPU: [TopProcess] = hasBaseline
            ? entries.sorted { $0.cpu > $1.cpu }.prefix(5).map {
                TopProcess(id: $0.pid, name: name(for: $0.pid), cpu: $0.cpu, footprint: $0.footprint)
            }
            : []
        let topMemory: [TopProcess] = entries.sorted { $0.footprint > $1.footprint }.prefix(5).map {
            TopProcess(id: $0.pid, name: name(for: $0.pid), cpu: $0.cpu, footprint: $0.footprint)
        }

        // 名字缓存只保留活着的进程
        nameCache = nameCache.filter { currentTimes[$0.key] != nil }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer != nil else { return }
            if hasBaseline { self.byCPU = topCPU }
            self.byMemory = topMemory
        }
    }

    private func name(for pid: pid_t) -> String {
        if let cached = nameCache[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: 4096)
        let resolved: String
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            resolved = URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
        } else {
            var nameBuffer = [CChar](repeating: 0, count: 64)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let short = String(cString: nameBuffer)
            resolved = short.isEmpty ? "pid \(pid)" : short
        }
        nameCache[pid] = resolved
        return resolved
    }

    private static func machToNs(_ value: UInt64) -> UInt64 {
        value * UInt64(timebase.numer) / UInt64(timebase.denom)
    }
}
