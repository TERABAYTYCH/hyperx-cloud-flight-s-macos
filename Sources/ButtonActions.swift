import AppKit

/// Кнопки на левой чашке, которые приходят событием 0x0B (см. `HeadsetMonitor`).
enum HeadsetButton: String, CaseIterable {
    case up, left, right, down, surround

    /// Позиция флага нажатия в отчёте `0b 00 bb 04 …`.
    var byteIndex: Int {
        switch self {
        case .up: return 4
        case .left: return 5
        case .right: return 6
        case .down: return 7
        case .surround: return 8
        }
    }

    var title: String {
        switch self {
        case .up: return L("Up")
        case .left: return L("Left")
        case .right: return L("Right")
        case .down: return L("Down")
        case .surround: return "7.1 Surround"
        }
    }

    /// По умолчанию — как настроено в NGENUITY: верх Play/Pause, лево Next, право Previous, низ Mute Volume.
    /// 7.1 гарнитура переключает сама, поэтому ей по умолчанию ничего не назначаем.
    var defaultAction: ButtonAction {
        switch self {
        case .up: return .playPause
        case .left: return .next
        case .right: return .previous
        case .down: return .muteVolume
        case .surround: return .none
        }
    }

    /// Двойное нажатие по умолчанию: нижняя — вывод звука на гарнитуру (HyperX Game), верхняя — на встроенные динамики Mac.
    var defaultDoubleAction: ButtonAction {
        switch self {
        case .down: return .outputGame
        case .up: return .outputMac
        default: return .none
        }
    }
}

enum ButtonAction: String, CaseIterable {
    case none, playPause, next, previous, muteVolume, volumeUp, volumeDown, outputGame, outputChat, outputMac

    var title: String {
        switch self {
        case .none: return L("Nothing")
        case .playPause: return "Play/Pause"
        case .next: return L("Next Track")
        case .previous: return L("Previous Track")
        case .muteVolume: return L("Mute")
        case .volumeUp: return L("Volume Up")
        case .volumeDown: return L("Volume Down")
        case .outputGame: return L("Sound Output → HyperX Game")
        case .outputChat: return L("Sound Output → HyperX Chat")
        case .outputMac: return L("Sound Output → Mac Speakers")
        }
    }

    /// Нужна ли этому действию отправка системных медиа-клавиш (разрешение «Универсальный доступ»).
    var needsEventAccess: Bool {
        switch self {
        case .none, .outputGame, .outputChat, .outputMac: return false
        default: return true
        }
    }

    func perform() {
        switch self {
        case .none: break
        case .playPause: MediaKeys.press(.play)
        case .next: MediaKeys.press(.fast)        // F9 на клавиатуре Mac шлёт именно FAST — так понимают все плееры
        case .previous: MediaKeys.press(.rewind)  // и F7 — REWIND
        case .muteVolume: MediaKeys.press(.mute)
        case .volumeUp: MediaKeys.press(.soundUp)
        case .volumeDown: MediaKeys.press(.soundDown)
        case .outputGame: AudioOutput.select(nameContains: "Cloud Flight S Game")
        case .outputChat: AudioOutput.select(nameContains: "Cloud Flight S Chat")
        case .outputMac: AudioOutput.selectBuiltIn()
        }
    }
}

/// Системные медиа-клавиши (как на клавиатуре Mac): работают с любым плеером и показывают системный индикатор.
enum MediaKeys {
    /// Коды NX_KEYTYPE_* из <IOKit/hidsystem/ev_keymap.h>.
    enum Key: Int {
        case soundUp = 0, soundDown = 1, mute = 7, play = 16, fast = 19, rewind = 20
    }

    /// Есть ли разрешение отправлять события — по мнению этого процесса.
    /// macOS кэширует ответ внутри процесса: после выдачи разрешения здесь может оставаться `false`.
    static var hasAccess: Bool { CGPreflightPostEventAccess() }

    /// Нажатие дошло (`true`) или не дошло из-за отсутствия разрешения (`false`).
    static var onAccessResult: ((Bool) -> Void)?

    static func press(_ key: Key) {
        if hasAccess {
            debugLog("медиа-клавиша \(key)")
            post(key)
            return
        }
        // Ответ этого процесса мог устареть — отправляем через короткий вспомогательный процесс,
        // он видит актуальное разрешение. Так кнопки заработают сразу, без перезапуска приложения.
        runHelper(["--press", String(key.rawValue)]) { sent in
            debugLog("медиа-клавиша \(key) через вспомогательный процесс: \(sent ? "ok" : "нет разрешения")")
            onAccessResult?(sent)
        }
    }

    /// Проверить разрешение в свежем процессе.
    static func checkFresh(_ completion: @escaping (Bool) -> Void) {
        runHelper(["--check-access"], completion: completion)
    }

    /// Отправить медиа-клавишу (нажатие и отпускание).
    static func post(_ key: Key) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key.rawValue << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Запустить этот же бинарник в служебном режиме (см. конец main.swift). Результат — на main.
    private static func runHelper(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        guard let exe = Bundle.main.executablePath else { completion(false); return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: exe)
        helper.arguments = arguments
        helper.terminationHandler = { process in
            let ok = process.terminationReason == .exit && process.terminationStatus == 0
            DispatchQueue.main.async { completion(ok) }
        }
        do { try helper.run() } catch { completion(false); return }
        // Страховка от зависшего процесса.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if helper.isRunning { helper.terminate() } }
    }
}

/// Отличает одиночное нажатие от двойного. Гарнитура шлёт только событие «нажата» (без отпускания),
/// поэтому двойное — это второе событие той же кнопки в пределах `window`.
/// Если двойного действия у кнопки нет, одиночное срабатывает сразу, без задержки.
final class ButtonPressRecognizer {
    /// Обычные неторопливые повторные нажатия идут с интервалом 330–530 мс, быстрый «дабл» — короче.
    static let window: TimeInterval = 0.3

    var hasDoubleAction: (HeadsetButton) -> Bool = { _ in false }
    var onPress: (_ button: HeadsetButton, _ double: Bool) -> Void = { _, _ in }

    private var pending: [HeadsetButton: (timer: Timer, time: Date)] = [:]

    func press(_ button: HeadsetButton) {
        if let first = pending.removeValue(forKey: button) {
            first.timer.invalidate()
            debugLog("двойное нажатие: \(button.title), интервал \(Int(Date().timeIntervalSince(first.time) * 1000)) мс")
            onPress(button, true)
            return
        }
        guard hasDoubleAction(button) else {
            onPress(button, false)
            return
        }
        let timer = Timer(timeInterval: Self.window, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.pending[button] = nil
            self.onPress(button, false)
        }
        RunLoop.main.add(timer, forMode: .common)
        pending[button] = (timer, Date())
    }
}
