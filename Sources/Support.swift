import Foundation

private let debugEnabled = ProcessInfo.processInfo.environment["HYPERX_DEBUG"] != nil

/// Отладочный вывод в stderr при `HYPERX_DEBUG=1`.
func debugLog(_ message: @autoclosure () -> String) {
    if debugEnabled {
        FileHandle.standardError.write(Data("[HyperX] \(message())\n".utf8))
    }
}

/// Локализованная строка: ключ — английский текст, перевод — в Resources/<язык>.lproj/Localizable.strings.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
