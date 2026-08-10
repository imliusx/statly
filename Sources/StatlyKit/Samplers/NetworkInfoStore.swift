import Foundation
import Combine
import Darwin
import SystemConfiguration

/// 网络环境信息（本机 IP / 网关 / DNS / Wi-Fi / 公网 IP）。
///
/// 轻量化守则"按需分级"：只在网络详情面板打开期间运行自己的定时器，关闭即停止、
/// 取消在途请求并清空状态，绝不进入常驻采样路径。结构与 TopProcessStore 一致。
///
/// 这些都是慢变量（IP、网关、DNS 基本不变，只有 Wi-Fi 信号强度值得跟着动），
/// 因此固定 5 秒刷新一次，与温度模块同一理由。
public final class NetworkInfoStore: ObservableObject {
    /// 公网 IP 缓存有效期。网络指纹没变也强制过期，兜底 ISP 侧换 IP。
    private static let publicIPTTL: TimeInterval = 30 * 60
    private static let refreshInterval: TimeInterval = 5

    @Published public private(set) var info = NetworkInfo()
    @Published public private(set) var publicIP: PublicIPState = .idle

    private let queue = DispatchQueue(label: "statly.network-info", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var publicIPEnabled = false
    private var inFlight: URLSessionDataTask?

    /// 公网 IP 缓存。**不随 stop() 清除**——正是它让"反复开关面板只请求一次"成立。
    private var cached: (fingerprint: String, value: PublicIP, stamp: TimeInterval)?
    /// 本次面板打开期间已经查过的指纹（无论成败）。防止查询失败后被 5 秒定时器
    /// 反复重试——对外承诺是"打开面板时查一次"，重试交给用户点按钮。
    /// 随 stop() 清除，因此重新打开面板会重试上次失败的查询。
    private var attempted: String?

    public init() {}

    // MARK: - 生命周期（主线程调用）

    public func start(publicIPEnabled: Bool) {
        stop()
        self.publicIPEnabled = publicIPEnabled
        self.publicIP = publicIPEnabled ? .idle : .disabled

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.refreshInterval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        inFlight?.cancel()
        inFlight = nil
        // cached 有意保留（重开面板不重复请求），attempted 清掉以便重试上次的失败
        attempted = nil
        info = NetworkInfo()
        publicIP = .idle
    }

    // MARK: - 采集

    private func refresh() {
        let collected = Self.collectLocal()
        DispatchQueue.main.async { [weak self] in
            // 停止后到达的迟到结果直接丢弃
            guard let self, self.timer != nil else { return }
            self.info = collected
            self.updatePublicIP(for: collected)
        }
    }

    // MARK: - 公网 IP（主线程）

    private func updatePublicIP(for info: NetworkInfo) {
        guard publicIPEnabled else {
            publicIP = .disabled
            return
        }
        let fingerprint = info.fingerprint
        let now = ProcessInfo.processInfo.systemUptime

        if let cached, cached.fingerprint == fingerprint, now - cached.stamp < Self.publicIPTTL {
            publicIP = .loaded(cached.value)
            return
        }
        // 指纹变了（换 Wi-Fi、插拔网线、连 VPN）：旧结果与在途请求都不作数
        if let attempted, attempted != fingerprint {
            cached = nil
            self.attempted = nil
            inFlight?.cancel()
            inFlight = nil
        }
        // 同一网络已经查过就不再自动重试，失败后交由"重试"按钮或重开面板
        guard inFlight == nil, attempted != fingerprint else { return }

        attempted = fingerprint
        publicIP = .loading
        inFlight = PublicIPService.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.timer != nil else { return }
                self.inFlight = nil
                switch result {
                case .success(let value):
                    self.cached = (fingerprint, value, ProcessInfo.processInfo.systemUptime)
                    self.publicIP = .loaded(value)
                case .failure(let failure):
                    self.publicIP = .failed(PublicIPService.message(for: failure))
                }
            }
        }
    }

    /// 用户在面板上点"重试"：清掉缓存与已查标记后重新走一遍。
    public func retryPublicIP() {
        guard publicIPEnabled, timer != nil else { return }
        cached = nil
        attempted = nil
        inFlight?.cancel()
        inFlight = nil
        updatePublicIP(for: info)
    }

    // MARK: - 本地信息读取（全部免权限，静态便于单测）

    static func collectLocal() -> NetworkInfo {
        var info = NetworkInfo()
        guard let store = SCDynamicStoreCreate(nil, "com.statly.app.netinfo" as CFString, nil, nil) else {
            return info
        }
        if let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            info.interfaceName = global["PrimaryInterface"] as? String
            info.router = global["Router"] as? String
        }
        if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
            info.dns = dns["ServerAddresses"] as? [String] ?? []
        }
        if let interface = info.interfaceName {
            let addresses = self.addresses(for: interface)
            info.ipv4 = addresses.v4
            info.ipv6 = addresses.v6
        }
        return info
    }

    /// 取指定接口的 IPv4 / IPv6 地址。遍历骨架同 NetworkSampler.readCounters，
    /// 但那里要的是 AF_LINK 的字节计数，这里要的是 AF_INET / AF_INET6 的地址。
    static func addresses(for interface: String) -> (v4: String?, v6: String?) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (nil, nil) }
        defer { freeifaddrs(addrs) }

        var v4: String?
        var v6: String?
        var cursor = addrs
        while let current = cursor {
            let ifa = current.pointee
            cursor = ifa.ifa_next

            guard String(cString: ifa.ifa_name) == interface, let addr = ifa.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr, socklen_t(addr.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            if family == UInt8(AF_INET) {
                if v4 == nil { v4 = String(cString: host) }
            } else if v6 == nil, let address = usableIPv6(String(cString: host)) {
                v6 = address
            }
        }
        return (v4, v6)
    }

    /// 链路本地地址（fe80::）每个接口都有、对用户没有意义，排除。
    /// getnameinfo 会给它带上 "%en0" 作用域后缀，一并去掉。
    static func usableIPv6(_ raw: String) -> String? {
        let bare = raw.split(separator: "%").first.map(String.init) ?? raw
        guard !bare.lowercased().hasPrefix("fe80") else { return nil }
        return bare.isEmpty ? nil : bare
    }
}
