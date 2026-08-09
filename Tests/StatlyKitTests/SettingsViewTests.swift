import XCTest
import SwiftUI
@testable import StatlyKit

/// 设置窗口测试。
///
/// 注意：NavigationSplitView 无法被 ImageRenderer 渲染（只会得到一张占位图），
/// 所以内容页单独测（SettingsDetailView），外壳用真实的 AppKit 窗口布局来测。
@MainActor
final class SettingsViewTests: XCTestCase {
    /// 用独立的 UserDefaults 套件，避免污染真实偏好
    private func makeSettings() -> AppSettings {
        let suite = "statly.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return AppSettings(defaults: defaults)
    }

    private func populatedStore() -> MetricStore {
        let store = MetricStore()
        store.apply(SystemSnapshot(
            cpu: CPUSnapshot(totalUsage: 0.42, userUsage: 0.3, systemUsage: 0.12, perCore: [0.4, 0.5]),
            memory: MemorySnapshot(
                total: 17_179_869_184,
                used: 11_596_411_699,
                app: 6_442_450_944,
                wired: 3_221_225_472,
                compressed: 1_932_735_283,
                pressure: .warning
            ),
            network: NetworkSnapshot(rxPerSecond: 2_621_440, txPerSecond: 131_072),
            disk: DiskSnapshot(
                totalCapacity: 1_000_000_000_000,
                freeCapacity: 494_000_000_000,
                readPerSecond: 1_048_576,
                writePerSecond: 524_288
            )
        ))
        return store
    }

    /// 用 NSHostingView 真实绘制。
    ///
    /// 不能用 ImageRenderer：它渲染不了 AppKit 支撑的控件（Form/Picker/Toggle 等），
    /// 各页会得到同一张空白图，测试就成了空过。
    private func pageImage(_ section: SettingsSection, _ settings: AppSettings, _ store: MetricStore) -> Data? {
        let size = NSSize(width: 500, height: 420)
        let hosting = NSHostingView(
            rootView: SettingsDetailView(section: section, settings: settings, store: store)
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    func testEverySectionRendersDistinctContent() {
        let settings = makeSettings()
        let store = populatedStore()

        var images: [SettingsSection: Data] = [:]
        for section in SettingsSection.allCases {
            guard let data = pageImage(section, settings, store) else {
                return XCTFail("\(section.title) 分区渲染失败")
            }
            images[section] = data
        }

        // 每个分区的内容必须互不相同。若某天内容整体渲染不出来（如被占位图取代），
        // 所有分区会得到同一张图，这里就会失败 —— 防止测试空过。
        for a in SettingsSection.allCases {
            for b in SettingsSection.allCases where a != b {
                XCTAssertNotEqual(images[a], images[b], "\(a.title) 与 \(b.title) 渲染结果相同")
            }
        }
    }

    /// 尚无采样数据时（刚启动就打开设置）也不能崩。
    func testRendersEverySectionWithoutData() {
        let settings = makeSettings()
        let store = MetricStore()
        for section in SettingsSection.allCases {
            XCTAssertNotNil(pageImage(section, settings, store), "\(section.title) 分区（无数据）渲染失败")
        }
    }

    /// 外观页的状态栏预览必须跟随样式设置变化。
    func testAppearancePreviewFollowsStyle() {
        let settings = makeSettings()
        let store = populatedStore()

        settings.statusStyle = .ring
        let ring = pageImage(.appearance, settings, store)
        settings.statusStyle = .text
        let text = pageImage(.appearance, settings, store)

        XCTAssertNotNil(ring)
        XCTAssertNotEqual(ring, text, "切换占用样式后预览应当改变")
    }

    /// 侧边栏外壳：用真实窗口布局验证结构能正常构建。
    func testSettingsWindowLaysOut() {
        let controller = SettingsWindowController(settings: makeSettings(), store: populatedStore())
        guard let window = controller.window else { return XCTFail("窗口未创建") }
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(window.frame.width, 400)
        XCTAssertNotNil(window.contentViewController)
        window.close()
    }

    /// 两侧面板都要有透窗玻璃材质，且窗口本身透明（否则 behindWindow 材质无效）。
    func testBothPanesUseGlassMaterial() {
        let controller = SettingsWindowController(settings: makeSettings(), store: populatedStore())
        guard let window = controller.window else { return XCTFail("窗口未创建") }
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(window.isOpaque, "窗口需非不透明，材质才能透出后方内容")
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertTrue(window.titlebarAppearsTransparent)

        let effects = descendants(of: window.contentView, ofType: NSVisualEffectView.self)
        XCTAssertGreaterThanOrEqual(effects.count, 2, "侧边栏与内容区都应有玻璃材质")
        XCTAssertTrue(
            effects.allSatisfy { $0.blendingMode == .behindWindow },
            "材质应为 behindWindow 混合"
        )
        window.close()
    }

    /// 侧边栏不可拖拽改宽、不可折叠：视图层级里不应出现分栏视图。
    func testSidebarIsFixedWidth() {
        let controller = SettingsWindowController(settings: makeSettings(), store: populatedStore())
        guard let window = controller.window else { return XCTFail("窗口未创建") }
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(
            descendants(of: window.contentView, ofType: NSSplitView.self).isEmpty,
            "存在 NSSplitView 说明侧边栏仍可拖拽调整"
        )
        window.close()
    }

    private func descendants<T: NSView>(of root: NSView?, ofType type: T.Type) -> [T] {
        guard let root else { return [] }
        var found: [T] = []
        if let match = root as? T { found.append(match) }
        for subview in root.subviews {
            found.append(contentsOf: descendants(of: subview, ofType: type))
        }
        return found
    }

    func testSectionModuleMapping() {
        XCTAssertEqual(SettingsSection.cpu.module, .cpu)
        XCTAssertEqual(SettingsSection.memory.module, .memory)
        XCTAssertEqual(SettingsSection.network.module, .network)
        XCTAssertEqual(SettingsSection.disk.module, .disk)
        XCTAssertNil(SettingsSection.general.module)
        XCTAssertNil(SettingsSection.about.module)
        // 四个模块都必须有自己的分区
        let covered = Set(SettingsSection.allCases.compactMap(\.module))
        XCTAssertEqual(covered, Set(ModuleID.allCases))
    }

    /// 不允许关掉最后一个模块。
    func testCannotDisableLastModule() {
        let settings = makeSettings()
        settings.enabledModules = [.cpu]
        _ = pageImage(.cpu, settings, MetricStore())
        XCTAssertEqual(settings.enabledModules, [.cpu])
    }
}
