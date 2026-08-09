import Foundation
import IOKit

/// 温度传感器读取。
///
/// macOS 没有公开的温度 API，只能走 IOHIDEventSystemClient 这组私有接口
/// （PLAN 第 9 节已就此定调：传感器功能只进直接分发版，不进 App Store 版）。
/// 这里用 dlsym 动态取符号，任一环节失败就整体降级为"不可用"，绝不崩溃。
///
/// 成本控制（实测数据）：每读一个传感器约 1ms，机器上有 16 个晶粒温度传感器，
/// 全读一次 16.7ms，按 2 秒周期会吃掉 0.83% CPU，远超 0.3% 的预算。
/// 实测均匀取其中 4 个取最大值，与全量最大值平均只差 0.01°C（最大 1.4°C），
/// 单次降到 3.6ms；再把采样间隔放宽到 5 秒（温度本就是慢变量），约 0.07% CPU。
final class HIDTemperatureSensors {
    /// 采样的传感器个数
    private static let sensorLimit = 4

    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private let field: Int32
    private let services: [AnyObject]
    /// 必须持有 client：服务对象依赖它内部的锁，client 一旦释放，
    /// 后续 CopyEvent 会在已释放的 os_unfair_lock 上解锁而崩溃。
    private let client: AnyObject

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject?, CFDictionary?) -> Int32
    private typealias CopyServicesFn = @convention(c) (AnyObject?) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject?, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (AnyObject?, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject?, Int32) -> Double

    /// 传感器不可用时返回 nil（Intel 机型、系统更新改了私有接口、权限受限等）。
    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, _ type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", CreateFn.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", SetMatchingFn.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", CopyServicesFn.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", CopyPropertyFn.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", CopyEventFn.self),
              let getFloat = symbol("IOHIDEventGetFloatValue", GetFloatFn.self),
              let clientRef = create(kCFAllocatorDefault)
        else { return nil }

        let client = clientRef.takeRetainedValue()
        // kHIDPage_AppleVendor = 0xff00，kHIDUsage_AppleVendor_TemperatureSensor = 0x0005
        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005] as CFDictionary)
        guard let servicesRef = copyServices(client) else { return nil }
        let allServices = servicesRef.takeRetainedValue() as [AnyObject]
        guard !allServices.isEmpty else { return nil }

        func name(_ service: AnyObject) -> String {
            copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
        }
        let selected = Self.selectSensors(allServices, name: name)
        guard !selected.isEmpty else { return nil }

        self.copyEvent = copyEvent
        self.getFloat = getFloat
        // kIOHIDEventTypeTemperature = 15，字段编号为 类型 << 16
        self.field = Int32(Int64(Self.temperatureEventType) << 16)
        self.services = selected
        self.client = client
    }

    private static let temperatureEventType: Int64 = 15

    /// 优先取晶粒温度（tdie），均匀抽样以覆盖不同核心簇。
    /// tcal 是校准参考值（恒定偏高）不是真实温度；电池与闪存温度另属别的部件，一并排除。
    static func selectSensors(
        _ services: [AnyObject],
        name: (AnyObject) -> String
    ) -> [AnyObject] {
        let excluded = ["tcal", "battery", "NAND"]
        let usable = services.filter { service in
            let label = name(service)
            return !excluded.contains { label.localizedCaseInsensitiveContains($0) }
        }
        let die = usable.filter { name($0).localizedCaseInsensitiveContains("tdie") }
        let pool = (die.isEmpty ? usable : die).sorted { name($0) < name($1) }
        guard pool.count > sensorLimit else { return pool }
        let step = pool.count / sensorLimit
        return stride(from: 0, to: pool.count, by: step).prefix(sensorLimit).map { pool[$0] }
    }

    /// 返回 (最高温, 平均温, 有效传感器数)；一个读数都拿不到时返回 nil。
    func read() -> (peak: Double, average: Double, count: Int)? {
        var values: [Double] = []
        values.reserveCapacity(services.count)
        for service in services {
            guard let eventRef = copyEvent(service, Self.temperatureEventType, 0, 0) else { continue }
            let value = getFloat(eventRef.takeRetainedValue(), field)
            // 无效读数：未接传感器会返回负值，异常高值同样丢弃
            guard value > 0, value < 150 else { continue }
            values.append(value)
        }
        guard let peak = values.max() else { return nil }
        return (peak, values.reduce(0, +) / Double(values.count), values.count)
    }
}

/// 温度采样器。温度是慢变量，独立按最小间隔节流，不跟随主刷新频率。
public final class TemperatureSampler {
    /// 两次真实读取之间的最小间隔
    private static let minimumInterval: TimeInterval = 5

    private let sensors: HIDTemperatureSensors?
    private var cached: TemperatureSnapshot?
    private var lastSampledAt: TimeInterval = 0

    public init() {
        sensors = HIDTemperatureSensors()
    }

    /// 本机是否能读到温度
    public var isAvailable: Bool { sensors != nil }

    public func sample() -> TemperatureSnapshot? {
        guard let sensors else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        if cached != nil, now - lastSampledAt < Self.minimumInterval { return cached }
        guard let reading = sensors.read() else { return cached }
        lastSampledAt = now
        cached = TemperatureSnapshot(
            celsius: reading.peak,
            average: reading.average,
            sensorCount: reading.count
        )
        return cached
    }

    /// 从睡眠恢复后调用：丢弃缓存，下一拍立即重新读取。
    public func resetBaseline() {
        cached = nil
        lastSampledAt = 0
    }
}
