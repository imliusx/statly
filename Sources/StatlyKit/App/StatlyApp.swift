import AppKit

@MainActor
public enum StatlyApp {
    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护：同 bundle id 已有实例在运行则直接退出，避免菜单栏出现重复图标。
        // （裸二进制开发模式无 bundle id，不受此保护，注意别同时开多个）
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApplication.shared.terminate(nil)
            return
        }
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }
}
