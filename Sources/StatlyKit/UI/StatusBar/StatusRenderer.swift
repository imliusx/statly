import AppKit

/// 把快照渲染成状态栏内容。统一格式：标签块 + 图形块，全部离屏绘制成模板图
/// （黑色 + isTemplate），由系统适配深浅色。
/// 标签块四种样式：图标（SF Symbols）/ 竖排小字 / 横排文本 / 隐藏。
/// 图形块：圆环+百分比 / 等宽数值 / 双行速率。
enum StatusRenderer {

    // MARK: - 入口

    /// 单个模块一个状态栏 item。
    static func render(
        module: ModuleID,
        snapshot: SystemSnapshot,
        style: StatusStyle,
        labelStyle: LabelStyle
    ) -> RenderOutput {
        let content = moduleContent(module: module, snapshot: snapshot, style: style)

        // 纯文本快速路径：不需要绘图，直接走 button.title（等宽字体已在 item 上配置）
        if case .valueText(let value) = content.graphic {
            if labelStyle == .text {
                let text = "\(shortLabel(module)) \(value)"
                return RenderOutput(key: "t-\(text)", content: .text(text), tooltip: content.tooltip)
            }
            if labelStyle == .hidden {
                return RenderOutput(key: "t-\(value)", content: .text(value), tooltip: content.tooltip)
            }
        }

        let block = groupBlock(
            module: module, labelStyle: labelStyle, graphic: content.graphic, symbol: content.symbol
        )
        return RenderOutput(
            key: "\(module.rawValue)-\(labelStyle.rawValue)-\(content.key)",
            content: .image(imageFrom(block)),
            tooltip: content.tooltip
        )
    }

    // MARK: - 模块内容（图形 + key + 悬停提示）

    private struct ModuleContent {
        let graphic: Graphic
        let key: String
        let tooltip: String
        /// 覆盖默认的模块图标（温度按冷热档位换水银柱高度）
        var symbol: String?
    }

    private enum Graphic {
        /// 圆环 + 右侧读数。widthTemplate 决定读数区定宽，避免数值变化引起抖动。
        case ring(fraction: Double, text: String, widthTemplate: String)
        case valueText(String)
        case rateColumns(String, String)
    }

    private static func moduleContent(
        module: ModuleID,
        snapshot: SystemSnapshot,
        style: StatusStyle
    ) -> ModuleContent {
        switch module {
        case .cpu:
            guard let cpu = snapshot.cpu else { return placeholderContent(module) }
            let tooltip = "CPU \(Format.percent(cpu.totalUsage, padded: false))"
                + " · 用户 \(Format.percent(cpu.userUsage, padded: false))"
                + " · 系统 \(Format.percent(cpu.systemUsage, padded: false))"
            return usageContent(style: style, fraction: cpu.totalUsage, tooltip: tooltip)

        case .memory:
            guard let memory = snapshot.memory else { return placeholderContent(module) }
            let tooltip = "内存 \(Format.memoryGB(memory.used)) / \(Format.memoryGB(memory.total))"
                + " · 压力\(memory.pressure.displayName)"
            return usageContent(style: style, fraction: memory.usedFraction, tooltip: tooltip)

        case .temperature:
            guard let temperature = snapshot.temperature else { return placeholderContent(module) }
            // 量化到显示的整度：圆环角度与读数严格对应，亚度变化不重绘
            let rounded = temperature.celsius.rounded()
            let text = Format.temperature(rounded)
            let tooltip = "\(temperature.source.displayName)\u{6e29}\u{5ea6} \(text) \u{b7} \u{5e73}\u{5747} \(Format.temperature(temperature.average))"
                + " \u{b7} \(temperature.sensorCount) \u{4e2a}\u{4f20}\u{611f}\u{5668}"
            let level = TemperatureLevel(celsius: rounded)
            switch style {
            case .text:
                let graphic = Graphic.valueText(text)
                return ModuleContent(
                    graphic: graphic, key: graphicKey(graphic), tooltip: tooltip, symbol: level.symbolName
                )
            case .ring:
                let graphic = Graphic.ring(
                    fraction: TemperatureSnapshot(celsius: rounded, average: 0, sensorCount: 0).heatFraction,
                    text: text,
                    widthTemplate: "88\u{b0}C"
                )
                return ModuleContent(
                    graphic: graphic, key: graphicKey(graphic), tooltip: tooltip, symbol: level.symbolName
                )
            }

        case .network:
            let rx = snapshot.network?.rxPerSecond ?? 0
            let tx = snapshot.network?.txPerSecond ?? 0
            let graphic = Graphic.rateColumns(Format.compactRate(rx), Format.compactRate(tx))
            return ModuleContent(
                graphic: graphic,
                key: graphicKey(graphic),
                tooltip: "网络 下行 \(Format.fullRate(rx)) · 上行 \(Format.fullRate(tx))"
            )

        case .disk:
            guard let disk = snapshot.disk else { return placeholderContent(module) }
            let tooltip = "磁盘已用 \(Format.percent(disk.usedFraction, padded: false))"
                + " · 可用 \(Format.diskFull(disk.freeCapacity))"
            switch style {
            case .text:
                let graphic = Graphic.valueText(Format.diskShort(disk.freeCapacity))
                return ModuleContent(graphic: graphic, key: graphicKey(graphic), tooltip: tooltip)
            case .ring:
                let graphic = percentRing(disk.usedFraction)
                return ModuleContent(graphic: graphic, key: graphicKey(graphic), tooltip: tooltip)
            }
        }
    }

    /// CPU/内存共用：按样式生成占用图形。
    private static func usageContent(
        style: StatusStyle,
        fraction: Double,
        tooltip: String
    ) -> ModuleContent {
        let graphic: Graphic
        switch style {
        case .text: graphic = .valueText(Format.percent(fraction))
        case .ring: graphic = percentRing(fraction)
        }
        return ModuleContent(graphic: graphic, key: graphicKey(graphic), tooltip: tooltip)
    }

    private static func placeholderContent(_ module: ModuleID) -> ModuleContent {
        ModuleContent(graphic: .valueText("–"), key: "ph", tooltip: "Statly · \(module.displayName)")
    }

    /// 百分比圆环，量化到整数百分比：key 与图像严格对应、数值不变不重绘。
    private static func percentRing(_ fraction: Double) -> Graphic {
        let percent = quantizePercent(fraction)
        return .ring(
            fraction: Double(percent) / 100,
            text: Format.percent(Double(percent) / 100, padded: false),
            widthTemplate: "88%"
        )
    }

    private static func quantizePercent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    private static func graphicKey(_ graphic: Graphic) -> String {
        switch graphic {
        case .ring(_, let text, _): return "ring-\(text)"
        case .valueText(let value): return "val-\(value)"
        case .rateColumns(let down, let up): return "rate-\(down)|\(up)"
        }
    }

    private static func shortLabel(_ module: ModuleID) -> String {
        switch module {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .temperature: return "TMP"
        case .network: return "NET"
        case .disk: return "SSD"
        }
    }

    /// 标签图标。网络返回 nil：双行速率的 ↓↑ 已经说明了这是网速，再挂一个地球图标
    /// 只是重复信息，却要多占 23pt（19pt 图标 + 4pt 间距）——网络本来就是最宽的模块。
    private static func symbolName(_ module: ModuleID) -> String? {
        switch module {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .temperature: return "thermometer"
        case .network: return nil
        case .disk: return "internaldrive"
        }
    }

    // MARK: - 字体与图标

    private static let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// 竖排字母：系统默认字体，字号取 6px 行高内能容纳的最大值
    private static let verticalFont = NSFont.systemFont(ofSize: 7, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private static let ringValueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)

    private static func attributed(_ string: String, _ font: NSFont) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black])
    }

    /// SF Symbol 图标缓存，按符号名索引（温度会在多个符号间切换，不能按模块缓存）。
    /// 仅主线程访问。
    private static var iconCache: [String: NSImage] = [:]

    private static func icon(named name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        iconCache[name] = image
        return image
    }

    // MARK: - 排版组合

    private typealias Block = (size: NSSize, draw: (NSRect) -> Void)

    /// 单模块块：[标签块] gap [图形块]，各自垂直居中。
    private static func groupBlock(
        module: ModuleID, labelStyle: LabelStyle, graphic: Graphic, symbol: String? = nil
    ) -> Block {
        let label = labelBlock(module: module, style: labelStyle, symbol: symbol)
        let content = graphicBlock(graphic)
        let gap: CGFloat = (label.size.width > 0 && content.size.width > 0) ? 4 : 0
        let width = label.size.width + gap + content.size.width
        let height = max(label.size.height, content.size.height)
        return (
            size: NSSize(width: width, height: height),
            draw: { rect in
                label.draw(NSRect(
                    x: rect.minX,
                    y: rect.minY + (rect.height - label.size.height) / 2,
                    width: label.size.width,
                    height: label.size.height
                ))
                content.draw(NSRect(
                    x: rect.minX + label.size.width + gap,
                    y: rect.minY + (rect.height - content.size.height) / 2,
                    width: content.size.width,
                    height: content.size.height
                ))
            }
        )
    }

    private static func imageFrom(_ block: Block) -> NSImage {
        let image = NSImage(size: block.size, flipped: false) { _ in
            block.draw(NSRect(origin: .zero, size: block.size))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func labelBlock(module: ModuleID, style: LabelStyle, symbol: String? = nil) -> Block {
        switch style {
        case .hidden:
            return (size: .zero, draw: { _ in })

        case .text:
            let text = attributed(shortLabel(module), labelFont)
            let textSize = text.size()
            return (
                size: NSSize(width: ceil(textSize.width), height: ceil(textSize.height)),
                draw: { rect in text.draw(at: rect.origin) }
            )

        case .icon:
            // 没有图标的模块（网络）当作"隐藏"处理，标签块不占位，groupBlock 的间距也一并归零
            guard let name = symbol ?? symbolName(module) else {
                return labelBlock(module: module, style: .hidden)
            }
            guard let image = icon(named: name) else {
                return labelBlock(module: module, style: .text)
            }
            let size = NSSize(width: ceil(image.size.width), height: ceil(image.size.height))
            return (
                size: size,
                draw: { rect in
                    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                }
            )

        case .vertical:
            // 单字母正立、自上而下堆叠（"CPU" → C/P/U 三行小字，系统默认字体，无变形）。
            // 按字体度量（capHeight/descender）沿基线定位，保证字形不超出画布。
            let letters = shortLabel(module).map { attributed(String($0), verticalFont) }
            let rowHeight: CGFloat = 6
            let capHeight = verticalFont.capHeight
            let descent = abs(verticalFont.descender)
            let width = ceil(letters.map { $0.size().width }.max() ?? rowHeight)
            let height = rowHeight * CGFloat(letters.count)
            return (
                size: NSSize(width: width, height: height),
                draw: { rect in
                    for (index, letter) in letters.enumerated() {
                        let bandBottom = rect.maxY - rowHeight * CGFloat(index + 1)
                        let baseline = bandBottom + (rowHeight - capHeight) / 2
                        let point = NSPoint(
                            x: rect.minX + (rect.width - letter.size().width) / 2,
                            // draw(at:) 的纵坐标是文本框底边 = 基线 - 下伸部
                            y: baseline - descent
                        )
                        letter.draw(at: point)
                    }
                }
            )
        }
    }

    private static func graphicBlock(_ graphic: Graphic) -> Block {
        switch graphic {
        case .ring(let fraction, let value, let widthTemplate):
            // 圆环 + 右侧读数。数字左对齐紧贴圆环；宽度按模板定宽，
            // 最常见的两位数值零余量，一位数留少量右侧空隙，超长时临时加宽。
            let diameter: CGFloat = 15
            let text = attributed(value, ringValueFont)
            let template = attributed(widthTemplate, ringValueFont)
            let textZoneWidth = max(ceil(text.size().width), ceil(template.size().width))
            let gap: CGFloat = 4
            return (
                size: NSSize(
                    width: diameter + gap + textZoneWidth,
                    height: max(diameter, ceil(template.size().height))
                ),
                draw: { rect in
                    let ringRect = NSRect(
                        x: rect.minX,
                        y: rect.midY - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    drawRing(in: ringRect, fraction: fraction)
                    text.draw(at: NSPoint(
                        x: rect.minX + diameter + gap,
                        y: rect.midY - text.size().height / 2
                    ))
                }
            )

        case .valueText(let value):
            let text = attributed(value, valueFont)
            let textSize = text.size()
            return (
                size: NSSize(width: ceil(textSize.width), height: ceil(textSize.height)),
                draw: { rect in text.draw(at: rect.origin) }
            )

        case .rateColumns(let down, let up):
            let downArrow = attributed("↓", rateFont)
            let upArrow = attributed("↑", rateFont)
            let downValue = attributed(down, rateFont)
            let upValue = attributed(up, rateFont)
            // compactRate 最宽输出为 "88.8MB/s"，模板取同宽；
            // 箭头列固定在左、数值列右对齐，长度差被两列之间的空隙吸收，不抖动
            let template = attributed("88.8MB/s", rateFont)
            let arrowWidth = ceil(max(downArrow.size().width, upArrow.size().width))
            let zone = NSSize(width: arrowWidth + 3 + ceil(template.size().width), height: 18)
            return (
                size: zone,
                draw: { rect in
                    downArrow.draw(at: NSPoint(x: rect.minX, y: rect.minY + 9))
                    upArrow.draw(at: NSPoint(x: rect.minX, y: rect.minY))
                    downValue.draw(at: NSPoint(x: rect.maxX - ceil(downValue.size().width), y: rect.minY + 9))
                    upValue.draw(at: NSPoint(x: rect.maxX - ceil(upValue.size().width), y: rect.minY))
                }
            )
        }
    }

    // MARK: - 图形绘制

    /// 圆环：12 点方向起顺时针，淡色轨道 + 实色进度。
    private static func drawRing(in rect: NSRect, fraction: Double) {
        let lineWidth: CGFloat = 2.5
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = (min(rect.width, rect.height) - lineWidth) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.25).setStroke()
        track.stroke()

        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0.001 else { return }
        let progress = NSBezierPath()
        progress.lineWidth = lineWidth
        progress.lineCapStyle = .round
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - clamped * 360,
            clockwise: true
        )
        NSColor.black.setStroke()
        progress.stroke()
    }
}
