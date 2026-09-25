import Foundation
import IOKit.ps
import CoreAudio
import Combine

/// Baterie a sluchátka: při připojení nabíječky nebo AirPods se na 3 s ukáže stav v křídlech.
@MainActor
final class PowerService: ObservableObject {
    static let shared = PowerService()
    struct Flash: Equatable { let icon: String; let text: String; let level: Int; let charging: Bool }
    @Published private(set) var flash: Flash?
    private var runLoopSource: CFRunLoopSource?
    private var lastCharging: Bool?
    private var lastOutputUID = ""
    private var hideWork: DispatchWorkItem?

    private init() {
        // baterie / nabíječka
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerService>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in me.powerChanged() }
        }, ctx)?.takeRetainedValue() {
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        lastCharging = Self.batteryInfo()?.charging
        // výstupní audio zařízení (AirPods)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in self?.outputChanged() }
        lastOutputUID = Self.defaultOutputName()
    }

    private func powerChanged() {
        guard let info = Self.batteryInfo() else { return }
        if info.charging != lastCharging {
            lastCharging = info.charging
            show(Flash(icon: info.charging ? "battery.100.bolt" : "battery.75", text: info.charging ? L("Nabíjení") : L("Odpojeno"), level: info.level, charging: info.charging))
        }
    }

    private func outputChanged() {
        let name = Self.defaultOutputName()
        guard name != lastOutputUID else { return }
        lastOutputUID = name
        guard !name.isEmpty, Self.isBluetoothOutput() else { return }
        // baterie sluchátek se v registru objeví chvilku po připojení
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let level = Self.headphoneBattery(matching: name)
            self?.show(Flash(icon: "airpodspro", text: name, level: level ?? -1, charging: false))
        }
    }

    private func show(_ f: Flash) {
        hideWork?.cancel()
        flash = f
        let w = DispatchWorkItem { [weak self] in self?.flash = nil }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: w)
    }

    // MARK: IOKit / CoreAudio helpers
    nonisolated static func batteryInfo() -> (level: Int, charging: Bool)? {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            let cap = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let charging = (d[kIOPSIsChargingKey] as? Bool ?? false) || (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (cap, charging)
        }
        return nil
    }

    nonisolated static func defaultOutputName() -> String {
        var dev = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return "" }
        var name: CFString = "" as CFString; size = UInt32(MemoryLayout<CFString>.size)
        addr.mSelector = kAudioObjectPropertyName
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &name) == noErr ? name as String : ""
    }

    nonisolated static func isBluetoothOutput() -> Bool {
        var dev = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return false }
        var transport: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Baterie BT sluchátek z IORegistry (AppleDeviceManagementHIDEventService: BatteryPercent / BatteryPercentLeft/Right).
    nonisolated static func headphoneBattery(matching name: String) -> Int? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Int? = nil
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS, let d = props?.takeRetainedValue() as? [String: Any] else { continue }
            let product = (d["Product"] as? String) ?? ""
            let levels = ["BatteryPercentLeft", "BatteryPercentRight", "BatteryPercent"].compactMap { d[$0] as? Int }.filter { $0 > 0 }
            guard !levels.isEmpty else { continue }
            let l = levels.min()!
            if !product.isEmpty, name.localizedCaseInsensitiveContains(product) || product.localizedCaseInsensitiveContains(name) { return l }
            best = best ?? l
        }
        return best
    }
}
