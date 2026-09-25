import AppKit
import Combine
import CoreAudio

struct CallApp: Identifiable, Equatable {
    let id: String   // bundle id
    let name: String
    let icon: String        // SF Symbol (záloha)
    var fa: String? = nil   // Font Awesome brand glyph
    var color: UInt = 0x4B5563
}

/// Detekce hovorů: běžící meetingové appky + zda někdo používá mikrofon (CoreAudio).
@MainActor
final class CallsService: ObservableObject {
    static let shared = CallsService()
    static let known: [CallApp] = [
        CallApp(id: "com.hnc.Discord", name: "Discord", icon: "gamecontroller.fill", fa: FA.discord, color: 0x5865F2),
        CallApp(id: "us.zoom.xos", name: "Zoom", icon: "video.fill", fa: nil, color: 0x2D8CFF),
        CallApp(id: "com.microsoft.teams2", name: "Teams", icon: "person.3.fill", fa: FA.microsoft, color: 0x6264A7),
        CallApp(id: "com.microsoft.teams", name: "Teams", icon: "person.3.fill", fa: FA.microsoft, color: 0x6264A7),
        CallApp(id: "com.apple.FaceTime", name: "FaceTime", icon: "video.fill", fa: nil, color: 0x34C759),
        CallApp(id: "com.google.Chrome", name: "Chrome (Meet)", icon: "globe", fa: FA.chrome, color: 0x4285F4),
        CallApp(id: "com.tinyspeck.slackmacgap", name: "Slack", icon: "number", fa: FA.slack, color: 0x4A154B),
        CallApp(id: "ru.keepcoder.Telegram", name: "Telegram", icon: "paperplane.fill", fa: FA.telegram, color: 0x2AABEE),
        CallApp(id: "net.whatsapp.WhatsApp", name: "WhatsApp", icon: "phone.fill", fa: FA.whatsapp, color: 0x25D366),
    ]
    @Published private(set) var running: [CallApp] = []
    @Published private(set) var micInUse = false
    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private func poll() {
        let apps = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        var seen = Set<String>()
        running = Self.known.filter { apps.contains($0.id) && seen.insert($0.name).inserted }
        micInUse = Self.isDefaultInputRunning()
    }

    /// Někdo právě čte z výchozího vstupního zařízení (mikrofonu)?
    private static func isDefaultInputRunning() -> Bool {
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Je pravděpodobně aktivní hovor? (mikrofon běží a je spuštěná nějaká hovorová appka)
    var onCall: Bool { micInUse && !running.isEmpty }
}
