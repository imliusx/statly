import Foundation

/// 指标模块标识。新增指标 = 新增一个 case + 对应采样器与渲染逻辑。
public enum ModuleID: String, CaseIterable, Codable, Sendable {
    case cpu
    case memory
    case network
    case disk

    public var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .network: return "网络"
        case .disk: return "磁盘"
        }
    }
}

/// 状态栏显示样式（全局统一，保证各模块格式一致）。
public enum StatusStyle: String, Codable, CaseIterable, Sendable {
    case ring
    case text

    public var displayName: String {
        switch self {
        case .ring: return "圆环"
        case .text: return "文本"
        }
    }
}

/// 状态栏标签样式（全局统一）。
public enum LabelStyle: String, Codable, CaseIterable, Sendable {
    case icon
    case vertical
    case text
    case hidden

    public var displayName: String {
        switch self {
        case .icon: return "图标"
        case .vertical: return "竖排"
        case .text: return "文本"
        case .hidden: return "隐藏"
        }
    }
}
