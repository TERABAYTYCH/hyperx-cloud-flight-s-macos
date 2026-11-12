// Рисует иконку приложения 1024×1024 в стиле значка в строке меню: тёмная плашка macOS,
// чёрная батарейка с белым контуром, серая заливка и красный логотип «hX».
// Запускается из tools/makeicons.sh.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let red = NSColor(srgbRed: 0xE2 / 255, green: 0x18 / 255, blue: 0x36 / 255, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Плашка по сетке Apple: 824×824 с отступом 100, радиус ~185, мягкая тень.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(white: 0.20, alpha: 1), ending: NSColor(white: 0.06, alpha: 1))!
    .draw(in: tilePath, angle: -90)

// Батарейка: те же пропорции, что в строке меню (24×12, радиус 3.5, контакт 2×5).
let k: CGFloat = 26
let bodyW = 24 * k, bodyH = 12 * k, nubW = 2 * k, nubH = 5 * k, gap = 0.6 * k
let totalW = bodyW + gap + nubW
let body = NSRect(x: (size - totalW) / 2, y: (size - bodyH) / 2, width: bodyW, height: bodyH)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 3.5 * k, yRadius: 3.5 * k)
let nub = NSRect(x: body.maxX + gap, y: body.midY - nubH / 2, width: nubW, height: nubH)

NSColor.white.withAlphaComponent(0.9).setFill()
NSBezierPath(roundedRect: nub, xRadius: nubW / 2.2, yRadius: nubW / 2.2).fill()
NSColor.black.setFill()
bodyPath.fill()

NSGraphicsContext.saveGraphicsState()
bodyPath.addClip()
// Серая заливка уровня (~75%).
let inset = 1.5 * k
let fill = NSRect(x: body.minX + inset, y: body.minY + inset,
                  width: (body.width - 2 * inset) * 0.75, height: body.height - 2 * inset)
NSColor.white.withAlphaComponent(0.4).setFill()
NSBezierPath(roundedRect: fill, xRadius: 2 * k, yRadius: 2 * k).fill()
// Логотип по центру, крупно — как в значке, с обрезкой по корпусу.
let logoH = body.height * 0.82
let logoW = logoH * HyperXLogo.aspect
let logoRect = NSRect(x: body.midX - logoW / 2, y: body.midY - logoH / 2, width: logoW, height: logoH)
red.setFill()
HyperXLogo.path(in: logoRect).fill()
NSGraphicsContext.restoreGraphicsState()

bodyPath.lineWidth = 1.0 * k
NSColor.white.withAlphaComponent(0.9).setStroke()
bodyPath.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Готово: \(out)")
