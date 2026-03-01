# STT App Ecosystem — Analysis & Learnings

> Compiled: Feb 21, 2026 | Context: Building FlowApp (voice-to-text Mac app)

---

## 1. How STT Apps Work (The Two Paths)

### Path A — Cloud API (what FlowApp uses today)
- Audio is uploaded to a cloud server (e.g. OpenAI).
- The server transcribes it using a massive model and returns text.
- **Pros:** Highest accuracy (Whisper-large-v3), no local compute needed, best for Indian languages.
- **Cons:** Pay-per-use, needs internet, audio leaves your device.
- **Cost:** ~$0.006 / minute of audio (OpenAI Whisper API).

### Path B — On-Device / Local (what MacWhisper uses)
- The model "brain" runs directly on your Mac's CPU/GPU/Neural Engine.
- Audio never leaves your machine.
- **Pros:** Free forever, offline, private, no quota errors.
- **Cons:** Requires a large model download (~150MB–3GB), heavier on battery.

---

## 2. OpenAI Whisper — Model Tiers

| Model | Size | Quality | Use Case |
|-------|------|---------|----------|
| Tiny | ~75 MB | Basic | Quick notes, English only |
| Base | ~145 MB | Decent | Everyday English dictation |
| Small | ~450 MB | Good | Best free-tier option |
| Medium | ~1.5 GB | Very Good | Multilingual (Hindi, Tamil) |
| Large-v3 | ~3.1 GB | Best (= OpenAI API) | Production-grade, all languages |
| Large-v3 Turbo | ~600 MB | Near-Large speed/quality | Best balance for M-series Macs |

> The OpenAI API always uses **Large-v3** (the best model) on their servers.

---

## 3. MacWhisper — Business Model Breakdown

- **App download size:** ~52 MB (just the UI shell).
- **Model files:** Downloaded separately on first launch (not bundled).
- **Free tier:** Tiny, Base, Small models (English-focused).
- **Pro tier (one-time fee):** Medium, Large-v3, Turbo, WhisperKit models, batch processing, speaker recognition.
- **Is it open-source?** ❌ No. The *Whisper model weights* are open-source (by OpenAI), but the MacWhisper app code is proprietary.
- **Who makes money:** The developer charges for the optimized CoreML models and polished Mac UI — not for the AI weights themselves.

---

## 4. Key Libraries for On-Device STT on macOS

| Library | Language | Notes |
|---------|----------|-------|
| **WhisperKit** (Argmax) | Swift | Best for Mac/iOS. Uses Apple CoreML + Neural Engine. Open-source. Recommended. |
| **SwiftWhisper** | Swift | Lower-level Swift bindings to `whisper.cpp`. |
| **whisper.cpp** | C++ | Original high-performance port. Used by MacWhisper internally. |
| **Apple SFSpeechRecognizer** | Swift | Native macOS framework. Free, no download. Good English, limited accuracy for Indian languages. |

---

## 5. FlowApp USP vs. Native macOS Dictation

| Feature | macOS Dictation | FlowApp |
|---------|----------------|---------|
| Filler word removal | ❌ | ✅ GPT polishes the draft |
| Verbal corrections ("actually...") | ❌ | ✅ LLM understands intent |
| Context-aware name spelling | ❌ | ✅ Reads surrounding text |
| Voice Snippets | ❌ | ✅ Say "link" → paste Calendly URL |
| Tone/Style adjustment | ❌ | ✅ Formal/Casual/Enthusiastic |
| Hinglish / Tanglish | Basic | ✅ Whisper handles code-switching |

**Conclusion:** Native dictation transcribes. FlowApp *edits and thinks*.

---

## 6. Recommended Architecture for FlowApp (Next Step)

```
[Microphone] 
    → [WhisperKit — Local STT, free, on-device]
    → Raw transcript (messy, includes "um/uh")
    → [GPT-4o-mini — Text polishing only, ~$0.0001/request]
    → Clean, context-aware text
    → [Paste into active app]
```

**Why this hybrid?**
- WhisperKit = **0 cost** for transcription (removes the 429 quota error).
- GPT-4o-mini = **near-zero cost** for polishing (the "smart" USP features stay).
- On-device STT + cloud LLM is the same architecture Wispr Flow uses.

---

## 7. Open-Source Alternatives to MacWhisper

- **[WhisperKit Demo App](https://github.com/argmaxinc/WhisperKit)** — Full open-source example of on-device Whisper on Mac.
- **[Whispering](https://github.com/braden-moore/whispering)** — Global hotkey transcription app, fully open-source.
- **[Dial8](https://github.com/dial8/dial8)** — Privacy-first, 100% local macOS STT app.

---

## 8. Next Steps for FlowApp

- [ ] Replace `OpenAIService.transcribeAudio()` with **WhisperKit** local inference.
- [ ] Keep `OpenAIService.polishTranscription()` but switch model to `gpt-4o-mini` to reduce cost.
- [ ] Add a first-launch model download flow (similar to MacWhisper).
- [ ] Let user pick model size (Tiny/Small/Medium) based on their Mac RAM.
