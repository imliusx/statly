import Foundation
import Darwin

/// 网速：getifaddrs 汇总各接口累计收发字节，差值 ÷ 间隔。
/// 按接口分别记录上次值以正确处理 32 位计数器回绕；排除回环与常见虚拟接口
/// （utun/ipsec 等 VPN 隧道流量最终也会经物理接口计数，排除它们可避免双重统计）。
public final class NetworkSampler {
    private static let excludedPrefixes = ["lo", "gif", "stf", "awdl", "llw", "utun", "ipsec", "anpi", "bridge"]
    /// 单周期超过 10GB 视为接口计数异常（重插/重置），丢弃该差值。
    private static let maxPlausibleDelta: UInt64 = 10_000_000_000

    private var previous: (counters: [String: (rx: UInt32, tx: UInt32)], time: TimeInterval)?

    public init() {}

    public func sample() -> NetworkSnapshot? {
        let now = ProcessInfo.processInfo.systemUptime
        guard let counters = Self.readCounters() else { return nil }
        defer { previous = (counters, now) }

        guard let previous, now > previous.time else { return nil }

        var rxDelta: UInt64 = 0
        var txDelta: UInt64 = 0
        for (name, current) in counters {
            guard let prev = previous.counters[name] else { continue }
            let rx = SamplerMath.delta32(current: current.rx, previous: prev.rx)
            let tx = SamplerMath.delta32(current: current.tx, previous: prev.tx)
            if rx < Self.maxPlausibleDelta { rxDelta += rx }
            if tx < Self.maxPlausibleDelta { txDelta += tx }
        }

        let elapsed = now - previous.time
        return NetworkSnapshot(
            rxPerSecond: Double(rxDelta) / elapsed,
            txPerSecond: Double(txDelta) / elapsed
        )
    }

    public func resetBaseline() {
        previous = nil
    }

    private static func readCounters() -> [String: (rx: UInt32, tx: UInt32)]? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return nil }
        defer { freeifaddrs(addrs) }

        var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
        var cursor = addrs
        while let current = cursor {
            let ifa = current.pointee
            cursor = ifa.ifa_next

            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPointer = ifa.ifa_data else { continue }
            let name = String(cString: ifa.ifa_name)
            guard !excludedPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = (rx: data.ifi_ibytes, tx: data.ifi_obytes)
        }
        return counters
    }
}
