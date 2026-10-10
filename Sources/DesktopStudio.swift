import AppKit
import AVFoundation
import Foundation
import SwiftUI

// MARK: - Color Hex Initializer
extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch clean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

// MARK: - Mumblr Atelier Design Tokens
struct MumblrTokens {
    // Surfaces
    static let porcelainSurface = Color(hex: "FAF4EB")
    static let porcelainSubtle  = Color(hex: "FDF8F0")
    static let cardBeige        = Color(hex: "F6EFE3")
    static let cardBorder       = Color.black.opacity(0.035)
    static let pureWhite        = Color(hex: "FFFFFF")

    // Typography & Accents
    static let primaryText      = Color(hex: "1A1A1E")
    static let stoneGray        = Color(hex: "686460")
    static let charcoalBadge    = Color(hex: "121214")

    // Pastel System
    static let peachBg          = Color(hex: "FCE3B4")
    static let peachText        = Color(hex: "7A4C18")

    static let blueBg           = Color(hex: "BCE2F9")
    static let blueText         = Color(hex: "1C5578")

    static let lilacBg          = Color(hex: "D5B8F6")
    static let lilacText        = Color(hex: "4D2A78")

    static let salmonBg         = Color(hex: "F8C6BC")
    static let salmonText       = Color(hex: "7D2F22")

    static let orchidBg         = Color(hex: "E2B2E6")
    static let orchidText       = Color(hex: "65256D")

    // Geometry Radii
    static let shellRadius: CGFloat   = 36
    static let bannerRadius: CGFloat  = 24
    static let cardRadius: CGFloat    = 22
    static let innerRadius: CGFloat   = 18
    static let pillRadius: CGFloat    = 9999
}

// MARK: - Core Desktop Navigation Tabs
enum MumblrTab: String, CaseIterable, Identifiable {
    case dictation  = "Dictation"
    case dictionary = "Dictionary"
    case companion  = "Companion & Flow"
    case insights   = "Insights"
    case settings   = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dictation:  return "mic"
        case .dictionary: return "book"
        case .companion:  return "sparkles"
        case .insights:   return "chart.line.uptrend.xyaxis"
        case .settings:   return "gearshape"
        }
    }
}

// MARK: - Studio UI Feedback Manager
final class StudioFeedbackManager: ObservableObject {
    static let shared = StudioFeedbackManager()
    @Published var toastMessage: String? = nil
    @Published var showProfileModal: Bool = false
    @Published var showShortcutModal: Bool = false
    private var dismissWorkItem: DispatchWorkItem?

    func show(message: String) {
        dismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.toastMessage = message
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.25)) {
                self?.toastMessage = nil
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }
}

// MARK: - Studio Audio Speech Synthesizer Manager
final class StudioAudioManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = StudioAudioManager()
    private var synth = AVSpeechSynthesizer()
    @Published var isSpeaking: Bool = false
    @Published var activeSpeakingText: String = ""

    override init() {
        super.init()
        synth.delegate = self
    }

    func toggleSpeaking(text: String) {
        if isSpeaking && activeSpeakingText == text {
            synth.stopSpeaking(at: .immediate)
            isSpeaking = false
            activeSpeakingText = ""
        } else {
            synth.stopSpeaking(at: .immediate)
            activeSpeakingText = text
            isSpeaking = true
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synth.speak(utterance)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.activeSpeakingText = ""
        }
    }
}

// MARK: - Text Transformation Helper
func transformSmartPolishText(_ input: String) -> String {
    var text = input
    let verbalFillers = ["you know", "like,", "rubbish", "I mean,"]
    for f in verbalFillers {
        text = text.replacingOccurrences(of: f, with: "", options: .caseInsensitive)
    }
    // Convert numbered items to clean bullet lists
    if text.contains("1. ") {
        text = text.replacingOccurrences(of: "1. ", with: "• ")
            .replacingOccurrences(of: "2. ", with: "• ")
            .replacingOccurrences(of: "3. ", with: "• ")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Mumblr Desktop Studio Window Controller
final class MumblrStudioWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MumblrStudioWindowController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.minSize = NSSize(width: 980, height: 620)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.98, green: 0.957, blue: 0.922, alpha: 1.0) // #FAF4EB

        let hostingView = NSHostingView(rootView: MumblrDesktopStudioView())
        window.contentView = hostingView

        self.init(window: window)
        window.delegate = self
    }

    func show() {
        guard let window = self.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        guard let window = self.window else { return }
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func setTab(_ tab: MumblrTab) {
        NotificationCenter.default.post(name: NSNotification.Name("MumblrSwitchTab"), object: tab)
    }
}

// MARK: - Main Desktop Studio View
struct MumblrDesktopStudioView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var feedback = StudioFeedbackManager.shared
    @ObservedObject var audio = StudioAudioManager.shared
    @State private var selectedTab: MumblrTab = .dictation

    var body: some View {
        ZStack {
            MumblrTokens.porcelainSurface
                .ignoresSafeArea()

            // APP VIEWPORT (3-COLUMN STUDIO LAYOUT)
            HStack(spacing: 0) {
                // 1. LEFT NAVIGATION RAIL
                MumblrSidebarView(selectedTab: $selectedTab)
                    .frame(width: 250)
                    .background(MumblrTokens.porcelainSurface)

                Divider()
                    .background(MumblrTokens.cardBorder)

                // 2. MAIN CENTER CONTENT VIEW
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        switch selectedTab {
                        case .dictation:
                            MumblrDictationStreamView(selectedTab: $selectedTab)
                        case .dictionary:
                            MumblrDictionaryView()
                        case .companion:
                            MumblrCompanionView()
                        case .insights:
                            MumblrInsightsView()
                        case .settings:
                            MumblrSettingsView()
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 36)
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MumblrTokens.porcelainSubtle)

                Divider()
                    .background(MumblrTokens.cardBorder)

                // 3. RIGHT ANALYTICS & QUOTA COLUMN
                MumblrRightAnalyticsView(selectedTab: $selectedTab)
                    .frame(width: 290)
                    .padding(.top, 24)
                    .background(MumblrTokens.porcelainSurface)
            }

            // FLOATING TOAST NOTIFICATION BANNER
            if let msg = feedback.toastMessage {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "27C93F"))
                            .font(.system(size: 14))
                        Text(msg)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(MumblrTokens.primaryText)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(MumblrTokens.pureWhite)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 4)
                    .padding(.top, 18)

                    Spacer()
                }
                .zIndex(100)
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }

            // USER ACCOUNT PROFILE MODAL OVERLAY
            if feedback.showProfileModal {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { feedback.showProfileModal = false }
                    }
                    .zIndex(150)

                VStack(spacing: 18) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(MumblrTokens.charcoalBadge)
                                .frame(width: 44, height: 44)
                            Text("A")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Aura")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(MumblrTokens.primaryText)
                            Text("aura@mumblr.ai")
                                .font(.system(size: 12))
                                .foregroundColor(MumblrTokens.stoneGray)
                        }
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) { feedback.showProfileModal = false }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(MumblrTokens.stoneGray.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    VStack(spacing: 10) {
                        HStack {
                            Text("Active Plan:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MumblrTokens.stoneGray)
                            Spacer()
                            Text("Mumblr Atelier Pro")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(MumblrTokens.primaryText)
                        }
                        HStack {
                            Text("Monthly Quota:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MumblrTokens.stoneGray)
                            Spacer()
                            Text("Unlimited Words")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(MumblrTokens.blueText)
                        }
                        HStack {
                            Text("License Seat:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MumblrTokens.stoneGray)
                            Spacer()
                            Text("Seat #182 (Active)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(MumblrTokens.primaryText)
                        }
                    }
                    .padding(14)
                    .background(MumblrTokens.cardBeige)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    HStack(spacing: 10) {
                        Button(action: {
                            if let url = URL(string: "https://flow.mumblr.ai/account/billing") {
                                NSWorkspace.shared.open(url)
                            }
                            feedback.showProfileModal = false
                        }) {
                            HStack {
                                Spacer()
                                Text("Manage on Web →")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            .background(MumblrTokens.charcoalBadge)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) { feedback.showProfileModal = false }
                        }) {
                            Text("Close")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(MumblrTokens.cardBeige)
                                .foregroundColor(MumblrTokens.primaryText)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
                .frame(width: 370)
                .background(MumblrTokens.pureWhite)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
                .zIndex(200)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // KEYBOARD SHORTCUTS CONFIG MODAL
            if feedback.showShortcutModal {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { feedback.showShortcutModal = false }
                    }
                    .zIndex(150)

                VStack(spacing: 16) {
                    HStack {
                        Text("Global Dictation Shortcuts")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(MumblrTokens.primaryText)
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) { feedback.showShortcutModal = false }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(MumblrTokens.stoneGray.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 8) {
                        Button(action: {
                            state.activeShortcut = "opt_space"
                            feedback.showShortcutModal = false
                            feedback.show(message: "Shortcut set to Option + Space (⌥ Space)")
                        }) {
                            HStack {
                                Text("Option + Space (⌥ Space)")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                if state.activeShortcut == "opt_space" {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            .padding(12)
                            .background(state.activeShortcut == "opt_space" ? MumblrTokens.peachBg : MumblrTokens.cardBeige)
                            .foregroundColor(state.activeShortcut == "opt_space" ? MumblrTokens.peachText : MumblrTokens.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            state.activeShortcut = "ctrl_space"
                            feedback.showShortcutModal = false
                            feedback.show(message: "Shortcut set to Control + Space (⌃ Space)")
                        }) {
                            HStack {
                                Text("Control + Space (⌃ Space)")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                if state.activeShortcut == "ctrl_space" {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            .padding(12)
                            .background(state.activeShortcut == "ctrl_space" ? MumblrTokens.peachBg : MumblrTokens.cardBeige)
                            .foregroundColor(state.activeShortcut == "ctrl_space" ? MumblrTokens.peachText : MumblrTokens.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            state.activeShortcut = "hold_option"
                            feedback.showShortcutModal = false
                            feedback.show(message: "Shortcut set to Hold Option (Push-to-Talk)")
                        }) {
                            HStack {
                                Text("Hold Option Key (Push-to-Talk)")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                if state.activeShortcut == "hold_option" {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            .padding(12)
                            .background(state.activeShortcut == "hold_option" ? MumblrTokens.peachBg : MumblrTokens.cardBeige)
                            .foregroundColor(state.activeShortcut == "hold_option" ? MumblrTokens.peachText : MumblrTokens.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(22)
                .frame(width: 360)
                .background(MumblrTokens.pureWhite)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
                .zIndex(200)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MumblrSwitchTab"))) { notif in
            if let tab = notif.object as? MumblrTab {
                self.selectedTab = tab
            } else if let raw = notif.object as? String, let tab = MumblrTab(rawValue: raw) {
                self.selectedTab = tab
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("MumblrSwitchTab"))) { notif in
            if let raw = notif.object as? String, let tab = MumblrTab(rawValue: raw) {
                self.selectedTab = tab
            } else if let raw = notif.userInfo?["tab"] as? String, let tab = MumblrTab(rawValue: raw) {
                self.selectedTab = tab
            }
        }
    }
}

// MARK: - Left Sidebar Component
struct MumblrSidebarView: View {
    @Binding var selectedTab: MumblrTab
    @ObservedObject var feedback = StudioFeedbackManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Brand Mark: Mumblr
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(MumblrTokens.charcoalBadge)
                        .frame(width: 30, height: 30)
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                Text("Mumblr")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(MumblrTokens.primaryText)
                    .tracking(-0.3)
            }
            .padding(.horizontal, 8)
            .padding(.top, 42)

            // Navigation Tabs
            VStack(spacing: 4) {
                ForEach(MumblrTab.allCases) { tab in
                    Button(action: {
                        selectedTab = tab
                        NSSound(named: "Tink")?.play()
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                                .frame(width: 20)
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .bold : .semibold))
                                .tracking(-0.2)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(selectedTab == tab ? MumblrTokens.pureWhite : Color.clear)
                        .foregroundColor(selectedTab == tab ? MumblrTokens.primaryText : MumblrTokens.stoneGray)
                        .clipShape(Capsule())
                        .shadow(color: selectedTab == tab ? Color.black.opacity(0.04) : Color.clear, radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }

            Spacer()

            // USER PROFILE IN NAV (CLICKABLE ACCOUNT PROFILE MODAL)
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    feedback.showProfileModal.toggle()
                }
                NSSound(named: "Tink")?.play()
            }) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(MumblrTokens.charcoalBadge)
                            .frame(width: 32, height: 32)
                        Text("A")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aura")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(MumblrTokens.primaryText)
                        Text("Pro Plan • aura@mumblr.ai")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(MumblrTokens.stoneGray)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(MumblrTokens.stoneGray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(MumblrTokens.cardBeige)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(MumblrTokens.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusable(false)

            // WEB PORTAL ONLINE REDIRECT CARD
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Account & Billing")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MumblrTokens.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(MumblrTokens.stoneGray)
                }

                Text("Manage subscriptions, seat allocations and team sync online.")
                    .font(.system(size: 11))
                    .foregroundColor(MumblrTokens.stoneGray)
                    .lineLimit(2)

                Button(action: {
                    if let url = URL(string: "https://flow.mumblr.ai/account/billing") {
                        NSWorkspace.shared.open(url)
                    }
                    feedback.show(message: "Opening web billing portal...")
                }) {
                    HStack {
                        Spacer()
                        Text("Manage on Web →")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .background(MumblrTokens.pureWhite)
                    .foregroundColor(MumblrTokens.primaryText)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(14)
            .background(MumblrTokens.cardBeige)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            // Subnav Links
            VStack(spacing: 4) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("https://flow.mumblr.ai/join/team-aura", forType: .string)
                    NSSound(named: "Tink")?.play()
                    feedback.show(message: "Team invite link copied to clipboard!")
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.system(size: 12))
                        Text("Invite your team")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(MumblrTokens.stoneGray)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .focusable(false)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("https://flow.mumblr.ai/referral?code=MUMBLR-AURA", forType: .string)
                    NSSound(named: "Tink")?.play()
                    feedback.show(message: "Referral link copied! Share for 1 free month.")
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gift")
                            .font(.system(size: 12))
                        Text("Get a free month")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(MumblrTokens.stoneGray)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Center Pane: 1. Dictation Stream View
struct MumblrDictationStreamView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var feedback = StudioFeedbackManager.shared
    @Binding var selectedTab: MumblrTab

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Welcome back, Aura")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundColor(MumblrTokens.primaryText)

            // Hero Promo Banner
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: MumblrTokens.bannerRadius)
                    .fill(LinearGradient(colors: [MumblrTokens.charcoalBadge, Color(hex: "25252A")], startPoint: .topLeading, endPoint: .bottomTrailing))

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Voice dictation that types as fast as you think")
                            .font(.custom("Georgia", size: 27).italic())
                            .foregroundColor(.white)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Powered by Whisper Large v3 on Groq LPU with intelligent self-correction, list formatting, and companion mascots.")
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 480, alignment: .leading)

                        HStack(spacing: 12) {
                            Button(action: {
                                HotkeyManager.shared.toggleRecording()
                                if state.isRecording {
                                    feedback.show(message: "Recording started. Speak naturally...")
                                } else {
                                    feedback.show(message: "Recording stopped. Transcribing...")
                                }
                            }) {
                                HStack(spacing: 6) {
                                    if state.isRecording {
                                        Circle()
                                            .fill(Color(hex: "FF5F56"))
                                            .frame(width: 8, height: 8)
                                        Text("Stop Dictating")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "mic")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(MumblrTokens.primaryText)
                                        Text("Dictate (⌥ Space)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(MumblrTokens.primaryText)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(state.isRecording ? Color(hex: "121214") : MumblrTokens.porcelainSurface)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(state.isRecording ? Color(hex: "FF5F56") : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .focusable(false)

                            Button(action: {
                                selectedTab = .settings
                                feedback.show(message: "Configure global keyboard shortcuts")
                            }) {
                                Text("Global Shortcuts")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(MumblrTokens.peachBg)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                        .padding(.top, 4)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        MumblrIconOrb(systemName: "waveform", label: "Audio Stream Active")
                        MumblrIconOrb(systemName: "message", label: "Slack Context Ready")
                        MumblrIconOrb(systemName: "doc.text", label: "Notion Docs Linked")
                        MumblrIconOrb(systemName: "terminal", label: "Terminal CLI Ready")
                    }
                }
                .padding(26)
            }
            .frame(minHeight: 165)

            // Timeline Header
            HStack {
                Text("RECENT TRANSCRIPTIONS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(MumblrTokens.stoneGray)
                Spacer()
                Button(action: {
                    feedback.show(message: "Showing all recent transcriptions (Filter: All Apps)")
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(MumblrTokens.stoneGray)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            // History Card 1
            MumblrHistoryCard(
                time: "5:11 PM",
                contextApp: "Slack",
                text: "It just randomly does rubbish and the sound is, I'm still hearing background noise, I don't know if it's from conduit or if it's from, or if it's actually from us, Vozia.",
                pillLabel: "Groq LPU 1.4s",
                pillBg: MumblrTokens.blueBg,
                pillText: MumblrTokens.blueText
            )

            // History Card 2
            MumblrHistoryCard(
                time: "8:25 PM",
                contextApp: "Notes",
                text: "Test 1: Here are three tasks for today:\n1. Review the pull request on GitHub.\n2. Send the updated invoice to the client.\n3. Prepare the slide deck for this afternoon.\n\nTest 2: How far back? The basic plan is around 2,000. The pro tier is 4K. Let me know if you want me to activate your account. We can schedule this call for 3 PM instead. I have another appointment in the morning.",
                pillLabel: "Phonetic Healing: 2 terms",
                pillBg: MumblrTokens.lilacBg,
                pillText: MumblrTokens.lilacText
            )
        }
    }
}

// MARK: - App Icon Orb
struct MumblrIconOrb: View {
    let systemName: String
    var label: String = ""
    @ObservedObject var feedback = StudioFeedbackManager.shared

    var body: some View {
        Button(action: {
            if !label.isEmpty {
                feedback.show(message: label)
            }
            NSSound(named: "Tink")?.play()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.2), lineWidth: 1))
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Card Component with Anchor Badge
struct MumblrHistoryCard: View {
    let time: String
    let contextApp: String
    let text: String
    let pillLabel: String
    let pillBg: Color
    let pillText: Color
    @ObservedObject var feedback = StudioFeedbackManager.shared
    @ObservedObject var audio = StudioAudioManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle()
                        .fill(MumblrTokens.charcoalBadge)
                        .frame(width: 22, height: 22)
                    Image(systemName: "mic")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text("\(time) • Cursor Context: \(contextApp)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MumblrTokens.stoneGray)

                Spacer()

                Text(pillLabel)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(pillBg)
                    .foregroundColor(pillText)
                    .clipShape(Capsule())
            }

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundColor(MumblrTokens.primaryText)

            HStack(spacing: 8) {
                // 1. Play Audio Button
                Button(action: {
                    audio.toggleSpeaking(text: text)
                    if audio.isSpeaking && audio.activeSpeakingText == text {
                        feedback.show(message: "Playing transcription audio...")
                    } else {
                        feedback.show(message: "Audio playback stopped.")
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: (audio.isSpeaking && audio.activeSpeakingText == text) ? "stop.fill" : "play.fill")
                            .font(.system(size: 9))
                        Text((audio.isSpeaking && audio.activeSpeakingText == text) ? "Stop Audio" : "Play Audio")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(MumblrTokens.pureWhite)
                    .foregroundColor(MumblrTokens.primaryText)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .focusable(false)

                // 2. Copy Button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    NSSound(named: "Tink")?.play()
                    feedback.show(message: "Transcription copied to clipboard!")
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(MumblrTokens.pureWhite)
                    .foregroundColor(MumblrTokens.primaryText)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .focusable(false)

                // 3. Transform Button
                Button(action: {
                    let polished = transformSmartPolishText(text)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(polished, forType: .string)
                    NSSound(named: "Glass")?.play()
                    feedback.show(message: "Transformed & copied polished text!")
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                        Text("Transform")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(MumblrTokens.pureWhite)
                    .foregroundColor(MumblrTokens.primaryText)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(20)
        .background(MumblrTokens.cardBeige)
        .clipShape(RoundedRectangle(cornerRadius: MumblrTokens.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MumblrTokens.cardRadius)
                .stroke(MumblrTokens.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Center Pane: 2. Dictionary View
struct MumblrDictionaryView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var feedback = StudioFeedbackManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Phonetic Healing & Custom Vocabulary")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(MumblrTokens.primaryText)

            Text("Teach Mumblr your custom technical jargon, company names, and colloquial terms to prevent Whisper acoustic slips.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(MumblrTokens.stoneGray)

            MumblrCardContainer(title: "Custom Vocabulary Glossaries", icon: "book") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Comma-separated glossary terms injected into Whisper's priming prompt:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MumblrTokens.stoneGray)

                    TextField("e.g. GitHub, PR, Vozia, Vercel, LiveKit, Conduit", text: $state.customVocab, prompt: Text("e.g. GitHub, PR, Vozia, Vercel, LiveKit, Conduit").foregroundColor(MumblrTokens.stoneGray))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(MumblrTokens.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(MumblrTokens.pureWhite)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    HStack {
                        Spacer()
                        Button(action: {
                            state.saveConfigToDisk()
                            NSSound(named: "Tink")?.play()
                            feedback.show(message: "Custom vocabulary glossary saved!")
                        }) {
                            Text("Save Glossary")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(MumblrTokens.charcoalBadge)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }

            MumblrCardContainer(title: "Active Phonetic Acoustic Replacements", icon: "waveform.path.badge.plus") {
                VStack(alignment: .leading, spacing: 10) {
                    MumblrPhoneticRow(misheard: "it for sale", corrected: "Vercel")
                    MumblrPhoneticRow(misheard: "light kit", corrected: "LiveKit")
                    MumblrPhoneticRow(misheard: "auto-deflect", corrected: "auto-detect")
                    MumblrPhoneticRow(misheard: "country documentation", corrected: "Conduit documentation")
                    MumblrPhoneticRow(misheard: "how far abeg", corrected: "How far, abeg (Colloquial preserved)")
                }
            }
        }
    }
}

struct MumblrPhoneticRow: View {
    let misheard: String
    let corrected: String
    @ObservedObject var feedback = StudioFeedbackManager.shared

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(corrected, forType: .string)
            NSSound(named: "Tink")?.play()
            feedback.show(message: "Copied \"\(corrected)\" to clipboard!")
        }) {
            HStack {
                Text("“\(misheard)”")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MumblrTokens.stoneGray)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MumblrTokens.stoneGray)
                Text(corrected)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MumblrTokens.primaryText)
                Spacer()
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(MumblrTokens.stoneGray.opacity(0.6))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.black.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Center Pane: 3. Companion & Flow View
struct MumblrCompanionView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var feedback = StudioFeedbackManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Companion & Flow Focus State")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(MumblrTokens.primaryText)

            Text("Customize your interactive desktop desk pet (GearBot, Neko, Luna, Kuro) and run Pomodoro deep-work focus sessions.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(MumblrTokens.stoneGray)

            MumblrCardContainer(title: "Interactive Desktop Pet", icon: "pawprint") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        MumblrPetSelectionTile(name: "GearBot", icon: "gearshape.2", active: state.hudCharacter == "gearbot") {
                            state.hudCharacter = "gearbot"
                            NSSound(named: "Tink")?.play()
                            feedback.show(message: "GearBot selected as desktop companion!")
                        }
                        MumblrPetSelectionTile(name: "Neko", icon: "cat", active: state.hudCharacter == "neko") {
                            state.hudCharacter = "neko"
                            NSSound(named: "Tink")?.play()
                            feedback.show(message: "Neko selected as desktop companion!")
                        }
                        MumblrPetSelectionTile(name: "Luna", icon: "moon.stars", active: state.hudCharacter == "luna") {
                            state.hudCharacter = "luna"
                            NSSound(named: "Tink")?.play()
                            feedback.show(message: "Luna selected as desktop companion!")
                        }
                        MumblrPetSelectionTile(name: "Kuro", icon: "sparkles", active: state.hudCharacter == "kuro") {
                            state.hudCharacter = "kuro"
                            NSSound(named: "Tink")?.play()
                            feedback.show(message: "Kuro selected as desktop companion!")
                        }
                    }

                    Toggle("Always show floating desk pet companion", isOn: $state.alwaysShowCompanion)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MumblrTokens.primaryText)
                        .onChange(of: state.alwaysShowCompanion) { _, enabled in
                            if enabled {
                                FloatingHUDController.shared.show()
                                feedback.show(message: "Floating desk pet HUD visible")
                            } else {
                                FloatingHUDController.shared.hide()
                                feedback.show(message: "Floating desk pet HUD hidden")
                            }
                        }
                }
            }

            MumblrCardContainer(title: "Flow Focus Mode Timer", icon: "timer") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(state.flowTimeString)
                            .font(.custom("Georgia", size: 36).italic())
                            .foregroundColor(MumblrTokens.primaryText)
                        Spacer()
                        Button(action: {
                            if state.isFlowActive {
                                state.stopFlow()
                                feedback.show(message: "Focus session stopped.")
                            } else {
                                state.startFlow(minutes: 25)
                                feedback.show(message: "Focus session started for 25 minutes!")
                            }
                        }) {
                            Text(state.isFlowActive ? "Stop Focus Session" : "Start 25m Focus")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(MumblrTokens.charcoalBadge)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }
        }
    }
}

struct MumblrPetSelectionTile: View {
    let name: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(active ? MumblrTokens.charcoalBadge : MumblrTokens.pureWhite)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(active ? .white : MumblrTokens.primaryText)
                }
                Text(name)
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(active ? MumblrTokens.peachBg : MumblrTokens.cardBeige)
            .foregroundColor(active ? MumblrTokens.peachText : MumblrTokens.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(active ? MumblrTokens.peachText : Color.black.opacity(0.06), lineWidth: active ? 1.5 : 1)
            )
            .shadow(color: Color.black.opacity(active ? 0.04 : 0.02), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Center Pane: 4. Insights View
struct MumblrInsightsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Voice Intelligence & Insights")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(MumblrTokens.primaryText)

            Text("Detailed telemetry of your spoken output, dictation velocity, and acoustic profile.")
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(MumblrTokens.stoneGray)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                MumblrInsightMetricBox(title: "Total Spoken Words", val: "40,920", sub: "+12% this week", tint: MumblrTokens.peachBg, tintText: MumblrTokens.peachText)
                MumblrInsightMetricBox(title: "Average Dictation Velocity", val: "132 WPM", sub: "3.2x faster than typing", tint: MumblrTokens.blueBg, tintText: MumblrTokens.blueText)
                MumblrInsightMetricBox(title: "Focus Dictation Streak", val: "3 Weeks", sub: "Active since Sept 2026", tint: MumblrTokens.lilacBg, tintText: MumblrTokens.lilacText)
                MumblrInsightMetricBox(title: "Estimated Time Saved", val: "14.2 Hours", sub: "Based on 40 WPM baseline", tint: MumblrTokens.salmonBg, tintText: MumblrTokens.salmonText)
            }
        }
    }
}

struct MumblrInsightMetricBox: View {
    let title: String
    let val: String
    let sub: String
    let tint: Color
    let tintText: Color
    @ObservedObject var feedback = StudioFeedbackManager.shared

    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(title): \(val) (\(sub))", forType: .string)
            NSSound(named: "Tink")?.play()
            feedback.show(message: "Copied \"\(title)\" metric to clipboard!")
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MumblrTokens.stoneGray)
                Text(val)
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(MumblrTokens.primaryText)
                Text(sub)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint)
                    .foregroundColor(tintText)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(MumblrTokens.cardBeige)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Center Pane: 5. Desktop Preferences View
struct MumblrSettingsView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var feedback = StudioFeedbackManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Desktop Preferences")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(MumblrTokens.primaryText)
                Spacer()
                Text("Mumblr v2.4")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MumblrTokens.peachBg)
                    .foregroundColor(MumblrTokens.peachText)
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                // Card 1: Dictation & STT Engine
                MumblrCardContainer(title: "Speech & STT Engine", icon: "mic") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Input Microphone:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(MumblrTokens.primaryText)

                            Menu {
                                Button("System Default") {
                                    state.selectedMicName = "System Default"
                                    feedback.show(message: "Selected System Default Microphone")
                                }
                                ForEach(state.availableMicDevices, id: \.name) { dev in
                                    Button(dev.name) {
                                        state.selectedMicName = dev.name
                                        feedback.show(message: "Selected \(dev.name)")
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(state.selectedMicName.isEmpty ? "System Default" : state.selectedMicName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(MumblrTokens.primaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(MumblrTokens.stoneGray)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(MumblrTokens.pureWhite)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .focusable(false)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Speech-to-Text Engine:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(MumblrTokens.primaryText)

                            Menu {
                                Button("Groq Cloud LPU (~1.2s Whisper Large v3)") {
                                    state.sttEngine = "groq"
                                    feedback.show(message: "Engine set to Groq Cloud LPU Whisper Large v3")
                                }
                                Button("Apple Silicon Metal (Offline Local MLX)") {
                                    state.sttEngine = "local_mlx"
                                    feedback.show(message: "Engine set to Local Metal Offline Whisper")
                                }
                            } label: {
                                HStack {
                                    Text(state.sttEngine == "groq" ? "Groq Cloud LPU (~1.2s Whisper Large v3)" : "Apple Silicon Metal (Offline Local MLX)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(MumblrTokens.primaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(MumblrTokens.stoneGray)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(MumblrTokens.pureWhite)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .focusable(false)
                        }

                        Toggle("Hold-to-Talk (Push-to-Talk)", isOn: $state.isHoldToTalk)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MumblrTokens.primaryText)
                            .onChange(of: state.isHoldToTalk) { _, val in
                                feedback.show(message: val ? "Hold-to-Talk mode enabled" : "Toggle key mode enabled")
                            }
                    }
                }

                // Card 2: Formatting & LLM
                MumblrCardContainer(title: "LLM Polish & Rules", icon: "sparkles") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("LLM Smart Polish Engine", isOn: $state.useLlmPolish)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MumblrTokens.primaryText)
                        Toggle("Strip Verbal Fillers (\"um\", \"uh\")", isOn: $state.stripFillers)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MumblrTokens.primaryText)
                        Toggle("Auto-Format Numbered Lists", isOn: $state.autoFormatLists)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MumblrTokens.primaryText)
                        Toggle("Self-Correction Healing", isOn: $state.selfCorrectionHealing)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MumblrTokens.primaryText)
                    }
                }

                // Card 3: Global Hotkeys
                MumblrCardContainer(title: "Keyboard Shortcuts", icon: "command") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Global Dictation Toggle:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MumblrTokens.stoneGray)
                            Spacer()
                            Button(action: {
                                feedback.showShortcutModal = true
                            }) {
                                Text("⌥ Space (Alt+D)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(MumblrTokens.primaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(MumblrTokens.pureWhite)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Text("Hold-to-Talk Key:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(MumblrTokens.stoneGray)
                            Spacer()
                            Button(action: {
                                feedback.showShortcutModal = true
                            }) {
                                Text("Hold ⌥")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(MumblrTokens.primaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(MumblrTokens.pureWhite)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Card 4: BYOK & Cloud Keys
                MumblrCardContainer(title: "API Keys & BYOK", icon: "key") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Custom Groq API Key (Optional):")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(MumblrTokens.stoneGray)

                        SecureField("gsk_...", text: $state.groqKey, prompt: Text("gsk_...").foregroundColor(MumblrTokens.stoneGray))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(MumblrTokens.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(MumblrTokens.pureWhite)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )

                        Button(action: {
                            state.saveConfigToDisk()
                            NSSound(named: "Tink")?.play()
                            feedback.show(message: "Custom Groq API Key saved successfully!")
                        }) {
                            Text("Save Key")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(MumblrTokens.charcoalBadge)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }
        }
    }
}

// MARK: - Right Column: Analytics & Quota
struct MumblrRightAnalyticsView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var feedback = StudioFeedbackManager.shared
    @Binding var selectedTab: MumblrTab

    var body: some View {
        VStack(spacing: 20) {
            // KPI Tiles in Pastel Palette (Clickable to jump to insights)
            VStack(spacing: 12) {
                MumblrPastelStatPill(
                    number: "40.9K",
                    label: "total words spoken",
                    icon: "bubble.left",
                    bg: MumblrTokens.peachBg,
                    text: MumblrTokens.peachText,
                    action: {
                        selectedTab = .insights
                        feedback.show(message: "Viewing Total Spoken Words telemetry")
                    }
                )

                MumblrPastelStatPill(
                    number: "132",
                    label: "average wpm",
                    icon: "bolt",
                    bg: MumblrTokens.blueBg,
                    text: MumblrTokens.blueText,
                    action: {
                        selectedTab = .insights
                        feedback.show(message: "Viewing Dictation Velocity metrics")
                    }
                )

                MumblrPastelStatPill(
                    number: "3 weeks",
                    label: "streak record",
                    icon: "flame",
                    bg: MumblrTokens.lilacBg,
                    text: MumblrTokens.lilacText,
                    action: {
                        selectedTab = .insights
                        feedback.show(message: "Viewing Focus Streak record")
                    }
                )
            }

            // Quota Alert Card (Salmon Coral)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("2,000 words left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MumblrTokens.salmonText)
                    Spacer()
                    Button(action: {
                        feedback.show(message: "Free tier refreshes weekly. Upgrade for unlimited dictation.")
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(MumblrTokens.salmonText)
                    }
                    .buttonStyle(.plain)
                }

                Text("You're close to your weekly dictation limit. Upgrade for unlimited access and full cloud Whisper Large v3 models.")
                    .font(.system(size: 11))
                    .foregroundColor(MumblrTokens.salmonText.opacity(0.9))
                    .lineSpacing(2)

                Button(action: {
                    if let url = URL(string: "https://flow.mumblr.ai/account/billing") {
                        NSWorkspace.shared.open(url)
                    }
                    feedback.show(message: "Opening checkout portal...")
                }) {
                    HStack {
                        Spacer()
                        Text("Upgrade to Pro")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(MumblrTokens.charcoalBadge)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(16)
            .background(MumblrTokens.salmonBg)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Voice Profile Box (Clickable for details)
            Button(action: {
                feedback.show(message: "Acoustic fingerprint tuning: 94% accuracy on MacBook Air.")
                NSSound(named: "Tink")?.play()
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Voice Profile")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(MumblrTokens.primaryText)

                    Text("Acoustic fingerprint tuning")
                        .font(.system(size: 11))
                        .foregroundColor(MumblrTokens.stoneGray)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(MumblrTokens.orchidBg)
                            .frame(height: 8)
                        Capsule()
                            .fill(MumblrTokens.orchidText)
                            .frame(width: 140, height: 8)
                    }
                    .padding(.top, 4)

                    Text("Updates in 752 words")
                        .font(.system(size: 10))
                        .foregroundColor(MumblrTokens.stoneGray)
                }
                .padding(18)
                .background(MumblrTokens.cardBeige)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(MumblrTokens.cardBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(20)
    }
}

struct MumblrPastelStatPill: View {
    let number: String
    let label: String
    let icon: String
    let bg: Color
    let text: Color
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(number)
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.5)
                        .foregroundColor(text)
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(text.opacity(0.85))
                }
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(text)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Card Container with Anchor Badge
struct MumblrCardContainer<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(MumblrTokens.charcoalBadge)
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.2)
                    .foregroundColor(MumblrTokens.primaryText)
            }

            content
        }
        .padding(20)
        .background(MumblrTokens.cardBeige)
        .clipShape(RoundedRectangle(cornerRadius: MumblrTokens.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MumblrTokens.cardRadius)
                .stroke(MumblrTokens.cardBorder, lineWidth: 1)
        )
    }
}
