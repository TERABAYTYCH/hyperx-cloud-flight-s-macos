// Рисует docs/menu-bar-icons.png — значок в строке меню в светлой и тёмной теме при разных состояниях.
// Использует тот же код, что и приложение (Sources/BatteryIcon.swift).
// Запускается из tools/makeicons.sh.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/menu-bar-icons.png"
let scale: CGFloat = 3

struct Sample { let label: String; let text: String?; let level: Double?; let low: Bool; let dimmed: Bool }
let samples = [
    Sample(label: "100%", text: "100", level: 1.0, low: false, dimmed: false),
    Sample(label: "83%", text: "83", level: 0.83, low: false, dimmed: false),
    Sample(label: "42%", text: "42", level: 0.42, low: false, dimmed: false),
    Sample(label: "≤ 15%", text: "9", level: 0.09, low: true, dimmed: false),
    Sample(label: "no number", text: nil, level: 0.6, low: false, dimmed: false),
    Sample(label: "offline", text: "–", level: nil, low: false, dimmed: true),
]

let cellW: CGFloat = 64, rowH: CGFloat = 30, labelH: CGFloat = 14, pad: CGFloat = 12
let width = pad * 2 + cellW * CGFloat(samples.count)
let height = labelH + rowH * 2 + 4
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(white: 0.97, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// Две полосы «строки меню»: светлая сверху, тёмная снизу.
let bars: [(dark: Bool, color: NSColor)] = [
    (false, NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)),
    (true, NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)),
]
for (row, bar) in bars.enumerated() {
    let y = height - labelH - rowH * CGFloat(row + 1) - 2
    bar.color.setFill()
    NSBezierPath(roundedRect: NSRect(x: pad / 2, y: y + 2, width: width - pad, height: rowH - 4), xRadius: 6, yRadius: 6).fill()
    for (i, sample) in samples.enumerated() {
        let icon = BatteryIcon.make(text: sample.text, level: sample.level, dark: bar.dark, low: sample.low, dimmed: sample.dimmed)
        let x = pad + cellW * CGFloat(i) + (cellW - icon.size.width) / 2
        icon.draw(in: NSRect(x: x, y: y + (rowH - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
    }
}

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 9, weight: .medium),
    .foregroundColor: NSColor(white: 0.35, alpha: 1),
]
for (i, sample) in samples.enumerated() {
    let s = NSAttributedString(string: sample.label, attributes: attrs)
    let w = s.size().width
    s.draw(at: NSPoint(x: pad + cellW * CGFloat(i) + (cellW - w) / 2, y: height - labelH + 1))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Готово: \(out)")
