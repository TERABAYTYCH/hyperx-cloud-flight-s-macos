import AppKit
import CoreText

/// Значок для строки меню (24×12 pt, как у AlDente): чёрная батарейка, на ней логотип «hX»
/// фирменного красного HyperX, поверх — белые цифры. На тёмной строке меню — с белым контуром,
/// на светлой — без него. Цвета фиксированные, тему передаёт вызывающий код.
enum BatteryIcon {
    /// Фирменный красный HyperX (#E21836, по данным Simple Icons).
    static let brandRed = NSColor(srgbRed: 0xE2 / 255.0, green: 0x18 / 255.0, blue: 0x36 / 255.0, alpha: 1)

    private static let height: CGFloat = 16
    private static let bodyWidth: CGFloat = 24
    private static let bodyHeight: CGFloat = 12
    private static let bodyRadius: CGFloat = 3.5
    private static let outlineWidth: CGFloat = 1
    private static let nubWidth: CGFloat = 2
    private static let nubHeight: CGFloat = 5
    private static let logoHeight: CGFloat = 11.7
    private static let logoOnlyHeight: CGFloat = 10.4
    private static let fillInset: CGFloat = 1.5
    private static let fillAlpha: CGFloat = 0.4

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)

    /// - Parameters:
    ///   - text: число или «–»/«…»; `nil` — только логотип.
    ///   - level: уровень заряда 0…1 для серой заливки; `nil` — без заливки.
    ///   - dark: тёмная строка меню — рисовать белый контур; на светлой контура нет, батарейка просто чёрная.
    ///   - low: низкий заряд — контур (если есть) и цифры оранжевые.
    ///   - dimmed: приглушённый вид (нет связи с гарнитурой).
    static func make(text: String?, level: Double? = nil, dark: Bool, low: Bool = false, dimmed: Bool = false) -> NSImage {
        let size = NSSize(width: bodyWidth + nubWidth - 0.5, height: height)
        let accent: NSColor = low ? .systemOrange : .white
        let outline: NSColor = dark ? accent : .black

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAlpha(dimmed ? 0.45 : 1)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { ctx.endTransparencyLayer() }

            // Контакт: чёрный с контуром, заходит под корпус.
            let nub = NSRect(x: bodyWidth - 1, y: (height - nubHeight) / 2, width: nubWidth, height: nubHeight)
                .insetBy(dx: outlineWidth / 2, dy: outlineWidth / 2)
            let nubPath = NSBezierPath(roundedRect: nub, xRadius: 1, yRadius: 1)
            NSColor.black.setFill(); nubPath.fill()
            outline.setStroke(); nubPath.lineWidth = outlineWidth; nubPath.stroke()

            // Корпус: чёрный фон + контур.
            let body = NSRect(x: 0, y: (height - bodyHeight) / 2, width: bodyWidth, height: bodyHeight)
                .insetBy(dx: outlineWidth / 2, dy: outlineWidth / 2)
            let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodyRadius - 0.5, yRadius: bodyRadius - 0.5)
            NSColor.black.setFill(); bodyPath.fill()

            // Серая заливка по уровню заряда.
            if let level, level > 0 {
                let inner = body.insetBy(dx: fillInset, dy: fillInset)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: inner, xRadius: bodyRadius - 1.5, yRadius: bodyRadius - 1.5).addClip()
                var filled = inner
                filled.size.width = max(1.5, inner.width * min(1, level))
                NSColor.white.withAlphaComponent(fillAlpha).setFill()
                filled.fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            // Логотип внутри, обрезанный по корпусу.
            NSGraphicsContext.saveGraphicsState()
            bodyPath.addClip()
            brandRed.setFill()
            logoPath(height: text == nil ? logoOnlyHeight : logoHeight, in: body).fill()
            NSGraphicsContext.restoreGraphicsState()

            outline.setStroke(); bodyPath.lineWidth = outlineWidth; bodyPath.stroke()

            // Цифры поверх.
            if let text {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: accent,
                ]))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: (body.midX - width / 2).rounded(),
                                           y: (body.midY - font.capHeight / 2).rounded())
                CTLineDraw(line, ctx)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func logoPath(height: CGFloat, in body: NSRect) -> NSBezierPath {
        let width = height * HyperXLogo.aspect
        return HyperXLogo.path(in: NSRect(x: body.midX - width / 2, y: body.midY - height / 2,
                                          width: width, height: height))
    }
}
