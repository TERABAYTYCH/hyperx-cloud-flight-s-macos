import CoreAudio
import Foundation

/// Переключение устройства вывода звука macOS (как выбор в меню «Звук»).
enum AudioOutput {
    /// Сделать устройством вывода первое устройство вывода, в имени которого есть `nameContains`.
    @discardableResult
    static func select(nameContains needle: String) -> Bool {
        guard let device = outputDevices().first(where: { $0.name.localizedCaseInsensitiveContains(needle) }) else {
            debugLog("устройство вывода «\(needle)» не найдено")
            return false
        }
        return setDefault(device)
    }

    /// Встроенные динамики Mac. Ищем по типу подключения, а не по имени: имя зависит от модели и языка.
    /// Если встроенных выходов несколько (на старых Mac отдельно бывают наушники), предпочитаем источник «динамики».
    @discardableResult
    static func selectBuiltIn() -> Bool {
        let builtIn = outputDevices().filter { transportType(of: $0.id) == kAudioDeviceTransportTypeBuiltIn }
        guard let device = builtIn.first(where: { dataSource(of: $0.id) == internalSpeakerSource }) ?? builtIn.first else {
            debugLog("встроенные динамики не найдены")
            return false
        }
        return setDefault(device)
    }

    /// FourCC 'ispk' — источник данных «встроенные динамики».
    private static let internalSpeakerSource: UInt32 = 0x6973_706B

    private static func dataSource(of id: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var source: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &source) == noErr ? source : nil
    }

    private static func transportType(of id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type) == noErr ? type : 0
    }

    private static func setDefault(_ device: (id: AudioDeviceID, name: String)) -> Bool {
        var id = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        debugLog("вывод звука → \(device.name): \(status == noErr ? "ok" : "ошибка \(status)")")
        return status == noErr
    }

    private static func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id), let name = name(of: id) else { return nil }
            return (id, name)
        }
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
