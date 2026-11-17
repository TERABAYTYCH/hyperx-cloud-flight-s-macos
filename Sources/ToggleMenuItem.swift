import AppKit

/// Пункт-переключатель, после нажатия на который меню остаётся открытым: удобно щёлкать несколько галочек подряд.
///
/// У `NSMenu` нет настройки «не закрываться», поэтому пункт рисуется своим видом: вид сам обрабатывает клик
/// и шлёт обычное действие пункта (`action`/`target`), а меню при этом не закрывается.
/// Состояние, заголовок и доступность меняются как у обычного пункта — вид перерисовывается сам.
final class ToggleMenuItem: NSMenuItem {
    override init(title: String, action selector: Selector?, keyEquivalent charCode: String) {
        super.init(title: title, action: selector, keyEquivalent: charCode)
        view = ToggleMenuItemView(item: self)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    override var state: NSControl.StateValue { didSet { refresh() } }
    override var title: String { didSet { refresh() } }
    override var isEnabled: Bool { didSet { refresh() } }
    override var indentationLevel: Int { didSet { refresh() } }
    override var toolTip: String? { didSet { view?.toolTip = toolTip } }

    /// См. `ToggleMenuItemView.resetWidth`.
    func resetWidth() { (view as? ToggleMenuItemView)?.resetWidth() }

    private func refresh() {
        (view as? ToggleMenuItemView)?.updateSize()
        view?.needsDisplay = true
    }
}

private final class ToggleMenuItemView: NSView {
    private weak var item: NSMenuItem?
    /// Подсветка под пунктом: скруглённый прямоугольник с непрерывными углами (суперэллипс), как у системных пунктов.
    private let highlight = CALayer()
    private let content = ContentView()
    /// Курсор над пунктом. После клика меню снимает с пункта `isHighlighted` до следующего движения мыши,
    /// поэтому наведение отслеживаем сами — иначе подсветка пропадала бы сразу после нажатия.
    private(set) var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    // Размеры сняты со скриншотов системного меню (macOS 26).
    static let height: CGFloat = 24
    /// Отступ текста от края меню — под колонку галочки.
    static let textInset: CGFloat = 29
    /// Отступ текста без колонки и шаг отступа на уровень — как у системных пунктов.
    static let baseInset: CGFloat = 16
    /// Левый край галочки — левее текста на столько.
    static let checkOffset: CGFloat = 17
    static let indentStep: CGFloat = 16
    static let highlightInset: CGFloat = 5
    static let cornerRadius: CGFloat = 8
    static let font = NSFont.menuFont(ofSize: 0)

    /// Где начинается текст: системные пункты с отступом выходят за колонку галочки, без отступа — встают за ней.
    static func textX(level: Int) -> CGFloat { max(textInset, baseInset + CGFloat(level) * indentStep) }

    init(item: NSMenuItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: Self.height))
        autoresizingMask = .width  // меню растягивает вид на свою ширину
        wantsLayer = true
        highlight.cornerRadius = Self.cornerRadius
        highlight.cornerCurve = .continuous
        highlight.isHidden = true
        layer?.addSublayer(highlight)
        content.item = item
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)  // текст поверх подсветки
        updateSize()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) не используется")
    }

    /// Вернуть ширину по тексту. Меню растягивает вид до своей ширины, а обратно не сужает — после скрытия
    /// широких подсказок подменю оставалось бы прежним.
    func resetWidth() {
        setFrameSize(NSSize(width: 0, height: Self.height))
        updateSize()
    }

    func updateSize() {
        let textX = Self.textX(level: item?.indentationLevel ?? 0)
        let width = textX + ((item?.title ?? "") as NSString).size(withAttributes: [.font: Self.font]).width + 20
        setFrameSize(NSSize(width: max(frame.width, ceil(width)), height: Self.height))
    }

    override var needsDisplay: Bool {
        didSet { if needsDisplay { content.needsDisplay = true; updateHighlight() } }
    }

    override func layout() {
        super.layout()
        updateHighlight()
    }

    private func updateHighlight() {
        guard let item else { return }
        if item.isHighlighted, window?.firstResponder !== self { window?.makeFirstResponder(self) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // без анимации, как у системной подсветки
        highlight.frame = bounds.insetBy(dx: Self.highlightInset, dy: 0)
        highlight.isHidden = !isLit
        effectiveAppearance.performAsCurrentDrawingAppearance {
            highlight.backgroundColor = NSColor.controlAccentColor.cgColor
        }
        CATransaction.commit()
    }

    /// Подсветка: меню выделило пункт или курсор над ним.
    /// Наведение не в счёт, если меню выделило другой пункт (стрелками с клавиатуры): иначе подсвечены были бы два.
    var isLit: Bool {
        guard let item, item.isEnabled else { return false }
        if item.isHighlighted { return true }
        let other = item.menu?.highlightedItem
        return hovered && (other == nil || other === item)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hovered = false  // меню закрыли и открыли заново — старое наведение не в счёт
    }

    override func draw(_ dirtyRect: NSRect) {
        // Меню отмечает пункт выделенным само и просит перерисовку — обновляем подсветку и текст.
        updateHighlight()
        content.needsDisplay = true
    }

    // Enter и пробел на выделенном с клавиатуры пункте. Меню само не передаёт их пунктам со своим видом,
    // поэтому выделенный пункт становится первым ответчиком (см. `updateHighlight`) и ловит клавиши сам.
    // Стрелки и прочее уходят дальше — навигация по меню работает как обычно.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // 36 Return, 76 Enter на цифровой клавиатуре, 49 пробел.
        if [36, 76, 49].contains(event.keyCode), let item, item.isHighlighted, item.isEnabled, let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let item, item.isEnabled, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
        hovered = true  // курсор всё ещё на пункте
        needsDisplay = true
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .menuItem }
    override func accessibilityLabel() -> String? { item?.title }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard let item, item.isEnabled, let action = item.action else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }
}

/// Галочка и текст пункта.
private final class ContentView: NSView {
    weak var item: NSMenuItem?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // клики обрабатывает родительский вид

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        typealias V = ToggleMenuItemView
        let highlighted = (superview as? ToggleMenuItemView)?.isLit ?? false
        let color: NSColor = !item.isEnabled ? .disabledControlTextColor : highlighted ? .selectedMenuItemTextColor : .labelColor
        let textX = V.textX(level: item.indentationLevel)

        if item.state == .mixed {
            // «Требует подтверждения» и т. п. — тире, как у системных пунктов.
            let dash = "–" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: V.font, .foregroundColor: color]
            let size = dash.size(withAttributes: attributes)
            dash.draw(at: NSPoint(x: V.textX(level: item.indentationLevel) - V.checkOffset + 1, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        }
        if item.state == .on,
           let check = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
               .withSymbolConfiguration(.init(pointSize: V.font.pointSize - 1, weight: .semibold)) {
            let tinted = NSImage(size: check.size, flipped: false) { rect in
                check.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(at: NSPoint(x: textX - V.checkOffset, y: (bounds.height - tinted.size.height) / 2),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }

        let title = item.title as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: V.font, .foregroundColor: color]
        let size = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: textX, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}
