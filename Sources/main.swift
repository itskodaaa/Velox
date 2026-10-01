import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import Foundation
import SwiftUI

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
    @AppStorage("hud_character") var hudCharacter: String = "gearbot" // "gearbot", "birb", "neko", "orb_gears", "custom"
    @AppStorage("hud_color") var hudColor: String = "amber"         // "amber", "rose", "emerald", "cyan", "purple", "monochrome"
    @AppStorage("hud_always_show") var alwaysShowCompanion: Bool = true // Desktop pet companion mode
    @AppStorage("hud_y_offset") var hudYOffset: Double = 0.0        // User nudge from dock/bottom
    @Published var isHUDDragging: Bool = false
    @Published var isHUDHovered: Bool = false
    @Published var isPetHappy: Bool = false
    @Published var petClickCount: Int = 0
    @Published var petReactionEmoji: String = "💖"

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
        if let hchar = json["hud_character"] as? String, !hchar.isEmpty { self.hudCharacter = hchar }
        if let hcol = json["hud_color"] as? String, !hcol.isEmpty { self.hudColor = hcol }
        if let halways = json["hud_always_show"] as? Bool { self.alwaysShowCompanion = halways }
        if let hyoff = json["hud_y_offset"] as? Double { self.hudYOffset = hyoff }
        refreshOpenRouterBalance()
    }

    func saveConfigToDisk() {
        let payload: [String: Any] = [
            "stt_engine": self.sttEngine,
            "groq_key": self.groqKey,
            "provider": self.provider,
            "openrouter_key": self.openRouterKey,
            "openrouter_model": self.openRouterModel,
            "ollama_url": self.ollamaUrl,
            "ollama_model": self.ollamaModel,
            "lmstudio_url": self.lmStudioUrl,
            "lmstudio_model": self.lmStudioModel,
            "use_llm_polish": self.useLlmPolish,
            "custom_vocab": self.customVocab,
            "hud_position": self.hudPosition,
            "hud_size": self.hudSize,
            "hud_character": self.hudCharacter,
            "hud_color": self.hudColor,
            "hud_always_show": self.alwaysShowCompanion,
            "hud_y_offset": self.hudYOffset
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) {
            try? data.write(to: configURL)
        }
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

    var healthURL: URL { URL(string: "http://127.0.0.1:\(port)/health")! }
    var transcribeURL: URL { URL(string: "http://127.0.0.1:\(port)/transcribe")! }

    func checkHealth(completion: @escaping (Bool) -> Void) {
        var req = URLRequest(url: healthURL)
        req.timeoutInterval = 1.0
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    func ensureRunning() {
        checkHealth { ready in
            if ready {
                AppState.shared.daemonReady = true
            } else {
                self.startDaemon()
            }
        }
    }

    private func startDaemon() {
        let venvPython = "/Users/macbookair/Documents/GitHub/rand/stt_bench/.venv/bin/python"
        let scriptPath = "/Users/macbookair/Documents/GitHub/rand/ParakeetFlow/parakeet_daemon.py"

        guard FileManager.default.fileExists(atPath: venvPython),
              FileManager.default.fileExists(atPath: scriptPath) else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: venvPython)
        p.arguments = [scriptPath]
        p.environment = ProcessInfo.processInfo.environment

        do {
            try p.run()
            self.process = p

            var attempts = 0
            Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { timer in
                attempts += 1
                self.checkHealth { ready in
                    if ready {
                        AppState.shared.daemonReady = true
                        timer.invalidate()
                    } else if attempts > 40 {
                        timer.invalidate()
                    }
                }
            }
        } catch {
            print("[DaemonManager] Start error: \(error)")
        }
    }
}

// MARK: - Hardware Microphone Recording (Native AVAudioRecorder with Hardware Metering)
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    static let shared = AudioRecorder()
    private var recorder: AVAudioRecorder?
    private var ffmpegProcess: Process?
    private var meterTimer: Timer?
    private var durationTimer: Timer?
    let recordPath = "/tmp/parakeet_recording.wav"

    func start() {
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
        meterTimer?.invalidate()
        meterTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil

        if let r = recorder {
            r.stop()
        }
        recorder = nil

        if let p = ffmpegProcess, p.isRunning {
            p.interrupt()
            p.waitUntilExit()
        }
        ffmpegProcess = nil

        AppState.shared.isRecording = false
        AppState.shared.audioLevel = 0.0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
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
        req.timeoutInterval = 35.0

        let tStart = Date()
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                AppState.shared.isProcessing = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let finalText = json["final_text"] as? String,
                      !finalText.isEmpty else {
                    AppState.shared.statusText = "No speech detected"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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

// MARK: - 1. GearBot Character (Cyber Mascot with Thinking Gears)
struct GearBotCharacterView: View {
    let time: Double
    let isRecording: Bool
    let isProcessing: Bool
    let isDone: Bool
    let audioLevel: Float
    let accentColor: Color
    var isHovered: Bool = false
    var isHappy: Bool = false

    var body: some View {
        let isIdle = !isRecording && !isProcessing && !isDone
        // 18-second life cycle for idle companion behaviors
        let cycle = isIdle ? time.truncatingRemainder(dividingBy: 18.0) : 0.0

        // Head tilt:
        let headTilt: Double = {
            if isHappy {
                return sin(time * 18.0) * 5.5 // Playful excited waggle!
            } else if isProcessing {
                return sin(time * 3.5) * 5.0
            } else if isRecording {
                return Double(audioLevel) * 7.0 - 3.5
            } else if isHovered {
                return 4.0 // Curious perk-up tilt when you hover
            } else {
                // Idle curious glances:
                if cycle >= 5.5 && cycle < 8.5 {
                    return 8.0 // Inquisitive tilt to the right
                } else if cycle >= 8.5 && cycle < 12.0 {
                    return -6.5 // Tilt to the left, watching user
                } else {
                    return sin(time * 0.9) * 1.5 // Gentle resting micro-sway
                }
            }
        }()

        // Head bob:
        let headBob: CGFloat = {
            if isHappy {
                // Excited bounce/hop!
                return -3.5 + CGFloat(abs(sin(time * 14.0))) * -2.0
            } else if isRecording {
                return -CGFloat(audioLevel) * 2.5
            } else if isProcessing {
                return 0.0
            } else if isHovered {
                return -1.6 // Perks up on hover
            } else {
                // Idle perk-up: pops up head as if noticing what you're doing!
                if cycle >= 5.2 && cycle < 7.0 {
                    return -2.2 // Pops up!
                } else if cycle >= 7.0 && cycle < 11.5 {
                    return -1.2 // Stays perched up watching
                } else {
                    return CGFloat(sin(time * 1.8) * 0.5) // Gentle breathing float
                }
            }
        }()

        // Eye glance direction:
        let (eyeOffsetX, eyeOffsetY): (CGFloat, CGFloat) = {
            if isHappy {
                return (0.0, 0.0)
            } else if isHovered {
                return (0.0, -0.6) // Looking slightly up towards your cursor
            } else if isIdle {
                if cycle >= 5.5 && cycle < 8.5 {
                    return (1.2, -0.8) // Looking up-right toward your screen work
                } else if cycle >= 8.5 && cycle < 12.0 {
                    return (-1.2, -0.8) // Looking up-left
                } else if cycle >= 14.5 && cycle < 16.0 {
                    return (0.0, 0.6) // Looking slightly down thoughtfully
                }
            }
            return (0.0, 0.0)
        }()

        // Antenna bulb illumination:
        let antennaBulbLit = isRecording || isProcessing || isHovered || isHappy || (isIdle && cycle >= 5.2 && cycle < 12.0)

        // Blinking:
        let blinkPhase = sin(time * 1.7)
        let isBlinking = (blinkPhase > 0.96 || (isIdle && cycle >= 12.0 && cycle < 12.35)) && !isProcessing && !isDone && !isHappy
        let eyeScaleY: CGFloat = isBlinking ? 0.15 : (isHovered ? 1.15 : 1.0)

        VStack(spacing: 0) {
            if isProcessing {
                InterlockingGearsView(time: time, accentColor: accentColor, isMini: true)
                    .transition(.scale.combined(with: .opacity))
                    .offset(y: 2)
            } else {
                VStack(spacing: 0) {
                    Circle()
                        .fill(antennaBulbLit ? accentColor : Color.white.opacity(0.8))
                        .frame(width: 3.5, height: 3.5)
                        .scaleEffect(isHappy ? (1.3 + sin(time * 24.0) * 0.2) : (antennaBulbLit ? 1.25 : 1.0))
                        .shadow(color: accentColor.opacity(antennaBulbLit ? 0.9 : 0.2), radius: antennaBulbLit ? 3.0 : 1)
                        .animation(.easeInOut(duration: 0.24), value: isRecording)
                        .animation(.easeInOut(duration: 0.20), value: isHovered)
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1.5, height: 3.5)
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
                    .overlay(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    )

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(accentColor)
                } else if isHappy {
                    // Kawaii smiling crescent eyes ^ ^ with blushing pink cheeks!
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
                    .transition(.scale.combined(with: .opacity))
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
                        ZStack {
                            Capsule()
                                .fill(isRecording || antennaBulbLit ? accentColor : Color.white.opacity(0.85))
                                .frame(width: 3.0, height: isHovered ? 5.5 : 5.0)
                                .scaleEffect(y: eyeScaleY)
                                .offset(x: eyeOffsetX, y: eyeOffsetY)
                                .shadow(color: accentColor.opacity(isRecording || antennaBulbLit ? 0.9 : 0.2), radius: 2.5)

                            if isHovered && !isBlinking {
                                Circle()
                                    .fill(Color.white.opacity(0.95))
                                    .frame(width: 1.1, height: 1.1)
                                    .offset(x: -0.6 + eyeOffsetX, y: -1.2 + eyeOffsetY)
                            }
                        }

                        ZStack {
                            Capsule()
                                .fill(isRecording || antennaBulbLit ? accentColor : Color.white.opacity(0.85))
                                .frame(width: 3.0, height: isHovered ? 5.5 : 5.0)
                                .scaleEffect(y: eyeScaleY)
                                .offset(x: eyeOffsetX, y: eyeOffsetY)
                                .shadow(color: accentColor.opacity(isRecording || antennaBulbLit ? 0.9 : 0.2), radius: 2.5)

                            if isHovered && !isBlinking {
                                Circle()
                                    .fill(Color.white.opacity(0.95))
                                    .frame(width: 1.1, height: 1.1)
                                    .offset(x: -0.6 + eyeOffsetX, y: -1.2 + eyeOffsetY)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.24), value: isRecording)
                    .animation(.easeInOut(duration: 0.20), value: isHovered)
                }
            }
        }
        .rotationEffect(.degrees(headTilt))
        .offset(y: headBob)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isRecording)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isProcessing)
        .animation(.spring(response: 0.30, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.26, dampingFraction: 0.65), value: isHappy)
    }
}

// MARK: - 2. Birb Character (Velox Parakeet with Audio-Reactive Beak)
struct BirbCharacterView: View {
    let time: Double
    let isRecording: Bool
    let isProcessing: Bool
    let isDone: Bool
    let audioLevel: Float
    let accentColor: Color
    var isHovered: Bool = false
    var isHappy: Bool = false

    var body: some View {
        let blinkPhase = sin(time * 1.8)
        let isBlinking = blinkPhase > 0.96 && !isProcessing && !isDone && !isHappy
        let tilt: Double = {
            if isHappy {
                return sin(time * 16.0) * 6.0
            } else if isHovered {
                return 4.0
            } else if isProcessing {
                return sin(time * 3.0) * 7.0
            } else if isRecording {
                return Double(audioLevel) * 6.0 - 3.0
            }
            return 0.0
        }()
        let beakOpen: CGFloat = {
            if isHappy {
                return 1.8 + CGFloat(abs(sin(time * 12.0))) * 1.5
            } else if isRecording {
                return max(0.5, CGFloat(audioLevel) * 4.0)
            }
            return 0.5
        }()
        let bob: CGFloat = isHappy ? (-2.5 + CGFloat(abs(sin(time * 14.0))) * -1.5) : (isHovered ? -1.0 : 0.0)

        VStack(spacing: -1) {
            if isProcessing {
                GearShape(teeth: 8, innerRadiusRatio: 0.6, centerHoleRatio: 0.25)
                    .fill(accentColor)
                    .frame(width: 13, height: 13)
                    .rotationEffect(.degrees(time * 220.0))
                    .shadow(color: accentColor.opacity(0.4), radius: 2)
            } else {
                HStack(spacing: 1.2) {
                    Capsule()
                        .fill(accentColor)
                        .frame(width: 2.0, height: 4.5 + CGFloat(audioLevel) * 2.5 + (isHappy ? 1.5 : 0))
                        .rotationEffect(.degrees(-15))
                    Capsule()
                        .fill(accentColor.opacity(0.9))
                        .frame(width: 1.8, height: 6.0 + CGFloat(audioLevel) * 3.5 + (isHappy ? 2.0 : 0))
                    Capsule()
                        .fill(accentColor.opacity(0.75))
                        .frame(width: 1.6, height: 4.0 + CGFloat(audioLevel) * 2.0 + (isHappy ? 1.5 : 0))
                        .rotationEffect(.degrees(15))
                }
                .offset(y: 1)
            }

            HStack(spacing: -2) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.95), accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 17, height: 17)
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.6))

                    if isDone || isHappy {
                        HStack(spacing: 2) {
                            Text("^")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                            if isHappy {
                                Circle().fill(Color.pink.opacity(0.85)).frame(width: 2, height: 1.5)
                            }
                        }
                        .offset(x: 2, y: -1)
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.85))
                            .frame(width: isHovered ? 5.2 : 4.5, height: isHovered ? 5.2 : 4.5)
                            .scaleEffect(y: isBlinking ? 0.2 : 1.0)
                            .overlay(
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: isHovered ? 1.6 : 1.2, height: isHovered ? 1.6 : 1.2)
                                    .offset(x: 1, y: -1)
                                    .opacity(isBlinking ? 0 : 1)
                            )
                            .offset(x: 2, y: -1)
                    }
                }

                Path { p in
                    p.move(to: CGPoint(x: 0, y: 3))
                    p.addLine(to: CGPoint(x: 4.5, y: 5.5 + beakOpen * 0.5))
                    p.addLine(to: CGPoint(x: 0, y: 8 + beakOpen))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.98, green: 0.72, blue: 0.15))
                .frame(width: 4.5, height: 9 + beakOpen)
                .offset(y: -1)
            }
        }
        .rotationEffect(.degrees(tilt))
        .offset(y: bob)
    }
}

// MARK: - 3. Neko Character (Glass Cat with Audio-Twitching Ears)
struct NekoCharacterView: View {
    let time: Double
    let isRecording: Bool
    let isProcessing: Bool
    let isDone: Bool
    let audioLevel: Float
    let accentColor: Color
    var isHovered: Bool = false
    var isHappy: Bool = false

    var body: some View {
        let blinkPhase = sin(time * 1.6)
        let isBlinking = blinkPhase > 0.96 && !isProcessing && !isDone && !isHappy
        let earTwitch: Double = isHappy ? sin(time * 16.0) * 10.0 : (isRecording ? Double(audioLevel) * 7.0 : (isHovered ? 3.0 : 0.0))
        let bob: CGFloat = isHappy ? (-2.5 + CGFloat(abs(sin(time * 14.0))) * -1.5) : (isHovered ? -1.0 : 0.0)

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
                    .fill(accentColor.opacity(0.9))
                    .frame(width: 6.5, height: 6.5)
                    .rotationEffect(.degrees(-earTwitch))

                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 6.5))
                        p.addLine(to: CGPoint(x: 3.2, y: 0))
                        p.addLine(to: CGPoint(x: 6.5, y: 6.5))
                        p.closeSubpath()
                    }
                    .fill(accentColor.opacity(0.9))
                    .frame(width: 6.5, height: 6.5)
                    .rotationEffect(.degrees(earTwitch))
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
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(accentColor)
                            .frame(width: isHovered ? 3.6 : 3.2, height: isHovered ? 5.5 : 5.0)
                            .scaleEffect(y: isBlinking ? 0.15 : (1.0 + CGFloat(audioLevel) * 0.25))
                            .shadow(color: accentColor.opacity(0.6), radius: 2)

                        Capsule()
                            .fill(accentColor)
                            .frame(width: isHovered ? 3.6 : 3.2, height: isHovered ? 5.5 : 5.0)
                            .scaleEffect(y: isBlinking ? 0.15 : (1.0 + CGFloat(audioLevel) * 0.25))
                            .shadow(color: accentColor.opacity(0.6), radius: 2)
                    }
                }
            }
        }
        .offset(y: bob)
    }
}

// MARK: - 4. OrbGears Character (Horology Tourbillon Gear Engine)
struct OrbGearsCharacterView: View {
    let time: Double
    let isRecording: Bool
    let isProcessing: Bool
    let isDone: Bool
    let audioLevel: Float
    let accentColor: Color
    var isHovered: Bool = false
    var isHappy: Bool = false

    var body: some View {
        let speed = isHappy ? 400.0 : (isProcessing ? 280.0 : (isRecording ? 60.0 + Double(audioLevel) * 160.0 : (isHovered ? 80.0 : 30.0)))

        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(isHappy ? 0.4 : (isHovered ? 0.28 : 0.18)), Color.black.opacity(0.45)],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 13
                    )
                )
                .frame(width: 23, height: 23)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )

            GearShape(teeth: 10, innerRadiusRatio: 0.72, centerHoleRatio: 0.55)
                .stroke(Color.white.opacity(0.4), lineWidth: 1.2)
                .frame(width: 21, height: 21)
                .rotationEffect(.degrees(-time * speed * 0.6))

            GearShape(teeth: 6, innerRadiusRatio: 0.58, centerHoleRatio: 0.25)
                .fill(
                    LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.8), Color.white.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(time * speed))
                .shadow(color: accentColor.opacity(0.5), radius: 2.5)

            Circle()
                .fill(isDone || isHappy ? Color.green : Color.white)
                .frame(width: isHappy ? 4.0 : 3.0, height: isHappy ? 4.0 : 3.0)
                .shadow(color: Color.white.opacity(0.8), radius: 2)
        }
        .scaleEffect(isHappy ? 1.12 : 1.0)
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

        ZStack {
            switch charType {
            case "birb", "parakeet":
                BirbCharacterView(
                    time: time,
                    isRecording: state.isRecording,
                    isProcessing: state.isProcessing,
                    isDone: isDone,
                    audioLevel: state.audioLevel,
                    accentColor: state.hudAccentColor,
                    isHovered: state.isHUDHovered,
                    isHappy: state.isPetHappy
                )
            case "neko", "cat":
                NekoCharacterView(
                    time: time,
                    isRecording: state.isRecording,
                    isProcessing: state.isProcessing,
                    isDone: isDone,
                    audioLevel: state.audioLevel,
                    accentColor: state.hudAccentColor,
                    isHovered: state.isHUDHovered,
                    isHappy: state.isPetHappy
                )
            case "orb_gears", "orb", "gears":
                OrbGearsCharacterView(
                    time: time,
                    isRecording: state.isRecording,
                    isProcessing: state.isProcessing,
                    isDone: isDone,
                    audioLevel: state.audioLevel,
                    accentColor: state.hudAccentColor,
                    isHovered: state.isHUDHovered,
                    isHappy: state.isPetHappy
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
                        isHappy: state.isPetHappy
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
                    isHappy: state.isPetHappy
                )
            }
        }
        .frame(width: 26, height: 26)
        .scaleEffect(0.68)
        .frame(width: 17, height: 17)
    }
}

// MARK: - Organic Harmonic Soundwave (Pure Fluid Audio Equalizer)
struct OrganicVoiceWaveform: View {
    @ObservedObject var state = AppState.shared
    let time: Double
    let barCount: Int = 6

    var body: some View {
        HStack(spacing: 1.6) {
            ForEach(0..<barCount, id: \.self) { i in
                let h = computeHeight(i: i, time: time)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                state.hudAccentColor,
                                state.hudAccentColor.opacity(0.65)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1.8, height: h)
            }
        }
        .frame(height: 12)
    }

    private func computeHeight(i: Int, time: Double) -> CGFloat {
        if !state.isRecording { return 2.0 }
        let freq = 3.6 + Double(i) * 1.4
        let phase = Double(i) * 0.72
        let harm1 = sin(time * freq + phase)
        let harm2 = cos(time * (freq * 0.55) + phase * 1.2)
        let oscillation = harm1 * 0.65 + harm2 * 0.35
        let centerDist = abs(Double(i) - 2.5) / 2.5
        let bell = 0.40 + 0.60 * cos(centerDist * .pi / 2.0)
        let energy = max(0.15, Double(state.audioLevel))
        let dynamicRange = 8.5 * bell * energy
        let rawHeight = 2.0 + dynamicRange * (1.0 + oscillation * 0.75)
        return CGFloat(max(2.0, min(12.0, rawHeight)))
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

    var isVertical: Bool {
        state.hudPosition == "left" || state.hudPosition == "right"
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.033)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let isMini = state.hudSize == "mini"
            let isSpacious = state.hudSize == "spacious"

            if isVertical {
                // VERTICAL CAPSULE FOR LEFT / RIGHT SCREEN EDGES
                let pillWidth: CGFloat = isMini ? 22 : (isSpacious ? 28 : 25)
                let pillHeight: CGFloat = {
                    if state.isRecording {
                        return isMini ? 68 : (isSpacious ? 84 : 76)
                    } else if state.isProcessing {
                        return isMini ? 50 : (isSpacious ? 62 : 56)
                    } else {
                        return isMini ? 36 : (isSpacious ? 44 : 40)
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
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    Color.white.opacity(state.isHUDDragging ? 0.45 : (state.isHUDHovered ? 0.32 : 0.22)),
                                    lineWidth: state.isHUDDragging ? 1.05 : 0.85
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(state.isHUDDragging ? 0.46 : 0.30),
                            radius: state.isHUDDragging ? 7 : 4,
                            x: 0,
                            y: state.isHUDDragging ? 4 : 2
                        )

                    VStack(spacing: 5) {
                        InteractiveCharacterView(state: state, time: time)

                        if state.isRecording {
                            OrganicVoiceWaveform(state: state, time: time)
                                .transition(.scale.combined(with: .opacity))
                        } else if state.isProcessing {
                            Circle()
                                .trim(from: 0.0, to: 0.65)
                                .stroke(state.hudAccentColor, lineWidth: 1.5)
                                .frame(width: 8, height: 8)
                                .rotationEffect(.degrees(time * 360.0))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(width: pillWidth, height: pillHeight)
                .scaleEffect(state.isPetHappy ? 1.06 : (state.isHUDHovered ? 1.03 : 1.0))
                .animation(.spring(response: 0.26, dampingFraction: 0.68), value: state.isPetHappy)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: state.isHUDHovered)
                .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.isRecording)
                .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.isProcessing)
                .scaleEffect(state.isHUDDragging ? 1.05 : 1.0)
                .frame(width: 50, height: 96, alignment: .center)
            } else {
                // HORIZONTAL CAPSULE FOR BOTTOM CENTER
                let pillWidth: CGFloat = {
                    if state.isRecording {
                        return isMini ? 68 : (isSpacious ? 84 : 76)
                    } else if state.isProcessing {
                        return isMini ? 50 : (isSpacious ? 62 : 56)
                    } else {
                        return isMini ? 36 : (isSpacious ? 44 : 40)
                    }
                }()
                let pillHeight: CGFloat = isMini ? 22 : (isSpacious ? 28 : 25)

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
                            .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        Color.white.opacity(state.isHUDDragging ? 0.45 : (state.isHUDHovered ? 0.32 : 0.22)),
                                        lineWidth: state.isHUDDragging ? 1.05 : 0.85
                                    )
                            )
                            .shadow(
                                color: Color.black.opacity(state.isHUDDragging ? 0.46 : 0.30),
                                radius: state.isHUDDragging ? 7 : 4,
                                x: 0,
                                y: state.isHUDDragging ? 4 : 2
                            )

                        HStack(spacing: 5) {
                            InteractiveCharacterView(state: state, time: time)

                            if state.isRecording {
                                OrganicVoiceWaveform(state: state, time: time)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.6, anchor: .leading)),
                                        removal: .opacity.combined(with: .scale(scale: 0.6, anchor: .leading))
                                    ))
                            } else if state.isProcessing {
                                ZStack {
                                    Circle()
                                        .stroke(state.hudAccentColor.opacity(0.3), lineWidth: 1.2)
                                        .frame(width: 10, height: 10)
                                    Circle()
                                        .trim(from: 0.0, to: 0.65)
                                        .stroke(
                                            LinearGradient(
                                                colors: [state.hudAccentColor, state.hudAccentColor.opacity(0.1)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                                        )
                                        .frame(width: 10, height: 10)
                                        .rotationEffect(.degrees(time * 360.0))
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(width: pillWidth, height: pillHeight)
                    .offset(y: state.isPetHappy ? -3.5 : 0)
                    .scaleEffect(state.isPetHappy ? 1.06 : (state.isHUDHovered ? 1.03 : 1.0))
                    .animation(.spring(response: 0.26, dampingFraction: 0.68), value: state.isPetHappy)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: state.isHUDHovered)
                    .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.isRecording)
                    .animation(.spring(response: 0.36, dampingFraction: 0.80), value: state.isProcessing)
                    .scaleEffect(state.isHUDDragging ? 1.05 : 1.0)
                    .animation(.spring(response: 0.24, dampingFraction: 0.72), value: state.isHUDDragging)
                }
                .frame(width: 96, height: 50, alignment: .bottom)
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
        if position == "left" || position == "right" {
            return NSSize(width: 50, height: 96)
        } else {
            return NSSize(width: 96, height: 50)
        }
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

        switch position {
        case "left":
            // DOCKED TO LEFT SCREEN EDGE (Vertically Centered)
            let x = fullScreenRect.origin.x + 8.0
            let y = fullScreenRect.origin.y + (fullScreenRect.height - 96.0) / 2.0
            return NSPoint(x: x, y: y)

        case "right":
            // DOCKED TO RIGHT SCREEN EDGE (Vertically Centered)
            let x = fullScreenRect.origin.x + fullScreenRect.width - 50.0 - 8.0
            let y = fullScreenRect.origin.y + (fullScreenRect.height - 96.0) / 2.0
            return NSPoint(x: x, y: y)

        default: // "bottom_center", "center", "middle"
            // ALWAYS STAY IN THE EXACT HORIZONTAL MIDDLE OF THE SCREEN
            let x = fullScreenRect.origin.x + (fullScreenRect.width - 96.0) / 2.0
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
        if AppState.shared.alwaysShowCompanion {
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

// MARK: - Ultra-Minimalist, Subdued Luxury Menu Bar Popover
struct MenuBarControlCenterView: View {
    @ObservedObject var state = AppState.shared
    private let pollTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 11) {
            // Header: Minimal & Quiet
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "waveform.badge.microphone")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))
                    Text("Velox")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(state.daemonReady ? Color.green.opacity(0.8) : Color.secondary)
                        .frame(width: 5, height: 5)
                    Text(state.sttEngine == "groq" ? "Groq Large v3" : "M1 Turbo")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Permissions Alert Banner (if needed)
            if !state.isMicrophoneGranted || !state.isAccessibilityGranted {
                VStack(spacing: 5) {
                    if !state.isMicrophoneGranted {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.slash.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(red: 0.88, green: 0.52, blue: 0.2))
                            Text("Mic permission needed")
                                .font(.system(size: 10, weight: .medium))
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
                            Text("Accessibility needed to paste")
                                .font(.system(size: 10, weight: .medium))
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

            // Tactile Microphone Orb (Frosted Glass)
            VStack(spacing: 5) {
                Button(action: { HotkeyManager.shared.toggleRecording() }) {
                    ZStack {
                        Circle()
                            .fill(state.isRecording ? Color(red: 0.82, green: 0.28, blue: 0.32) : Color.primary.opacity(0.08))
                            .frame(width: 46, height: 46)

                        if state.isRecording {
                            Circle()
                                .stroke(Color(red: 0.82, green: 0.28, blue: 0.32).opacity(0.25), lineWidth: 2)
                                .frame(width: 56, height: 56)
                                .scaleEffect(1.0 + CGFloat(state.audioLevel) * 0.2)
                        }

                        Image(systemName: state.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 17, weight: .medium))
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
                        .font(.system(size: 9))
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 1)

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
                            Text(state.provider == "groq" ? "Groq 27B" : (state.provider == "lmstudio" ? "Bionic LLM" : "LLM Polish"))
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

                Text((!state.useLlmPolish || state.provider == "local_rules") ? "⚡ Built-in Rules: Offline, Instant 0ms (No LLM)" : "🤖 LLM Mode: \(state.provider == "groq" ? "Groq Qwen 27B" : (state.provider == "lmstudio" ? "Bionic Local" : (state.provider == "ollama" ? "Ollama Local" : "OpenRouter Cloud")))")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Shortcut Keycaps
            VStack(alignment: .leading, spacing: 3) {
                Text("Shortcut:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    ShortcutChip(id: "opt_space", label: "⌥ Space")
                    ShortcutChip(id: "f8", label: "F8")
                    ShortcutChip(id: "ctrl_space", label: "⌃ Space")
                    ShortcutChip(id: "cmd_shift_d", label: "⌘⇧D")
                    ShortcutChip(id: "hold_option", label: "Hold ⌥")
                }
            }

            // Companion Mascot Picker
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Companion Mascot:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mascotDisplayName(state.hudCharacter))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                }

                HStack(spacing: 4) {
                    MascotChip(id: "gearbot", icon: "🤖", label: "Gear")
                    MascotChip(id: "birb", icon: "🦜", label: "Birb")
                    MascotChip(id: "neko", icon: "🐱", label: "Neko")
                    MascotChip(id: "orb_gears", icon: "⚙️", label: "Orb")
                }
            }

            // Always on Desktop Toggle
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: state.alwaysShowCompanion ? "sparkles" : "eye.slash")
                        .font(.system(size: 9.5))
                        .foregroundColor(state.alwaysShowCompanion ? state.hudAccentColor : .secondary)
                    Text("Always on Desktop")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("(Pet)")
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
                        } else if !state.isRecording && !state.isProcessing {
                            FloatingHUDController.shared.hide()
                        }
                    }
            }

            // Position & Dock Snapping
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Dock & Position:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(positionDisplayName(state.hudPosition, offset: state.hudYOffset))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
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
                                .font(.system(size: 7.5))
                            Text("Lower")
                                .font(.system(size: 8.5))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
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
                                .font(.system(size: 7.5))
                            Text("Raise")
                                .font(.system(size: 8.5))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(Int(state.hudYOffset)) px")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 1)

                Text("💡 Middle bottom with smooth automatic Dock tracking & pet interactions")
                    .font(.system(size: 7.5))
                    .foregroundColor(.secondary.opacity(0.75))
            }

            // Dedicated Web Dashboard & Settings Button (Opens full browser UI)
            Button(action: {
                if let url = URL(string: "http://127.0.0.1:18765/history#settings") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("Dashboard & Settings")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .foregroundColor(.primary.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Divider().opacity(0.15)

            // Minimal Footer with Restart & Quit
            HStack {
                Button(action: { restartAppAndDaemon() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text("Restart")
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if state.isAccessibilityGranted {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: 5, height: 5)
                        Text("Ready")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button(action: { state.requestAccessibility() }) {
                        Text("Enable Paste")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(red: 0.88, green: 0.52, blue: 0.2))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: { NSApp.terminate(nil) }) {
                    Text("Quit")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .frame(width: 275)
        .onAppear {
            state.loadConfigFromDisk()
            state.refreshPermissions()
        }
        .onReceive(pollTimer) { _ in
            state.refreshPermissions()
        }
    }

    private func mascotDisplayName(_ id: String) -> String {
        switch id.lowercased() {
        case "birb", "parakeet": return "🦜 Birb"
        case "neko", "cat": return "🐱 Neko"
        case "orb_gears", "orb", "gears": return "⚙️ Tourbillon Orb"
        default: return "🤖 GearBot"
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
    private var popover: NSPopover!

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
        p.contentSize = NSSize(width: 275, height: 430)
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: MenuBarControlCenterView())
        self.popover = p

        AppState.shared.loadConfigFromDisk()
        AppState.shared.requestAccessibility()
        FloatingHUDController.shared.setup()
        HotkeyManager.shared.setup()
        DaemonManager.shared.ensureRunning()
        DictationService.shared.setupAppObserver()
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
