import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI
import UserNotifications

// MARK: - Control Center Tab Navigation
enum ControlCenterTab: String, CaseIterable {
    case dictate = "Dictate"
    case flow = "Flow"
    case companion = "Companion"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .dictate: return "mic.fill"
        case .flow: return "timer"
        case .companion: return "sparkles"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - App State & Storage
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var statusText: String = "Ready"
    @Published var audioLevel: Float = 0.0
    @Published var recordDuration: Double = 0.0
    @Published var lastResultText: String = ""
    @Published var lastLatencyMs: Double = 0.0
    @Published var daemonReady: Bool = false
    @Published var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @Published var isMicrophoneGranted: Bool = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    @Published var currentMicName: String = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Default Microphone"
    @Published var selectedMicDevice: String = ":default"

    // Menu Bar Control Center Active Tab
    @Published var activeTab: ControlCenterTab = .dictate

    // MARK: - Flow Mode Focus Timer
    @Published var isFlowActive: Bool = false
    @Published var isFlowPaused: Bool = false
    @Published var flowRemainingSeconds: Int = 1500
    @Published var flowTotalSeconds: Int = 1500
    private var flowTimer: Timer? = nil

    var flowTimeString: String {
        let mins = flowRemainingSeconds / 60
        let secs = flowRemainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var flowProgress: CGFloat {
        guard flowTotalSeconds > 0 else { return 0 }
        return CGFloat(flowRemainingSeconds) / CGFloat(flowTotalSeconds)
    }

    func startFlow(minutes: Int) {
        flowTotalSeconds = minutes * 60
        flowRemainingSeconds = flowTotalSeconds
        isFlowPaused = false
        isFlowActive = true

        flowTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isFlowActive && !self.isFlowPaused {
                if self.flowRemainingSeconds > 0 {
                    self.flowRemainingSeconds -= 1
                } else {
                    self.completeFlowSession()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        flowTimer = t

        FloatingHUDController.shared.show()
    }

    func toggleFlowPause() {
        guard isFlowActive else { return }
        isFlowPaused.toggle()
    }

    func addFlowMinutes(_ minutes: Int) {
        guard isFlowActive else { return }
        flowRemainingSeconds += minutes * 60
        flowTotalSeconds += minutes * 60
    }

    func stopFlow() {
        flowTimer?.invalidate()
        flowTimer = nil
        isFlowActive = false
        isFlowPaused = false
    }

    func completeFlowSession() {
        stopFlow()
        NSSound(named: "Glass")?.play()
        FloatingHUDController.shared.triggerCuteClickReaction()

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Flow Session Completed! 🏆"
        content.body = "Great focus! Take a 5-minute break and recharge."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    // Settings
    @AppStorage("active_shortcut") var activeShortcut: String = "opt_space"
    @AppStorage("stt_engine") var sttEngine: String = "groq" // "groq", "local_mlx"
    @AppStorage("groq_key") var groqKey: String = ""
    @AppStorage("provider") var provider: String = "groq" // "groq", "openrouter", "ollama", "lmstudio", "local_rules"
    @AppStorage("openrouter_key") var openRouterKey: String = ""
    @AppStorage("openrouter_model") var openRouterModel: String = "meta/muse-spark-1.3-contributor"
    @AppStorage("ollama_url") var ollamaUrl: String = "http://127.0.0.1:11434"
    @AppStorage("ollama_model") var ollamaModel: String = "llama3.2"
    @AppStorage("lmstudio_url") var lmStudioUrl: String = "http://127.0.0.1:1234"
    @AppStorage("lmstudio_model") var lmStudioModel: String = "local-model"
    @AppStorage("use_llm_polish") var useLlmPolish: Bool = true
    @AppStorage("custom_vocab") var customVocab: String = "how far, abeg, naira, GitHub, PR, Velox, model, models"
    @AppStorage("auto_paste") var autoPaste: Bool = true
    @Published var openRouterBalanceText: String = "OpenRouter"

    // HUD Customization
    @AppStorage("hud_position") var hudPosition: String = "bottom_center" // "bottom_left", "bottom_center", "bottom_right"
    @AppStorage("hud_size") var hudSize: String = "compact"         // "mini", "compact", "spacious"
    @AppStorage("hud_character") var hudCharacter: String = "gearbot" // "gearbot", "neko", "luna", "kuro", "custom"
    @AppStorage("hud_color") var hudColor: String = "amber"         // "amber", "rose", "emerald", "cyan", "purple", "monochrome"
    @AppStorage("hud_always_show") var alwaysShowCompanion: Bool = true // Desktop pet companion mode
    @AppStorage("hud_y_offset") var hudYOffset: Double = 0.0        // User nudge from dock/bottom
    @AppStorage("hud_listening_style") var listeningStyle: String = "morph" // "morph", "character", "waveform"
    @AppStorage("app_theme") var appTheme: String = "system"        // "system", "dark", "light"
    @Published var isHUDDragging: Bool = false
    @Published var isHUDHovered: Bool = false
    @Published var isPetHappy: Bool = false
    @Published var petClickCount: Int = 0
    @Published var petReactionEmoji: String = "💖"

    // Live Cursor & Keyboard Interactivity (Fluid Look-At & Dynamic Typing Emotions)
    @Published var cursorLookX: Double = 0.0 // -1.0 (left) ... +1.0 (right)
    @Published var cursorLookY: Double = 0.0 // -1.0 (down) ... +1.0 (up)
    @Published var isCursorNear: Bool = false
    @Published var lastTypingTime: Double = 0.0
    @Published var typingStartTime: Double = 0.0
    @Published var typingKeystrokeCount: Int = 0
    @Published var typingSpeedBurst: Bool = false
    @Published var isUserTyping: Bool = false

    var hudWidth: CGFloat {
        switch hudSize {
        case "mini": return 104
        case "spacious": return 138
        default: return 120 // "compact"
        }
    }

    var hudHeight: CGFloat {
        switch hudSize {
        case "mini": return 32
        case "spacious": return 40
        default: return 36 // "compact"
        }
    }

    func increaseHUDSize() {
        if hudSize == "mini" {
            hudSize = "compact"
        } else if hudSize == "compact" {
            hudSize = "spacious"
        }
        saveConfigToDisk()
        FloatingHUDController.shared.applyHUDSize()
    }

    func decreaseHUDSize() {
        if hudSize == "spacious" {
            hudSize = "compact"
        } else if hudSize == "compact" {
            hudSize = "mini"
        }
        saveConfigToDisk()
        FloatingHUDController.shared.applyHUDSize()
    }

    func setHUDSize(_ size: String) {
        guard size == "mini" || size == "compact" || size == "spacious" else { return }
        hudSize = size
        saveConfigToDisk()
        FloatingHUDController.shared.applyHUDSize()
    }

    var hudAccentColor: Color {
        switch hudColor {
        case "rose": return Color(red: 0.957, green: 0.247, blue: 0.369)
        case "emerald": return Color(red: 0.063, green: 0.725, blue: 0.506)
        case "cyan": return Color(red: 0.024, green: 0.714, blue: 0.831)
        case "purple": return Color(red: 0.545, green: 0.361, blue: 0.965)
        case "monochrome": return Color(white: 0.92)
        default: return Color(red: 0.961, green: 0.620, blue: 0.043) // amber
        }
    }

    private init() {
        loadConfigFromDisk()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".parakeetflow/config.json")
    }

    func loadConfigFromDisk() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let stt = json["stt_engine"] as? String, !stt.isEmpty { self.sttEngine = stt }
        if let gkey = json["groq_key"] as? String, !gkey.isEmpty { self.groqKey = gkey }
        if let prov = json["provider"] as? String, !prov.isEmpty { self.provider = prov }
        if let key = json["openrouter_key"] as? String, !key.isEmpty { self.openRouterKey = key }
        if let model = json["openrouter_model"] as? String, !model.isEmpty { self.openRouterModel = model }
        if let ourl = json["ollama_url"] as? String, !ourl.isEmpty { self.ollamaUrl = ourl }
        if let omod = json["ollama_model"] as? String, !omod.isEmpty { self.ollamaModel = omod }
        if let lmurl = json["lmstudio_url"] as? String, !lmurl.isEmpty { self.lmStudioUrl = lmurl }
        if let lmmod = json["lmstudio_model"] as? String, !lmmod.isEmpty { self.lmStudioModel = lmmod }
        if let polish = json["use_llm_polish"] as? Bool { self.useLlmPolish = polish }
        if let vocab = json["custom_vocab"] as? String { self.customVocab = vocab }
        if let hpos = json["hud_position"] as? String, !hpos.isEmpty {
            if hpos == "left" || hpos == "bottom_left" {
                self.hudPosition = "left"
            } else if hpos == "right" || hpos == "bottom_right" {
                self.hudPosition = "right"
            } else {
                self.hudPosition = "bottom_center"
            }
        }
        if let hsize = json["hud_size"] as? String, !hsize.isEmpty { self.hudSize = hsize }
        if let hchar = json["hud_character"] as? String, !hchar.isEmpty {
            if hchar == "birb" || hchar == "parakeet" {
                self.hudCharacter = "luna"
            } else if hchar == "orb_gears" || hchar == "orb" {
                self.hudCharacter = "kuro"
            } else {
                self.hudCharacter = hchar
            }
        }
        if let hcol = json["hud_color"] as? String, !hcol.isEmpty { self.hudColor = hcol }
        if let halways = json["hud_always_show"] as? Bool { self.alwaysShowCompanion = halways }
        if let hyoff = json["hud_y_offset"] as? Double { self.hudYOffset = hyoff }
        if let lstyle = json["hud_listening_style"] as? String, !lstyle.isEmpty { self.listeningStyle = lstyle }
        if let theme = json["app_theme"] as? String, !theme.isEmpty { self.appTheme = theme }
        applyTheme()
        refreshOpenRouterBalance()
    }

    func applyTheme() {
        DispatchQueue.main.async {
            let popover = AppDelegate.shared?.popover
            switch self.appTheme {
            case "dark":
                popover?.appearance = NSAppearance(named: .darkAqua)
            case "light":
                popover?.appearance = NSAppearance(named: .aqua)
            default:
                popover?.appearance = nil
            }
        }
    }

    func saveConfigToDisk() {
        var payload: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload = existing
        }
        payload["stt_engine"] = self.sttEngine
        if !self.groqKey.isEmpty { payload["groq_key"] = self.groqKey }
        payload["provider"] = self.provider
        if !self.openRouterKey.isEmpty { payload["openrouter_key"] = self.openRouterKey }
        payload["openrouter_model"] = self.openRouterModel
        payload["ollama_url"] = self.ollamaUrl
        payload["ollama_model"] = self.ollamaModel
        payload["lmstudio_url"] = self.lmStudioUrl
        payload["lmstudio_model"] = self.lmStudioModel
        payload["use_llm_polish"] = self.useLlmPolish
        payload["custom_vocab"] = self.customVocab
        payload["hud_position"] = self.hudPosition
        payload["hud_size"] = self.hudSize
        payload["hud_character"] = self.hudCharacter
        payload["hud_color"] = self.hudColor
        payload["hud_always_show"] = self.alwaysShowCompanion
        payload["hud_y_offset"] = self.hudYOffset
        payload["hud_listening_style"] = self.listeningStyle
        payload["app_theme"] = self.appTheme

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? data.write(to: configURL)
        }
        applyTheme()
    }

    func refreshOpenRouterBalance() {
        guard !openRouterKey.isEmpty else {
            self.openRouterBalanceText = "No Key"
            return
        }
        let urlStr = "http://127.0.0.1:18765/api/openrouter/balance?key=\(openRouterKey)"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async {
                if let valid = json["valid"] as? Bool, valid {
                    if let bal = json["balance"] as? Double {
                        self.openRouterBalanceText = String(format: "$%.2f", bal)
                    } else {
                        self.openRouterBalanceText = "Active"
                    }
                } else {
                    self.openRouterBalanceText = "⚠️ Key 401"
                }
            }
        }.resume()
    }

    func refreshPermissions() {
        let trusted = AXIsProcessTrusted()
        if self.isAccessibilityGranted != trusted {
            self.isAccessibilityGranted = trusted
        }
        let micAuth = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        if self.isMicrophoneGranted != micAuth {
            self.isMicrophoneGranted = micAuth
        }
        let micName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Default Microphone"
        if self.currentMicName != micName {
            self.currentMicName = micName
        }
        if trusted && !CompanionTrackerManager.shared.isRunning {
            CompanionTrackerManager.shared.start()
        }
    }

    func requestAccessibility() {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptPrompt: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.isAccessibilityGranted = trusted
        if !trusted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.isMicrophoneGranted = granted
                }
            }
        } else if status != .authorized {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Daemon Manager
final class DaemonManager {
    static let shared = DaemonManager()
    private var process: Process?
    private let port = 18765
    private var watchdogTimer: Timer?
    private(set) var isStarting: Bool = false

    var healthURL: URL { URL(string: "http://127.0.0.1:\(port)/health")! }
    var transcribeURL: URL { URL(string: "http://127.0.0.1:\(port)/transcribe")! }

    func checkHealth(completion: @escaping (Bool) -> Void) {
        var req = URLRequest(url: healthURL)
        req.timeoutInterval = 1.2
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    func ensureRunning() {
        checkHealth { [weak self] ready in
            if ready {
                AppState.shared.daemonReady = true
            } else {
                self?.startDaemon()
            }
        }
    }

    func startWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.checkHealth { ready in
                AppState.shared.daemonReady = ready
                if !ready && !self.isStarting {
                    print("[DaemonManager] Watchdog detected daemon offline. Auto-reviving...")
                    self.startDaemon()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.watchdogTimer = timer
    }

    func ensureReady(completion: @escaping (Bool) -> Void) {
        checkHealth { [weak self] ready in
            if ready {
                AppState.shared.daemonReady = true
                completion(true)
            } else {
                guard let self = self else { completion(false); return }
                AppState.shared.statusText = "Waking AI Daemon..."
                self.startDaemon()
                var attempts = 0
                let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
                    attempts += 1
                    self?.checkHealth { ok in
                        if ok {
                            AppState.shared.daemonReady = true
                            t.invalidate()
                            completion(true)
                        } else if attempts > 20 {
                            t.invalidate()
                            completion(false)
                        }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    func startDaemon() {
        guard !isStarting else { return }
        isStarting = true

        let venvPython = "/Users/macbookair/Documents/GitHub/rand/stt_bench/.venv/bin/python"
        let scriptPath = "/Users/macbookair/Documents/GitHub/rand/ParakeetFlow/parakeet_daemon.py"

        guard FileManager.default.fileExists(atPath: venvPython),
              FileManager.default.fileExists(atPath: scriptPath) else {
            isStarting = false
            return
        }

        let script = """
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        pkill -f parakeet_daemon.py 2>/dev/null || true
        sleep 0.2
        nohup "\(venvPython)" "\(scriptPath)" > /tmp/parakeet_daemon.log 2>&1 &
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", script]
        try? task.run()
        task.waitUntilExit()

        var attempts = 0
        let pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            attempts += 1
            self.checkHealth { ready in
                if ready {
                    AppState.shared.daemonReady = true
                    self.isStarting = false
                    timer.invalidate()
                } else if attempts > 25 {
                    self.isStarting = false
                    timer.invalidate()
                }
            }
        }
        RunLoop.main.add(pollTimer, forMode: .common)
    }
}

// MARK: - Hardware Microphone Recording (Native AVAudioRecorder with Hardware Metering)
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    static let shared = AudioRecorder()
    private var recorder: AVAudioRecorder?
    private var ffmpegProcess: Process?
    private var meterTimer: Timer?
    private var durationTimer: Timer?
    private var isStopping: Bool = false
    let recordPath = "/tmp/parakeet_recording.wav"

    func start() {
        if isStopping { return }
        // Ensure no stale ffmpeg process locks the recording file or microphone
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killTask.arguments = ["-9", "-f", "ffmpeg.*parakeet_recording"]
        try? killTask.run()
        killTask.waitUntilExit()

        try? FileManager.default.removeItem(atPath: recordPath)
        AppState.shared.refreshPermissions()

        let url = URL(fileURLWithPath: recordPath)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            rec.isMeteringEnabled = true

            guard rec.record() else {
                print("[AudioRecorder] AVAudioRecorder record() returned false. Using ffmpeg :default.")
                startFfmpegFallback()
                return
            }
            self.recorder = rec

            AppState.shared.isRecording = true
            AppState.shared.recordDuration = 0.0
            AppState.shared.statusText = "Listening..."
            AppState.shared.audioLevel = 0.08

            durationTimer = Timer(timeInterval: 0.1, repeats: true) { _ in
                AppState.shared.recordDuration += 0.1
            }
            RunLoop.main.add(durationTimer!, forMode: .common)

            // Direct real-time hardware audio metering from active microphone
            meterTimer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
                guard let self = self, let r = self.recorder, r.isRecording else { return }
                r.updateMeters()
                let avg = r.averagePower(forChannel: 0) // -160 dB to 0 dB
                // Map speech range (-55 dB silence to -8 dB loud speech) to 0.0 ... 1.0 linear
                let normalized = max(0.0, min(1.0, Float((avg + 55.0) / 47.0)))
                AppState.shared.audioLevel = normalized
            }
            RunLoop.main.add(meterTimer!, forMode: .common)
        } catch {
            print("[AudioRecorder] Native init error: \(error). Using ffmpeg :default.")
            startFfmpegFallback()
        }
    }

    private func startFfmpegFallback() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        p.arguments = [
            "-y",
            "-f", "avfoundation",
            "-i", ":default",
            "-ar", "16000",
            "-ac", "1",
            recordPath,
            "-loglevel", "error"
        ]
        try? p.run()
        self.ffmpegProcess = p
        AppState.shared.isRecording = true
        AppState.shared.recordDuration = 0.0
        AppState.shared.statusText = "Listening..."
        AppState.shared.audioLevel = 0.25

        durationTimer = Timer(timeInterval: 0.1, repeats: true) { _ in
            AppState.shared.recordDuration += 0.1
        }
        RunLoop.main.add(durationTimer!, forMode: .common)
    }

    func stop(completion: @escaping (String?) -> Void) {
        guard !isStopping else { return }
        isStopping = true

        meterTimer?.invalidate()
        meterTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil

        // Instantly transition UI so the user experiences zero lag
        AppState.shared.isRecording = false
        AppState.shared.audioLevel = 0.0

        // Trailing buffer grace period (450ms):
        // Allow CoreAudio hardware buffers to flush and capture lingering end-of-sentence syllables.
        // This permanently eliminates audio cutting out before the speaker finishes talking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self = self else { return }

            if let r = self.recorder {
                r.stop()
            }
            self.recorder = nil

            if let p = self.ffmpegProcess, p.isRunning {
                p.interrupt()
                p.waitUntilExit()
            }
            self.ffmpegProcess = nil

            self.isStopping = false
            let exists = FileManager.default.fileExists(atPath: self.recordPath)
            completion(exists ? self.recordPath : nil)
        }
    }
}

// MARK: - Dictation & Target Application Auto-Paste
final class DictationService {
    static let shared = DictationService()
    var lastExternalBundleId: String = "com.google.antigravity"

    func setupAppObserver() {
        // Track the active user application (e.g. Antigravity, Cursor, Notes) continuously!
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let bid = app.bundleIdentifier,
               bid != Bundle.main.bundleIdentifier {
                self?.lastExternalBundleId = bid
            }
        }

        // Initialize with current frontmost
        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           bid != Bundle.main.bundleIdentifier {
            self.lastExternalBundleId = bid
        }
    }

    func captureScreenContext() -> (appName: String, windowTitle: String, selectedText: String) {
        let bundleId = self.lastExternalBundleId.isEmpty ? "com.google.antigravity" : self.lastExternalBundleId
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return ("", "", "")
        }
        let appName = app.localizedName ?? ""
        var windowTitle = ""
        var selectedText = ""

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Capture front window title (e.g. document name, code file, Slack channel)
        var focusedWindow: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
           let windowRef = focusedWindow {
            var titleVal: AnyObject?
            if AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleVal) == .success,
               let titleStr = titleVal as? String {
                windowTitle = titleStr
            }
        }

        // Capture highlighted text if the user selected code or text before dictating
        var focusedUIElement: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement) == .success,
           let elementRef = focusedUIElement {
            var selectedVal: AnyObject?
            if AXUIElementCopyAttributeValue(elementRef as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedVal) == .success,
               let selStr = selectedVal as? String {
                selectedText = String(selStr.prefix(250))
            }
        }

        return (appName, windowTitle, selectedText)
    }

    func transcribeAndPaste(audioPath: String) {
        AppState.shared.isProcessing = true
        AppState.shared.statusText = "Transcribing..."

        // Ensure daemon is awake and ready before dispatching audio
        DaemonManager.shared.ensureReady { [weak self] ready in
            guard let self = self else { return }
            guard ready else {
                AppState.shared.isProcessing = false
                AppState.shared.statusText = "AI Daemon offline. Auto-reviving..."
                DaemonManager.shared.startDaemon()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    AppState.shared.statusText = ""
                    FloatingHUDController.shared.hide()
                }
                return
            }
            self.sendTranscribeRequest(audioPath: audioPath)
        }
    }

    private func sendTranscribeRequest(audioPath: String) {
        let context = self.captureScreenContext()

        let payload: [String: Any] = [
            "audio_path": audioPath,
            "stt_engine": AppState.shared.sttEngine,
            "groq_key": AppState.shared.groqKey,
            "provider": AppState.shared.provider,
            "ollama_url": AppState.shared.ollamaUrl,
            "ollama_model": AppState.shared.ollamaModel,
            "lmstudio_url": AppState.shared.lmStudioUrl,
            "lmstudio_model": AppState.shared.lmStudioModel,
            "use_llm_polish": AppState.shared.useLlmPolish,
            "use_polish": AppState.shared.useLlmPolish,
            "openrouter_key": AppState.shared.openRouterKey,
            "openrouter_model": AppState.shared.openRouterModel,
            "custom_vocab": AppState.shared.customVocab,
            "context_app": context.appName,
            "context_title": context.windowTitle,
            "context_selected_text": context.selectedText
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            AppState.shared.isProcessing = false
            return
        }

        var req = URLRequest(url: DaemonManager.shared.transcribeURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        req.timeoutInterval = 90.0

        let tStart = Date()
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                AppState.shared.isProcessing = false
                if let err = err {
                    print("[DictationService] Request error: \(err.localizedDescription)")
                    AppState.shared.statusText = "Error: \(err.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        AppState.shared.statusText = ""
                        FloatingHUDController.shared.hide()
                    }
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    AppState.shared.statusText = "Invalid server response"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        AppState.shared.statusText = ""
                        FloatingHUDController.shared.hide()
                    }
                    return
                }

                let rawFinal = (json["final_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rawSpeech = (json["raw_text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let finalText = !rawFinal.isEmpty ? rawFinal : rawSpeech

                guard !finalText.isEmpty else {
                    let errMsg = json["error"] as? String
                    AppState.shared.statusText = errMsg ?? "No speech detected"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        AppState.shared.statusText = ""
                        FloatingHUDController.shared.hide()
                    }
                    return
                }

                let totalMs = round(Date().timeIntervalSince(tStart) * 1000)
                AppState.shared.lastResultText = finalText
                AppState.shared.lastLatencyMs = totalMs
                AppState.shared.statusText = "Pasted in \(Int(totalMs))ms ✓"

                if AppState.shared.autoPaste {
                    self.performInfalliblePaste(finalText)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    AppState.shared.lastResultText = ""
                    AppState.shared.statusText = ""
                    if !AppState.shared.isRecording && !AppState.shared.isProcessing {
                        FloatingHUDController.shared.hide()
                    }
                }
            }
        }.resume()
    }

    func performInfalliblePaste(_ text: String) {
        // 1. Copy formatted text to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 2. Hide Floating HUD pill and popover immediately
        FloatingHUDController.shared.hide()
        AppDelegate.shared.closePopover()

        let bundleId = self.lastExternalBundleId.isEmpty ? "com.google.antigravity" : self.lastExternalBundleId

        // 3. Force-activate the target application (e.g. Antigravity) via both AppKit and AppleScript
        if let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            targetApp.activate()
        }
        let activateScript = "tell application id \"\(bundleId)\" to activate"
        NSAppleScript(source: activateScript)?.executeAndReturnError(nil)

        // 4. Wait 220ms for the target application to gain active window and input focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            // First release any modifier keys that might still be held (Option, Shift, Control)
            let optUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Option), keyDown: false)
            optUp?.flags = []
            optUp?.post(tap: .cgSessionEventTap)

            let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)
            shiftUp?.flags = []
            shiftUp?.post(tap: .cgSessionEventTap)

            let ctrlUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Control), keyDown: false)
            ctrlUp?.flags = []
            ctrlUp?.post(tap: .cgSessionEventTap)

            // Maccy & Clipy proven paste method:
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )

            // 0x000008 = NX_DEVICELCMDKEYMASK (Required for Electron/Chromium to register Command key)
            let cmdFlag = CGEventFlags(rawValue: UInt64(CGEventFlags.maskCommand.rawValue) | 0x000008)
            let vCode: CGKeyCode = 0x09 // kVK_ANSI_V

            guard let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true),
                  let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false) else { return }

            keyVDown.flags = cmdFlag
            keyVUp.flags = cmdFlag

            // Post EXACTLY ONCE to .cgSessionEventTap
            keyVDown.post(tap: .cgSessionEventTap)
            keyVUp.post(tap: .cgSessionEventTap)

            NSSound(named: "Tink")?.play()
        }
    }
}

// MARK: - Carbon Global Hotkey Manager
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var fileSource: DispatchSourceFileSystemObject?
    private var globalMonitor: Any?

    func setup() {
        registerCarbonHotKey()
        setupDistributedNotification()
        setupFileTrigger()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            if AppState.shared.activeShortcut == "hold_option" {
                if event.modifierFlags.contains(.option) && !AppState.shared.isRecording {
                    self?.startRecording()
                } else if !event.modifierFlags.contains(.option) && AppState.shared.isRecording {
                    self?.stopRecording()
                }
            }
        }
    }

    private func setupFileTrigger() {
        let triggerPath = "/tmp/parakeet_toggle"
        if !FileManager.default.fileExists(atPath: triggerPath) {
            FileManager.default.createFile(atPath: triggerPath, contents: Data(), attributes: nil)
        }
        let fd = open(triggerPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.toggleRecording()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.fileSource = source
    }

    func setShortcut(_ key: String) {
        AppState.shared.activeShortcut = key
        registerCarbonHotKey()
    }

    private func registerCarbonHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }

        var keyCode: UInt32 = UInt32(kVK_Space)
        var modifiers: UInt32 = UInt32(optionKey)

        switch AppState.shared.activeShortcut {
        case "opt_space":
            keyCode = UInt32(kVK_Space)
            modifiers = UInt32(optionKey)
        case "f8":
            keyCode = UInt32(kVK_F8)
            modifiers = 0
        case "ctrl_space":
            keyCode = UInt32(kVK_Space)
            modifiers = UInt32(controlKey)
        case "cmd_shift_d":
            keyCode = UInt32(kVK_ANSI_D)
            modifiers = UInt32(cmdKey | shiftKey)
        case "hold_option":
            return
        default:
            break
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x504B4654), id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handlerCallback: EventHandlerUPP = { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                HotkeyManager.shared.toggleRecording()
            }
            return noErr
        }

        InstallEventHandler(GetEventDispatcherTarget(), handlerCallback, 1, &eventType, nil, &eventHandlerRef)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    private func setupDistributedNotification() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.parakeetflow.toggle"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggleRecording()
        }
    }

    func toggleRecording() {
        if AppState.shared.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        // Enforce permissions: verify both Microphone and Accessibility before showing HUD or recording
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let isMicGranted = (micStatus == .authorized)
        let isAxGranted = AXIsProcessTrusted()

        if !isMicGranted || !isAxGranted {
            NSSound.beep()
            AppState.shared.refreshPermissions()
            AppDelegate.shared.showPopover()
            if !isMicGranted {
                AppState.shared.requestMicrophone()
            }
            if !isAxGranted {
                AppState.shared.requestAccessibility()
            }
            return
        }

        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           bid != Bundle.main.bundleIdentifier {
            DictationService.shared.lastExternalBundleId = bid
        }
        FloatingHUDController.shared.show()
        AudioRecorder.shared.start()
    }

    func stopRecording() {
        AudioRecorder.shared.stop { path in
            if let p = path {
                DictationService.shared.transcribeAndPaste(audioPath: p)
            } else {
                FloatingHUDController.shared.hide()
            }
        }
    }
}

// MARK: - Precision Mathematical Gear Shape
struct GearShape: Shape {
    var teeth: Int = 8
    var innerRadiusRatio: CGFloat = 0.65
    var centerHoleRatio: CGFloat = 0.28

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2.0
        let innerR = outerR * innerRadiusRatio
        let angleStep = (2.0 * .pi) / Double(teeth)

        for i in 0..<teeth {
            let base = Double(i) * angleStep
            let a0 = base
            let a1 = base + angleStep * 0.18
            let a2 = base + angleStep * 0.38
            let a3 = base + angleStep * 0.56

            let p0 = CGPoint(x: center.x + innerR * cos(a0), y: center.y + innerR * sin(a0))
            let p1 = CGPoint(x: center.x + outerR * cos(a1), y: center.y + outerR * sin(a1))
            let p2 = CGPoint(x: center.x + outerR * cos(a2), y: center.y + outerR * sin(a2))
            let p3 = CGPoint(x: center.x + innerR * cos(a3), y: center.y + innerR * sin(a3))

            if i == 0 {
                path.move(to: p0)
            } else {
                path.addLine(to: p0)
            }
            path.addLine(to: p1)
            path.addLine(to: p2)
            path.addLine(to: p3)
        }
        path.closeSubpath()

        let holeR = outerR * centerHoleRatio
        path.addEllipse(in: CGRect(x: center.x - holeR, y: center.y - holeR, width: holeR * 2, height: holeR * 2))
        return path
    }
}

// MARK: - Meshing Interlocking Gears (Processing State Gear Engine)
struct InterlockingGearsView: View {
    let time: Double
    let accentColor: Color
    var isMini: Bool = false

    var body: some View {
        let r1: CGFloat = isMini ? 8.5 : 12.0
        let r2: CGFloat = isMini ? 6.5 : 9.0
        let angle1 = time * 190.0
        let angle2 = -angle1 * (8.0 / 6.0) + 18.0

        HStack(spacing: -3.0) {
            GearShape(teeth: 8, innerRadiusRatio: 0.62, centerHoleRatio: 0.28)
                .fill(
                    LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.85), Color.white.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: r1 * 2, height: r1 * 2)
                .rotationEffect(.degrees(angle1))
                .shadow(color: accentColor.opacity(0.4), radius: 2.5, x: 0, y: 1)

            GearShape(teeth: 6, innerRadiusRatio: 0.60, centerHoleRatio: 0.30)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), accentColor.opacity(0.9), accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: r2 * 2, height: r2 * 2)
                .rotationEffect(.degrees(angle2))
                .offset(y: 1.5)
                .shadow(color: accentColor.opacity(0.35), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - 1. GearBot Character (Curious Cyber Inventor)
struct GearBotCharacterView: View {
    let time: Double
    let isRecording: Bool
    let isProcessing: Bool
    let isDone: Bool
    let audioLevel: Float
    let accentColor: Color
    var isHovered: Bool = false
    var isHappy: Bool = false
    var cursorLookX: Double = 0.0
    var cursorLookY: Double = 0.0
    var isCursorNear: Bool = false
    var isTyping: Bool = false
    var isFlowActive: Bool = false
    var isLookingAtTimer: Bool = false
    var isTimerLow: Bool = false
    var isTimerUrgent: Bool = false
    var timerLookX: Double = 0.0
    var timerLookY: Double = 0.0

    var body: some View {
        let isIdle = !isRecording && !isProcessing && !isDone
        let cycle = isIdle ? time.truncatingRemainder(dividingBy: 18.0) : 0.0

        // Head tilt: reacts dynamically to typing, timer look-at, cursor, or idle
        let headTilt: Double = {
            if isHappy {
                return sin(time * 18.0) * 5.5
            } else if isLookingAtTimer {
                return timerLookX * 6.5 // Leans head toward the timer countdown!
            } else if isTyping {
                return -3.0 // Gentle subtle focus tilt
            } else if isTimerLow {
                return sin(time * 24.0) * (isTimerUrgent ? 1.4 : 0.8) // Nervous timer jitter
            } else if isCursorNear {
                return cursorLookX * 6.5
            } else if isProcessing {
                return sin(time * 3.5) * 5.0
            } else if isRecording {
                return Double(audioLevel) * 7.0 - 3.5
            } else if isHovered {
                return 4.0
            } else {
                if cycle >= 5.5 && cycle < 8.5 {
                    return 7.0
                } else if cycle >= 8.5 && cycle < 12.0 {
                    return -6.0
                } else {
                    return sin(time * 0.9) * 1.5
                }
            }
        }()

        // Head bob / vertical perk
        let headBob: CGFloat = {
            if isHappy {
                return -3.5 + CGFloat(abs(sin(time * 14.0))) * -2.0
            } else if isLookingAtTimer {
                return CGFloat(-timerLookY * 1.5)
            } else if isTyping {
                return -0.8 // Calm attentive posture
            } else if isTimerUrgent {
                return -2.0 + CGFloat(abs(sin(time * 18.0))) * -1.8 // Excited sprint bounce!
            } else if isTimerLow {
                return CGFloat(sin(time * 24.0) * 0.6) // Nervous pacing
            } else if isCursorNear {
                return CGFloat(-cursorLookY * 1.5)
            } else if isRecording {
                return -CGFloat(audioLevel) * 2.5
            } else if isHovered {
                return -1.6
            } else {
                return CGFloat(sin(time * 1.8) * 0.5)
            }
        }()

        // Eye glance direction:
        let (eyeOffsetX, eyeOffsetY): (CGFloat, CGFloat) = {
            if isHappy {
                return (0.0, 0.0)
            } else if isLookingAtTimer {
                return (CGFloat(timerLookX * 1.7), CGFloat(-timerLookY * 1.0))
            } else if isTyping {
                return (-1.0, 0.7) // Gentle downward keyboard glance
            } else if isTimerUrgent {
                return (CGFloat(sin(time * 8.0) * 1.4), 0.0) // Nervous darting glance
            } else if isCursorNear {
                return (CGFloat(cursorLookX * 1.6), CGFloat(-cursorLookY * 1.0))
            } else if isHovered {
                return (0.0, -0.6)
            } else if isIdle {
                if cycle >= 5.5 && cycle < 8.5 {
                    return (1.2, -0.8)
                } else if cycle >= 8.5 && cycle < 12.0 {
                    return (-1.2, -0.8)
                }
            }
            return (0.0, 0.0)
        }()

        // Antenna bulb illumination & frequency:
        let antennaBulbLit = isRecording || isProcessing || isHovered || isHappy || isTyping || isCursorNear || isTimerLow
        let antennaSpeed = isTimerUrgent ? 36.0 : (isTyping ? 24.0 : 20.0)

        // Blinking:
        let blinkPhase = sin(time * 1.7)
        let isBlinking = (blinkPhase > 0.96) && !isProcessing && !isDone && !isHappy && !isTimerUrgent

        let leftEyeScaleY: CGFloat = {
            if isBlinking { return 0.15 }
            if isTimerUrgent { return 1.25 }
            return 1.0
        }()

        let rightEyeScaleY: CGFloat = {
            if isBlinking { return 0.15 }
            if isTimerUrgent { return 1.25 }
            return 1.0
        }()

        VStack(spacing: 0) {
            if isProcessing {
                InterlockingGearsView(time: time, accentColor: accentColor, isMini: true)
                    .transition(.scale.combined(with: .opacity))
                    .offset(y: 2)
            } else {
                VStack(spacing: 0) {
                    Circle()
                        .fill(isTimerUrgent ? Color.red : (antennaBulbLit ? accentColor : Color.white.opacity(0.8)))
                        .frame(width: 3.5, height: 3.5)
                        .scaleEffect(isHappy || isTyping || isTimerUrgent ? (1.25 + sin(time * antennaSpeed) * 0.25) : (antennaBulbLit ? 1.2 : 1.0))
                        .shadow(color: (isTimerUrgent ? Color.red : accentColor).opacity(antennaBulbLit ? 0.9 : 0.2), radius: antennaBulbLit ? 3.0 : 1)
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1.5, height: 3.5)
                        .rotationEffect(.degrees(isLookingAtTimer ? timerLookX * 12.0 : (isCursorNear ? cursorLookX * 12.0 : 0)))
                }
                .offset(y: 1)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.24), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 22, height: 17)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.45), Color.white.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 18, height: 13)

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(accentColor)
                } else if isHappy {
                    HStack(spacing: 2.8) {
                        Text("^")
                            .font(.system(size: 8.5, weight: .black, design: .rounded))
                            .foregroundColor(accentColor)
                            .offset(y: 1)
                        Circle()
                            .fill(Color.pink.opacity(0.85))
                            .frame(width: 2.0, height: 1.5)
                        Text("^")
                            .font(.system(size: 8.5, weight: .black, design: .rounded))
                            .foregroundColor(accentColor)
                            .offset(y: 1)
                    }
                } else if isProcessing {
                    HStack(spacing: 3.5) {
                        GearShape(teeth: 6, innerRadiusRatio: 0.5, centerHoleRatio: 0.2)
                            .fill(accentColor)
                            .frame(width: 5.5, height: 5.5)
                            .rotationEffect(.degrees(time * 360.0))
                        GearShape(teeth: 6, innerRadiusRatio: 0.5, centerHoleRatio: 0.2)
                            .fill(accentColor)
                            .frame(width: 5.5, height: 5.5)
                            .rotationEffect(.degrees(-time * 360.0))
                    }
                } else {
                    HStack(spacing: 4) {
                        // Left Eye
                        ZStack {
                            Capsule()
                                .fill(isRecording || antennaBulbLit ? accentColor : Color.white.opacity(0.85))
                                .frame(width: 3.0, height: 5.0)
                                .scaleEffect(y: leftEyeScaleY)
                                .offset(x: eyeOffsetX, y: eyeOffsetY)
                                .shadow(color: accentColor.opacity(antennaBulbLit ? 0.9 : 0.2), radius: 2.5)

                            if (isCursorNear || isHovered) && !isBlinking && !isTyping {
                                Circle()
                                    .fill(Color.white.opacity(0.95))
                                    .frame(width: 1.1, height: 1.1)
                                    .offset(x: eyeOffsetX - 0.5, y: eyeOffsetY - 1.0)
                            }
                        }

                        // Right Eye
                        ZStack {
                            Capsule()
                                .fill(isRecording || antennaBulbLit ? accentColor : Color.white.opacity(0.85))
                                .frame(width: 3.0, height: 5.0)
                                .scaleEffect(y: rightEyeScaleY)
                                .offset(x: eyeOffsetX, y: eyeOffsetY)
                                .shadow(color: accentColor.opacity(antennaBulbLit ? 0.9 : 0.2), radius: 2.5)

                            if (isCursorNear || isHovered) && !isBlinking && !isTyping {
                                Circle()
                                    .fill(Color.white.opacity(0.95))
                                    .frame(width: 1.1, height: 1.1)
                                    .offset(x: eyeOffsetX - 0.5, y: eyeOffsetY - 1.0)
                            }
                        }
                    }
                }

                // Nervous sweat or urgent sprint indicator
                if isTimerUrgent {
                    Text("⚡")
                        .font(.system(size: 6))
                        .offset(x: 9, y: -7 + sin(time * 8.0) * 1.2)
                } else if isTimerLow {
                    Text("💧")
                        .font(.system(size: 5.5))
                        .offset(x: 8, y: -6 + sin(time * 6.0) * 1.0)
                }
            }
        }
        .rotationEffect(.degrees(headTilt))
        .offset(y: headBob)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isTyping)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isCursorNear)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isLookingAtTimer)
    }
}

// MARK: - 2. Neko Character (Cozy & Expressive Cat Companion)
struct NekoCharacterView: View {
    let time: Double
    let isRecording: Bool
    let isProcessing: Bool
    let isDone: Bool
    let audioLevel: Float
    let accentColor: Color
    var isHovered: Bool = false
    var isHappy: Bool = false
    var cursorLookX: Double = 0.0
    var cursorLookY: Double = 0.0
    var isCursorNear: Bool = false
    var isTyping: Bool = false
    var isFlowActive: Bool = false
    var isLookingAtTimer: Bool = false
    var isTimerLow: Bool = false
    var isTimerUrgent: Bool = false
    var timerLookX: Double = 0.0
    var timerLookY: Double = 0.0

    var body: some View {
        let blinkPhase = sin(time * 1.6)
        let isBlinking = blinkPhase > 0.96 && !isProcessing && !isDone && !isHappy && !isTimerUrgent

        // Ear twitches:
        let leftEarTwitch: Double = {
            if isHappy {
                return sin(time * 16.0) * 10.0
            } else if isLookingAtTimer {
                return timerLookX * 4.0
            } else if isTyping {
                return -4.0 // Subtle slight perked ear
            } else if isTimerUrgent {
                return sin(time * 26.0) * 10.0 // Nervous ear twitch
            } else if isCursorNear {
                return cursorLookX * 8.0 - 2.0
            } else if isRecording {
                return Double(audioLevel) * 9.0
            }
            return 0.0
        }()

        let rightEarTwitch: Double = {
            if isHappy {
                return -sin(time * 16.0) * 10.0
            } else if isLookingAtTimer {
                return timerLookX * 12.0 // Right ear pointed toward timer!
            } else if isTyping {
                return 5.0 // Subtle alert ear
            } else if isTimerUrgent {
                return -sin(time * 26.0) * 10.0
            } else if isCursorNear {
                return cursorLookX * 8.0 + 2.0
            } else if isRecording {
                return -Double(audioLevel) * 9.0
            }
            return 0.0
        }()

        let headTilt: Double = {
            if isHappy {
                return sin(time * 16.0) * 6.0
            } else if isLookingAtTimer {
                return timerLookX * 7.0 // Head turns toward timer!
            } else if isTyping {
                return -3.0 // Gentle curious head tilt
            } else if isTimerLow {
                return sin(time * 24.0) * (isTimerUrgent ? 1.5 : 0.8) // Nervous timer jitter
            } else if isCursorNear {
                return cursorLookX * 6.0
            }
            return 0.0
        }()

        let bob: CGFloat = {
            if isHappy {
                return -2.5 + CGFloat(abs(sin(time * 14.0))) * -1.5
            } else if isLookingAtTimer {
                return CGFloat(-timerLookY * 1.5)
            } else if isTyping {
                return -0.5 // Calm attentive posture
            } else if isTimerUrgent {
                return -2.0 + CGFloat(abs(sin(time * 18.0))) * -1.6 // Excited bounce!
            } else if isTimerLow {
                return CGFloat(sin(time * 24.0) * 0.5)
            } else if isHovered {
                return -1.0
            }
            return 0.0
        }()

        let (eyeOffsetX, eyeOffsetY): (CGFloat, CGFloat) = {
            if isHappy {
                return (0.0, 0.0)
            } else if isLookingAtTimer {
                return (CGFloat(timerLookX * 1.8), CGFloat(-timerLookY * 1.1))
            } else if isTyping {
                return (-1.0, 0.7) // Gentle glance toward keyboard
            } else if isTimerUrgent {
                return (CGFloat(sin(time * 8.0) * 1.5), 0.0)
            } else if isCursorNear {
                return (CGFloat(cursorLookX * 1.8), CGFloat(-cursorLookY * 1.1))
            }
            return (0.0, 0.0)
        }()

        VStack(spacing: -3) {
            if isProcessing {
                InterlockingGearsView(time: time, accentColor: accentColor, isMini: true)
                    .offset(y: 2)
            } else {
                HStack(spacing: 7) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 6.5))
                        p.addLine(to: CGPoint(x: 3.2, y: 0))
                        p.addLine(to: CGPoint(x: 6.5, y: 6.5))
                        p.closeSubpath()
                    }
                    .fill(accentColor.opacity(0.95))
                    .frame(width: 6.5, height: 6.5)
                    .rotationEffect(.degrees(leftEarTwitch))

                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 6.5))
                        p.addLine(to: CGPoint(x: 3.2, y: 0))
                        p.addLine(to: CGPoint(x: 6.5, y: 6.5))
                        p.closeSubpath()
                    }
                    .fill(accentColor.opacity(0.95))
                    .frame(width: 6.5, height: 6.5)
                    .rotationEffect(.degrees(rightEarTwitch))
                }
                .offset(y: 2)
            }

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 19, height: 17)
                    .overlay(
                        Circle()
                            .stroke(LinearGradient(colors: [Color.white.opacity(0.4), Color.clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
                    )

                if isDone || isHappy {
                    HStack(spacing: 3) {
                        Text("^")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(accentColor)
                        Circle()
                            .fill(Color.pink.opacity(0.85))
                            .frame(width: 2, height: 1.5)
                        Text("^")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                } else if isProcessing {
                    HStack(spacing: 3) {
                        Circle().fill(accentColor).frame(width: 2.5, height: 2.5)
                        Circle().fill(accentColor).frame(width: 2.5, height: 2.5)
                    }
                } else {
                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            // Left Eye
                            ZStack {
                                Capsule()
                                    .fill(accentColor)
                                    .frame(width: isCursorNear ? 3.6 : 3.2, height: 4.5)
                                    .scaleEffect(y: isBlinking ? 0.15 : 1.0)
                                    .offset(x: eyeOffsetX, y: eyeOffsetY)
                                    .shadow(color: accentColor.opacity(0.6), radius: 2)

                                if isCursorNear && !isBlinking {
                                    Circle()
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: 1.0, height: 1.0)
                                        .offset(x: eyeOffsetX - 0.4, y: eyeOffsetY - 1.0)
                                }
                            }

                            // Right Eye
                            ZStack {
                                Capsule()
                                    .fill(accentColor)
                                    .frame(width: isCursorNear ? 3.6 : 3.2, height: 4.5)
                                    .scaleEffect(y: isBlinking ? 0.15 : 1.0)
                                    .offset(x: eyeOffsetX, y: eyeOffsetY)
                                    .shadow(color: accentColor.opacity(0.6), radius: 2)

                                if isCursorNear && !isBlinking {
                                    Circle()
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: 1.0, height: 1.0)
                                        .offset(x: eyeOffsetX - 0.4, y: eyeOffsetY - 1.0)
                                }
                            }
                        }

                        if isTimerUrgent {
                            Text("o")
                                .font(.system(size: 4.5, weight: .bold))
                                .foregroundColor(accentColor.opacity(0.85))
                                .offset(y: -1)
                        }
                    }
                }

                if isTimerUrgent {
                    Text("⚡")
                        .font(.system(size: 6))
                        .offset(x: 8, y: -7 + sin(time * 8.0) * 1.2)
                } else if isTimerLow {
                    Text("💧")
                        .font(.system(size: 5.5))
                        .offset(x: 7, y: -6 + sin(time * 6.0) * 1.0)
                }
            }
        }
        .rotationEffect(.degrees(headTilt))
        .offset(y: bob)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isTyping)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isCursorNear)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isLookingAtTimer)
    }
}

// MARK: - 3. Luna Character (Gentle Celestial Spirit)
struct LunaCharacterView: View {
    let time: Double
    let isRecording: Bool
    let isProcessing: Bool
    let isDone: Bool
    let audioLevel: Float
    let accentColor: Color
    var isHovered: Bool = false
    var isHappy: Bool = false
    var cursorLookX: Double = 0.0
    var cursorLookY: Double = 0.0
    var isCursorNear: Bool = false
    var isTyping: Bool = false
    var isFlowActive: Bool = false
    var isLookingAtTimer: Bool = false
    var isTimerLow: Bool = false
    var isTimerUrgent: Bool = false
    var timerLookX: Double = 0.0
    var timerLookY: Double = 0.0

    var body: some View {
        let blinkPhase = sin(time * 1.5)
        let isBlinking = blinkPhase > 0.96 && !isProcessing && !isDone && !isHappy && !isTimerUrgent

        let floatBob: Double = {
            if isHappy {
                return -3.0 + abs(sin(time * 14.0)) * -2.0
            } else if isLookingAtTimer {
                return -timerLookY * 1.5
            } else if isTimerUrgent {
                return -2.0 + sin(time * 14.0) * 2.2
            } else if isTyping {
                return -0.8 // Calm attentive hovering
            } else if isTimerLow {
                return sin(time * 10.0) * 1.8
            }
            return sin(time * 2.4) * 1.6
        }()

        let bodyTilt: Double = {
            if isHappy {
                return sin(time * 16.0) * 8.0
            } else if isLookingAtTimer {
                return timerLookX * 7.5
            } else if isTyping {
                return -3.0 // Gentle soft tilt
            } else if isTimerLow {
                return sin(time * 24.0) * (isTimerUrgent ? 1.6 : 0.8)
            } else if isCursorNear {
                return cursorLookX * 7.0
            }
            return sin(time * 1.2) * 2.0
        }()

        let (eyeOffsetX, eyeOffsetY): (CGFloat, CGFloat) = {
            if isHappy {
                return (0.0, 0.0)
            } else if isLookingAtTimer {
                return (CGFloat(timerLookX * 1.8), CGFloat(-timerLookY * 1.1))
            } else if isTyping {
                return (-1.0, 0.7) // Gentle glance toward keyboard
            } else if isTimerUrgent {
                return (CGFloat(sin(time * 8.0) * 1.4), 0.0)
            } else if isCursorNear {
                return (CGFloat(cursorLookX * 1.8), CGFloat(-cursorLookY * 1.1))
            }
            return (0.0, 0.0)
        }()

        let wispSpeed = isTimerUrgent ? 14.0 : 3.5

        VStack(spacing: -1) {
            // Little floating star crown / celestial wisp on top
            Circle()
                .fill(accentColor.opacity(0.95))
                .frame(width: 3.2, height: 3.2)
                .shadow(color: accentColor.opacity(0.8), radius: 2)
                .offset(y: sin(time * wispSpeed) * 1.5)

            ZStack {
                // Ethereal Ghost/Wisp Body with soft gradient
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.85), Color(white: 0.15).opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.7)
                    )
                    .shadow(color: accentColor.opacity(isHovered || isCursorNear ? 0.5 : 0.2), radius: 3)

                // Face Features
                if isDone || isHappy {
                    HStack(spacing: 2.5) {
                        Text("^")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                        Circle().fill(Color.pink.opacity(0.9)).frame(width: 2.2, height: 1.6)
                        Text("^")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else if isProcessing {
                    HStack(spacing: 3) {
                        Circle().fill(Color.white).frame(width: 2.5, height: 2.5)
                            .scaleEffect(0.6 + max(0, sin(time * 6.0)) * 0.6)
                        Circle().fill(Color.white).frame(width: 2.5, height: 2.5)
                            .scaleEffect(0.6 + max(0, sin(time * 6.0 + 1.0)) * 0.6)
                    }
                } else {
                    VStack(spacing: 0.5) {
                        // Big starry anime wisp eyes
                        HStack(spacing: 4) {
                            ZStack {
                                Capsule()
                                    .fill(Color.black.opacity(0.88))
                                    .frame(width: 3.6, height: 5.2)
                                    .scaleEffect(y: isBlinking ? 0.15 : 1.0)
                                    .offset(x: eyeOffsetX, y: eyeOffsetY)

                                if !isBlinking {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 1.4, height: 1.4)
                                        .offset(x: eyeOffsetX - 0.7, y: eyeOffsetY - 1.2)
                                }
                            }

                            ZStack {
                                Capsule()
                                    .fill(Color.black.opacity(0.88))
                                    .frame(width: 3.6, height: 5.2)
                                    .scaleEffect(y: isBlinking ? 0.15 : 1.0)
                                    .offset(x: eyeOffsetX, y: eyeOffsetY)

                                if !isBlinking {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 1.4, height: 1.4)
                                        .offset(x: eyeOffsetX - 0.7, y: eyeOffsetY - 1.2)
                                }
                            }
                        }

                        // Soft blushing cheeks
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.pink.opacity(isCursorNear || isTimerLow ? 0.90 : 0.45))
                                .frame(width: 2.2, height: 1.4)
                            Circle()
                                .fill(Color.pink.opacity(isCursorNear || isTimerLow ? 0.90 : 0.45))
                                .frame(width: 2.2, height: 1.4)
                        }
                        .offset(y: -0.5)
                    }
                }

                if isTimerUrgent {
                    Text("⚡")
                        .font(.system(size: 6))
                        .offset(x: 8, y: -7 + sin(time * 8.0) * 1.2)
                } else if isTimerLow {
                    Text("💧")
                        .font(.system(size: 5.5))
                        .offset(x: 7, y: -6 + sin(time * 6.0) * 1.0)
                }
            }
        }
        .rotationEffect(.degrees(bodyTilt))
        .offset(y: CGFloat(floatBob))
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isTyping)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isCursorNear)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isLookingAtTimer)
    }
}

// MARK: - 4. Kuro Character (Clever Shadow Fox)
struct KuroCharacterView: View {
    let time: Double
    let isRecording: Bool
    let isProcessing: Bool
    let isDone: Bool
    let audioLevel: Float
    let accentColor: Color
    var isHovered: Bool = false
    var isHappy: Bool = false
    var cursorLookX: Double = 0.0
    var cursorLookY: Double = 0.0
    var isCursorNear: Bool = false
    var isTyping: Bool = false
    var isFlowActive: Bool = false
    var isLookingAtTimer: Bool = false
    var isTimerLow: Bool = false
    var isTimerUrgent: Bool = false
    var timerLookX: Double = 0.0
    var timerLookY: Double = 0.0

    var body: some View {
        let blinkPhase = sin(time * 1.7)
        let isBlinking = blinkPhase > 0.96 && !isProcessing && !isDone && !isHappy && !isTimerUrgent

        // Fox ear angles:
        let leftEarAngle: Double = {
            if isHappy {
                return sin(time * 18.0) * 12.0
            } else if isLookingAtTimer {
                return timerLookX * 4.0
            } else if isTyping {
                return -8.0 // Subtle alert cocked ear
            } else if isTimerUrgent {
                return sin(time * 26.0) * 12.0
            } else if isCursorNear {
                return cursorLookX * 9.0 - 4.0
            }
            return -4.0
        }()

        let rightEarAngle: Double = {
            if isHappy {
                return -sin(time * 18.0) * 12.0
            } else if isLookingAtTimer {
                return timerLookX * 14.0 // Pointed toward timer!
            } else if isTyping {
                return 8.0 // Subtle alert ear
            } else if isTimerUrgent {
                return -sin(time * 26.0) * 12.0
            } else if isCursorNear {
                return cursorLookX * 9.0 + 4.0
            }
            return 4.0
        }()

        let headTilt: Double = {
            if isHappy {
                return sin(time * 16.0) * 7.0
            } else if isLookingAtTimer {
                return timerLookX * 7.5
            } else if isTyping {
                return -3.0 // Gentle subtle tilt
            } else if isTimerLow {
                return sin(time * 24.0) * (isTimerUrgent ? 1.6 : 0.8)
            } else if isCursorNear {
                return cursorLookX * 7.5
            }
            return 0.0
        }()

        let bob: CGFloat = {
            if isHappy {
                return -2.5 + CGFloat(abs(sin(time * 14.0))) * -1.5
            } else if isLookingAtTimer {
                return CGFloat(-timerLookY * 1.5)
            } else if isTyping {
                return -0.5 // Calm attentive posture
            } else if isTimerUrgent {
                return -2.0 + CGFloat(abs(sin(time * 18.0))) * -1.8
            } else if isTimerLow {
                return CGFloat(sin(time * 24.0) * 0.6)
            } else if isHovered {
                return -1.0
            }
            return 0.0
        }()

        let (eyeOffsetX, eyeOffsetY): (CGFloat, CGFloat) = {
            if isHappy {
                return (0.0, 0.0)
            } else if isLookingAtTimer {
                return (CGFloat(timerLookX * 2.0), CGFloat(-timerLookY * 1.1))
            } else if isTyping {
                return (-1.0, 0.7) // Gentle downward keyboard glance
            } else if isTimerUrgent {
                return (CGFloat(sin(time * 8.0) * 1.6), 0.0)
            } else if isCursorNear {
                return (CGFloat(cursorLookX * 2.0), CGFloat(-cursorLookY * 1.1))
            }
            return (0.0, 0.0)
        }()

        VStack(spacing: -3) {
            // Fox Pointed Ears
            HStack(spacing: 8) {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 7))
                        p.addLine(to: CGPoint(x: 3.5, y: 0))
                        p.addLine(to: CGPoint(x: 7, y: 7))
                        p.closeSubpath()
                    }
                    .fill(Color(white: 0.22))

                    Path { p in
                        p.move(to: CGPoint(x: 1.5, y: 6))
                        p.addLine(to: CGPoint(x: 3.5, y: 1.5))
                        p.addLine(to: CGPoint(x: 5.5, y: 6))
                        p.closeSubpath()
                    }
                    .fill(accentColor)
                }
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(leftEarAngle))

                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 7))
                        p.addLine(to: CGPoint(x: 3.5, y: 0))
                        p.addLine(to: CGPoint(x: 7, y: 7))
                        p.closeSubpath()
                    }
                    .fill(Color(white: 0.22))

                    Path { p in
                        p.move(to: CGPoint(x: 1.5, y: 6))
                        p.addLine(to: CGPoint(x: 3.5, y: 1.5))
                        p.addLine(to: CGPoint(x: 5.5, y: 6))
                        p.closeSubpath()
                    }
                    .fill(accentColor)
                }
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(rightEarAngle))
            }
            .offset(y: 2)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.24), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 19, height: 17)
                    .overlay(
                        Circle()
                            .stroke(LinearGradient(colors: [Color.white.opacity(0.4), Color.clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
                    )

                if isDone || isHappy {
                    HStack(spacing: 3) {
                        Text("^")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(accentColor)
                        Circle().fill(Color.pink.opacity(0.85)).frame(width: 2, height: 1.5)
                        Text("^")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                } else if isProcessing {
                    HStack(spacing: 3) {
                        Circle().fill(accentColor).frame(width: 2.5, height: 2.5)
                        Circle().fill(accentColor).frame(width: 2.5, height: 2.5)
                    }
                } else {
                    VStack(spacing: 0.5) {
                        HStack(spacing: 4) {
                            // Left Eye
                            Capsule()
                                .fill(accentColor)
                                .frame(width: isCursorNear ? 3.6 : 3.2, height: 4.5)
                                .scaleEffect(y: isBlinking ? 0.15 : 1.0)
                                .offset(x: eyeOffsetX, y: eyeOffsetY)
                                .shadow(color: accentColor.opacity(0.7), radius: 2)

                            // Right Eye
                            Capsule()
                                .fill(accentColor)
                                .frame(width: isCursorNear ? 3.6 : 3.2, height: 4.5)
                                .scaleEffect(y: isBlinking ? 0.15 : 1.0)
                                .offset(x: eyeOffsetX, y: eyeOffsetY)
                                .shadow(color: accentColor.opacity(0.7), radius: 2)
                        }

                        // Fox Snout & Smirk
                        Circle()
                            .fill(Color.black.opacity(0.9))
                            .frame(width: 1.8, height: 1.2)

                        if isTimerUrgent {
                            Text("^")
                                .font(.system(size: 5.0, weight: .bold))
                                .foregroundColor(accentColor.opacity(0.9))
                                .offset(y: -1)
                        }
                    }
                }

                if isTimerUrgent {
                    Text("⚡")
                        .font(.system(size: 6))
                        .offset(x: 8, y: -7 + sin(time * 8.0) * 1.2)
                } else if isTimerLow {
                    Text("💧")
                        .font(.system(size: 5.5))
                        .offset(x: 7, y: -6 + sin(time * 6.0) * 1.0)
                }
            }
        }
        .rotationEffect(.degrees(headTilt))
        .offset(y: bob)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isTyping)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isCursorNear)
        .animation(.spring(response: 0.26, dampingFraction: 0.75), value: isLookingAtTimer)
    }
}

// MARK: - 5. Custom GIF Player Support
struct CustomGIFCharacterView: NSViewRepresentable {
    let gifPath: String

    func makeNSView(context: Context) -> NSImageView {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.animates = true
        iv.canDrawSubviewsIntoLayer = true
        if FileManager.default.fileExists(atPath: gifPath), let img = NSImage(contentsOfFile: gifPath) {
            iv.image = img
        }
        return iv
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if FileManager.default.fileExists(atPath: gifPath), nsView.image == nil {
            nsView.image = NSImage(contentsOfFile: gifPath)
            nsView.animates = true
        }
    }
}

// MARK: - Interactive Character Engine Router
struct InteractiveCharacterView: View {
    @ObservedObject var state = AppState.shared
    let time: Double

    var body: some View {
        let isDone = !state.isRecording && !state.isProcessing && !state.lastResultText.isEmpty
        let charType = state.hudCharacter.lowercased()

        // 1. Dynamic typing state (instant recovery: 0.45s after typing stops)
        let now = ProcessInfo.processInfo.systemUptime
        let isTyping = state.isUserTyping || (now - state.lastTypingTime < 0.45)

        // 2. Flow mode timer awareness:
        let isFlow = state.isFlowActive
        let remaining = state.flowRemainingSeconds
        let total = max(1, state.flowTotalSeconds)
        let isTimerLow = isFlow && (remaining <= 180 || Double(remaining) / Double(total) <= 0.15)
        let isTimerUrgent = isFlow && remaining <= 60

        // Periodic glance at timer:
        // When urgent, glance frequently (every 3.2s for 1.1s)
        // When normal flow, glance every 10s for 1.8s
        let timerPeriod: Double = isTimerUrgent ? 3.2 : (isTimerLow ? 5.5 : 10.0)
        let timerGlanceDuration: Double = isTimerUrgent ? 1.1 : 1.6
        let timeInCycle = time.truncatingRemainder(dividingBy: timerPeriod)
        let isLookingAtTimer = isFlow && !isTyping && (timeInCycle < timerGlanceDuration)

        // Direction to look at timer:
        // If vertical HUD, timer is below character -> look down (Y = -1.5, X = 0.0)
        // If horizontal HUD, timer is to the right of character -> look right (X = 1.6, Y = 0.0)
        let isVertical = state.hudPosition == "left" || state.hudPosition == "right"
        let timerLookX: CGFloat = isVertical ? 0.0 : 1.6
        let timerLookY: CGFloat = isVertical ? -1.5 : 0.0

        ZStack {
            switch charType {
            case "neko", "cat":
                NekoCharacterView(
                    time: time,
                    isRecording: state.isRecording,
                    isProcessing: state.isProcessing,
                    isDone: isDone,
                    audioLevel: state.audioLevel,
                    accentColor: state.hudAccentColor,
                    isHovered: state.isHUDHovered,
                    isHappy: state.isPetHappy,
                    cursorLookX: state.cursorLookX,
                    cursorLookY: state.cursorLookY,
                    isCursorNear: state.isCursorNear,
                    isTyping: isTyping,
                    isLookingAtTimer: isLookingAtTimer,
                    isTimerLow: isTimerLow,
                    isTimerUrgent: isTimerUrgent,
                    timerLookX: timerLookX,
                    timerLookY: timerLookY
                )
            case "luna", "spirit", "ghost", "birb":
                LunaCharacterView(
                    time: time,
                    isRecording: state.isRecording,
                    isProcessing: state.isProcessing,
                    isDone: isDone,
                    audioLevel: state.audioLevel,
                    accentColor: state.hudAccentColor,
                    isHovered: state.isHUDHovered,
                    isHappy: state.isPetHappy,
                    cursorLookX: state.cursorLookX,
                    cursorLookY: state.cursorLookY,
                    isCursorNear: state.isCursorNear,
                    isTyping: isTyping,
                    isLookingAtTimer: isLookingAtTimer,
                    isTimerLow: isTimerLow,
                    isTimerUrgent: isTimerUrgent,
                    timerLookX: timerLookX,
                    timerLookY: timerLookY
                )
            case "kuro", "fox", "orb_gears":
                KuroCharacterView(
                    time: time,
                    isRecording: state.isRecording,
                    isProcessing: state.isProcessing,
                    isDone: isDone,
                    audioLevel: state.audioLevel,
                    accentColor: state.hudAccentColor,
                    isHovered: state.isHUDHovered,
                    isHappy: state.isPetHappy,
                    cursorLookX: state.cursorLookX,
                    cursorLookY: state.cursorLookY,
                    isCursorNear: state.isCursorNear,
                    isTyping: isTyping,
                    isLookingAtTimer: isLookingAtTimer,
                    isTimerLow: isTimerLow,
                    isTimerUrgent: isTimerUrgent,
                    timerLookX: timerLookX,
                    timerLookY: timerLookY
                )
            case "custom":
                let customPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".parakeetflow/character.gif").path
                if FileManager.default.fileExists(atPath: customPath) {
                    CustomGIFCharacterView(gifPath: customPath)
                        .frame(width: 26, height: 26)
                } else {
                    GearBotCharacterView(
                        time: time,
                        isRecording: state.isRecording,
                        isProcessing: state.isProcessing,
                        isDone: isDone,
                        audioLevel: state.audioLevel,
                        accentColor: state.hudAccentColor,
                        isHovered: state.isHUDHovered,
                        isHappy: state.isPetHappy,
                        cursorLookX: state.cursorLookX,
                        cursorLookY: state.cursorLookY,
                        isCursorNear: state.isCursorNear,
                        isTyping: isTyping,
                        isLookingAtTimer: isLookingAtTimer,
                        isTimerLow: isTimerLow,
                        isTimerUrgent: isTimerUrgent,
                        timerLookX: timerLookX,
                        timerLookY: timerLookY
                    )
                }
            default: // "gearbot"
                GearBotCharacterView(
                    time: time,
                    isRecording: state.isRecording,
                    isProcessing: state.isProcessing,
                    isDone: isDone,
                    audioLevel: state.audioLevel,
                    accentColor: state.hudAccentColor,
                    isHovered: state.isHUDHovered,
                    isHappy: state.isPetHappy,
                    cursorLookX: state.cursorLookX,
                    cursorLookY: state.cursorLookY,
                    isCursorNear: state.isCursorNear,
                    isTyping: isTyping,
                    isLookingAtTimer: isLookingAtTimer,
                    isTimerLow: isTimerLow,
                    isTimerUrgent: isTimerUrgent,
                    timerLookX: timerLookX,
                    timerLookY: timerLookY
                )
            }
        }
        .frame(width: 26, height: 26)
        .scaleEffect(state.hudSize == "mini" ? 0.56 : (state.hudSize == "spacious" ? 0.88 : 0.70))
        .frame(width: state.hudSize == "mini" ? 15 : (state.hudSize == "spacious" ? 23 : 18),
               height: state.hudSize == "mini" ? 15 : (state.hudSize == "spacious" ? 23 : 18))
    }
}

// MARK: - Centered Organic Harmonic Soundwave (Pure Fluid Audio Equalizer)
struct OrganicVoiceWaveform: View {
    @ObservedObject var state = AppState.shared
    let time: Double
    var isVertical: Bool = false
    let barCount: Int = 7

    var body: some View {
        if isVertical {
            VStack(spacing: 2.2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let breadth = computeBreadth(i: i, time: time)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    state.hudAccentColor,
                                    state.hudAccentColor.opacity(0.70)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: breadth, height: 2.0)
                        .shadow(color: state.hudAccentColor.opacity(0.4), radius: 1.5)
                }
            }
            .frame(width: 16)
        } else {
            HStack(spacing: 2.2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let height = computeBreadth(i: i, time: time)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    state.hudAccentColor,
                                    state.hudAccentColor.opacity(0.70)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2.2, height: height)
                        .shadow(color: state.hudAccentColor.opacity(0.4), radius: 1.5)
                }
            }
            .frame(height: 14)
        }
    }

    private func computeBreadth(i: Int, time: Double) -> CGFloat {
        if !state.isRecording { return 2.5 }
        let freq = 4.2 + Double(i) * 1.5
        let phase = Double(i) * 0.78
        let harm1 = sin(time * freq + phase)
        let harm2 = cos(time * (freq * 0.52) + phase * 1.3)
        let oscillation = harm1 * 0.65 + harm2 * 0.35
        let centerDist = abs(Double(i) - 3.0) / 3.0 // 7 bars: center is index 3
        let bell = 0.35 + 0.65 * cos(centerDist * .pi / 2.0)
        let energy = max(0.18, Double(state.audioLevel))
        let dynamicRange = 9.5 * bell * energy
        let raw = 2.5 + dynamicRange * (1.0 + oscillation * 0.75)
        return CGFloat(max(2.5, min(14.0, raw)))
    }
}

// MARK: - Centered Bouncing Processing Dots
struct CenteredProcessingDotsView: View {
    @ObservedObject var state = AppState.shared
    let time: Double

    var body: some View {
        HStack(spacing: 3.2) {
            ForEach(0..<3, id: \.self) { i in
                let wave = sin(time * 7.5 + Double(i) * 1.2)
                Circle()
                    .fill(state.hudAccentColor)
                    .frame(width: 3.2, height: 3.2)
                    .scaleEffect(0.6 + max(0.0, wave) * 0.65)
                    .opacity(0.35 + max(0.0, wave) * 0.65)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Centered Listening Character with Dynamic Sonic Pulse Aura
struct ListeningCharacterView: View {
    @ObservedObject var state = AppState.shared
    let time: Double

    var body: some View {
        ZStack {
            if state.isRecording {
                let energy = max(0.12, CGFloat(state.audioLevel))
                Circle()
                    .strokeBorder(
                        state.hudAccentColor.opacity(Double(0.25 + energy * 0.5)),
                        lineWidth: 1.0
                    )
                    .frame(width: 22, height: 22)
                    .scaleEffect(1.05 + energy * 0.45 + CGFloat(sin(time * 7.0)) * 0.06)

                Circle()
                    .strokeBorder(
                        state.hudAccentColor.opacity(Double(0.12 + energy * 0.3)),
                        lineWidth: 0.8
                    )
                    .frame(width: 22, height: 22)
                    .scaleEffect(1.3 + energy * 0.35 + CGFloat(cos(time * 5.0)) * 0.08)
            } else if state.isProcessing {
                Circle()
                    .strokeBorder(state.hudAccentColor.opacity(0.35), lineWidth: 1.0)
                    .frame(width: 22, height: 22)
                    .scaleEffect(1.1 + CGFloat(sin(time * 6.0)) * 0.1)
            }

            InteractiveCharacterView(state: state, time: time)
        }
    }
}

// MARK: - Dedicated Non-Shadow Panel Subclass (Permanently Eliminates macOS Box Shadows)
final class HUDPanel: NSPanel {
    override var hasShadow: Bool {
        get { return false }
        set { }
    }
}

// MARK: - Visual Snap Guide Silhouette (Matches User Screenshot Drop-Zone Perfectly)
struct SnapGuideView: View {
    @ObservedObject var state = AppState.shared
    var targetPosition: String = "bottom_center"

    var body: some View {
        let isVertical = targetPosition == "left" || targetPosition == "right"
        let width: CGFloat = isVertical ? 44 : 80
        let height: CGFloat = isVertical ? 80 : 44

        ZStack {
            // Frosted translucent capsule matching user screenshot
            Capsule()
                .fill(Color(white: 0.88).opacity(0.35))

            // Unified clean white border
            Capsule()
                .strokeBorder(Color.white.opacity(0.40), lineWidth: 1.0)
        }
        .frame(width: width, height: height)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isVertical ? .center : .bottom)
        .padding(.bottom, isVertical ? 0 : 4)
    }
}

// MARK: - Compact Dark HUD Capsule (Minimal Footprint, Pure Capsule Shadow, Zero Box Bleed)
struct FloatingHUDView: View {
    @ObservedObject var state = AppState.shared
    @Environment(\.colorScheme) var systemColorScheme

    var isVertical: Bool {
        state.hudPosition == "left" || state.hudPosition == "right"
    }

    var isDark: Bool {
        if state.appTheme == "dark" { return true }
        if state.appTheme == "light" { return false }
        return systemColorScheme == .dark
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.033)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let isMini = state.hudSize == "mini"
            let isSpacious = state.hudSize == "spacious"
            let capsuleFill = isDark ? Color(red: 0.08, green: 0.08, blue: 0.10) : Color(red: 0.96, green: 0.96, blue: 0.98)
            let capsuleBorder = isDark ? Color.white.opacity(state.isHUDDragging ? 0.45 : (state.isHUDHovered ? 0.32 : 0.22)) : Color.black.opacity(state.isHUDDragging ? 0.35 : (state.isHUDHovered ? 0.25 : 0.15))

            if isVertical {
                // VERTICAL CAPSULE FOR LEFT / RIGHT SCREEN EDGES
                let isFlow = state.isFlowActive && !state.isRecording && !state.isProcessing
                let pillWidth: CGFloat = isMini ? 24 : (isSpacious ? 32 : 28)
                let pillHeight: CGFloat = {
                    if isFlow {
                        return isMini ? 66 : (isSpacious ? 92 : 78)
                    }
                    if state.listeningStyle == "character" {
                        return isMini ? 34 : (isSpacious ? 48 : 42)
                    }
                    if state.isRecording {
                        return isMini ? 56 : (isSpacious ? 80 : 68)
                    } else if state.isProcessing {
                        return isMini ? 40 : (isSpacious ? 56 : 48)
                    } else {
                        return isMini ? 34 : (isSpacious ? 48 : 42)
                    }
                }()

                ZStack {
                    if state.isHUDHovered || state.isPetHappy {
                        Capsule()
                            .fill(state.hudAccentColor.opacity(state.isPetHappy ? 0.32 : 0.16))
                            .blur(radius: state.isPetHappy ? 7 : 5)
                            .padding(-3)
                    }

                    Capsule()
                        .fill(capsuleFill)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    capsuleBorder,
                                    lineWidth: state.isHUDDragging ? 1.05 : 0.85
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(state.isHUDDragging ? 0.46 : 0.30),
                            radius: state.isHUDDragging ? 7 : 4,
                            x: 0,
                            y: state.isHUDDragging ? 4 : 2
                        )

                    // Unified Centered Morphing Content
                    ZStack {
                        if state.isRecording {
                            if state.listeningStyle == "character" {
                                ListeningCharacterView(state: state, time: time)
                            } else {
                                OrganicVoiceWaveform(state: state, time: time, isVertical: true)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.65).combined(with: .opacity),
                                        removal: .scale(scale: 0.65).combined(with: .opacity)
                                    ))
                            }
                        } else if state.isProcessing {
                            if state.listeningStyle == "character" {
                                ListeningCharacterView(state: state, time: time)
                            } else {
                                CenteredProcessingDotsView(state: state, time: time)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.65).combined(with: .opacity),
                                        removal: .scale(scale: 0.65).combined(with: .opacity)
                                    ))
                            }
                        } else if state.isFlowActive {
                            // Flow Mode: Mascot on top, countdown below
                            VStack(spacing: 3) {
                                InteractiveCharacterView(state: state, time: time)
                                    .frame(width: 18, height: 18)

                                Rectangle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 10, height: 1)

                                let mins = state.flowRemainingSeconds / 60
                                let secs = state.flowRemainingSeconds % 60
                                let isLow = state.flowRemainingSeconds <= 180
                                let isUrgent = state.flowRemainingSeconds <= 60
                                let timerColor: Color = isUrgent ? Color(red: 1.0, green: 0.35, blue: 0.35) : (isLow ? Color.orange : state.hudAccentColor)

                                Text(mins > 0 ? "\(mins)m" : "\(secs)s")
                                    .font(.system(size: isMini ? 8 : (isSpacious ? 9.5 : 8.5), weight: .bold, design: .monospaced))
                                    .foregroundColor(state.isFlowPaused ? .secondary : timerColor)
                                    .opacity(state.isFlowPaused ? (Int(time * 2) % 2 == 0 ? 0.4 : 1.0) : (isUrgent ? (Int(time * 3) % 2 == 0 ? 0.75 : 1.0) : 1.0))
                                    .scaleEffect(isUrgent ? (1.0 + sin(time * 8.0) * 0.08) : 1.0)
                            }
                            .padding(.vertical, 4)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.75).combined(with: .opacity),
                                removal: .scale(scale: 0.75).combined(with: .opacity)
                            ))
                        } else {
                            if state.listeningStyle == "waveform" {
                                OrganicVoiceWaveform(state: state, time: time, isVertical: true)
                                    .transition(.scale(scale: 0.65).combined(with: .opacity))
                            } else {
                                InteractiveCharacterView(state: state, time: time)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.75).combined(with: .opacity),
                                        removal: .scale(scale: 0.75).combined(with: .opacity)
                                    ))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(width: pillWidth, height: pillHeight)
                .scaleEffect(state.isPetHappy ? 1.06 : (state.isHUDHovered ? 1.03 : 1.0))
                .animation(.spring(response: 0.26, dampingFraction: 0.68), value: state.isPetHappy)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: state.isHUDHovered)
                .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.isRecording)
                .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.isProcessing)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.isFlowActive)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.isFlowPaused)
                .scaleEffect(state.isHUDDragging ? 1.05 : 1.0)
                .frame(width: isMini ? 44 : (isSpacious ? 64 : 52), height: isMini ? 86 : (isSpacious ? 124 : 100), alignment: .center)
            } else {
                // HORIZONTAL CAPSULE FOR BOTTOM CENTER
                let isFlow = state.isFlowActive && !state.isRecording && !state.isProcessing
                let pillWidth: CGFloat = {
                    if isFlow {
                        return isMini ? 72 : (isSpacious ? 102 : 86)
                    }
                    if state.listeningStyle == "character" {
                        return isMini ? 34 : (isSpacious ? 48 : 42)
                    }
                    if state.isRecording {
                        return isMini ? 56 : (isSpacious ? 80 : 68)
                    } else if state.isProcessing {
                        return isMini ? 40 : (isSpacious ? 56 : 48)
                    } else {
                        return isMini ? 34 : (isSpacious ? 48 : 42)
                    }
                }()
                let pillHeight: CGFloat = isMini ? 24 : (isSpacious ? 32 : 28)

                VStack(spacing: 0) {
                    ZStack {
                        if state.isPetHappy {
                            Text(state.petReactionEmoji)
                                .font(.system(size: 13))
                                .shadow(color: state.hudAccentColor.opacity(0.4), radius: 3, x: 0, y: 1)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.3).combined(with: .offset(y: 8)).combined(with: .opacity),
                                    removal: .opacity.combined(with: .offset(y: -10))
                                ))
                        }
                    }
                    .frame(height: 15)

                    ZStack {
                        if state.isHUDHovered || state.isPetHappy {
                            Capsule()
                                .fill(state.hudAccentColor.opacity(state.isPetHappy ? 0.32 : 0.16))
                                .blur(radius: state.isPetHappy ? 7 : 5)
                                .padding(-3)
                        }

                        Capsule()
                            .fill(capsuleFill)
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        capsuleBorder,
                                        lineWidth: state.isHUDDragging ? 1.05 : 0.85
                                    )
                            )
                            .shadow(
                                color: Color.black.opacity(state.isHUDDragging ? 0.46 : 0.30),
                                radius: state.isHUDDragging ? 7 : 4,
                                x: 0,
                                y: state.isHUDDragging ? 4 : 2
                            )

                        // Unified Centered Morphing Content
                        ZStack {
                            if state.isRecording {
                                if state.listeningStyle == "character" {
                                    ListeningCharacterView(state: state, time: time)
                                } else {
                                    OrganicVoiceWaveform(state: state, time: time, isVertical: false)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.65).combined(with: .opacity),
                                            removal: .scale(scale: 0.65).combined(with: .opacity)
                                        ))
                                }
                            } else if state.isProcessing {
                                if state.listeningStyle == "character" {
                                    ListeningCharacterView(state: state, time: time)
                                } else {
                                    CenteredProcessingDotsView(state: state, time: time)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.65).combined(with: .opacity),
                                            removal: .scale(scale: 0.65).combined(with: .opacity)
                                        ))
                                }
                            } else if state.isFlowActive {
                                HStack(spacing: 5) {
                                    InteractiveCharacterView(state: state, time: time)
                                        .frame(width: 20, height: 20)

                                    Rectangle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 1, height: 11)

                                    let isLow = state.flowRemainingSeconds <= 180
                                    let isUrgent = state.flowRemainingSeconds <= 60
                                    let timerColor: Color = isUrgent ? Color(red: 1.0, green: 0.35, blue: 0.35) : (isLow ? Color.orange : state.hudAccentColor)

                                    Text(state.flowTimeString)
                                        .font(.system(size: isMini ? 9.5 : (isSpacious ? 11.5 : 10.5), weight: .bold, design: .monospaced))
                                        .foregroundColor(state.isFlowPaused ? .secondary : timerColor)
                                        .opacity(state.isFlowPaused ? (Int(time * 2) % 2 == 0 ? 0.4 : 1.0) : (isUrgent ? (Int(time * 3) % 2 == 0 ? 0.75 : 1.0) : 1.0))
                                        .scaleEffect(isUrgent ? (1.0 + sin(time * 8.0) * 0.06) : 1.0)
                                }
                                .padding(.horizontal, 6)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.75).combined(with: .opacity),
                                    removal: .scale(scale: 0.75).combined(with: .opacity)
                                ))
                            } else {
                                if state.listeningStyle == "waveform" {
                                    OrganicVoiceWaveform(state: state, time: time, isVertical: false)
                                        .transition(.scale(scale: 0.65).combined(with: .opacity))
                                } else {
                                    InteractiveCharacterView(state: state, time: time)
                                        .transition(.asymmetric(
                                            insertion: .scale(scale: 0.75).combined(with: .opacity),
                                            removal: .scale(scale: 0.75).combined(with: .opacity)
                                        ))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .frame(width: pillWidth, height: pillHeight)
                    .offset(y: state.isPetHappy ? -3.5 : 0)
                    .scaleEffect(state.isPetHappy ? 1.06 : (state.isHUDHovered ? 1.03 : 1.0))
                    .animation(.spring(response: 0.26, dampingFraction: 0.68), value: state.isPetHappy)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: state.isHUDHovered)
                    .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.isRecording)
                    .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.isProcessing)
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.isFlowActive)
                    .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.isFlowPaused)
                    .scaleEffect(state.isHUDDragging ? 1.05 : 1.0)
                    .animation(.spring(response: 0.24, dampingFraction: 0.72), value: state.isHUDDragging)
                }
                .frame(width: isMini ? 96 : (isSpacious ? 136 : 112), height: isMini ? 44 : (isSpacious ? 62 : 52), alignment: .bottom)
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Native AppKit Draggable View (Multi-Screen Fluid Mouse Tracking & Hover/Click Detection)
final class DraggableHUDView<Content: View>: NSHostingView<Content> {
    private var initialMouseScreen: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var isDraggingThis = false
    private var hasMoved = false
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        self.trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        AppState.shared.isHUDHovered = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        AppState.shared.isHUDHovered = false
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if !AppState.shared.isHUDHovered {
            AppState.shared.isHUDHovered = true
        }
        NSCursor.pointingHand.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseScreen = NSEvent.mouseLocation
        if let window = self.window {
            initialWindowOrigin = window.frame.origin
            isDraggingThis = true
            hasMoved = false
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingThis else { return }
        let currentMouseScreen = NSEvent.mouseLocation
        let deltaX = currentMouseScreen.x - initialMouseScreen.x
        let deltaY = currentMouseScreen.y - initialMouseScreen.y

        if !hasMoved && (abs(deltaX) > 3 || abs(deltaY) > 3) {
            hasMoved = true
            NSCursor.closedHand.set()
            FloatingHUDController.shared.beginDrag(at: initialMouseScreen)
        }

        if hasMoved {
            let proposedOrigin = NSPoint(x: initialWindowOrigin.x + deltaX, y: initialWindowOrigin.y + deltaY)
            FloatingHUDController.shared.updateDrag(currentMouse: currentMouseScreen, proposedOrigin: proposedOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isDraggingThis else { return }
        isDraggingThis = false
        NSCursor.pointingHand.set()

        if hasMoved {
            FloatingHUDController.shared.endDrag(currentMouse: NSEvent.mouseLocation)
        } else {
            if AppState.shared.isRecording {
                HotkeyManager.shared.stopRecording()
            } else if event.clickCount >= 2 {
                AppDelegate.shared.showPopover()
            } else {
                FloatingHUDController.shared.triggerCuteClickReaction()
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = FloatingHUDController.shared.buildContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - Floating Desktop Companion Window Controller (Auto External Monitor Middle & 3-Zone Edge Snapping)
final class FloatingHUDController {
    static let shared = FloatingHUDController()
    private var panel: HUDPanel?
    private var snapGuidePanel: HUDPanel?
    private var currentSnapTarget: String = "bottom_center"
    private var dockMonitorTimer: Timer?
    private var lastKnownDockTop: CGFloat = -1
    private var cachedDockElement: AXUIElement?
    private var lastDockPID: pid_t = 0
    private var activeScreenID: CGDirectDisplayID?
    private var lastObservedScreenIDs: Set<CGDirectDisplayID> = []

    func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let desc = screen.deviceDescription
        return desc[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    func isExternal(_ screen: NSScreen) -> Bool {
        guard let id = displayID(for: screen) else { return false }
        return CGDisplayIsBuiltin(id) == 0
    }

    func panelSize(for position: String) -> NSSize {
        let size = AppState.shared.hudSize
        if position == "left" || position == "right" {
            switch size {
            case "mini": return NSSize(width: 44, height: 86)
            case "spacious": return NSSize(width: 64, height: 124)
            default: return NSSize(width: 52, height: 100) // "compact"
            }
        } else {
            switch size {
            case "mini": return NSSize(width: 96, height: 44)
            case "spacious": return NSSize(width: 136, height: 62)
            default: return NSSize(width: 112, height: 52) // "compact"
            }
        }
    }

    func applyHUDSize() {
        guard let p = panel else { return }
        let screen = currentTargetScreen()
        let targetFrame = calculateFrame(for: AppState.shared.hudPosition, screen: screen)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(targetFrame, display: true)
        }
        p.hasShadow = false
        p.invalidateShadow()
    }

    func currentHUDCenter() -> NSPoint {
        guard let p = panel else { return .zero }
        let frame = p.frame
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: - Mascot & Flow Mode Context Menu
    func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        // 1. Flow Mode Section
        let titleText = AppState.shared.isFlowActive
            ? "⚡ Flow: \(AppState.shared.flowTimeString) \(AppState.shared.isFlowPaused ? "(Paused)" : "")"
            : "⚡ Flow Mode (Focus Timer)"
        let titleItem = NSMenuItem(title: titleText, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if AppState.shared.isFlowActive {
            let pauseItem = NSMenuItem(
                title: AppState.shared.isFlowPaused ? "▶️ Resume Focus" : "⏸ Pause Focus",
                action: #selector(contextToggleFlowPause),
                keyEquivalent: ""
            )
            pauseItem.target = self
            menu.addItem(pauseItem)

            let add5Item = NSMenuItem(
                title: "➕ Add 5 Minutes",
                action: #selector(contextAdd5Minutes),
                keyEquivalent: ""
            )
            add5Item.target = self
            menu.addItem(add5Item)

            let stopItem = NSMenuItem(
                title: "⏹ Stop Session",
                action: #selector(contextStopFlow),
                keyEquivalent: ""
            )
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let p25 = NSMenuItem(title: "🍅 25 min Focus (Pomodoro)", action: #selector(contextStart25Min), keyEquivalent: "")
            p25.target = self
            menu.addItem(p25)

            let p45 = NSMenuItem(title: "🌊 45 min Deep Work", action: #selector(contextStart45Min), keyEquivalent: "")
            p45.target = self
            menu.addItem(p45)

            let p60 = NSMenuItem(title: "🚀 60 min Flow State", action: #selector(contextStart60Min), keyEquivalent: "")
            p60.target = self
            menu.addItem(p60)

            let p15 = NSMenuItem(title: "⚡ 15 min Quick Sprint", action: #selector(contextStart15Min), keyEquivalent: "")
            p15.target = self
            menu.addItem(p15)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Companion Mascot Submenu
        let mascotMenu = NSMenu()
        let bots: [(id: String, name: String)] = [
            ("gearbot", "🤖 GearBot (Curious)"),
            ("neko", "🐱 Neko (Cozy Cat)"),
            ("luna", "👻 Luna (Gentle Spirit)"),
            ("kuro", "🦊 Kuro (Clever Fox)")
        ]
        for bot in bots {
            let item = NSMenuItem(title: bot.name, action: #selector(contextSelectMascot(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bot.id
            if AppState.shared.hudCharacter == bot.id {
                item.state = .on
            }
            mascotMenu.addItem(item)
        }
        let mascotSubmenuItem = NSMenuItem(title: "Companion Mascot", action: nil, keyEquivalent: "")
        mascotSubmenuItem.submenu = mascotMenu
        menu.addItem(mascotSubmenuItem)

        // 3. Companion Size Submenu
        let sizeMenu = NSMenu()
        let sizes: [(id: String, name: String)] = [
            ("mini", "Mini (Small)"),
            ("compact", "Regular (Standard)"),
            ("spacious", "Large (Spacious)")
        ]
        for s in sizes {
            let item = NSMenuItem(title: s.name, action: #selector(contextSelectSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.id
            if AppState.shared.hudSize == s.id {
                item.state = .on
            }
            sizeMenu.addItem(item)
        }
        sizeMenu.addItem(NSMenuItem.separator())
        let incItem = NSMenuItem(title: "➕ Increase Size", action: #selector(contextIncreaseSize), keyEquivalent: "")
        incItem.target = self
        sizeMenu.addItem(incItem)
        let decItem = NSMenuItem(title: "➖ Reduce Size", action: #selector(contextDecreaseSize), keyEquivalent: "")
        decItem.target = self
        sizeMenu.addItem(decItem)

        let sizeSubmenuItem = NSMenuItem(title: "Companion Size", action: nil, keyEquivalent: "")
        sizeSubmenuItem.submenu = sizeMenu
        menu.addItem(sizeSubmenuItem)

        // 4. Dock Position Submenu
        let posMenu = NSMenu()
        let positions: [(id: String, name: String)] = [
            ("left", "Left Edge"),
            ("bottom_center", "Dock Middle (Default)"),
            ("right", "Right Edge")
        ]
        for pos in positions {
            let item = NSMenuItem(title: pos.name, action: #selector(contextSelectPosition(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pos.id
            if AppState.shared.hudPosition == pos.id {
                item.state = .on
            }
            posMenu.addItem(item)
        }
        let posSubmenuItem = NSMenuItem(title: "Dock Position", action: nil, keyEquivalent: "")
        posSubmenuItem.submenu = posMenu
        menu.addItem(posSubmenuItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Control Center & Dashboard
        let controlCenterItem = NSMenuItem(title: "Control Center...", action: #selector(contextOpenControlCenter), keyEquivalent: "")
        controlCenterItem.target = self
        menu.addItem(controlCenterItem)

        let dashItem = NSMenuItem(title: "Web Dashboard & Settings", action: #selector(contextOpenDashboard), keyEquivalent: "")
        dashItem.target = self
        menu.addItem(dashItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Velox", action: #selector(contextQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc func contextStart25Min() { AppState.shared.startFlow(minutes: 25) }
    @objc func contextStart45Min() { AppState.shared.startFlow(minutes: 45) }
    @objc func contextStart60Min() { AppState.shared.startFlow(minutes: 60) }
    @objc func contextStart15Min() { AppState.shared.startFlow(minutes: 15) }
    @objc func contextToggleFlowPause() { AppState.shared.toggleFlowPause() }
    @objc func contextAdd5Minutes() { AppState.shared.addFlowMinutes(5) }
    @objc func contextStopFlow() { AppState.shared.stopFlow() }
    @objc func contextSelectMascot(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppState.shared.hudCharacter = id
        AppState.shared.saveConfigToDisk()
        show()
    }
    @objc func contextSelectSize(_ sender: NSMenuItem) {
        guard let sizeId = sender.representedObject as? String else { return }
        AppState.shared.setHUDSize(sizeId)
    }
    @objc func contextIncreaseSize() {
        AppState.shared.increaseHUDSize()
    }
    @objc func contextDecreaseSize() {
        AppState.shared.decreaseHUDSize()
    }
    @objc func contextSelectPosition(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppState.shared.hudPosition = id
        AppState.shared.hudYOffset = 0.0
        AppState.shared.saveConfigToDisk()
        updatePosition(animated: true)
    }
    @objc func contextOpenControlCenter() {
        AppDelegate.shared.showPopover()
    }
    @objc func contextOpenDashboard() {
        if let url = URL(string: "http://127.0.0.1:18765/history#settings") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func contextQuit() {
        NSApp.terminate(nil)
    }

    func currentTargetScreen() -> NSScreen {
        // 1. If an activeScreenID is set and that screen is currently connected, use it
        if let targetID = activeScreenID,
           let screen = NSScreen.screens.first(where: { displayID(for: $0) == targetID }) {
            return screen
        }

        // 2. If an external monitor is connected, automatically prioritize it!
        if let external = NSScreen.screens.first(where: { isExternal($0) }) {
            activeScreenID = displayID(for: external)
            return external
        }

        // 3. Otherwise default to primary / main display
        let fallback = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        activeScreenID = displayID(for: fallback)
        return fallback
    }

    func screen(for mousePoint: NSPoint) -> NSScreen {
        return NSScreen.screens.first(where: { NSMouseInRect(mousePoint, $0.frame, false) })
            ?? currentTargetScreen()
    }

    func setup() {
        lastObservedScreenIDs = Set(NSScreen.screens.compactMap { displayID(for: $0) })
        _ = currentTargetScreen()

        let size = panelSize(for: AppState.shared.hudPosition)
        let p = HUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovableByWindowBackground = false

        let hudView = FloatingHUDView()
        p.contentView = DraggableHUDView(rootView: hudView)
        p.hasShadow = false
        p.invalidateShadow()
        self.panel = p

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }

        startDockMonitoring()
    }

    private func startDockMonitoring() {
        dockMonitorTimer?.invalidate()
        dockMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.checkDockPositionChange()
        }
        if let timer = dockMonitorTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func handleScreenChange() {
        let currentScreenIDs = Set(NSScreen.screens.compactMap { displayID(for: $0) })
        let newScreenIDs = currentScreenIDs.subtracting(lastObservedScreenIDs)
        lastObservedScreenIDs = currentScreenIDs

        // If an external monitor was newly connected (or screen topology changed):
        if let newExt = NSScreen.screens.first(where: { screen in
            guard let id = displayID(for: screen) else { return false }
            return newScreenIDs.contains(id) && isExternal(screen)
        }) {
            // Automatically find the middle of the external screen and stay in it!
            activeScreenID = displayID(for: newExt)
        } else if let currentID = activeScreenID, !currentScreenIDs.contains(currentID) {
            // Screen was disconnected: fallback to external if available, else primary
            let screen = NSScreen.screens.first(where: { isExternal($0) }) ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
            activeScreenID = displayID(for: screen)
        }

        // Always find and stay in the middle of the screen when screen changes
        AppState.shared.hudPosition = "bottom_center"
        AppState.shared.hudYOffset = 0.0
        AppState.shared.saveConfigToDisk()
        updatePosition(animated: true)
    }

    private func checkDockPositionChange() {
        guard let p = panel else { return }
        if AppState.shared.isHUDDragging || AppState.shared.isRecording || AppState.shared.isProcessing { return }

        let screen = currentTargetScreen()
        // If monitor configuration changed and window is on wrong screen, re-center!
        if p.screen != screen && p.screen != nil {
            updatePosition(animated: true)
            return
        }

        if AppState.shared.hudPosition == "bottom_center" {
            let currentDockTop = getLiveDockTop(for: screen)
            if abs(currentDockTop - lastKnownDockTop) > 1.5 {
                lastKnownDockTop = currentDockTop
                updatePosition(animated: true)
            }
        }
    }

    func getLiveDockTop(for screen: NSScreen) -> CGFloat {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let dockApp = runningApps.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return screen.visibleFrame.origin.y
        }

        if cachedDockElement == nil || lastDockPID != dockApp.processIdentifier {
            cachedDockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
            lastDockPID = dockApp.processIdentifier
        }
        guard let dockElement = cachedDockElement else { return screen.visibleFrame.origin.y }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return screen.visibleFrame.origin.y
        }

        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXList" {
                var posValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posValue) == .success,
                   let pv = posValue {
                    var pos = CGPoint.zero
                    AXValueGetValue(pv as! AXValue, .cgPoint, &pos)

                    if pos.y >= screen.frame.height - 4.0 {
                        return screen.visibleFrame.origin.y
                    }
                    let dockTopInCocoa = max(0, screen.frame.height - pos.y)
                    return max(screen.visibleFrame.origin.y, dockTopInCocoa)
                }
            }
        }
        return screen.visibleFrame.origin.y
    }

    func snapOrigin(for position: String, screen: NSScreen) -> NSPoint {
        let fullScreenRect = screen.frame
        let yOffset = CGFloat(AppState.shared.hudYOffset)
        let effectiveDockTop = getLiveDockTop(for: screen)
        let baseSpacing: CGFloat = 14.0
        let pSize = panelSize(for: position)

        switch position {
        case "left":
            // DOCKED TO LEFT SCREEN EDGE (Vertically Centered)
            let x = fullScreenRect.origin.x + 8.0
            let y = fullScreenRect.origin.y + (fullScreenRect.height - pSize.height) / 2.0
            return NSPoint(x: x, y: y)

        case "right":
            // DOCKED TO RIGHT SCREEN EDGE (Vertically Centered)
            let x = fullScreenRect.origin.x + fullScreenRect.width - pSize.width - 8.0
            let y = fullScreenRect.origin.y + (fullScreenRect.height - pSize.height) / 2.0
            return NSPoint(x: x, y: y)

        default: // "bottom_center", "center", "middle"
            // ALWAYS STAY IN THE EXACT HORIZONTAL MIDDLE OF THE SCREEN
            let x = fullScreenRect.origin.x + (fullScreenRect.width - pSize.width) / 2.0
            let dockSnugY = max(fullScreenRect.origin.y + baseSpacing, fullScreenRect.origin.y + effectiveDockTop + yOffset + baseSpacing)
            return NSPoint(x: x, y: dockSnugY)
        }
    }

    func calculateSnapTarget(for mousePoint: NSPoint, screen: NSScreen) -> String {
        let screenRect = screen.frame
        let isNearBottom = mousePoint.y < screenRect.origin.y + screenRect.height * 0.35

        let leftMargin = screenRect.origin.x + (isNearBottom ? screenRect.width * 0.18 : screenRect.width * 0.25)
        let rightMargin = screenRect.origin.x + (isNearBottom ? screenRect.width * 0.82 : screenRect.width * 0.75)

        if mousePoint.x < leftMargin {
            return "left"
        } else if mousePoint.x > rightMargin {
            return "right"
        } else {
            return "bottom_center"
        }
    }

    func calculateFrame(for position: String, screen: NSScreen) -> NSRect {
        let size = panelSize(for: position)
        let origin = snapOrigin(for: position, screen: screen)
        return NSRect(origin: origin, size: size)
    }

    func show() {
        if panel == nil { setup() }
        let screen = currentTargetScreen()
        guard let p = panel else { return }
        if !p.isVisible {
            AppState.shared.loadConfigFromDisk()
            let targetFrame = calculateFrame(for: AppState.shared.hudPosition, screen: screen)
            p.setFrame(targetFrame, display: true)
            p.orderFrontRegardless()
        } else {
            // If monitor configuration changed, smoothly glide to middle of active monitor
            let targetFrame = calculateFrame(for: AppState.shared.hudPosition, screen: screen)
            if p.screen != screen && p.screen != nil {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.28
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    p.animator().setFrame(targetFrame, display: true)
                }
            }
            p.orderFrontRegardless()
        }
        p.hasShadow = false
        p.invalidateShadow()
    }

    func updatePosition(animated: Bool = false) {
        guard let p = panel else { return }
        if AppState.shared.isHUDDragging || AppState.shared.isRecording || AppState.shared.isProcessing { return }
        let screen = currentTargetScreen()
        let targetFrame = calculateFrame(for: AppState.shared.hudPosition, screen: screen)
        p.hasShadow = false
        p.invalidateShadow()
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().setFrame(targetFrame, display: true)
            }
        } else {
            p.setFrame(targetFrame, display: true)
        }
    }

    func hide() {
        if AppState.shared.alwaysShowCompanion || AppState.shared.isFlowActive {
            return
        }
        panel?.orderOut(nil)
    }

    func triggerCuteClickReaction() {
        let emojis = ["💖", "✨", "⭐", "🌸", "🥰", "🎉", "🫧", "💫"]
        AppState.shared.petClickCount += 1
        AppState.shared.petReactionEmoji = emojis[AppState.shared.petClickCount % emojis.count]

        NSSound(named: "Pop")?.play()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
            AppState.shared.isPetHappy = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeOut(duration: 0.35)) {
                AppState.shared.isPetHappy = false
            }
        }
    }

    private func setupSnapGuide(for position: String, screen: NSScreen) {
        let targetFrame = calculateFrame(for: position, screen: screen)
        let guide = HUDPanel(
            contentRect: targetFrame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        guide.isFloatingPanel = true
        guide.level = .floating
        guide.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        guide.backgroundColor = .clear
        guide.isOpaque = false
        guide.hasShadow = false
        guide.ignoresMouseEvents = true
        guide.contentView = NSHostingView(rootView: SnapGuideView(targetPosition: position))
        guide.hasShadow = false
        guide.invalidateShadow()
        self.snapGuidePanel = guide
    }

    func beginDrag(at mouseScreen: NSPoint) {
        AppState.shared.isHUDDragging = true
        let screen = screen(for: mouseScreen)
        let target = calculateSnapTarget(for: mouseScreen, screen: screen)
        currentSnapTarget = target

        if snapGuidePanel == nil {
            setupSnapGuide(for: target, screen: screen)
        }
        guard let guide = snapGuidePanel else { return }

        let targetFrame = calculateFrame(for: target, screen: screen)
        guide.setFrame(targetFrame, display: false)
        guide.contentView = NSHostingView(rootView: SnapGuideView(targetPosition: target))
        guide.alphaValue = 0.0
        guide.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            guide.animator().alphaValue = 1.0
        }
    }

    func updateDrag(currentMouse: NSPoint, proposedOrigin: NSPoint) {
        guard let p = panel else { return }
        p.setFrameOrigin(proposedOrigin)

        let screen = screen(for: currentMouse)
        let newTarget = calculateSnapTarget(for: currentMouse, screen: screen)
        if newTarget != currentSnapTarget {
            currentSnapTarget = newTarget
            if let guide = snapGuidePanel {
                let targetFrame = calculateFrame(for: newTarget, screen: screen)
                guide.contentView = NSHostingView(rootView: SnapGuideView(targetPosition: newTarget))
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.20
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    guide.animator().setFrame(targetFrame, display: true)
                }
            }
        }
    }

    func endDrag(currentMouse: NSPoint) {
        AppState.shared.isHUDDragging = false
        guard let p = panel else { return }
        let screen = screen(for: currentMouse)
        let finalTarget = currentSnapTarget

        if let guide = snapGuidePanel {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                guide.animator().alphaValue = 0.0
            } completionHandler: { [weak self] in
                self?.snapGuidePanel?.orderOut(nil)
                self?.snapGuidePanel = nil
            }
        }

        activeScreenID = displayID(for: screen)
        AppState.shared.hudPosition = finalTarget
        AppState.shared.hudYOffset = 0.0
        AppState.shared.saveConfigToDisk()

        let targetFrame = calculateFrame(for: finalTarget, screen: screen)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(targetFrame, display: true)
        }
    }

    func cancelDrag() {
        AppState.shared.isHUDDragging = false
        if let guide = snapGuidePanel {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                guide.animator().alphaValue = 0.0
            } completionHandler: { [weak self] in
                self?.snapGuidePanel?.orderOut(nil)
                self?.snapGuidePanel = nil
            }
        }
    }
}

// MARK: - Low-Power Interactive Companion Tracker (Cursor Look-At & Typing Side-Eye)
final class CompanionTrackerManager {
    static let shared = CompanionTrackerManager()

    private(set) var isRunning: Bool = false
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var lastMouseTime: Double = 0.0
    private var typingResetTimer: Timer?
    private var mouseIdleTimer: Timer?

    private init() {}

    func start() {
        guard !isRunning else { return }
        stop()
        isRunning = true

        // 1. Local Monitors (within Velox app itself)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseMoved(event)
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }

        // 2. Global Monitors (system-wide when typing or navigating in other apps)
        guard AXIsProcessTrusted() else { return }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseMoved(event)
        }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    func stop() {
        isRunning = false
        if let m = mouseMonitor {
            NSEvent.removeMonitor(m)
            mouseMonitor = nil
        }
        if let k = keyMonitor {
            NSEvent.removeMonitor(k)
            keyMonitor = nil
        }
        if let lm = localMouseMonitor {
            NSEvent.removeMonitor(lm)
            localMouseMonitor = nil
        }
        if let lk = localKeyMonitor {
            NSEvent.removeMonitor(lk)
            localKeyMonitor = nil
        }
        typingResetTimer?.invalidate()
        typingResetTimer = nil
        mouseIdleTimer?.invalidate()
        mouseIdleTimer = nil
    }

    private func handleMouseMoved(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        // Strict rate-limiting to ~35Hz to protect battery & prevent lag
        guard (now - lastMouseTime) >= 0.028 else { return }
        lastMouseTime = now

        let hudCenter = FloatingHUDController.shared.currentHUDCenter()
        guard hudCenter != .zero else {
            resetCursorLook()
            return
        }

        let mouseLoc = NSEvent.mouseLocation
        let dx = mouseLoc.x - hudCenter.x
        let dy = mouseLoc.y - hudCenter.y

        // Dynamic tracking boundary: horizontal tracking width is 2/3 of screen height
        let targetScreen = FloatingHUDController.shared.currentTargetScreen()
        let screenHeight = targetScreen.frame.height > 0 ? targetScreen.frame.height : (NSScreen.main?.frame.height ?? 900.0)
        let trackingWidth = screenHeight * (2.0 / 3.0)
        let trackingHeight = screenHeight

        // Proximity check: active across 2/3 screen height horizontally & full screen height vertically
        if abs(dx) <= trackingWidth && abs(dy) <= trackingHeight {
            let divisorX = max(100.0, trackingWidth * 0.85)
            let divisorY = max(180.0, screenHeight * 0.65)
            let normalizedX = max(-1.0, min(1.0, Double(dx / divisorX)))
            let normalizedY = max(-1.0, min(1.0, Double(dy / divisorY)))

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                AppState.shared.isCursorNear = true
                AppState.shared.cursorLookX = normalizedX
                AppState.shared.cursorLookY = normalizedY

                // Auto-relax eyes after 1.5s of mouse idle
                self.mouseIdleTimer?.invalidate()
                let t = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                    AppState.shared.isCursorNear = false
                    AppState.shared.cursorLookX = 0.0
                    AppState.shared.cursorLookY = 0.0
                }
                RunLoop.main.add(t, forMode: .common)
                self.mouseIdleTimer = t
            }
        } else {
            resetCursorLook()
        }
    }

    private func resetCursorLook() {
        if AppState.shared.isCursorNear {
            DispatchQueue.main.async { [weak self] in
                self?.mouseIdleTimer?.invalidate()
                self?.mouseIdleTimer = nil
                AppState.shared.isCursorNear = false
                AppState.shared.cursorLookX = 0.0
                AppState.shared.cursorLookY = 0.0
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            AppState.shared.lastTypingTime = now
            AppState.shared.isUserTyping = true

            // Fast 0.45s debounce: immediately stops reacting once typing stops!
            self.typingResetTimer?.invalidate()
            let t = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                AppState.shared.isUserTyping = false
            }
            RunLoop.main.add(t, forMode: .common)
            self.typingResetTimer = t
        }
    }
}

// MARK: - Ultra-Clean Two-Pane Menu Bar Control Center
struct MenuBarControlCenterView: View {
    @ObservedObject var state = AppState.shared
    @Environment(\.colorScheme) var systemColorScheme
    private let pollTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var isDark: Bool {
        if state.appTheme == "dark" { return true }
        if state.appTheme == "light" { return false }
        return systemColorScheme == .dark
    }

    var body: some View {
        let baseBg = isDark ? Color(red: 0.052, green: 0.055, blue: 0.065) : Color(red: 0.985, green: 0.988, blue: 0.995)
        let sidebarBg = isDark ? Color(red: 0.038, green: 0.040, blue: 0.048) : Color(red: 0.938, green: 0.942, blue: 0.952)
        let borderStroke = isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)

        HStack(spacing: 0) {
            // 1. LEFT SIDEBAR NAVIGATION
            VStack(spacing: 6) {
                // Brand Mark
                VStack(spacing: 3) {
                    Image(systemName: "waveform.badge.microphone")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(state.hudAccentColor)
                    Text("VELOX")
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .foregroundColor(isDark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                        .tracking(1.0)
                }
                .padding(.top, 10)
                .padding(.bottom, 6)

                // Navigation Tabs
                VStack(spacing: 4) {
                    SidebarTabButton(tab: .dictate, current: state.activeTab, isDark: isDark) { state.activeTab = .dictate }
                    SidebarTabButton(tab: .flow, current: state.activeTab, isDark: isDark) { state.activeTab = .flow }
                    SidebarTabButton(tab: .companion, current: state.activeTab, isDark: isDark) { state.activeTab = .companion }
                    SidebarTabButton(tab: .settings, current: state.activeTab, isDark: isDark) { state.activeTab = .settings }
                }

                Spacer()

                // Theme Quick Toggle Pill
                Button(action: {
                    if state.appTheme == "system" {
                        state.appTheme = "dark"
                    } else if state.appTheme == "dark" {
                        state.appTheme = "light"
                    } else {
                        state.appTheme = "system"
                    }
                    state.saveConfigToDisk()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: state.appTheme == "dark" ? "moon.stars.fill" : (state.appTheme == "light" ? "sun.max.fill" : "circle.lefthalf.filled"))
                            .font(.system(size: 7.5))
                            .foregroundColor(state.hudAccentColor)
                        Text(state.appTheme == "dark" ? "Dark" : (state.appTheme == "light" ? "Light" : "Auto"))
                            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                            .foregroundColor(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Theme: Click to toggle Auto / Dark / Light")

                // Status Indicator at bottom of sidebar
                HStack(spacing: 3) {
                    Circle()
                        .fill(state.daemonReady ? Color.green.opacity(0.85) : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(state.daemonReady ? "Ready" : "Offline")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
            }
            .frame(width: 76)
            .background(sidebarBg)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(borderStroke),
                alignment: .trailing
            )

            // 2. RIGHT CONTENT PANE
            VStack(spacing: 0) {
                Group {
                    switch state.activeTab {
                    case .dictate:
                        DictateTabPane()
                    case .flow:
                        FlowTabPane()
                    case .companion:
                        CompanionTabPane()
                    case .settings:
                        SettingsTabPane()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 274)
            .background(baseBg)
        }
        .frame(width: 350, height: 330)
        .background(baseBg)
        .preferredColorScheme(state.appTheme == "dark" ? .dark : (state.appTheme == "light" ? .light : nil))
        .onAppear {
            state.loadConfigFromDisk()
            state.refreshPermissions()
            state.applyTheme()
        }
        .onReceive(pollTimer) { _ in
            state.refreshPermissions()
        }
    }
}

// MARK: - Sidebar Tab Button
struct SidebarTabButton: View {
    let tab: ControlCenterTab
    let current: ControlCenterTab
    var isDark: Bool = true
    let action: () -> Void

    var isSelected: Bool { tab == current }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? AppState.shared.hudAccentColor : (isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.45)))
                Text(tab.rawValue)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? (isDark ? .white : .black) : (isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.55)))
            }
            .frame(width: 64, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? (isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.09)) : Color.clear, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Pane 1: Dictation (Clean & Spacious on First Sight)
struct DictateTabPane: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Dictation")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.daemonReady ? Color.green.opacity(0.85) : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(state.sttEngine == "groq" ? "Groq Large v3" : "M1 Turbo")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Permissions Alert (if needed)
            if !state.isMicrophoneGranted || !state.isAccessibilityGranted {
                VStack(spacing: 5) {
                    if !state.isMicrophoneGranted {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.slash.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.88, green: 0.52, blue: 0.2))
                            Text("Mic needed")
                                .font(.system(size: 9.5, weight: .medium))
                            Spacer()
                            Button("Enable") { state.requestMicrophone() }
                                .font(.system(size: 9, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    if !state.isAccessibilityGranted {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.88, green: 0.52, blue: 0.2))
                            Text("Paste needed")
                                .font(.system(size: 9.5, weight: .medium))
                            Spacer()
                            Button("Enable") { state.requestAccessibility() }
                                .font(.system(size: 9, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(7)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            }

            Spacer(minLength: 0)

            // Tactile Center Orb
            VStack(spacing: 6) {
                Button(action: { HotkeyManager.shared.toggleRecording() }) {
                    ZStack {
                        Circle()
                            .fill(state.isRecording ? Color(red: 0.85, green: 0.25, blue: 0.3) : Color.primary.opacity(0.08))
                            .frame(width: 48, height: 48)

                        if state.isRecording {
                            Circle()
                                .stroke(Color(red: 0.85, green: 0.25, blue: 0.3).opacity(0.3), lineWidth: 2.5)
                                .frame(width: 58, height: 58)
                                .scaleEffect(1.0 + CGFloat(state.audioLevel) * 0.25)
                        }

                        Image(systemName: state.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(state.isRecording ? .white : .primary)
                    }
                }
                .buttonStyle(.plain)

                Text(state.isRecording ? "Click to Stop & Paste" : "Press ⌥ Space to Dictate")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.9))

                HStack(spacing: 3) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8))
                    Text(state.currentMicName)
                        .font(.system(size: 8.5))
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            // Segmented Engine Switch (Local Rules vs LLM)
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Button(action: {
                        state.useLlmPolish = false
                        state.provider = "local_rules"
                        state.saveConfigToDisk()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                            Text("Local Rules (0ms)")
                        }
                        .font(.system(size: 9.5, weight: (!state.useLlmPolish || state.provider == "local_rules") ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor((!state.useLlmPolish || state.provider == "local_rules") ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background((!state.useLlmPolish || state.provider == "local_rules") ? Color.primary.opacity(0.12) : Color.clear)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        state.useLlmPolish = true
                        if state.provider == "local_rules" { state.provider = "groq" }
                        state.saveConfigToDisk()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                            Text(state.provider == "groq" ? "Groq 27B" : "LLM Polish")
                        }
                        .font(.system(size: 9.5, weight: (state.useLlmPolish && state.provider != "local_rules") ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor((state.useLlmPolish && state.provider != "local_rules") ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background((state.useLlmPolish && state.provider != "local_rules") ? Color.primary.opacity(0.12) : Color.clear)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)

                Text((!state.useLlmPolish || state.provider == "local_rules") ? "⚡ Built-in Rules: Offline, Instant" : "🤖 LLM Mode: \(state.provider == "groq" ? "Groq Qwen 27B" : "LLM Polish")")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Bottom Micro Status Card
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.green.opacity(0.8))
                    Text(state.lastLatencyMs > 0 ? String(format: "%.0f ms", state.lastLatencyMs) : "Ready")
                        .font(.system(size: 8.5, weight: .medium))
                }
                Spacer()
                Text("Auto-Paste: ON")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(5)
        }
    }
}

// MARK: - Tab Pane 2: Flow Mode Focus Timer
struct FlowTabPane: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 11) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flow Mode")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("Focus & Deep Work")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if state.isFlowActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.isFlowPaused ? Color.orange : state.hudAccentColor)
                            .frame(width: 6, height: 6)
                        Text(state.isFlowPaused ? "PAUSED" : "ACTIVE")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(state.isFlowPaused ? .orange : state.hudAccentColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
            }

            // Big Timer Display Card
            VStack(spacing: 5) {
                Text(state.flowTimeString)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundColor(state.isFlowActive ? (state.isFlowPaused ? .secondary : state.hudAccentColor) : .primary)

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)

                        Capsule()
                            .fill(state.hudAccentColor)
                            .frame(width: geo.size.width * (state.isFlowActive ? state.flowProgress : 1.0), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 14)

                Text(state.isFlowActive ? (state.isFlowPaused ? "Paused — take a quick breath" : "Locked in. Flow state engaged.") : "Select a focus session duration:")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(8)

            // Preset Grid (2x2)
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    FlowPresetButton(title: "🍅 25m Focus", minutes: 25)
                    FlowPresetButton(title: "🌊 45m Deep Work", minutes: 45)
                }
                HStack(spacing: 5) {
                    FlowPresetButton(title: "🚀 60m Flow State", minutes: 60)
                    FlowPresetButton(title: "⚡ 15m Sprint", minutes: 15)
                }
            }

            // Controls when Flow is active
            if state.isFlowActive {
                HStack(spacing: 6) {
                    Button(action: { state.toggleFlowPause() }) {
                        HStack(spacing: 3) {
                            Image(systemName: state.isFlowPaused ? "play.fill" : "pause.fill")
                            Text(state.isFlowPaused ? "Resume" : "Pause")
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    Button(action: { state.addFlowMinutes(5) }) {
                        Text("+5 min")
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.vertical, 4)
                            .frame(width: 54)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    Button(action: { state.stopFlow() }) {
                        Text("Reset")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.vertical, 4)
                            .frame(width: 48)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            // Pro Tip
            HStack(spacing: 4) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 8))
                Text("Right-click desktop mascot anytime to start Flow")
                    .font(.system(size: 8))
            }
            .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

struct FlowPresetButton: View {
    let title: String
    let minutes: Int
    @ObservedObject var state = AppState.shared

    var isCurrentTarget: Bool {
        state.isFlowActive && state.flowTotalSeconds == minutes * 60
    }

    var body: some View {
        Button(action: {
            state.startFlow(minutes: minutes)
        }) {
            Text(title)
                .font(.system(size: 9, weight: isCurrentTarget ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(isCurrentTarget ? state.hudAccentColor.opacity(0.2) : Color.primary.opacity(0.05))
                .foregroundColor(isCurrentTarget ? state.hudAccentColor : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isCurrentTarget ? state.hudAccentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Pane 3: Desktop Companion & Aesthetics
struct CompanionTabPane: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Text("Companion")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(mascotDisplayName(state.hudCharacter))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(state.hudAccentColor)
            }

            // Mascot Picker
            VStack(alignment: .leading, spacing: 3) {
                Text("Mascot Character:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    MascotChip(id: "gearbot", icon: "🤖", label: "Gear")
                    MascotChip(id: "neko", icon: "🐱", label: "Neko")
                    MascotChip(id: "luna", icon: "👻", label: "Luna")
                    MascotChip(id: "kuro", icon: "🦊", label: "Kuro")
                }
            }

            // Listening Animation Style Picker
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Listening Visual:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(state.listeningStyle == "morph" ? "Morph to Bar" : (state.listeningStyle == "character" ? "Aura Only" : "Wave Only"))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    ListeningStyleChip(id: "morph", icon: "sparkles", label: "Morph")
                    ListeningStyleChip(id: "character", icon: "waveform.circle", label: "Aura")
                    ListeningStyleChip(id: "waveform", icon: "waveform", label: "Wave")
                }
            }

            // Accent Color Swatches
            VStack(alignment: .leading, spacing: 4) {
                Text("Accent Color:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 7) {
                    AccentColorDot(id: "amber", color: Color(red: 0.961, green: 0.620, blue: 0.043))
                    AccentColorDot(id: "rose", color: Color(red: 0.957, green: 0.247, blue: 0.369))
                    AccentColorDot(id: "emerald", color: Color(red: 0.063, green: 0.725, blue: 0.506))
                    AccentColorDot(id: "cyan", color: Color(red: 0.024, green: 0.714, blue: 0.831))
                    AccentColorDot(id: "purple", color: Color(red: 0.545, green: 0.361, blue: 0.965))
                    AccentColorDot(id: "monochrome", color: Color(white: 0.92))
                }
            }

            // Companion Size (Increase & Reduce)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Companion Size:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(sizeDisplayName(state.hudSize))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(state.hudAccentColor)
                }

                HStack(spacing: 4) {
                    SizeChip(id: "mini", icon: "arrow.down.right.and.arrow.up.left", label: "Mini")
                    SizeChip(id: "compact", icon: "square", label: "Regular")
                    SizeChip(id: "spacious", icon: "arrow.up.left.and.arrow.down.right", label: "Large")

                    Spacer(minLength: 2)

                    // Stepper (+ / -) to quickly increase or reduce size
                    HStack(spacing: 3) {
                        Button(action: { state.decreaseHUDSize() }) {
                            Image(systemName: "minus")
                                .font(.system(size: 7.5, weight: .bold))
                                .frame(width: 18, height: 19)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Reduce Size (-)")

                        Button(action: { state.increaseHUDSize() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 7.5, weight: .bold))
                                .frame(width: 18, height: 19)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Increase Size (+)")
                    }
                }
            }

            Divider().opacity(0.12)

            // Desktop Pet Toggle
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Always on Desktop")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("Keep mascot floating next to Dock")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $state.alwaysShowCompanion)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: state.alwaysShowCompanion) { _, enabled in
                        state.saveConfigToDisk()
                        if enabled {
                            FloatingHUDController.shared.show()
                        } else if !state.isRecording && !state.isProcessing && !state.isFlowActive {
                            FloatingHUDController.shared.hide()
                        }
                    }
            }
        }
    }

    private func mascotDisplayName(_ id: String) -> String {
        switch id.lowercased() {
        case "luna", "spirit", "ghost": return "👻 Luna (Spirit)"
        case "neko", "cat": return "🐱 Neko (Cat)"
        case "kuro", "fox": return "🦊 Kuro (Fox)"
        default: return "🤖 GearBot (Bot)"
        }
    }

    private func sizeDisplayName(_ id: String) -> String {
        switch id {
        case "mini": return "Mini (Small)"
        case "spacious": return "Large (Spacious)"
        default: return "Regular (Default)"
        }
    }
}

// MARK: - Companion Size Preset Chip
struct SizeChip: View {
    let id: String
    let icon: String
    let label: String
    @ObservedObject var state = AppState.shared

    var isSelected: Bool { state.hudSize == id }

    var body: some View {
        Button(action: {
            state.setHUDSize(id)
        }) {
            HStack(spacing: 2.5) {
                Image(systemName: icon)
                    .font(.system(size: 7))
                Text(label)
                    .font(.system(size: 8.5, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3.5)
            .background(isSelected ? state.hudAccentColor.opacity(0.20) : Color.primary.opacity(0.05))
            .foregroundColor(isSelected ? state.hudAccentColor : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? state.hudAccentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

struct AccentColorDot: View {
    let id: String
    let color: Color
    @ObservedObject var state = AppState.shared

    var isSelected: Bool { state.hudColor == id }

    var body: some View {
        Button(action: {
            state.hudColor = id
            state.saveConfigToDisk()
        }) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)

                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Preset Chip
struct ThemePresetChip: View {
    @ObservedObject var state = AppState.shared
    let id: String
    let icon: String
    let label: String

    var isSelected: Bool { state.appTheme == id }

    var body: some View {
        Button(action: {
            state.appTheme = id
            state.saveConfigToDisk()
        }) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 8.5, weight: isSelected ? .bold : .medium))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .padding(.horizontal, 3)
            .background(isSelected ? state.hudAccentColor.opacity(0.18) : Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? state.hudAccentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 0.8)
            )
            .cornerRadius(5)
            .foregroundColor(isSelected ? state.hudAccentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Pane 4: Settings & Preferences
struct SettingsTabPane: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
            }

            // Theme & Appearance
            VStack(alignment: .leading, spacing: 3) {
                Text("Appearance & Theme:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    ThemePresetChip(id: "system", icon: "circle.lefthalf.filled", label: "Auto")
                    ThemePresetChip(id: "dark", icon: "moon.stars.fill", label: "Premium Dark")
                    ThemePresetChip(id: "light", icon: "sun.max.fill", label: "Light")
                }
            }

            // Shortcuts
            VStack(alignment: .leading, spacing: 3) {
                Text("Shortcut:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 3) {
                    ShortcutChip(id: "opt_space", label: "⌥ Space")
                    ShortcutChip(id: "f8", label: "F8")
                    ShortcutChip(id: "ctrl_space", label: "⌃ Space")
                    ShortcutChip(id: "cmd_shift_d", label: "⌘⇧D")
                    ShortcutChip(id: "hold_option", label: "Hold ⌥")
                }
            }

            // Dock Position & Nudge
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Dock & Position:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(positionDisplayName(state.hudPosition, offset: state.hudYOffset))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    PositionPresetChip(id: "left", icon: "arrow.left.to.line", label: "Left")
                    PositionPresetChip(id: "bottom_center", icon: "dock.rectangle", label: "Middle")
                    PositionPresetChip(id: "right", icon: "arrow.right.to.line", label: "Right")
                }

                HStack(spacing: 6) {
                    Text("Dock Nudge:")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)

                    Button(action: {
                        state.hudYOffset = max(-20.0, state.hudYOffset - 3.0)
                        state.saveConfigToDisk()
                        FloatingHUDController.shared.updatePosition(animated: true)
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 7))
                            Text("Lower")
                                .font(.system(size: 8.5))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        state.hudYOffset = min(80.0, state.hudYOffset + 3.0)
                        state.saveConfigToDisk()
                        FloatingHUDController.shared.updatePosition(animated: true)
                    }) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 7))
                            Text("Raise")
                                .font(.system(size: 8.5))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(Int(state.hudYOffset)) px")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // Web Dashboard Link
            Button(action: {
                if let url = URL(string: "http://127.0.0.1:18765/history#settings") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                    Text("Web Dashboard & Advanced Settings")
                        .font(.system(size: 9.5, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8))
                }
                .foregroundColor(.primary.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
            Divider().opacity(0.12)

            // Footer
            HStack {
                Button(action: { restartAppAndDaemon() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text("Restart Velox")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { NSApp.terminate(nil) }) {
                    Text("Quit Velox")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func positionDisplayName(_ id: String, offset: Double) -> String {
        let offsetStr = offset == 0 ? "" : (offset > 0 ? " (+\(Int(offset))px)" : " (\(Int(offset))px)")
        switch id {
        case "bottom_left", "left": return "Left Edge"
        case "bottom_right", "right": return "Right Edge"
        default: return "Screen Middle\(offsetStr)"
        }
    }

    private func restartAppAndDaemon() {
        let script = """
        pkill -f parakeet_daemon.py || true
        sleep 0.4
        nohup /Users/macbookair/Documents/GitHub/rand/stt_bench/.venv/bin/python /Users/macbookair/Documents/GitHub/rand/ParakeetFlow/parakeet_daemon.py > /tmp/parakeet_daemon.log 2>&1 &
        sleep 0.8
        open -n /Applications/Velox.app
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", script]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}

struct ShortcutChip: View {
    let id: String
    let label: String
    @ObservedObject var state = AppState.shared

    var body: some View {
        Button(action: { HotkeyManager.shared.setShortcut(id) }) {
            Text(label)
                .font(.system(size: 9, weight: state.activeShortcut == id ? .semibold : .regular))
                .foregroundColor(state.activeShortcut == id ? .primary : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(state.activeShortcut == id ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct MascotChip: View {
    let id: String
    let icon: String
    let label: String
    @ObservedObject var state = AppState.shared

    var isSelected: Bool {
        state.hudCharacter.lowercased() == id.lowercased()
    }

    var body: some View {
        Button(action: {
            state.hudCharacter = id
            state.saveConfigToDisk()
            FloatingHUDController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if !AppState.shared.isRecording && !AppState.shared.isProcessing {
                    FloatingHUDController.shared.hide()
                }
            }
        }) {
            HStack(spacing: 3) {
                Text(icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
            }
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 3.5)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.primary.opacity(0.14) : Color.primary.opacity(0.04))
            .foregroundColor(isSelected ? .primary : .secondary)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct ListeningStyleChip: View {
    let id: String
    let icon: String
    let label: String
    @ObservedObject var state = AppState.shared

    var isSelected: Bool {
        state.listeningStyle.lowercased() == id.lowercased()
    }

    var body: some View {
        Button(action: {
            state.listeningStyle = id
            state.saveConfigToDisk()
            FloatingHUDController.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if !AppState.shared.isRecording && !AppState.shared.isProcessing && !AppState.shared.alwaysShowCompanion {
                    FloatingHUDController.shared.hide()
                }
            }
        }) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 8.5, weight: isSelected ? .semibold : .regular))
            }
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 3.5)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.primary.opacity(0.14) : Color.primary.opacity(0.04))
            .foregroundColor(isSelected ? .primary : .secondary)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct PositionPresetChip: View {
    let id: String
    let icon: String
    let label: String
    @ObservedObject var state = AppState.shared

    var isSelected: Bool {
        if id == "left" { return state.hudPosition == "left" || state.hudPosition == "bottom_left" }
        if id == "right" { return state.hudPosition == "right" || state.hudPosition == "bottom_right" }
        return state.hudPosition == id
    }

    var body: some View {
        Button(action: {
            state.hudPosition = id
            state.hudYOffset = 0.0
            state.saveConfigToDisk()
            FloatingHUDController.shared.updatePosition(animated: true)
        }) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8.5))
                Text(label)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
            }
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 3.5)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.primary.opacity(0.14) : Color.primary.opacity(0.04))
            .foregroundColor(isSelected ? .primary : .secondary)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Delegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    private var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.badge.microphone", accessibilityDescription: "Velox")
            button.toolTip = "Velox — AI Voice Dictation"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let p = NSPopover()
        p.contentSize = NSSize(width: 350, height: 330)
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: MenuBarControlCenterView())
        self.popover = p

        AppState.shared.loadConfigFromDisk()
        AppState.shared.requestAccessibility()
        FloatingHUDController.shared.setup()
        HotkeyManager.shared.setup()
        DaemonManager.shared.ensureRunning()
        DaemonManager.shared.startWatchdog()
        DictationService.shared.setupAppObserver()
        CompanionTrackerManager.shared.start()
        if AppState.shared.alwaysShowCompanion {
            FloatingHUDController.shared.show()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        AppState.shared.refreshPermissions()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        AppState.shared.refreshPermissions()
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }
}

// MARK: - Entrypoint
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
