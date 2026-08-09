import Foundation
import IOKit

/// 磁盘：容量走 URL resourceValues（ImportantUsage 口径与 Finder 一致，30s 缓存一次），
/// 读写速度走 IOKit IOBlockStorageDriver 的累计统计差值（每周期）。
public final class DiskSampler {
    private static let capacityRefreshInterval: TimeInterval = 30

    private var previousIO: (read: UInt64, written: UInt64, time: TimeInterval)?
    private var cachedCapacity: (total: UInt64, free: UInt64, fetchedAt: TimeInterval)?

    public init() {}

    public func sample() -> DiskSnapshot? {
        let now = ProcessInfo.processInfo.systemUptime

        if cachedCapacity == nil || now - cachedCapacity!.fetchedAt > Self.capacityRefreshInterval {
            if let capacity = Self.readCapacity() {
                cachedCapacity = (capacity.total, capacity.free, now)
            }
        }
        guard let capacity = cachedCapacity else { return nil }

        var readRate: Double = 0
        var writeRate: Double = 0
        if let io = Self.readIOTotals() {
            if let previous = previousIO, now > previous.time {
                let elapsed = now - previous.time
                readRate = Double(SamplerMath.delta64(current: io.read, previous: previous.read)) / elapsed
                writeRate = Double(SamplerMath.delta64(current: io.written, previous: previous.written)) / elapsed
            }
            previousIO = (io.read, io.written, now)
        }

        return DiskSnapshot(
            totalCapacity: capacity.total,
            freeCapacity: capacity.free,
            readPerSecond: readRate,
            writePerSecond: writeRate
        )
    }

    public func resetBaseline() {
        previousIO = nil
    }

    private static func readCapacity() -> (total: UInt64, free: UInt64)? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let free = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return (total: UInt64(max(0, total)), free: UInt64(max(0, free)))
    }

    private static func readIOTotals() -> (read: UInt64, written: UInt64)? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return (read: read, written: written)
    }
}
