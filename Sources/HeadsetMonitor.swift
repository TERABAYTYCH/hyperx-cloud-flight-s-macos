import Foundation
import IOKit.hid

/// Состояние гарнитуры, которое видит UI.
enum HeadsetState: Equatable {
    case disconnected                 // донгл не подключён
    case waiting                      // донгл есть, ответа ещё не было
    case noResponse                   // донгл есть, гарнитура не отвечает (скорее всего выключена)
    case battery(percent: Int, millivolts: Int)
}

/// Работа с донглом HyperX Cloud Flight S через IOHIDManager.
///
/// Протокол (из оригинального Electron-приложения, проверено на macOS):
///  * запрос — output report 0x06: 06 00 02 00 9a 00 00 68 4a 8e 0a 00 00 00 bb 02 (+ нули до 62 байт);
///  * ответ — input report (на macOS приходит как 0x0B длиной 12 байт, на Windows hidapi отдаёт 62):
///    data[3] == 0x02, data[5..6] — напряжение в мВ (big-endian), data[7] — заряд в процентах;
///  * data[3] == 0x01 && data[4] == 0x01 — гарнитура только что включилась, 0x03 — выключается (долгое нажатие питания);
///  * 0x0B с data[3] == 0x04 — нажатие кнопки: data[4] верх, [5] лево, [6] право, [7] низ, [8] 7.1.
///    Если в NGENUITY кнопкам назначены «мультимедийные» действия, гарнитура сама ничего не делает —
///    только шлёт это событие; иначе вслед приходит отчёт состояния 0x0A (мониторинг, mute, баланс).
///  * колёсико громкости — стандартный consumer-отчёт 0x02 (01 громче / 02 тише), его обрабатывает macOS.
final class HeadsetMonitor {
    static let vendorID = 0x0951   // 2385
    static let productID = 0x16EA  // 5866

    private static let requestReportID: CFIndex = 0x06
    private static let outputReportLength = 62
    private static let batteryRequest: [UInt8] = [
        0x06, 0x00, 0x02, 0x00, 0x9a, 0x00, 0x00, 0x68,
        0x4a, 0x8e, 0x0a, 0x00, 0x00, 0x00, 0xbb, 0x02,
    ]
    private static let responseTimeout: TimeInterval = 5
    private static let inputBufferSize = 64

    var onChange: ((HeadsetState) -> Void)?
    /// Нажатие кнопки на левой чашке (приходит событием 0x0B, см. `HeadsetButton`).
    var onButton: ((HeadsetButton) -> Void)?
    private(set) var state: HeadsetState = .disconnected {
        didSet { if state != oldValue { onChange?(state) } }
    }
    /// Последнее полученное значение — остаётся, даже если гарнитуру выключили.
    private(set) var lastReading: (percent: Int, millivolts: Int, date: Date)?

    private let manager: IOHIDManager
    private var device: IOHIDDevice?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var timeoutTimer: Timer?
    private var pollTimer: Timer?

    var pollInterval: TimeInterval {
        didSet { restartPolling() }
    }

    init(pollInterval: TimeInterval) {
        self.pollInterval = pollInterval
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        stop()
    }

    func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HeadsetMonitor>.fromOpaque(ctx).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HeadsetMonitor>.fromOpaque(ctx).takeUnretainedValue().detach(device)
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        debugLog("IOHIDManagerOpen -> \(hex(result))")
        restartPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        timeoutTimer?.invalidate()
        if let device { releaseDevice(device) }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Отправить запрос заряда. Ответ придёт асинхронно в input-callback.
    func requestBattery() {
        guard let device else { state = .disconnected; return }

        var report = [UInt8](repeating: 0, count: Self.outputReportLength)
        report.replaceSubrange(0..<Self.batteryRequest.count, with: Self.batteryRequest)
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, Self.requestReportID, report, report.count)
        debugLog("SetReport -> \(hex(result))")

        if result != kIOReturnSuccess {
            state = .noResponse
            return
        }
        if case .battery = state {} else { state = .waiting }

        timeoutTimer?.invalidate()
        let timer = Timer(timeInterval: Self.responseTimeout, repeats: false) { [weak self] _ in
            guard let self, self.device != nil else { return }
            debugLog("ответа нет за \(Self.responseTimeout) с")
            self.state = .noResponse
        }
        // .common — чтобы таймеры и HID-события работали и при открытом меню.
        RunLoop.main.add(timer, forMode: .common)
        timeoutTimer = timer
    }

    // MARK: - Устройство

    private func attach(_ newDevice: IOHIDDevice) {
        debugLog("подключено устройство")
        if let device { releaseDevice(device) }
        device = newDevice

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputBufferSize)
        inputBuffer = buffer
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(newDevice, buffer, Self.inputBufferSize, { ctx, _, _, _, reportID, report, length in
            guard let ctx else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<HeadsetMonitor>.fromOpaque(ctx).takeUnretainedValue().handle(reportID: reportID, bytes: bytes)
        }, ctx)

        state = .waiting
        // Донглу нужно мгновение после подключения, прежде чем он начнёт отвечать.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.requestBattery() }
    }

    private func detach(_ removed: IOHIDDevice) {
        guard removed == device else { return }
        debugLog("устройство отключено")
        releaseDevice(removed)
        device = nil
        timeoutTimer?.invalidate()
        state = .disconnected
    }

    private func releaseDevice(_ device: IOHIDDevice) {
        guard let buffer = inputBuffer else { return }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.inputBufferSize, nil, nil)
        buffer.deallocate()
        inputBuffer = nil
    }

    private func handle(reportID: UInt32, bytes: [UInt8]) {
        debugLog("in rid=0x\(String(reportID, radix: 16)) len=\(bytes.count): " + bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
        guard bytes.count >= 8 else { return }

        if bytes[3] == 0x02, bytes[5] != 0 || bytes[6] != 0 {
            let percent = Int(bytes[7])
            guard (0...100).contains(percent) else { return }
            let millivolts = Int(bytes[5]) << 8 | Int(bytes[6])
            timeoutTimer?.invalidate()
            lastReading = (percent, millivolts, Date())
            state = .battery(percent: percent, millivolts: millivolts)
        } else if bytes[3] == 0x01, bytes[4] == 0x01 {
            debugLog("гарнитура включилась")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.requestBattery() }
        } else if bytes[3] == 0x01, bytes[4] == 0x03 {
            debugLog("гарнитура выключается")
            timeoutTimer?.invalidate()
            state = .noResponse
        } else if reportID == 0x0B, bytes[3] == 0x04, bytes.count >= 9 {
            // Кнопки: 0b 00 bb 04 <верх> <лево> <право> <низ> <7.1> — в нажатой позиции 01.
            for button in HeadsetButton.allCases where bytes[button.byteIndex] != 0 {
                debugLog("кнопка: \(button.title)")
                onButton?(button)
            }
        }
    }

    private func restartPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.requestBattery()
        }
        timer.tolerance = min(30, pollInterval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Утилиты

    private func hex(_ value: IOReturn) -> String {
        String(format: "0x%08x", UInt32(bitPattern: value))
    }
}
