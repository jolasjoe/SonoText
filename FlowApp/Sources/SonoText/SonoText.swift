import SwiftUI
import AppKit
import KeyboardShortcuts
import os.log

let logger = Logger(subsystem: "com.sonotext.mac", category: "SonoText")

@main
struct SonoText: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Keyable Panel

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - App State

enum FlowStatus {
    case idle
    case listening
    case processing
    case error(String)
}

enum OnboardingStep {
    case downloading
    case ready
    case done
}

class AppState: ObservableObject {
    @Published var status: FlowStatus = .idle
    @Published var onboardingStep: OnboardingStep
    
    init() {
        self.onboardingStep = UserDefaults.standard.bool(forKey: "onboarding_complete") ? .done : .downloading
    }
    
    var isOnboardingComplete: Bool { onboardingStep == .done }
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_complete")
        UserDefaults.standard.synchronize()
        onboardingStep = .done
        logger.notice("🟢 Onboarding marked complete")
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var whisperService: LocalWhisperService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                Text("SonoText Setup")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Divider()
            
            if appState.onboardingStep == .downloading {
                downloadingView
            } else {
                readyView
            }
        }
        .padding(18)
        .frame(minWidth: 280, maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: appState.onboardingStep) { step in
            if step == .done {
                // Notify panel to resize to widget size
                NotificationCenter.default.post(name: .sonotextOnboardingComplete, object: nil)
            }
        }
    }
    
    var downloadingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            checklistRow(icon: "arrow.down.circle", label: "Download Speech Model", done: false, active: true)
            checklistRow(icon: "checkmark.seal.fill", label: "All Set — Start Dictating!", done: false, active: false)
            
            Divider()
            
            Text(whisperService.statusMessage)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            ProgressView(value: whisperService.downloadProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(height: 5)
        }
    }
    
    var readyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            checklistRow(icon: "arrow.down.circle", label: "Download Speech Model", done: true, active: false)
            checklistRow(icon: "checkmark.seal.fill", label: "All Set — Ready to dictate!", done: true, active: true)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("🎉 You're all set!")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                Text("Double-tap Control (⌃⌃) to start/stop dictation.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Spacer()
                Button(action: { appState.completeOnboarding() }) {
                    Text("Get Started")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    func checklistRow(icon: String, label: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .font(.system(size: 13))
                .foregroundColor(done ? .green : (active ? .blue : .secondary))
            Text(label)
                .font(.system(size: 12, weight: active ? .semibold : .regular, design: .rounded))
                .foregroundColor(done ? .green.opacity(0.9) : (active ? .primary : .secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Waveform Bar View

struct WaveformBarsView: View {
    let level: Float   // 0..1
    private let barCount = 18
    // Pre-computed phase seeds so each bar has a stable independent offset
    private let phases: [Float] = (0..<18).map { Float($0) / 18.0 * Float.pi * 2 }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = Float(timeline.date.timeIntervalSinceReferenceDate)
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = barHeight(index: i, t: t)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.red.opacity(0.85))
                        .frame(width: 2.5, height: h)
                }
            }
            .frame(height: 20)
        }
    }
    
    private func barHeight(index: Int, t: Float) -> CGFloat {
        guard level > 0.01 else { return 3 }   // flat when silent
        let wave = sin(t * 10 + phases[index])  // fast oscillation per bar
        let h = CGFloat(level) * (12 + CGFloat(wave) * 6)
        return max(3, h)
    }
}

// MARK: - Floating Widget View

struct FloatingWidgetView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var audioRecorder: AudioRecorder
    var onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            statusDot
            if case .listening = appState.status {
                WaveformBarsView(level: audioRecorder.audioLevel)
                    .frame(maxWidth: 80)
            } else {
                statusLabel
            }
            Spacer(minLength: 4)
            closeButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        // When engine finishes warming up, clear any "Warming up" error status
        .onReceive(audioRecorder.$isRecording) { _ in }
    }
    
    var borderColor: Color {
        switch appState.status {
        case .listening: return .red.opacity(0.7)
        case .processing: return .blue.opacity(0.5)
        case .error:     return .orange.opacity(0.7)
        default:         return .white.opacity(0.25)
        }
    }
    
    @ViewBuilder
    var statusDot: some View {
        switch appState.status {
        case .listening:
            Circle().fill(Color.red).frame(width: 9, height: 9)
                .scaleEffect(1.2)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: UUID())
        case .processing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                .scaleEffect(0.55).frame(width: 9, height: 9)
        case .error:
            Circle().fill(Color.orange).frame(width: 9, height: 9)
        default:
            Circle().fill(Color.green).frame(width: 9, height: 9)
        }
    }
    
    @ViewBuilder
    var statusLabel: some View {
        switch appState.status {
        case .idle:
            Text("SonoText  ⌃⌃")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
        case .listening:
            Text("Listening...")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.red)
        case .processing:
            Text("Processing...")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.blue.opacity(0.9))
        case .error(let msg):
            Text(msg)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.orange)
                .lineLimit(2)
        }
    }
    
    var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main Panel Root View

struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var whisperService: LocalWhisperService
    @ObservedObject var audioRecorder: AudioRecorder
    var onClose: () -> Void
    
    var body: some View {
        if appState.isOnboardingComplete {
            FloatingWidgetView(appState: appState, audioRecorder: audioRecorder, onClose: onClose)
        } else {
            OnboardingView(appState: appState, whisperService: whisperService)
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let sonotextOnboardingComplete = Notification.Name("sonotextOnboardingComplete")
}

// MARK: - Double-Tap Control Monitor

class DoubleTapControlMonitor {
    private var lastControlTapTime: Date?
    private var eventMonitor: Any?
    private let threshold: TimeInterval = 0.4
    var onDoubleTap: (() -> Void)?
    
    func start() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            let otherModifiers: NSEvent.ModifierFlags = [.command, .shift, .option]
            guard !event.modifierFlags.contains(otherModifiers) else { return }
            guard event.modifierFlags.contains(.control) else { return }
            
            let now = Date()
            if let last = self.lastControlTapTime, now.timeIntervalSince(last) < self.threshold {
                self.lastControlTapTime = nil
                logger.notice("🟢 Double-tap ⌃ detected")
                DispatchQueue.main.async { self.onDoubleTap?() }
            } else {
                self.lastControlTapTime = now
            }
        }
        logger.notice("🟢 Double-tap Control monitor started")
    }
    
    func stop() {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        eventMonitor = nil
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var floatingPanel: NSPanel?
    let appState = AppState()
    let whisperService = LocalWhisperService.shared
    let audioRecorder = AudioRecorder()
    let doubleTapMonitor = DoubleTapControlMonitor()
    private var capturedContext: String = ""
    private var previousApp: NSRunningApplication?
    
    // Panel sizes
    private let onboardingSize = NSSize(width: 316, height: 290)
    private let widgetSize     = NSSize(width: 280, height: 44)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "SonoText")
        
        setupFloatingPanel()
        constructMenu()
        
        doubleTapMonitor.onDoubleTap = { [weak self] in self?.toggleRecording() }
        doubleTapMonitor.start()
        
        // Listen for onboarding completion to resize panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onboardingDidComplete),
            name: .sonotextOnboardingComplete,
            object: nil
        )
        
        // Warm up WhisperKit in background (always needed on launch to load model into RAM)
        Task {
            await whisperService.downloadAndInitialize()
            await MainActor.run {
                if self.whisperService.isModelReady {
                    if !self.appState.isOnboardingComplete {
                        self.appState.onboardingStep = .ready
                    }
                    // Reset any "Warming up" error status now that engine is ready
                    if case .error = self.appState.status {
                        self.appState.status = .idle
                    }
                }
            }
        }
        
        logger.notice("🟢 SonoText launched. Onboarding complete: \(self.appState.isOnboardingComplete)")
    }
    
    func setupFloatingPanel() {
        let initialSize = appState.isOnboardingComplete ? widgetSize : onboardingSize
        
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        
        let root = MainPanelView(appState: appState, whisperService: whisperService, audioRecorder: audioRecorder) {
            panel.orderOut(nil)
        }
        let hc = NSHostingController(rootView: root)
        hc.view.layer?.backgroundColor = .clear
        panel.contentViewController = hc
        
        positionPanel(panel, size: initialSize)
        panel.orderFrontRegardless()
        self.floatingPanel = panel
    }
    
    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.maxX - size.width - 16
        let y = screen.visibleFrame.minY + 16
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
    
    @objc private func onboardingDidComplete() {
        guard let panel = floatingPanel else { return }
        // Animate resize to compact widget
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - widgetSize.width - 16
                let y = screen.visibleFrame.minY + 16
                panel.animator().setFrame(NSRect(x: x, y: y, width: widgetSize.width, height: widgetSize.height), display: true)
            }
        }
    }
    
    @objc func showWidget() {
        floatingPanel?.orderFrontRegardless()
    }
    
    @objc func toggleRecording() {
        guard whisperService.isModelReady else {
            // Silently ignore — engine is loading
            NSSound(named: "Basso")?.play()
            logger.notice("\"⏳ Engine still loading, ignoring double-tap\"")
            return
        }
        guard appState.isOnboardingComplete else { return }

        if !audioRecorder.isRecording {
            NSSound(named: "Pop")?.play()
            previousApp = NSWorkspace.shared.frontmostApplication
            let prevName = previousApp?.localizedName ?? "none"
            logger.notice("🟢 Starting recording. Previous app: \(prevName, privacy: .public)")
            appState.status = .listening
            capturedContext = KeystrokeSynthesizer.shared.copySelectedText() ?? ""
        } else {
            NSSound(named: "Glass")?.play()
            logger.notice("🟢 Stopping recording")
            appState.status = .processing
        }
        
        audioRecorder.toggleRecording { [weak self] url in
            guard let self, let fileURL = url else { return }
            logger.notice("🟢 Recording saved: \(fileURL.lastPathComponent, privacy: .public)")
            self.processAudio(fileURL: fileURL)
        }
        
        updateUIIcon()
    }
    
    private func updateUIIcon() {
        guard let btn = statusItem?.button else { return }
        btn.image = NSImage(systemSymbolName: audioRecorder.isRecording ? "record.circle.fill" : "waveform.circle", accessibilityDescription: "SonoText")
        btn.contentTintColor = audioRecorder.isRecording ? .systemRed : nil
    }
    
    private func processAudio(fileURL: URL) {
        let targetApp = previousApp
        Task {
            do {
                let text = try await whisperService.transcribe(audioURL: fileURL)
                logger.notice("🟢 Transcription result: \(text, privacy: .public)")
                
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    logger.notice("🟢 Empty transcription, skipping paste")
                    await MainActor.run { self.appState.status = .idle }
                    return
                }
                
                // 1. Put text on pasteboard
                await MainActor.run {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(trimmed, forType: .string)
                    logger.notice("🟢 Text placed on pasteboard")
                }
                
                // 2. Re-activate the previous app
                var targetPid: pid_t = 0
                if let app = targetApp {
                    targetPid = app.processIdentifier
                    logger.notice("🟢 Activating: \(app.localizedName ?? "?", privacy: .public) PID=\(targetPid, privacy: .public)")
                    await MainActor.run {
                        app.activate(options: .activateIgnoringOtherApps)
                    }
                    // Poll until the app is frontmost (up to 1.5s)
                    for _ in 0..<30 {
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                        if app.isActive { break }
                    }
                    logger.notice("🟢 Target app isActive: \(app.isActive, privacy: .public)")
                }
                
                // 3. Extra settle time for the window focus
                try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
                
                // 4. Paste using AppleScript (most reliable cross-app method)
                await MainActor.run {
                    self.pasteViaAppleScript()
                    self.appState.status = .idle
                }
                
            } catch {
                logger.error("🔴 \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self.appState.status = .error(error.localizedDescription) }
            }
        }
    }
    
    private func pasteViaAppleScript() {
        // AppleScript "keystroke v using command down" is the most reliable way
        // to paste into the frontmost application on macOS
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        var errorDict: NSDictionary?
        script?.executeAndReturnError(&errorDict)
        if let err = errorDict {
            logger.error("🔴 AppleScript paste error: \(err, privacy: .public)")
            // Fallback to CGEvent
            simulatePasteCGEvent()
        } else {
            logger.notice("🟢 Paste sent via AppleScript")
        }
    }
    
    private func simulatePasteCGEvent() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        logger.notice("🟢 Paste sent via CGEvent fallback")
    }
    
    func constructMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Widget", action: #selector(showWidget), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toggle Dictation (⌃⌃)", action: #selector(toggleRecording), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SonoText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
}
