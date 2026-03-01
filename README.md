# SonoText

**Sound to text.** A small macOS app that turns speech into text and pastes it into the frontmost app. Hold right Option (push-to-talk mode) or use right-Option double-tap mode; transcription runs on-device with Whisper (no cloud required).

---

## Prerequisites

- **macOS 14+**
- **Xcode** (or the Swift toolchain) with **Swift 5.9+**  
  - Swift is included with Xcode from the App Store, or install the [Swift toolchain](https://www.swift.org/install/) for the command line.
- On first run, grant the permissions below for full functionality:
  - **Microphone**: required for `AVAudioEngine` recording.
  - **Accessibility**: required for simulated keystrokes/paste fallback.
  - **Input Monitoring**: required for global right-Option hotkey detection.
  - **Automation (System Events)**: used by AppleScript paste (`keystroke "v" using command down`) and improves paste reliability across apps.
- **Network** (once): the app downloads the Whisper model (~145 MB) to `~/Library/Application Support/SonoText/Models/` on first launch.

---

## Build

From the repo root:

```bash
cd SonoText
swift build
```

Optional: resolve/update dependencies first:

```bash
swift package resolve
# or
swift package update
```

Release build:

```bash
swift build -c release
```

The release binary is at `SonoText/.build/release/SonoText`.

---

## Run

From the `SonoText` directory:

```bash
swift run SonoText
```

Or run the release binary directly:

```bash
./.build/release/SonoText
```

On first run, complete setup (model download if needed), then hold **right Option (⌥)** to dictate (push-to-talk). You can switch to right-Option double-tap toggle mode from the status-bar menu.

---

## Reset Permissions + Onboarding

If you want a clean onboarding run, do these steps in order.

1) Quit SonoText.

2) Reset app state:

```bash
defaults delete com.sonotext.mac onboarding_complete 2>/dev/null || true
defaults delete SonoText onboarding_complete 2>/dev/null || true
```

3) Reset TCC permissions (prompts will appear again next run):

```bash
tccutil reset Microphone com.sonotext.mac
tccutil reset Accessibility com.sonotext.mac
tccutil reset ListenEvent com.sonotext.mac
tccutil reset AppleEvents com.sonotext.mac
```

If macOS does not track your local build under `com.sonotext.mac`, use System Settings manually:
- Privacy & Security -> Microphone
- Privacy & Security -> Accessibility
- Privacy & Security -> Input Monitoring
- Privacy & Security -> Automation (System Events)

4) (Optional) force model-download onboarding again:

```bash
rm -rf "$HOME/Library/Application Support/SonoText/Models"
```

5) Start with the helper script from repo root:

```bash
./scripts/run-onboarding.sh --full
```

This script launches a stable app bundle at `/Applications/SonoText.app` (via `open`) and ad-hoc signs it so macOS permission prompts and TCC tracking behave like a normal app.

---

## Credits

SonoText uses the following open source libraries:

- **[WhisperKit](https://github.com/argmaxinc/WhisperKit)** by Argmax — on-device speech-to-text using OpenAI's Whisper models. Used for all transcription in this app.  
  License: [MIT](https://github.com/argmaxinc/WhisperKit/blob/main/LICENSE)

- **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)** by Sindre Sorhus — keyboard shortcut handling for macOS.  
  License: [MIT](https://github.com/sindresorhus/KeyboardShortcuts/blob/main/license)

WhisperKit in turn relies on [Swift Transformers](https://github.com/huggingface/swift-transformers), [Swift Jinja](https://github.com/argmaxinc/swift-jinja), and [Swift Collections](https://github.com/apple/swift-collections). Thanks to OpenAI for the [Whisper](https://github.com/openai/whisper) model architecture and to all contributors of the above projects.
