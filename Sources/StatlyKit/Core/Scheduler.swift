import Foundation

/// 全局唯一的采样定时器：所有模块共享一次唤醒（轻量化守则 #1）。
/// leeway 取周期的 1/4，允许系统合并定时器唤醒以省电。
final class Scheduler {
    private let queue = DispatchQueue(label: "statly.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// 在采样队列上回调。
    var handler: (() -> Void)?

    func start(interval: TimeInterval) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let leeway = DispatchTimeInterval.milliseconds(max(100, Int(interval * 250)))
        timer.schedule(deadline: .now(), repeating: interval, leeway: leeway)
        timer.setEventHandler { [weak self] in
            self?.handler?()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// 在采样队列上执行一段代码，与定时 tick 串行（用于重置采样基线等）。
    func perform(_ block: @escaping () -> Void) {
        queue.async(execute: block)
    }

    var isRunning: Bool { timer != nil }
}
