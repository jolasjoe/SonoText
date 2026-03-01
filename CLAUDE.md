# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

All Swift commands are run from the `FlowApp/` subdirectory (where `Package.swift` lives):

```bash
cd FlowApp

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

The release binary is output to `FlowApp/.build/release/SonoText`. There is no test suite.

## Architecture

SonoText is a macOS 14+ dictation app: the user double-taps Control, speaks, then taps again — the transcript is pasted into whichever app was active. All speech-to-text happens on-device via WhisperKit (no network required for transcription). An OpenAI GPT-4o integration for text polishing is implemented in `OpenAIService.swift` but not wired into the current recording flow.

### Execution Flow

```
⌃⌃ hotkey → DoubleTapControlMonitor → AppDelegate.toggleRecording()
    → AudioRecorder (AVAudioEngine → /tmp/sonotext_capture.wav)
⌃⌃ again → LocalWhisperService.transcribe() → raw transcript
    → NSPasteboard → previous app re-activated → AppleScript Cmd+V (CGEvent fallback)
```

### Key Components

| File | Role |
|---|---|
| `SonoText.swift` | Entry point, `AppDelegate` (lifecycle + recording orchestration), `AppState` (published status), `FloatingWidgetView`, `OnboardingView`, `DoubleTapControlMonitor` |
| `AudioRecorder.swift` | `AVAudioEngine`-based mic capture; real-time RMS level for waveform UI |
| `LocalWhisperService.swift` | Singleton wrapping WhisperKit; handles model download (~145 MB to `~/Library/Application Support/SonoText/Models/`) and transcription |
| `KeystrokeSynthesizer.swift` | Singleton; pastes text via AppleScript with CGEvent fallback; requires Accessibility permission |
| `OpenAIService.swift` | GPT-4o API client (currently unused in recording flow) |
| `PersonalizationEngine.swift` | `@AppStorage`-backed user prefs (custom dictionary, snippets, writing style) intended for GPT-4o prompt context |
| `SettingsView.swift` | SwiftUI settings panel |

### State Management

- `AppState` (ObservableObject) holds `FlowStatus` (idle / listening / processing / error) and `OnboardingStep`
- Services are singletons accessed via `.shared`
- User settings use `@AppStorage` (backed by `UserDefaults`)

### UI

- `KeyablePanel` (NSPanel subclass) floats above all windows, joins all spaces, no shadow
- Transitions from onboarding size (316×290) to widget size (280×44) on first-launch completion
- `WaveformBarsView` uses `TimelineView(.animation)` with per-bar phase offsets

## Dependencies

- **WhisperKit** (`argmaxinc/WhisperKit`, `>=0.9.0`) — on-device Whisper inference; brings in `swift-transformers`, `swift-jinja`, `swift-collections`
- **KeyboardShortcuts** (`sindresorhus/KeyboardShortcuts`, `>=1.16.1`) — imported but not actively used; custom `DoubleTapControlMonitor` via `NSEvent.flagsChanged` is used instead

## Required Permissions

The app needs these entitlements / user grants at runtime:
- **Microphone** — for `AVAudioEngine` capture
- **Accessibility** — for `KeystrokeSynthesizer` (AppleScript / CGEvent pasting)
- **Network** (optional) — only if OpenAI polishing is re-enabled
