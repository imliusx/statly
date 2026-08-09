import Foundation

/// 全部采样器的集合。sample(enabled:) 在采样队列上一次唤醒内采完所有启用模块。
public final class SamplerSet {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let temperature = TemperatureSampler()
    private let network = NetworkSampler()
    private let disk = DiskSampler()

    public init() {}

    /// 本机是否支持温度读取（Intel 机型或系统改动私有接口时为 false）
    public var isTemperatureAvailable: Bool { temperature.isAvailable }

    public func sample(enabled: Set<ModuleID>) -> SystemSnapshot {
        SystemSnapshot(
            cpu: enabled.contains(.cpu) ? cpu.sample() : nil,
            memory: enabled.contains(.memory) ? memory.sample() : nil,
            temperature: enabled.contains(.temperature) ? temperature.sample() : nil,
            network: enabled.contains(.network) ? network.sample() : nil,
            disk: enabled.contains(.disk) ? disk.sample() : nil
        )
    }

    /// 从睡眠/锁屏恢复后调用：丢弃旧基线，避免首个周期出现速率尖峰。
    public func resetBaselines() {
        cpu.resetBaseline()
        temperature.resetBaseline()
        network.resetBaseline()
        disk.resetBaseline()
    }
}
