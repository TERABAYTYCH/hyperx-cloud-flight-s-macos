import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let pollMinutes = "pollMinutes"
        static let showPercent = "showPercent"
        static let hideWhenOffline = "hideWhenOffline"
    }
    private static let intervals = [1, 5, 15, 30, 60]
    private static let lowBatteryThreshold = 15
    /// Сколько показывать скрытый значок после повторного запуска приложения.
    private static let revealDuration: TimeInterval = 60

    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var appearanceObservation: NSKeyValueObservation?
    private var monitor: HeadsetMonitor!

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let detailLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let remainingLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let estimator = BatteryEstimator()
    private let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .short
        f.maximumUnitCount = 2
        return f
    }()
    private let showPercentItem = NSMenuItem(title: L("Show Percentage in Icon"), action: #selector(toggleShowPercent), keyEquivalent: "")
    private let hideOfflineItem = NSMenuItem(title: L("Hide When Headset Is Off"), action: #selector(toggleHideWhenOffline), keyEquivalent: "")
    private var revealTimer: Timer?
    private var menuIsOpen = false
    private let loginItem = NSMenuItem(title: L("Launch at Login"), action: #selector(toggleLoginItem), keyEquivalent: "")
    private var intervalItems: [NSMenuItem] = []
    private var buttonActionItems: [NSMenuItem] = []
    private let pressRecognizer = ButtonPressRecognizer()
    private let accessItem = NSMenuItem(title: "", action: #selector(requestEventAccess), keyEquivalent: "")

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Keys.pollMinutes: 15, Keys.showPercent: true, Keys.hideWhenOffline: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "hyperx-battery"
        statusItem.behavior = []  // не даём убрать значок перетаскиванием с ⌘ — видимостью управляем сами
        statusItem.button?.imagePosition = .imageOnly
        // Строка меню меняет тему вместе с системой и обоями — перерисовываем значок.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.render() }
        }
        statusItem.menu = buildMenu()

        monitor = HeadsetMonitor(pollInterval: TimeInterval(pollMinutes * 60))
        monitor.onChange = { [weak self] _ in self?.render() }
        monitor.onReading = { [weak self] percent in
            self?.estimator.record(percent: percent)
            self?.render()
        }
        monitor.onSessionBreak = { [weak self] reason in self?.estimator.breakSession(reason) }
        estimator.maxGap = Self.maxReadingGap(pollMinutes: pollMinutes)
        pressRecognizer.hasDoubleAction = { [weak self] in self?.action(for: $0, double: true) != ButtonAction.none }
        pressRecognizer.onPress = { [weak self] button, double in self?.action(for: button, double: double).perform() }
        monitor.onButton = { [weak self] in self?.pressRecognizer.press($0) }
        render()
        monitor.start()

        // Медиа-действия на кнопках требуют «Универсальный доступ» — спрашиваем сразу, а не при первом нажатии.
        if needsMediaAccess && !MediaKeys.hasAccess { CGRequestPostEventAccess() }
        observeAccessChanges()
        // Нажатие не дошло из-за разрешения (например, его сбросило обновление) — показываем значок с пунктом
        // «Разрешить…». Дошло через вспомогательный процесс — значит, разрешение уже есть.
        MediaKeys.onAccessResult = { [weak self] sent in
            self?.setMediaAccess(sent)
            if !sent { self?.reveal() }
        }
        // Значок виден минуту после любого запуска, даже если гарнитура выключена: видно, что приложение работает.
        reveal()

        // Пока Mac спит, мы не знаем, была ли гарнитура включена, — этот отрезок в оценку не берём.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.estimator.breakSession("сон Mac") }

        // После сна HID-сессия жива, но значение устарело — перезапрашиваем.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.monitor.requestBattery() }
        }
    }

    /// Повторный запуск уже работающего приложения (Finder, Spotlight, `open`) — показываем скрытый значок.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reveal()
        return false
    }

    private func reveal() {
        revealTimer?.invalidate()
        let timer = Timer(timeInterval: Self.revealDuration, repeats: false) { [weak self] _ in
            self?.revealTimer = nil
            self?.render()
        }
        RunLoop.main.add(timer, forMode: .common)
        revealTimer = timer
        render()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - Меню

    private var pollMinutes: Int {
        get { defaults.integer(forKey: Keys.pollMinutes) }
        set { defaults.set(newValue, forKey: Keys.pollMinutes) }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "HyperX Cloud Flight S", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        statusLine.isEnabled = false
        detailLine.isEnabled = false
        remainingLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(remainingLine)
        menu.addItem(detailLine)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: L("Refresh Now"), action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let intervalMenu = NSMenu()
        for minutes in Self.intervals {
            let item = NSMenuItem(title: String(format: L("%d min"), minutes), action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            intervalMenu.addItem(item)
            intervalItems.append(item)
        }
        let intervalItem = NSMenuItem(title: L("Polling Interval"), action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())
        menu.addItem(buildButtonsMenuItem())
        accessItem.target = self
        menu.addItem(accessItem)
        menu.addItem(.separator())

        showPercentItem.target = self
        menu.addItem(showPercentItem)
        hideOfflineItem.target = self
        hideOfflineItem.toolTip = L("To bring a hidden icon back for a minute, open the app again")
        menu.addItem(hideOfflineItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Пока меню открыто, значок не прячем (см. `render`).
        menuIsOpen = true
        for item in intervalItems { item.state = item.tag == pollMinutes ? .on : .off }
        showPercentItem.state = defaults.bool(forKey: Keys.showPercent) ? .on : .off
        hideOfflineItem.state = defaults.bool(forKey: Keys.hideWhenOffline) ? .on : .off
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on
        case .requiresApproval: loginItem.state = .mixed
        default: loginItem.state = .off
        }
        for item in buttonActionItems {
            guard let binding = item.representedObject as? ButtonBinding else { continue }
            item.state = action(for: binding.button, double: binding.double) == binding.action ? .on : .off
        }
        // Пункт про разрешение показываем, только если оно нужно и его ещё нет.
        accessItem.title = L("Allow Media Control (Accessibility)…")
        updateAccessItem()
        // Пока меню открыто, уточняем состояние в свежем процессе — пункт исчезнет, если разрешение уже выдано.
        if !accessItem.isHidden { refreshMediaAccess() }
        render()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        // Применяем отложенное скрытие уже после закрытия меню.
        DispatchQueue.main.async { self.render() }
    }

    // MARK: - Кнопки гарнитуры

    /// Какое действие на какой кнопке выбрано пунктом меню.
    private struct ButtonBinding {
        let button: HeadsetButton
        let double: Bool
        let action: ButtonAction
    }

    fileprivate var needsMediaAccess: Bool {
        HeadsetButton.allCases.contains {
            action(for: $0, double: false).needsEventAccess || action(for: $0, double: true).needsEventAccess
        }
    }

    private func defaultsKey(_ button: HeadsetButton, double: Bool) -> String {
        "button." + button.rawValue + (double ? ".double" : "")
    }

    private func action(for button: HeadsetButton, double: Bool) -> ButtonAction {
        defaults.string(forKey: defaultsKey(button, double: double)).flatMap(ButtonAction.init(rawValue:))
            ?? (double ? button.defaultDoubleAction : button.defaultAction)
    }

    private func buildButtonsMenuItem() -> NSMenuItem {
        let buttonsMenu = NSMenu()
        buttonsMenu.autoenablesItems = false
        for button in HeadsetButton.allCases {
            let actionsMenu = NSMenu()
            actionsMenu.autoenablesItems = false
            for double in [false, true] {
                if double { actionsMenu.addItem(.separator()) }
                let header = NSMenuItem(title: double ? L("Double Press") : L("Single Press"), action: nil, keyEquivalent: "")
                header.isEnabled = false
                actionsMenu.addItem(header)
                for action in ButtonAction.allCases {
                    let item = NSMenuItem(title: action.title, action: #selector(selectButtonAction(_:)), keyEquivalent: "")
                    item.target = self
                    item.indentationLevel = 1
                    item.representedObject = ButtonBinding(button: button, double: double, action: action)
                    actionsMenu.addItem(item)
                    buttonActionItems.append(item)
                }
            }
            let buttonItem = NSMenuItem(title: button.title, action: nil, keyEquivalent: "")
            buttonItem.submenu = actionsMenu
            buttonsMenu.addItem(buttonItem)
        }
        buttonsMenu.addItem(.separator())
        let note = NSMenuItem(title: String(format: L("Works when the buttons are set to multimedia\nactions in NGENUITY (otherwise the headset\nperforms its own default action first).\nIf a double press is assigned, a single press\nfires after a %.1f s delay"), ButtonPressRecognizer.window), action: nil, keyEquivalent: "")
        note.isEnabled = false
        buttonsMenu.addItem(note)
        let item = NSMenuItem(title: L("Headset Buttons"), action: nil, keyEquivalent: "")
        item.submenu = buttonsMenu
        return item
    }

    @objc private func selectButtonAction(_ sender: NSMenuItem) {
        guard let binding = sender.representedObject as? ButtonBinding else { return }
        let action = binding.action
        defaults.set(action.rawValue, forKey: defaultsKey(binding.button, double: binding.double))
        if action.needsEventAccess && !mediaAccessGranted { CGRequestPostEventAccess() }
        updateAccessItem()
    }

    /// Последнее известное состояние разрешения. Обновляется проверкой в свежем процессе, потому что
    /// ответ macOS внутри этого процесса кэшируется и после выдачи разрешения остаётся «нет».
    private lazy var mediaAccessGranted = MediaKeys.hasAccess

    private func setMediaAccess(_ granted: Bool) {
        if granted != mediaAccessGranted { debugLog("разрешение «Универсальный доступ»: \(granted ? "есть" : "нет")") }
        mediaAccessGranted = granted
        updateAccessItem()
    }

    private func refreshMediaAccess() {
        MediaKeys.checkFresh { [weak self] in self?.setMediaAccess($0) }
    }

    private func updateAccessItem() {
        accessItem.isHidden = !needsMediaAccess || mediaAccessGranted
    }

    /// Следим за списком «Универсального доступа»: macOS рассылает уведомление при каждом его изменении.
    private func observeAccessChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // TCC обновляет базу не мгновенно — проверяем сразу и ещё пару раз.
            for delay in [0.3, 1.5, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.refreshMediaAccess() }
            }
        }
    }

    /// «Разрешить управление медиа…» — показать системный диалог с кнопкой «Открыть Системные настройки».
    /// macOS показывает его, только пока приложения нет в списке. Запись от прошлой сборки (ad-hoc подпись
    /// меняется при каждой сборке) мешает диалогу и уже не действует, поэтому сначала сбрасываем запись
    /// этого приложения — и только его.
    @objc private func requestEventAccess() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", bundleID]
        reset.terminationHandler = { process in
            let ok = process.terminationStatus == 0
            DispatchQueue.main.async {
                debugLog("tccutil reset Accessibility: \(ok ? "ok" : "ошибка \(process.terminationStatus)")")
                NSApp.activate(ignoringOtherApps: true)
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                if !AXIsProcessTrustedWithOptions(options) && !ok {
                    // Сбросить не вышло — диалога может не быть, открываем настройки сами.
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
        do { try reset.run() } catch { reset.terminationHandler?(reset) }
    }

    @objc private func refreshNow() {
        monitor.requestBattery()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        pollMinutes = sender.tag
        monitor.pollInterval = TimeInterval(sender.tag * 60)
        estimator.maxGap = Self.maxReadingGap(pollMinutes: sender.tag)
        // Свежее показание сразу: иначе шаг от старого, редкого опроса оценщик примет за перерыв.
        monitor.requestBattery()
    }

    @objc private func toggleShowPercent() {
        defaults.set(!defaults.bool(forKey: Keys.showPercent), forKey: Keys.showPercent)
        render()
    }

    @objc private func toggleHideWhenOffline() {
        defaults.set(!defaults.bool(forKey: Keys.hideWhenOffline), forKey: Keys.hideWhenOffline)
        // Включили скрытие из меню — не прячем значок прямо из-под курсора, даём минуту.
        reveal()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                // macOS может потребовать подтвердить объект входа вручную.
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Couldn’t Change Launch at Login")
            alert.informativeText = error.localizedDescription + "\n\n" + L("Move the app to Applications and try again, or add it manually: System Settings → General → Login Items.")
            NSApp.activate(ignoringOtherApps: true)
            alert.window.level = .floating
            alert.runModal()
        }
    }

    // MARK: - Отрисовка

    /// Дольше этого между показаниями — значит, гарнитура была не на связи (два пропущенных опроса и запас).
    private static func maxReadingGap(pollMinutes: Int) -> TimeInterval {
        TimeInterval(2 * pollMinutes * 60 + 5 * 60)
    }

    /// Оценка грубая, поэтому без ложной точности: часы, если осталось много, и минуты, только когда мало.
    private static func roundRemaining(_ seconds: TimeInterval) -> TimeInterval {
        let step: TimeInterval = seconds >= 3 * 3600 ? 3600 : seconds >= 3600 ? 15 * 60 : 5 * 60
        return max(step, (seconds / step).rounded() * step)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let showPercent = defaults.bool(forKey: Keys.showPercent)

        // Значок не шаблонный (в нём фирменный красный), поэтому тему строки меню учитываем сами.
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let icon: NSImage
        let tooltip: String

        switch monitor.state {
        case .disconnected:
            icon = BatteryIcon.make(text: nil, dark: dark, dimmed: true)
            tooltip = L("Dongle not connected")
            statusLine.title = L("Dongle not connected")
        case .waiting:
            icon = BatteryIcon.make(text: showPercent ? "…" : nil, dark: dark, dimmed: true)
            tooltip = L("Waiting for the headset…")
            statusLine.title = L("Waiting for response…")
        case .noResponse:
            icon = BatteryIcon.make(text: showPercent ? "–" : nil, dark: dark, dimmed: true)
            tooltip = L("Headset not responding (turned off?)")
            statusLine.title = L("Headset not responding (turned off?)")
        case let .battery(percent, millivolts):
            let low = percent <= Self.lowBatteryThreshold
            icon = BatteryIcon.make(
                text: showPercent ? "\(percent)" : nil,
                level: Double(percent) / 100,
                dark: dark,
                low: low
            )
            tooltip = String(format: L("Battery: %d%%"), percent)
            statusLine.title = String(format: L("Battery: %d%% · %.2f V"), percent, Double(millivolts) / 1000)
            if let seconds = estimator.remaining(percent: percent) {
                // С момента показания гарнитура продолжала разряжаться.
                let sinceReading = max(0, monitor.lastReading.map { Date().timeIntervalSince($0.date) } ?? 0)
                let text = durationFormatter.string(from: Self.roundRemaining(seconds - sinceReading)) ?? ""
                remainingLine.title = String(format: L("About %@ left"), text)
            } else {
                remainingLine.title = L("Time left: collecting data…")
            }
        }

        if case .battery = monitor.state {
            remainingLine.isHidden = false
        } else {
            remainingLine.isHidden = true
        }

        if let reading = monitor.lastReading {
            let time = timeFormatter.string(from: reading.date)
            if case .battery = monitor.state {
                detailLine.title = String(format: L("Updated at %@"), time)
            } else {
                detailLine.title = String(format: L("Last: %d%% at %@"), reading.percent, time)
            }
            detailLine.isHidden = false
        } else {
            detailLine.isHidden = true
        }

        // Без данных о заряде (донгл отключён, гарнитура выключена, ждём ответа) значок прячем, если так настроено.
        var online = false
        if case .battery = monitor.state { online = true }
        statusItem.isVisible = online || !defaults.bool(forKey: Keys.hideWhenOffline) || revealTimer != nil || menuIsOpen

        icon.accessibilityDescription = tooltip
        button.image = icon
        button.title = ""
        button.toolTip = tooltip
    }
}

// Служебные режимы вспомогательного процесса (см. `MediaKeys.runHelper`): свежий процесс видит актуальное
// разрешение, тогда как в основном оно закэшировано.
let arguments = CommandLine.arguments
if arguments.contains("--check-access") {
    exit(CGPreflightPostEventAccess() ? 0 : 1)
}
if let i = arguments.firstIndex(of: "--press"), i + 1 < arguments.count,
   let raw = Int(arguments[i + 1]), let key = MediaKeys.Key(rawValue: raw) {
    guard CGPreflightPostEventAccess() else { exit(1) }
    MediaKeys.post(key)
    usleep(50_000)  // даём событиям уйти до выхода процесса
    exit(0)
}

// Второй экземпляр (например, `open -n`) не нужен: кнопки сработали бы дважды. Будим первый и выходим.
if let bundleID = Bundle.main.bundleIdentifier,
   let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
       .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    if let url = other.bundleURL { NSWorkspace.shared.open(url) }  // придёт reopen → значок покажется
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
