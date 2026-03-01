# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

All Swift commands are run from the `SonoText/` subdirectory (where `Package.swift` lives):

```bash
cd SonoText

# Debug build
swift build

# Release build
swift build -c release

# Resolve/update dependencies
swift package resolve
swift package update

# Run directly (debug)
swift run SonoText
```

The release binary is output to `SonoText/.build/release/SonoText`. There is no test suite.

Release, test, and debug script output (DMGs, etc.) goes in **`output/`** at the repo root (gitignored).

## Dev Launch Script (preferred)

Always use `scripts/run-onboarding.sh` from the repo root instead of `swift run` directly. It:

1. Kills any running SonoText process
2. Resets the `onboarding_complete` UserDefaults flag
3. Runs `swift package clean` + `rm -rf .build` (avoids PCH/module cache path mismatch errors when paths have changed)
4. Builds a release binary (`swift build -c release`)
5. Packages it into `/Applications/SonoText.app` with `Info.plist` (bundle id `com.sonotext.mac`, `LSUIElement=true`)
6. Ad-hoc signs the bundle (`codesign --force --deep --sign -`)
7. Launches with `open /Applications/SonoText.app`

Launching as a real `.app` bundle (rather than via `swift run`) is required for macOS TCC permissions to work correctly — especially Input Monitoring, which will not prompt or list CLI binaries reliably.

```bash
# From repo root — standard onboarding reset
./scripts/run-onboarding.sh

# Full first-run replay (also wipes local Whisper model cache)
./scripts/run-onboarding.sh --full

# Full "rebirth" replay (model cache + TCC permission resets)
./scripts/run-onboarding.sh --rebirth
```

Writing to `/Applications` may require admin rights; prefix with `sudo` if needed.

## Architecture

SonoText is a macOS 14+ dictation app that runs as a menu bar accessory. The user holds right Option (⌥) to record (push-to-talk mode, default) or double-taps right Option in toggle mode. When recording stops, the transcript is pasted into whichever app was previously active. All speech-to-text happens on-device via WhisperKit — no network required for transcription. An OpenAI GPT-4o integration for text polishing exists in `OpenAIService.swift` but is not wired into the recording flow.

### Execution Flow

```
right ⌥ held/tapped → RightOptionPressMonitor → AppDelegate.startRecordingFromHotkey()
    → AudioRecorder (AVAudioEngine → /tmp/sonotext_capture.wav)
right ⌥ released → AppDelegate.stopRecordingFromHotkey()
    → LocalWhisperService.transcribe() → raw transcript
    → NSPasteboard → previous app re-activated → AppleScript Cmd+V (CGEvent fallback)
```

### Key Components

| File | Role |
|---|---|
| `SonoText.swift` | Entry point (`@main`), `AppDelegate` (lifecycle + full recording orchestration including paste), `AppState` (published status), `FloatingWidgetView`, `OnboardingView`, `RightOptionPressMonitor`, `MainPanelView`, `WaveformBarsView`, `KeyablePanel` |
| `AudioRecorder.swift` | `AVAudioEngine`-based mic capture; real-time RMS level (mapped -55..0 dB → 0..1) for waveform UI |
| `LocalWhisperService.swift` | Singleton wrapping WhisperKit; handles model download (~145 MB to `~/Library/Application Support/SonoText/Models/openai_whisper-base`) and transcription |
| `KeystrokeSynthesizer.swift` | Singleton; `copySelectedText()` captures selected text before recording begins; Accessibility permission required |
| `Logging.swift` | Defines `os.log` `Logger` instances per component: `logger`, `audioLogger`, `whisperLogger`, `keystrokeLogger`, `openAILogger`, `settingsLogger`, `personalizationLogger` (subsystem: `com.sonotext.mac`) |
| `OpenAIService.swift` | GPT-4o API client (currently unused in recording flow) |
| `PersonalizationEngine.swift` | `@AppStorage`-backed user prefs (custom dictionary, snippets, writing style) intended for GPT-4o prompt context |
| `SettingsView.swift` | SwiftUI settings panel |

### Trigger Modes

`AppDelegate` reads `UserDefaults` key `dictation_trigger_mode` (`"pushToTalk"` | `"toggle"`):
- **Push-to-talk** (default): hold right ⌥ to record, release to stop
- **Toggle**: double-tap right ⌥ to start, double-tap again to stop (threshold: 0.4s)

Both modes are switchable from the status-bar menu without restarting.

### State Management

- `AppState` (ObservableObject) holds `FlowStatus` (idle / listening / processing / error) and `OnboardingStep` (downloading / ready / done)
- `AppState` also tracks live permission status: `isMicrophoneGranted`, `isAccessibilityGranted`, `isInputMonitoringGranted` (polled every 1s during onboarding via `refreshPermissions()`)
- Services are singletons accessed via `.shared` (`LocalWhisperService`, `KeystrokeSynthesizer`)
- `AudioRecorder` is instantiated directly in `AppDelegate`
- User settings use `@AppStorage` (backed by `UserDefaults`)

### UI

- `KeyablePanel` (NSPanel subclass) floats above all windows, joins all spaces, no shadow
- Transitions from onboarding size (316×290) to widget size (280×44) on first-launch completion via `NotificationCenter` post (`.sonotextOnboardingComplete`)
- `WaveformBarsView` uses `TimelineView(.animation)` with per-bar phase offsets
- `OnboardingView` shows live permission rows (Microphone, Accessibility, Input Monitoring) with Grant/Open Settings buttons; "Get Started" is disabled until `hasAllRequiredPermissions == true`
- Input Monitoring "Open Settings" button uses `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` deep link (TCC prompt alone is unreliable for this permission)
- On onboarding completion (`onboardingDidComplete`), `RightOptionPressMonitor` is stopped and restarted so the global event monitor re-registers with newly granted permissions

### Paste Flow

`AppDelegate.processAudio(fileURL:)` (async Task):
1. Transcribes audio via `LocalWhisperService`
2. Places text on `NSPasteboard.general`
3. Re-activates the previously frontmost app (polls `isActive` up to 1.5s in 50ms steps)
4. Waits 300ms for window focus
5. Calls `pasteViaAppleScript()` → falls back to `simulatePasteCGEvent()` on failure

## Dependencies

- **WhisperKit** (`argmaxinc/WhisperKit`, `>=0.9.0`) — on-device Whisper inference ("base" model); brings in `swift-transformers`, `swift-jinja`, `swift-collections`
- **KeyboardShortcuts** (`sindresorhus/KeyboardShortcuts`, `>=1.16.1`) — imported but not actively used; hotkey detection is handled by `RightOptionPressMonitor` via `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` (right Option = keyCode 61)

## Required Permissions

- **Microphone** — for `AVAudioEngine` capture
- **Accessibility** — for `KeystrokeSynthesizer` (AppleScript / CGEvent pasting) and `copySelectedText()`
- **Input Monitoring** — for `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` global right-Option hotkey detection; **without this, hotkeys are silently ignored**
- **Automation (System Events)** — for AppleScript `keystroke "v" using command down` paste
- **Network** (optional) — only if OpenAI polishing is re-enabled

### Resetting permissions for a clean onboard

```bash
tccutil reset Microphone com.sonotext.mac
tccutil reset Accessibility com.sonotext.mac
tccutil reset ListenEvent com.sonotext.mac
tccutil reset AppleEvents com.sonotext.mac
```

If `tccutil` doesn't affect the local build (bundle not tracked yet), reset manually in:
- System Settings → Privacy & Security → Microphone
- System Settings → Privacy & Security → Accessibility
- System Settings → Privacy & Security → Input Monitoring
- System Settings → Privacy & Security → Automation

## Known Issues & Fixes

### PCH / module cache path mismatch on first build after moving directories
`error: PCH was compiled with module cache path '.../FlowApp/...' but path is currently '.../SonoText/...'`
**Fix:** `swift package clean && rm -rf SonoText/.build` before building. The launch script does this automatically.

### Global hotkey (right Option) not firing after onboarding
`NSEvent.addGlobalMonitorForEvents` returns `nil` silently when Input Monitoring is not yet granted at launch time. The monitor is therefore re-registered in `AppDelegate.onboardingDidComplete()` after the user grants all permissions. Additionally, press detection uses `event.modifierFlags.contains(.option)` (not `CGEventSource.keyState`) which is the reliable source of truth for `flagsChanged` events.

### Input Monitoring not listing the app in System Settings
Only proper `.app` bundles with a stable bundle identifier are reliably listed by TCC for Input Monitoring. Running via `swift run` (CLI binary) will often not appear. Always launch via `scripts/run-onboarding.sh` which installs an ad-hoc-signed bundle to `/Applications/SonoText.app`.
