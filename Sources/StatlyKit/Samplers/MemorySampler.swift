import Foundation
import Darwin

/// 内存：host_statistics64，口径对齐活动监视器
/// （已用 = App 内存(internal - purgeable) + 联动 wired + 已压缩）。
/// 内存压力走 DISPATCH_SOURCE_TYPE_MEMORYPRESSURE 事件驱动，零轮询成本。
public final class MemorySampler {
    private let host = mach_host_self()
    private let total = ProcessInfo.processInfo.physicalMemory

    private let pressureLock = NSLock()
    private var _pressure: MemoryPressure = .normal
    private var pressureSource: DispatchSourceMemoryPressure?

    public init() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: DispatchQueue(label: "statly.memory-pressure", qos: .utility)
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let event = source.data
            let pressure: MemoryPressure
            if event.contains(.critical) {
                pressure = .critical
            } else if event.contains(.warning) {
                pressure = .warning
            } else {
                pressure = .normal
            }
            self.pressureLock.lock()
            self._pressure = pressure
            self.pressureLock.unlock()
        }
        source.activate()
        pressureSource = source
    }

    deinit {
        pressureSource?.cancel()
    }

    public func sample() -> MemorySnapshot? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(vm_page_size)
        let appPages = stats.internal_page_count > stats.purgeable_count
            ? UInt64(stats.internal_page_count - stats.purgeable_count)
            : 0
        let app = appPages * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let used = min(app + wired + compressed, total)

        pressureLock.lock()
        let pressure = _pressure
        pressureLock.unlock()

        return MemorySnapshot(
            total: total,
            used: used,
            app: app,
            wired: wired,
            compressed: compressed,
            pressure: pressure
        )
    }
}
