import Foundation

/// 公网 IP 查询。项目里除"检查更新"外唯一的对外请求，因此约束更严：
///
/// - 只在网络详情面板打开期间发起，面板关闭即取消（见 NetworkInfoStore）；
/// - 结果按本地网络指纹缓存，同一网络环境下重复开关面板不会重复请求；
/// - 用户可在设置里彻底关闭，关闭后一个字节都不发；
/// - 用 ephemeral session，不往磁盘写 cookie 与缓存，守住"卸载无残留"。
enum PublicIPService {
    /// 一次请求即可拿到地址、城市与运营商，免 token。换服务只需改这一处。
    static let endpoint = URL(string: "https://ipinfo.io/json")!

    /// 不落盘的会话：无 cookie、无磁盘缓存。
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    enum Failure: Error {
        case transport(String)
        case badStatus(Int)
        case malformed
    }

    /// 返回可取消的 task —— 面板关闭时必须 cancel，否则"关闭即释放"不成立。
    /// 回调在调用方指定的队列之外，统一由调用方切回主线程。
    @discardableResult
    static func fetch(completion: @escaping (Result<PublicIP, Failure>) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                // 取消是正常的生命周期事件，不当成失败上报
                if (error as NSError).code == NSURLErrorCancelled { return }
                return completion(.failure(.transport(error.localizedDescription)))
            }
            guard let http = response as? HTTPURLResponse else {
                return completion(.failure(.transport("无响应")))
            }
            guard http.statusCode == 200 else {
                return completion(.failure(.badStatus(http.statusCode)))
            }
            guard let data, let ip = parse(data) else {
                return completion(.failure(.malformed))
            }
            completion(.success(ip))
        }
        task.resume()
        return task
    }

    /// 纯函数，便于脱离网络单测。缺少 ip 字段视为无效；其余字段缺失只是少显示一项。
    static func parse(_ data: Data) -> PublicIP? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = (json["ip"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty
        else { return nil }

        func field(_ key: String) -> String? {
            guard let value = (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }
        return PublicIP(
            address: address,
            city: field("city"),
            region: field("region"),
            country: field("country"),
            org: normalizeOrg(field("org"))
        )
    }

    /// ipinfo 的 org 形如 "AS4134 Chinanet"，前面的自治系统号对用户没有意义，去掉。
    static func normalizeOrg(_ org: String?) -> String? {
        guard let org else { return nil }
        let parts = org.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].hasPrefix("AS"),
              // 去掉 "AS" 两个字母后必须全是数字，否则是 "ASIA Telecom" 这类正常名字
              parts[0].dropFirst(2).allSatisfy(\.isNumber), parts[0].count > 2
        else {
            return org
        }
        return String(parts[1])
    }

    /// 失败原因的中文短语，直接显示在面板上。
    static func message(for failure: Failure) -> String {
        switch failure {
        case .transport(let reason): return reason
        case .badStatus(let code): return "HTTP \(code)"
        case .malformed: return "响应解析失败"
        }
    }
}
