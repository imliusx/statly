#!/usr/bin/env swift
// 生成 Statly 应用图标母版（1024×1024 PNG，透明背景 + 圆角矩形 + 进度环）。
// 用法: swift scripts/make-icon.swift <输出路径.png>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("用法: swift scripts/make-icon.swift <输出路径.png>\n", stderr)
    exit(1)
}
let outputURL = URL(fileURLWithPath: arguments[1])

let canvas: CGFloat = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("创建位图失败\n", stderr)
    exit(1)
}
rep.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple 图标栅格：1024 画布内 824×824 圆角矩形居中，圆角半径 ≈185
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let center = NSPoint(x: canvas / 2, y: canvas / 2)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

// 底：取自参考图的实测配色 —— 纯竖直渐变，顶部灰阶 111 线性落到 56% 处的纯黑，
// 其后保持纯黑。经典的玻璃质感完全由这条渐变本身产生，无需额外高光层。
// 数值由参考图的原始像素采样得来（用 colorAt 读会因色彩空间转换而虚高约 13%）。
// 必须用 sRGB 指定：calibratedWhite 走的是另一套 gamma，渲染出来会明显偏亮。
func srgbGray(_ level: Double) -> NSColor {
    NSColor(srgbRed: level / 255, green: level / 255, blue: level / 255, alpha: 1)
}
let base = NSGradient(colorsAndLocations:
    (srgbGray(111), 0.0),
    (srgbGray(0), 0.56),
    (srgbGray(0), 1.0)
)
base?.draw(in: platePath, angle: -90)

// 进度环：与菜单栏 UI 同构 —— 淡色轨道 + 实色进度（12 点起顺时针 72%，圆头）
let radius: CGFloat = 235
let strokeWidth: CGFloat = 96

let track = NSBezierPath()
track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
track.lineWidth = strokeWidth
NSColor.white.withAlphaComponent(0.20).setStroke()
track.stroke()

let progress = NSBezierPath()
progress.lineWidth = strokeWidth
progress.lineCapStyle = .round
progress.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 0.72 * 360, clockwise: true)
NSColor.white.setStroke()
progress.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("PNG 编码失败\n", stderr)
    exit(1)
}
do {
    try png.write(to: outputURL)
    print("已生成: \(outputURL.path)")
} catch {
    fputs("写入失败: \(error)\n", stderr)
    exit(1)
}
