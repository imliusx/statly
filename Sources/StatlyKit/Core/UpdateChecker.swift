import AppKit

/// 检查更新：请求 GitHub Releases 最新版本号与当前版本比较。
/// 零依赖实现（无 Sparkle），主更新渠道是 Homebrew cask / 手动下载。
enum UpdateChecker {
    static let repositoryURL = URL(string: "https://github.com/imliusx/statly")!
    static let releasesPageURL = URL(string: "https://github.com/imliusx/statly/releases")!
    private static let latestAPIURL = URL(string: "https://api.github.com/repos/imliusx/statly/releases/latest")!

    enum Outcome {
        case upToDate(current: String)
        case newVersion(String)
        case noReleases
        case failed(String)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// 完成回调在主线程。
    static func check(completion: @escaping (Outcome) -> Void) {
        var request = URLRequest(url: latestAPIURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let outcome = parse(data: data, response: response, error: error)
            DispatchQueue.main.async { completion(outcome) }
        }.resume()
    }

    private static func parse(data: Data?, response: URLResponse?, error: Error?) -> Outcome {
        if let error {
            return .failed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            return .failed("无响应")
        }
        if http.statusCode == 404 {
            return .noReleases
        }
        guard http.statusCode == 200,
              let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else {
            return .failed("响应解析失败（HTTP \(http.statusCode)）")
        }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(latest, than: currentVersion) ? .newVersion(latest) : .upToDate(current: currentVersion)
    }

    /// 数字段逐段比较（"0.2.0" > "0.1.9"）。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
