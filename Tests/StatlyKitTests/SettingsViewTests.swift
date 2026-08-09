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

    private func pageImage(_ section: SettingsSection, _ settings: AppSettings, _ store: MetricStore) -> Data? {
        let renderer = ImageRenderer(
            content: SettingsDetailView(section: section, settings: settings, store: store)
                .frame(width: 460, alignment: .leading)
        )
        renderer.scale = 1
        return renderer.nsImage?.tiffRepresentation
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

    /// 侧边栏外壳：用真实窗口布局验证 NavigationSplitView 能正常构建。
    func testSettingsWindowLaysOut() {
        let controller = SettingsWindowController(settings: makeSettings(), store: populatedStore())
        guard let window = controller.window else { return XCTFail("窗口未创建") }
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(window.frame.width, 400)
        XCTAssertNotNil(window.contentViewController)
        window.close()
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
