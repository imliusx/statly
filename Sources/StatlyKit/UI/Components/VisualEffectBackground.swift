import SwiftUI
import AppKit

/// NSVisualEffectView 的 SwiftUI 封装：给面板加系统材质（玻璃）背景。
/// blendingMode 用 .behindWindow 时，窗口需设置 isOpaque = false 且背景透明，
/// 材质才会真正透出窗口后方的内容。
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = isEmphasized
    }
}
