import AppKit

extension NSMenu {
    /// Вернуть системную подсветку на выделенный пункт.
    ///
    /// Если пункты прячутся или появляются, пока меню открыто (например, строки состояния — из подменю), macOS
    /// пересчитывает строки, а подсветку пункта с открытым подменю оставляет со сдвигом — например, на высоту
    /// убранного разделителя. Подсветка — отдельный вид поверх таблицы пунктов, поэтому ставим его по строке
    /// выделенного пункта. Пункты со своим видом рисуют подсветку сами, их не трогаем.
    /// Если устройство меню в новой macOS другое — ничего не делаем.
    func realignHighlight() {
        guard let item = highlightedItem, item.view == nil,
              let window = items.lazy.compactMap({ $0.view?.window }).first, window.isVisible,
              let table = Self.find(NSTableView.self, in: window.contentView?.superview ?? window.contentView),
              let highlight = table.subviews.first(where: { String(describing: type(of: $0)).contains("BackgroundView") })
        else { return }
        let visible = items.filter { !$0.isHidden }
        guard let row = visible.firstIndex(of: item), row < table.numberOfRows else { return }
        let rect = table.rect(ofRow: row)
        let inset = (rect.width - highlight.frame.width) / 2
        let target = NSRect(x: rect.minX + inset, y: rect.minY, width: highlight.frame.width, height: rect.height)
        if highlight.frame != target { highlight.frame = target }
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for subview in view.subviews { if let match = find(type, in: subview) { return match } }
        return nil
    }
}
