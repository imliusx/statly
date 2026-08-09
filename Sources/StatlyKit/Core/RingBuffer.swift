import Foundation

/// 定长环形缓冲，只存原始 Double，供历史曲线 / 迷你图使用。
public struct RingBuffer {
    public let capacity: Int
    private var storage: [Double]
    private var head = 0
    private var count = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = Array(repeating: 0, count: capacity)
    }

    public mutating func push(_ value: Double) {
        storage[head] = value
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// 从旧到新返回。
    public func values() -> [Double] {
        guard count == capacity else { return Array(storage[0..<count]) }
        return Array(storage[head..<capacity]) + Array(storage[0..<head])
    }

    public var isEmpty: Bool { count == 0 }
}
