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

// 底：深黑玻璃 —— 近黑渐变 + 环后柔光 + 对角高光 + 内侧亮边
let base = NSGradient(
    starting: NSColor(calibratedRed: 0.090, green: 0.095, blue: 0.110, alpha: 1),
    ending: NSColor.black
)
base?.draw(in: platePath, angle: -90)

NSGraphicsContext.saveGraphicsState()
platePath.addClip()

// 环后柔光：中心径向白光，营造玻璃内的微弱透亮感
let glowPath = NSBezierPath(ovalIn: NSRect(x: center.x - 330, y: center.y - 330, width: 660, height: 660))
let glow = NSGradient(colorsAndLocations:
    (NSColor(white: 1, alpha: 0.09), 0.0),
    (NSColor(white: 1, alpha: 0.00), 1.0)
)
glow?.draw(in: glowPath, relativeCenterPosition: .zero)

// 对角玻璃高光：左上入射的镜面反光带
let sheen = NSGradient(colorsAndLocations:
    (NSColor(white: 1, alpha: 0.15), 0.00),
    (NSColor(white: 1, alpha: 0.04), 0.38),
    (NSColor(white: 1, alpha: 0.00), 0.60)
)
sheen?.draw(in: plate, angle: -60)

// 内侧亮边：玻璃切面的细描边
let rim = NSBezierPath(roundedRect: plate.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
rim.lineWidth = 6
NSColor(white: 1, alpha: 0.10).setStroke()
rim.stroke()

NSGraphicsContext.restoreGraphicsState()

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
