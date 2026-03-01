# SonoText

**Sound to text.** A small macOS app that turns speech into text and pastes it into the frontmost app. Double-tap Control to start or stop dictation; transcription runs on-device with Whisper (no cloud required).

---

## Prerequisites

- **macOS 14+**
- **Xcode** (or the Swift toolchain) with **Swift 5.9+**  
  - Swift is included with Xcode from the App Store, or install the [Swift toolchain](https://www.swift.org/install/) for the command line.
- On first run you’ll be prompted for:
  - **Microphone** access (for recording).
  - **Accessibility** access (for pasting into other apps).  
  Grant both for full functionality.
- **Network** (once): the app downloads the Whisper model (~145 MB) to `~/Library/Application Support/SonoText/Models/` on first launch.

---

## Build

From the repo root:

```bash
cd FlowApp
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

The release binary is at `FlowApp/.build/release/SonoText`.

---

## Run

From the `FlowApp` directory:

```bash
swift run SonoText
```

Or run the release binary directly:

```bash
./.build/release/SonoText
```

On first run, complete the one-time setup (model download if needed), then **double-tap Control (⌃⌃)** to start recording and again to stop; the transcript is pasted into the app that was active when you started.
