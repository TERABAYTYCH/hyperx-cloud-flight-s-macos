import Foundation

/// Оценка оставшегося времени работы по накопленной статистике разряда.
///
/// Показания заряда сравниваются с опорной точкой. Если между ними гарнитура была на связи без перерыва
/// (не выключалась, Mac не засыпал), то прошедшее время и упавшие проценты добавляются в статистику.
/// Скорость разряда = сумма упавших процентов / сумма часов работы. Статистика сохраняется между запусками
/// и «скользит»: учитываются примерно последние `windowHours` часов, так что оценка подстраивается
/// под износ аккумулятора и манеру использования.
final class BatteryEstimator {
    /// Сколько часов работы помнить.
    static let windowHours = 100.0
    /// Минимум данных для оценки: меньше — слишком грубо из-за целых процентов.
    static let minHours = 2.0
    static let minDrained = 5.0
    /// Подъём на столько процентов и больше (или до 100%) — зарядка. Меньший подъём — дрожание показаний.
    static let chargeRise = 3

    private enum Keys {
        static let drained = "estimator.drainedPercent"
        static let hours = "estimator.hours"
    }

    private struct Point {
        let percent: Int
        let date: Date
        /// Монотонное время без учёта сна — по расхождению с `date` видно, что Mac спал или часы перевели.
        let uptime: TimeInterval
    }

    private let defaults: UserDefaults
    /// Опорная точка текущего отрезка.
    private var anchor: Point?
    /// Предыдущее показание — по нему ищем перерывы.
    private var previous: Point?

    /// Отрезок длиннее этого не учитывается: скорее всего, между показаниями был незамеченный перерыв.
    var maxGap: TimeInterval = 2 * 15 * 60 + 5 * 60

    /// Всего процентов разряда и часов работы в статистике.
    private(set) var drainedPercent: Double
    private(set) var hours: Double

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        drainedPercent = defaults.double(forKey: Keys.drained)
        hours = defaults.double(forKey: Keys.hours)
    }

    /// Средняя скорость разряда, % в час, или nil, если данных пока мало.
    var drainRate: Double? {
        guard hours >= Self.minHours, drainedPercent >= Self.minDrained else { return nil }
        return drainedPercent / hours
    }

    /// Сколько ещё проработает гарнитура при текущем заряде, или nil, если данных мало.
    func remaining(percent: Int) -> TimeInterval? {
        guard let rate = drainRate, rate > 0 else { return nil }
        return Double(percent) / rate * 3600
    }

    /// Новое показание заряда.
    func record(percent: Int, at date: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let point = Point(percent: percent, date: date, uptime: uptime)
        defer { self.previous = point }
        guard let anchor, let previous else { self.anchor = point; return }

        // Перерыв между соседними показаниями: Mac спал (монотонное время отстаёт от часов),
        // часы перевели или показаний долго не было. Что было в перерыве — неизвестно.
        let step = uptime - previous.uptime
        let wallStep = date.timeIntervalSince(previous.date)
        if step < 0 || abs(wallStep - step) > 60 || step > maxGap {
            debugLog(String(format: "оценка: перерыв %.0f с (по часам %.0f с) — новый отрезок", step, wallStep))
            self.anchor = point
            return
        }

        let elapsed = uptime - anchor.uptime
        let dropped = anchor.percent - percent

        if dropped <= -Self.chargeRise || (dropped < 0 && percent == 100) {
            debugLog("оценка: заряд вырос \(anchor.percent)% → \(percent)%, похоже на зарядку — новый отрезок")
            self.anchor = point
            return
        }
        if dropped < 0 {
            // Дрожание на границе процентов: опорную точку не трогаем, иначе падения считались бы,
            // а подъёмы нет, и скорость завышалась бы.
            return
        }
        guard elapsed > 0 else { return }
        if anchor.percent == 100 {
            // Плато после зарядки или работа от кабеля: разряд не виден, время не берём.
            // Первое показание ниже 100 тоже только начинает отрезок: этот процент копился всё плато,
            // а засчитался бы за один интервал опроса.
            self.anchor = point
            return
        }
        add(drained: Double(dropped), hours: elapsed / 3600)
        self.anchor = point
    }

    /// Непрерывность прервалась (гарнитура выключалась, донгл вынимали, Mac засыпал):
    /// следующее показание начнёт новый отрезок.
    func breakSession(_ reason: String) {
        if anchor != nil { debugLog("оценка: разрыв (\(reason))") }
        anchor = nil
        previous = nil
    }

    private func add(drained: Double, hours addedHours: Double) {
        drainedPercent += drained
        hours += addedHours
        // Скользящее окно: старые данные пропорционально «забываются».
        if hours > Self.windowHours {
            let scale = Self.windowHours / hours
            drainedPercent *= scale
            hours *= scale
        }
        defaults.set(drainedPercent, forKey: Keys.drained)
        defaults.set(hours, forKey: Keys.hours)
        debugLog(String(format: "оценка: +%.0f%% за %.2f ч, всего %.1f%% за %.1f ч", drained, addedHours, drainedPercent, hours))
    }
}
