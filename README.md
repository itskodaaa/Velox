<p align="center">
  <img src="assets/app_icon.png" alt="Mumblr App Icon" width="120" height="120">
</p>

<h1 align="center">Mumblr</h1>

<p align="center">
  <strong>Native, zero-latency voice dictation and desktop companion for macOS.</strong><br>
  <sub>Engineered for Apple Silicon with Whisper Large v3, MLX Metal acceleration, and context-aware LLM synthesis.</sub>
</p>

<p align="center">
  <a href="#overview">Overview</a> •
  <a href="#quickstart">Quickstart</a> •
  <a href="#shortcuts--controls">Shortcuts</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#troubleshooting">Troubleshooting</a> •
  <a href="#development">Development</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-black?style=flat-square&logo=apple" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/swift-6.4-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.4">
  <img src="https://img.shields.io/badge/python-3.11%2B-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python 3.11+">
  <img src="https://img.shields.io/badge/inference-Metal%20%2F%20Groq%20LPU-00C7B7?style=flat-square" alt="Inference">
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License">
</p>

---

## Overview

Mumblr is a native macOS dictation engine and interactive workspace companion built exclusively for Apple Silicon. Press `⌥ Space` in any application to speak — Mumblr captures audio, transcribes speech with Whisper Large v3, formats and refines text with context-aware LLMs, and injects the result directly into your active cursor in under two seconds.

```
Audio Input (⌥ Space) ──► Whisper Large v3 ──► LLM Polish Engine ──► macOS Cursor Auto-Paste
  [AVFoundation mic]      [Groq LPU / MLX Metal]   [Qwen 27B / Rules]      [Accessibility AXUI]
```

### Core Capabilities

| Capability | Engine & Implementation | Latency & Privacy |
| :--- | :--- | :--- |
| **Hybrid STT Pipeline** | Cloud Groq LPU (`whisper-large-v3`) with zero-config Apple Silicon MLX Metal fallback | ~1.5s cloud / fully offline local |
| **Context-Aware Polish** | Multi-provider LLM post-processing (Qwen 27B, Ollama, LM Studio) or zero-overhead rule engine | Heals phonetic mishears, strips fillers, structures lists |
| **Active Screen Context** | macOS `AXUIElement` inspection captures active app name, window title, and selected text | Technical terms and variable names transcribe accurately |
| **Desktop Companion** | Real-time SwiftUI HUD with audio metering, reactive cursor gaze, and typing awareness | Hardware-accelerated, <1% idle CPU footprint |
| **Flow Focus Timer** | Integrated Pomodoro deep-work presets (15m, 25m, 45m, 60m) with audio chimes | Visual companion morphs seamlessly between work & dictation |
| **Web Control Studio** | Dark-glass control panel at `http://127.0.0.1:18765` | Real-time transcription history, latency metrics, provider health |

---

## Quickstart

### Prerequisites

- macOS running on Apple Silicon (M1/M2/M3/M4)
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3.11+
- Groq API Key *(free tier supported for ~1.5s cloud transcription)*: [console.groq.com](https://console.groq.com)

### 1. Build and Install

```bash
# Clone the repository
git clone https://github.com/itskodaaa/mumblr.git
cd mumblr

# Create environment and install runtime dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install mlx mlx-whisper httpx numpy soundfile

# Compile native binary, code-sign, and bundle into /Applications/Mumblr.app
./build.sh
```

### 2. Configure & Run

```bash
# Configure your credentials and preferences
mkdir -p ~/.mumblr
cat > ~/.mumblr/config.json << 'EOF'
{
  "stt_engine": "groq",
  "groq_key": "YOUR_GROQ_API_KEY",
  "provider": "groq",
  "use_llm_polish": true
}
EOF

# Launch the daemon and start Mumblr
nohup .venv/bin/python mumblr_daemon.py > /tmp/mumblr_daemon.log 2>&1 &
open /Applications/Mumblr.app
```

> **First Launch:** Grant **Microphone** and **Accessibility** permissions in *System Settings → Privacy & Security* when prompted.

---

## Shortcuts & Controls

| Shortcut / Trigger | Action | Target / Scope |
| :--- | :--- | :--- |
| `⌥ Space` | Toggle Dictation | Global (Default hotkey) |
| `F8` / `⌃ Space` / `⌘⇧D` | Alternate Hotkeys | Global |
| `Hold ⌥` | Push-to-Talk | Transcribes immediately on key release |
| `touch /tmp/mumblr_toggle` | IPC Trigger | Raycast / Alfred / CLI scripts / Stream Deck |
| Menu Bar Extra | Control Center | Quick access to Dictate, Flow, Mascots, and Settings |
| Right-click Mascot | Flow Mode Menu | Quick-select Pomodoro timers or switch companion |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Mumblr.app (Swift 6.4)                    │
│                                                             │
│   Menu Bar Extra      Floating HUD        Accessibility API │
│  [Status / Panes]   [Mascot / Waves]    [Context & Injection]│
└──────────────────────────────┬──────────────────────────────┘
                               │ POST /transcribe (localhost:18765)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                 mumblr_daemon.py (FastAPI)                  │
│                                                             │
│  ┌─────────────────────────┐   ┌──────────────────────────┐ │
│  │   Speech-to-Text        │   │   Formatting & Polish    │ │
│  │  • Groq Cloud (~1.5s)   │──►│  • Qwen 27B / OpenRouter │ │
│  │  • MLX Metal (Offline)  │   │  • Ollama / LM Studio    │ │
│  │  • Automatic Failover   │   │  • Zero-latency Rules    │ │
│  └─────────────────────────┘   └──────────────────────────┘ │
│                                                             │
│  Web Studio Dashboard: http://127.0.0.1:18765               │
└─────────────────────────────────────────────────────────────┘
```

---

## Configuration

Settings are stored in `~/.mumblr/config.json` and hot-reloaded automatically:

```jsonc
{
  // Speech-to-Text: "groq" (cloud ~1.5s) | "local_mlx" (on-device Apple Silicon)
  "stt_engine": "groq",
  "groq_key": "gsk_...",
  "groq_model": "whisper-large-v3",

  // LLM Polish: "groq" | "openrouter" | "ollama" | "lmstudio" | "local_rules"
  "provider": "groq",
  "use_llm_polish": true,
  "groq_polish_model": "qwen/qwen3.8-27b",

  // Custom Domain Vocabulary (comma-separated hints for Whisper & LLM)
  "custom_vocab": "GitHub, PR, Mumblr, Apple Silicon, Metal, Swift",

  // Companion Interface
  "hud_character": "gearbot",         // "gearbot" | "neko" | "bongo"
  "hud_position": "bottom_center",    // "bottom_center" | "left" | "right"
  "hud_color": "amber",               // "amber" | "rose" | "emerald" | "cyan" | "purple"
  "hud_always_show": true             // Persistent desktop companion mode
}
```

<details>
<summary><strong>Air-Gapped / Fully Offline Configuration</strong></summary>

Mumblr supports 100% private, offline execution without transmitting data over the network:

```json
{
  "stt_engine": "local_mlx",
  "provider": "local_rules",
  "use_llm_polish": false
}
```

Inference runs locally using MLX Metal GPU kernels. For offline local LLM post-processing, run [Ollama](https://ollama.com) and configure `"provider": "ollama"` with `"ollama_model": "llama3.2"`.
</details>

---

## Troubleshooting

| Symptom | Probable Cause | Recommended Fix |
| :--- | :--- | :--- |
| **No text injected on dictation** | Missing Accessibility rights | Enable *System Settings → Privacy & Security → Accessibility*. |
| **Audio meter remains static** | Microphone access denied | Grant access in *System Settings → Privacy & Security → Microphone*. |
| **503 "Model is warming up"** | Metal graph compiling | Allow 3–5 seconds on first boot for MLX Metal pipeline initialization. |
| **Cloud transcription fails** | Groq API quota or bad key | Validate key in `~/.mumblr/config.json` or run health check via Web Studio. |

---

## Development

```bash
# Run daemon in foreground for real-time inspection
.venv/bin/python mumblr_daemon.py

# Recompile and install the macOS application bundle
./build.sh && open /Applications/Mumblr.app

# Directly verify audio transcription endpoint
curl -s -X POST http://127.0.0.1:18765/transcribe \
  -H "Content-Type: application/json" \
  -d '{"audio_path": "/tmp/test.wav", "stt_engine": "groq"}'
```

---

## Contributing

Pull requests are welcome. For significant changes, please open an issue first to discuss the design:

1. Fork the project & create your feature branch: `git checkout -b feature/improvement`
2. Validate locally with `./build.sh`
3. Commit your changes: `git commit -m "feat: add capability"`
4. Open a Pull Request

---

## License

Mumblr is open-source software licensed under the [MIT License](LICENSE).
