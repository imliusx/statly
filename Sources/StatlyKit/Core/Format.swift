import Foundation

/// 格式化工具。状态栏用的字符串一律等宽、定宽（figure space 填充），避免数字跳动引起菜单栏重排。
public enum Format {
    /// 与数字同宽的空格 U+2007
    public static let figureSpace = "\u{2007}"

    /// 0.07 -> "  7%"（填充到 4 个字符宽）
    public static func percent(_ fraction: Double, padded: Bool = true) -> String {
        let clamped = min(max(fraction, 0), 9.99)
        var s = "\(Int((clamped * 100).rounded()))%"
        if padded {
            while s.count < 4 { s = figureSpace + s }
        }
        return s
    }

    /// 状态栏紧凑速率，带单位："0KB/s" "999KB/s" "1.2MB/s" "12.3MB/s" "1.5GB/s"
    public static func compactRate(_ bytesPerSecond: Double) -> String {
        let kb = max(0, bytesPerSecond) / 1024
        if kb < 999.5 { return String(format: "%.0fKB/s", kb) }
        let mb = kb / 1024
        if mb < 99.95 { return String(format: "%.1fMB/s", mb) }
        if mb < 999.5 { return String(format: "%.0fMB/s", mb) }
        return String(format: "%.1fGB/s", mb / 1024)
    }

    /// 弹窗完整速率："1.2 MB/s"
    public static func fullRate(_ bytesPerSecond: Double) -> String {
        let kb = max(0, bytesPerSecond) / 1024
        if kb < 999.5 { return String(format: "%.1f KB/s", kb) }
        let mb = kb / 1024
        if mb < 999.5 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.2f GB/s", mb / 1024)
    }

    /// 磁盘容量（十进制，与 Finder 口径一致）："118G" "1.2T"
    public static func diskShort(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb < 99.95 { return String(format: "%.1fG", gb) }
        if gb < 999.5 { return String(format: "%.0fG", gb) }
        return String(format: "%.2fT", gb / 1000)
    }

    /// 磁盘容量完整（十进制）："118.3 GB"
    public static func diskFull(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb < 999.5 { return String(format: "%.1f GB", gb) }
        return String(format: "%.2f TB", gb / 1000)
    }

    /// 内存容量（二进制，RAM 惯例）："8.2 GB"
    public static func memoryGB(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
