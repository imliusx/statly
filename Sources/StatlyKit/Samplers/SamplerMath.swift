import Foundation

public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// 采样差值的纯函数集合，便于单测覆盖回绕等边界。
public enum SamplerMath {
    /// UInt32 计数器差值，处理回绕（内核网络计数器是 32 位，4GB 流量即回绕一次）。
    public static func delta32(current: UInt32, previous: UInt32) -> UInt64 {
        if current >= previous {
            return UInt64(current - previous)
        }
        return UInt64(current) &+ (UInt64(UInt32.max) + 1) &- UInt64(previous)
    }

    /// UInt64 计数器差值，计数器被重置时返回 0 而不是天文数字。
    public static func delta64(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    /// 由两次 tick 快照计算 CPU 使用率。返回 nil 表示差值无效（首次采样等）。
    public static func cpuUsage(
        previous: [CPUTicks],
        current: [CPUTicks]
    ) -> (total: Double, user: Double, system: Double, perCore: [Double])? {
        guard !previous.isEmpty, previous.count == current.count else { return nil }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalAll: UInt64 = 0
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)

        for (prev, cur) in zip(previous, current) {
            let user = delta32(current: cur.user, previous: prev.user)
            let system = delta32(current: cur.system, previous: prev.system)
            let idle = delta32(current: cur.idle, previous: prev.idle)
            let nice = delta32(current: cur.nice, previous: prev.nice)
            let all = user + system + idle + nice
            let busy = user + system + nice

            totalUser += user + nice
            totalSystem += system
            totalAll += all
            perCore.append(all == 0 ? 0 : Double(busy) / Double(all))
        }

        guard totalAll > 0 else { return nil }
        return (
            total: Double(totalUser + totalSystem) / Double(totalAll),
            user: Double(totalUser) / Double(totalAll),
            system: Double(totalSystem) / Double(totalAll),
            perCore: perCore
        )
    }
}
