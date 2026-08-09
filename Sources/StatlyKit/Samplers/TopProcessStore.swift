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

/// 单个进程的原始采样值。
struct ProcessSample {
    let pid: pid_t
    /// 累计 CPU 时间（纳秒，user + system）
    let cpuTimeNs: UInt64
    /// 物理内存足迹（字节）
    let footprint: UInt64
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

    // MARK: - 进程读取（libproc，无需任何权限）

    /// 读取所有可访问进程的累计 CPU 时间与内存足迹。
    ///
    /// proc_pid_rusage 的第三个参数虽然声明为 `rusage_info_t *`（即 `void **`），
    /// 但内核把它当作**目标结构体的地址**直接写入，所以必须传结构体自身的地址
    /// （C 里的写法是 `(rusage_info_t *)&info`）。若传一个指针变量的地址，内核会把
    /// 整个结构体写进那 8 字节里造成栈溢出。
    ///
    /// 非 root 运行时对其他用户/系统进程返回 EPERM，这些进程被跳过。
    static func readProcesses() -> [ProcessSample] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard filled > 0 else { return [] }

        var samples: [ProcessSample] = []
        samples.reserveCapacity(Int(filled))
        for index in 0..<Int(min(filled, Int32(pids.count))) {
            let pid = pids[index]
            guard pid > 0 else { continue }

            // 只用到 user/system time 与 phys_footprint，v0 即可（96 字节，ABI 最稳定）
            var info = rusage_info_v0()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V0, rebound)
                }
            }
            guard result == 0 else { continue }

            samples.append(ProcessSample(
                pid: pid,
                cpuTimeNs: machToNs(info.ri_user_time &+ info.ri_system_time),
                footprint: info.ri_phys_footprint
            ))
        }
        return samples
    }

    // MARK: - 采样

    private func sample() {
        let samples = Self.readProcesses()
        guard !samples.isEmpty else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let hasBaseline = previousStamp > 0
        let elapsed = hasBaseline ? now - previousStamp : 0

        var currentTimes: [pid_t: UInt64] = [:]
        currentTimes.reserveCapacity(samples.count)
        var entries: [(sample: ProcessSample, cpu: Double)] = []
        entries.reserveCapacity(samples.count)

        for sample in samples {
            currentTimes[sample.pid] = sample.cpuTimeNs
            var cpu: Double = 0
            if elapsed > 0, let previous = previousTimes[sample.pid], sample.cpuTimeNs >= previous {
                cpu = Double(sample.cpuTimeNs - previous) / (elapsed * 1_000_000_000) * 100
            }
            entries.append((sample, cpu))
        }

        previousTimes = currentTimes
        previousStamp = now

        let topCPU: [TopProcess] = hasBaseline
            ? entries.sorted { $0.cpu > $1.cpu }.prefix(5).map {
                TopProcess(id: $0.sample.pid, name: name(for: $0.sample.pid), cpu: $0.cpu, footprint: $0.sample.footprint)
            }
            : []
        let topMemory: [TopProcess] = entries.sorted { $0.sample.footprint > $1.sample.footprint }.prefix(5).map {
            TopProcess(id: $0.sample.pid, name: name(for: $0.sample.pid), cpu: $0.cpu, footprint: $0.sample.footprint)
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
            var nameBuffer = [CChar](repeating: 0, count: 256)
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
