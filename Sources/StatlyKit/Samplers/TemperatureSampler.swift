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
    /// 每种来源最多采样的传感器个数。CPU 晶粒传感器多且分布在不同核心簇，取 4 个；
    /// 电池只有一个物理电芯，多个条目读数几乎一致，取 2 个即可。
    private static func sensorLimit(for source: TemperatureSource) -> Int {
        switch source {
        case .cpu: return 4
        case .battery: return 2
        }
    }

    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn
    private let field: Int32
    private let services: [TemperatureSource: [AnyObject]]
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
        var selected: [TemperatureSource: [AnyObject]] = [:]
        for source in TemperatureSource.allCases {
            let picked = Self.selectSensors(allServices, name: name, for: source)
            if !picked.isEmpty { selected[source] = picked }
        }
        guard !selected.isEmpty else { return nil }

        self.copyEvent = copyEvent
        self.getFloat = getFloat
        // kIOHIDEventTypeTemperature = 15，字段编号为 类型 << 16
        self.field = Int32(Int64(Self.temperatureEventType) << 16)
        self.services = selected
        self.client = client
    }

    private static let temperatureEventType: Int64 = 15

    /// 按来源挑选传感器并均匀抽样。
    ///
    /// CPU：优先取晶粒温度（tdie），覆盖不同核心簇。tcal 是校准参考值（恒定偏高）
    /// 不是真实温度，电池与闪存温度属于别的部件，一并排除。
    /// 电池：只取名字含 battery 的传感器。
    static func selectSensors(
        _ services: [AnyObject],
        name: (AnyObject) -> String,
        for source: TemperatureSource
    ) -> [AnyObject] {
        let pool: [AnyObject]
        switch source {
        case .cpu:
            let excluded = ["tcal", "battery", "NAND"]
            let usable = services.filter { service in
                let label = name(service)
                return !excluded.contains { label.localizedCaseInsensitiveContains($0) }
            }
            let die = usable.filter { name($0).localizedCaseInsensitiveContains("tdie") }
            pool = die.isEmpty ? usable : die
        case .battery:
            pool = services.filter { name($0).localizedCaseInsensitiveContains("battery") }
        }
        let sorted = pool.sorted { name($0) < name($1) }
        let limit = sensorLimit(for: source)
        guard sorted.count > limit else { return sorted }
        let step = sorted.count / limit
        return stride(from: 0, to: sorted.count, by: step).prefix(limit).map { sorted[$0] }
    }

    /// 本机可用的温度来源
    var availableSources: Set<TemperatureSource> { Set(services.keys) }

    /// 返回 (最高温, 平均温, 有效传感器数)；一个读数都拿不到时返回 nil。
    func read(_ source: TemperatureSource) -> (peak: Double, average: Double, count: Int)? {
        guard let group = services[source] else { return nil }
        var values: [Double] = []
        values.reserveCapacity(group.count)
        for service in group {
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
    private var lastSource: TemperatureSource?

    public init() {
        sensors = HIDTemperatureSensors()
    }

    /// 本机可用的温度来源（台式机型通常没有电池传感器）
    public var availableSources: Set<TemperatureSource> {
        sensors?.availableSources ?? []
    }

    /// 本机是否能读到任一温度
    public var isAvailable: Bool { !availableSources.isEmpty }

    public func sample(source: TemperatureSource) -> TemperatureSnapshot? {
        guard let sensors, sensors.availableSources.contains(source) else { return nil }
        // 换了来源就作废缓存：两种来源量的不是同一件事，不能沿用旧读数
        if source != lastSource {
            cached = nil
            lastSampledAt = 0
            lastSource = source
        }
        let now = ProcessInfo.processInfo.systemUptime
        if cached != nil, now - lastSampledAt < Self.minimumInterval { return cached }
        guard let reading = sensors.read(source) else { return cached }
        lastSampledAt = now
        cached = TemperatureSnapshot(
            source: source,
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
