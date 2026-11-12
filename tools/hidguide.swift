// Пошаговая запись нажатий кнопок HyperX Cloud Flight S.
// Каждый шаг: действие → 3 с подготовки → «ПОЕХАЛИ» → нажимайте несколько раз подряд;
// шаг кончается через 2 с после последнего нажатия (или через 10 с, если нажатий не было). В конце — сводка по кнопкам. Полный лог — в файл из аргумента.
// Сборка и запуск: swiftc tools/hidguide.swift -o build/hidguide && build/hidguide build/capture.log
import Foundation
import IOKit.hid

setvbuf(stdout, nil, _IOLBF, 0)

let buttons = [
    "Крестовина: ВЕРХНЯЯ кнопка",
    "Крестовина: НИЖНЯЯ кнопка",
    "Крестовина: ЛЕВАЯ кнопка",
    "Крестовина: ПРАВАЯ кнопка",
    "Кнопка 7.1 SURROUND",
    "Колёсико громкости ВВЕРХ (1 щелчок)",
    "Колёсико громкости ВНИЗ (1 щелчок)",
    "Кнопка ПИТАНИЯ (коротко, НЕ удерживать)",
]
let prepare: TimeInterval = 3
let window: TimeInterval = 10
let idleAfterPress: TimeInterval = 2

struct Event { let button: Int; let time: Date; let id: UInt32; let bytes: [UInt8] }
var events: [Event] = []
var current = -1
var pressed = false
var lastPress = Date.distantPast
var pressCount = 0

let logPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "capture.log"
FileManager.default.createFile(atPath: logPath, contents: nil)
let logHandle = FileHandle(forWritingAtPath: logPath)!
let fmt = DateFormatter(); fmt.dateFormat = "HH:mm:ss.SSS"
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }
func log(_ s: String) { logHandle.write(Data((s + "\n").utf8)) }

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey: 0x0951, kIOHIDProductIDKey: 0x16EA] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
guard let dev = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>)?.first else { print("Донгл не найден"); exit(1) }
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
IOHIDDeviceRegisterInputReportCallback(dev, buf, 64, { _, _, _, _, rid, rep, len in
    let b = Array(UnsafeBufferPointer(start: rep, count: len))
    events.append(Event(button: current, time: Date(), id: rid, bytes: b))
    log("\(fmt.string(from: Date()))  кнопка \(current >= 0 ? buttons[current] : "—")  id=0x\(String(rid, radix: 16)) len=\(len): \(hex(b))")
    let kind: String
    switch rid {
    case 0x0A: kind = "состояние"
    case 0x0B: kind = "событие"
    case 0x02: kind = b.count > 1 && b[1] == 0 ? "медиа-клавиша отпущена" : "медиа-клавиша"
    default: kind = "отчёт"
    }
    print("        • \(kind) id=0x\(String(rid, radix: 16)): \(hex(b))")
    // Нажатием считаем событие кнопки (0b … 04), нажатую медиа-клавишу и любой незнакомый отчёт;
    // ответы о заряде, отпускание клавиш и отчёты состояния — нет.
    let isButtonEvent = rid == 0x0B && b.count > 3 && b[3] == 0x04
    let isMediaPress = rid == 0x02 && b.count > 1 && b[1] != 0
    if isButtonEvent || isMediaPress || (rid != 0x0A && rid != 0x02 && rid != 0x0B) {
        pressed = true
        lastPress = Date()
        pressCount += 1
    }
}, nil)

func run(for seconds: TimeInterval, untilPress: Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if untilPress && pressed { return true }
        CFRunLoopRunInMode(.defaultMode, 0.05, false)
    }
    return pressed
}

print("Запись кнопок: \(buttons.count) шагов. На каждом шаге нажмите кнопку несколько раз подряд.\n")
for (bi, name) in buttons.enumerated() {
    current = -1
    print("━━━ \(bi + 1)/\(buttons.count)  \(name) — несколько раз подряд")
    print("     приготовьтесь… 3 с")
    _ = run(for: prepare, untilPress: false)
    pressed = false
    pressCount = 0
    current = bi
    log("=== \(name)")
    print("     ▶ ПОЕХАЛИ")
    if run(for: window, untilPress: true) {
        // Ждём, пока нажатия не прекратятся на idleAfterPress секунд.
        while Date().timeIntervalSince(lastPress) < idleAfterPress {
            CFRunLoopRunInMode(.defaultMode, 0.05, false)
        }
        print("     ✓ нажатий: \(pressCount)\n")
    } else {
        print("     — нажатия нет\n")
    }
    current = -1
}

// Сводка по кнопкам.
var out = "\n══════ СВОДКА ══════\n"
for (bi, name) in buttons.enumerated() {
    let ev = events.filter { $0.button == bi }
    out += "\n\(name)\n"
    if ev.isEmpty { out += "  ничего не пришло\n"; continue }
    var seen: [String: Int] = [:]
    var order: [String] = []
    for e in ev {
        let key = "id=0x\(String(e.id, radix: 16)): \(hex(e.bytes))"
        if seen[key] == nil { order.append(key) }
        seen[key, default: 0] += 1
    }
    for k in order { out += "  ×\(seen[k]!)  \(k)\n" }
}
print(out)
log(out)
print("Готово. Полный лог: \(logPath)")
