import Foundation
import Darwin

/// CPU 使用率：host_processor_info 每核 tick 数，两次采样差值。
public final class CPUSampler {
    private let host = mach_host_self()
    private var previousTicks: [CPUTicks] = []

    public init() {}

    public func sample() -> CPUSnapshot? {
        guard let ticks = readTicks() else { return nil }
        defer { previousTicks = ticks }
        guard let usage = SamplerMath.cpuUsage(previous: previousTicks, current: ticks) else { return nil }
        return CPUSnapshot(
            totalUsage: usage.total,
            userUsage: usage.user,
            systemUsage: usage.system,
            perCore: usage.perCore
        )
    }

    public func resetBaseline() {
        previousTicks = []
    }

    private func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let states = Int(CPU_STATE_MAX)
        guard Int(infoCount) >= Int(cpuCount) * states else { return nil }

        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = core * states
            ticks.append(CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ))
        }
        return ticks
    }
}
