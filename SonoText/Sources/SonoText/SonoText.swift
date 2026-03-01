import SwiftUI
import AppKit
import AVFoundation

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
    @Published var isMicrophoneGranted: Bool
    @Published var isAccessibilityGranted: Bool
    @Published var isInputMonitoringGranted: Bool
    
    init() {
        self.onboardingStep = UserDefaults.standard.bool(forKey: "onboarding_complete") ? .done : .downloading
        self.isMicrophoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        self.isAccessibilityGranted = KeystrokeSynthesizer.shared.isAccessibilityGranted
        self.isInputMonitoringGranted = CGPreflightListenEventAccess()
    }
    
    var isOnboardingComplete: Bool { onboardingStep == .done }
    var hasAllRequiredPermissions: Bool {
        isMicrophoneGranted && isAccessibilityGranted && isInputMonitoringGranted
    }
    var shouldShowSetup: Bool {
        !isOnboardingComplete || !hasAllRequiredPermissions
    }
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_complete")
        onboardingStep = .done
        logger.notice("🟢 Onboarding marked complete")
    }
    
    func refreshPermissions() {
        isMicrophoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        isAccessibilityGranted = KeystrokeSynthesizer.shared.isAccessibilityGranted
        isInputMonitoringGranted = CGPreflightListenEventAccess()
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var whisperService: LocalWhisperService
    private let permissionPollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
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
        .onChange(of: appState.onboardingStep) { _, step in
            if step == .done {
                // Notify panel to resize to widget size
                NotificationCenter.default.post(name: .sonotextOnboardingComplete, object: nil)
            }
        }
        .onAppear { appState.refreshPermissions() }
        .onReceive(permissionPollTimer) { _ in appState.refreshPermissions() }
    }
    
    var downloadingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            checklistRow(icon: "arrow.down.circle", label: "Download Speech Model", done: false, active: true)
            checklistRow(icon: "checkmark.seal.fill", label: "Grant required permissions", done: appState.hasAllRequiredPermissions, active: !appState.hasAllRequiredPermissions)
            
            Divider()
            requiredPermissionsSection
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
            checklistRow(icon: "checkmark.seal.fill", label: "Grant required permissions", done: appState.hasAllRequiredPermissions, active: !appState.hasAllRequiredPermissions)
            
            Divider()
            requiredPermissionsSection
            Divider()
            
            VStack(alignment: .leading, spacing: 4) {
                Text("🎉 You're all set!")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                Text(appState.hasAllRequiredPermissions
                     ? "Hold right Option (⌥) to dictate. You can switch to double-tap in the menu."
                     : "Grant all required permissions to enable dictation and paste into other apps.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Spacer()
                Button(action: { appState.completeOnboarding() }) {
                    Text("Get Started")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(appState.hasAllRequiredPermissions ? .black : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(appState.hasAllRequiredPermissions ? Color.green : Color.gray.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(!appState.hasAllRequiredPermissions)
            }
        }
    }
    
    var requiredPermissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Required Permissions")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            
            permissionRow(
                title: "Microphone",
                subtitle: "Capture your voice for dictation.",
                granted: appState.isMicrophoneGranted,
                action: requestMicrophonePermission
            )
            
            permissionRow(
                title: "Accessibility",
                subtitle: "Paste text into whichever app you were using.",
                granted: appState.isAccessibilityGranted,
                action: requestAccessibilityPermission
            )
            
            permissionRow(
                title: "Input Monitoring",
                subtitle: "Detect global right Option hotkey presses.",
                granted: appState.isInputMonitoringGranted,
                actionTitle: "Open Settings",
                action: requestInputMonitoringPermission
            )
            
            if !appState.isInputMonitoringGranted {
                Text("Needed for global right Option hotkey detection. You may need to re-open the app after granting.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    func permissionRow(title: String, subtitle: String, granted: Bool, actionTitle: String = "Grant", action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(granted ? .green : .orange)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if granted {
                Text("Granted")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
            } else {
                Button(actionTitle) { action() }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
            }
        }
    }
    
    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async {
                appState.refreshPermissions()
            }
        }
    }
    
    private func requestAccessibilityPermission() {
        KeystrokeSynthesizer.shared.requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            appState.refreshPermissions()
        }
    }
    
    private func requestInputMonitoringPermission() {
        _ = CGRequestListenEventAccess()
        openPrivacySettings(anchor: "ListenEvent")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            appState.refreshPermissions()
        }
    }
    
    private func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(anchor)") else { return }
        NSWorkspace.shared.open(url)
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
    @AppStorage("dictation_trigger_mode") private var triggerMode = "pushToTalk"
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
            Text(triggerMode == "toggle" ? "SonoText  double-tap right ⌥" : "SonoText  hold right ⌥")
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
        if appState.shouldShowSetup {
            OnboardingView(appState: appState, whisperService: whisperService)
        } else {
            FloatingWidgetView(appState: appState, audioRecorder: audioRecorder, onClose: onClose)
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let sonotextOnboardingComplete = Notification.Name("sonotextOnboardingComplete")
}

// MARK: - Right Option Press Monitor

class RightOptionPressMonitor {
    private var eventMonitor: Any?
    private var isRightOptionDown = false
    private var lastRightOptionPressTime: Date?
    private let doubleTapThreshold: TimeInterval = 0.4
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    
    func start() {
        let hasInputMonitoring = CGPreflightListenEventAccess()
        if !hasInputMonitoring {
            _ = CGRequestListenEventAccess()
            logger.notice("🟢 Requested Input Monitoring permission prompt")
        }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            // 61 is the right Option key (left Option is 58).
            guard event.keyCode == 61 else { return }
            let flagsPressed = event.modifierFlags.contains(.option)
            let isPressedNow = flagsPressed
            if isPressedNow && !self.isRightOptionDown {
                self.isRightOptionDown = true
                logger.notice("🟢 Right Option pressed")
                DispatchQueue.main.async { self.onPress?() }

                let now = Date()
                if let last = self.lastRightOptionPressTime, now.timeIntervalSince(last) < self.doubleTapThreshold {
                    self.lastRightOptionPressTime = nil
                    logger.notice("🟢 Right Option double-tap detected")
                    DispatchQueue.main.async { self.onDoubleTap?() }
                } else {
                    self.lastRightOptionPressTime = now
                }
            } else if !isPressedNow && self.isRightOptionDown {
                self.isRightOptionDown = false
                logger.notice("🟢 Right Option released")
                DispatchQueue.main.async { self.onRelease?() }
            }
        }
        logger.notice("🟢 Right Option monitor started")
    }
    
    func stop() {
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        eventMonitor = nil
        isRightOptionDown = false
        lastRightOptionPressTime = nil
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DictationTriggerMode: String {
        case pushToTalk
        case toggle
    }

    var statusItem: NSStatusItem?
    var floatingPanel: NSPanel?
    let appState = AppState()
    let whisperService = LocalWhisperService.shared
    let audioRecorder = AudioRecorder()
    let rightOptionMonitor = RightOptionPressMonitor()
    private var previousApp: NSRunningApplication?
    private var permissionRefreshTimer: Timer?
    private let triggerModeKey = "dictation_trigger_mode"
    
    // Panel sizes
    private let onboardingSize = NSSize(width: 316, height: 290)
    private let widgetSize     = NSSize(width: 280, height: 44)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "SonoText")
        
        setupFloatingPanel()
        constructMenu()
        
        rightOptionMonitor.onPress = { [weak self] in self?.handleRightOptionPress() }
        rightOptionMonitor.onRelease = { [weak self] in self?.handleRightOptionRelease() }
        rightOptionMonitor.onDoubleTap = { [weak self] in self?.handleRightOptionDoubleTap() }
        rightOptionMonitor.start()
        appState.refreshPermissions()
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.appState.refreshPermissions()
        }
        
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
                } else if self.appState.isOnboardingComplete {
                    self.appState.status = .error("Speech model failed to load. Re-launch onboarding.")
                }
            }
        }
        
        logger.notice("🟢 SonoText launched. Onboarding complete: \(self.appState.isOnboardingComplete)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
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
        // Re-register the global hotkey monitor now that permissions are granted
        rightOptionMonitor.stop()
        rightOptionMonitor.start()
        
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

    private var triggerMode: DictationTriggerMode {
        get {
            let raw = UserDefaults.standard.string(forKey: triggerModeKey) ?? DictationTriggerMode.pushToTalk.rawValue
            return DictationTriggerMode(rawValue: raw) ?? .pushToTalk
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: triggerModeKey)
        }
    }

    private func handleRightOptionPress() {
        guard triggerMode == .pushToTalk else { return }
        startRecordingFromHotkey()
    }

    private func handleRightOptionRelease() {
        guard triggerMode == .pushToTalk else { return }
        stopRecordingFromHotkey()
    }

    private func handleRightOptionDoubleTap() {
        guard triggerMode == .toggle else { return }
        toggleRecordingFromHotkey()
    }
    
    @objc private func startRecordingFromHotkey() {
        guard whisperService.isModelReady else {
            transientError("Speech model still loading")
            NSSound(named: "Basso")?.play()
            logger.notice("\"⏳ Engine still loading, ignoring right Option press\"")
            return
        }
        guard appState.isOnboardingComplete else { return }
        guard !audioRecorder.isRecording else { return }
        if case .processing = appState.status { return }
        guard appState.hasAllRequiredPermissions else {
            transientError("Permissions needed. Open setup.")
            NSSound(named: "Basso")?.play()
            return
        }

        NSSound(named: "Pop")?.play()
        previousApp = NSWorkspace.shared.frontmostApplication
        let prevName = previousApp?.localizedName ?? "none"
        logger.notice("🟢 Starting recording. Previous app: \(prevName, privacy: .public)")
        appState.status = .listening
        let didStart = audioRecorder.startRecording()
        if !didStart {
            appState.status = .error("Could not access microphone")
        }
        updateUIIcon()
    }

    @objc private func stopRecordingFromHotkey() {
        guard audioRecorder.isRecording else { return }

        NSSound(named: "Glass")?.play()
        logger.notice("🟢 Stopping recording")
        appState.status = .processing
        audioRecorder.stopRecording { [weak self] fileURL in
            guard let self else { return }
            logger.notice("🟢 Recording saved: \(fileURL.lastPathComponent, privacy: .public)")
            self.processAudio(fileURL: fileURL)
        }
        updateUIIcon()
    }

    @objc private func toggleRecordingFromHotkey() {
        if audioRecorder.isRecording {
            stopRecordingFromHotkey()
        } else {
            startRecordingFromHotkey()
        }
    }

    @objc private func setPushToTalkMode() {
        setTriggerMode(.pushToTalk)
    }

    @objc private func setToggleMode() {
        setTriggerMode(.toggle)
    }

    private func setTriggerMode(_ mode: DictationTriggerMode) {
        if triggerMode == mode { return }
        triggerMode = mode
        // Avoid carrying a recording across mode boundaries.
        if audioRecorder.isRecording {
            stopRecordingFromHotkey()
        }
        constructMenu()
        logger.notice("🟢 Trigger mode changed to \(mode.rawValue, privacy: .public)")
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
                    await MainActor.run {
                        self.transientError("Nothing heard")
                    }
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
                    _ = await MainActor.run {
                        app.activate(options: [])
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
                    if self.pasteViaAppleScript() {
                        self.appState.status = .idle
                    } else {
                        self.transientError("Could not paste into target app")
                    }
                }
                
            } catch {
                logger.error("🔴 \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self.appState.status = .error(error.localizedDescription) }
            }
        }
    }
    
    private func pasteViaAppleScript() -> Bool {
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
            return simulatePasteCGEvent()
        } else {
            logger.notice("🟢 Paste sent via AppleScript")
            return true
        }
    }
    
    private func simulatePasteCGEvent() -> Bool {
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        guard let vDown, let vUp else {
            logger.error("🔴 CGEvent paste fallback creation failed")
            return false
        }
        vDown.flags = .maskCommand
        vUp.flags   = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        logger.notice("🟢 Paste sent via CGEvent fallback")
        return true
    }
    
    private func transientError(_ message: String, duration: UInt64 = 2_000_000_000) {
        appState.status = .error(message)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: duration)
            await self?.clearTransientErrorIfNeeded(message)
        }
    }
    
    @MainActor
    private func clearTransientErrorIfNeeded(_ message: String) {
        if case .error(let current) = appState.status, current == message {
            appState.status = .idle
        }
    }
    
    func constructMenu() {
        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Widget", action: #selector(showWidget), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(.separator())

        let pushItem = NSMenuItem(title: "Push-to-Talk (hold right ⌥)", action: #selector(setPushToTalkMode), keyEquivalent: "")
        pushItem.target = self
        pushItem.state = triggerMode == .pushToTalk ? .on : .off
        menu.addItem(pushItem)

        let toggleItem = NSMenuItem(title: "Toggle (double-tap right ⌥)", action: #selector(setToggleMode), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = triggerMode == .toggle ? .on : .off
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SonoText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }
}
