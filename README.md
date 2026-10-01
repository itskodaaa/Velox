<p align="center">
  <img src="assets/banner.jpg" alt="Velox Banner" width="100%">
</p>

<h1 align="center">Velox</h1>

<p align="center">
  <strong>Blazing-fast macOS dictation with Whisper Large v3, intelligent formatting, and a desktop companion.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#demo">Demo</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#contributing">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026%2B-blue?style=flat-square&logo=apple" alt="macOS 26+">
  <img src="https://img.shields.io/badge/swift-6.4-orange?style=flat-square&logo=swift" alt="Swift 6.4">
  <img src="https://img.shields.io/badge/python-3.11%2B-blue?style=flat-square&logo=python" alt="Python 3.11+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/apple%20silicon-native-black?style=flat-square&logo=apple" alt="Apple Silicon Native">
</p>

---

## What is Velox?

**Velox** is a native macOS menu bar dictation app that turns your voice into perfectly formatted, publication-ready text — then pastes it wherever your cursor is. It's an open-source alternative to [Wispr Flow](https://wispr.com), built from scratch for Apple Silicon.

Press **⌥ Space** anywhere on your Mac. Speak. Velox transcribes your speech using OpenAI's Whisper Large v3, intelligently formats it with an LLM polisher, and pastes it directly into whatever app you're using — all in under 2 seconds.

### The Pipeline

```
🎙️ Your Voice
   ↓  (Option + Space)
📊 Live Audio Metering (Floating HUD)
   ↓
🧠 Whisper Large v3 (Groq Cloud LPU ~1.5s / Local MLX Metal fallback)
   ↓
✨ LLM Polish Engine (Qwen 27B — fixes lists, punctuation, slang healing)
   ↓
📋 Auto-Paste at Cursor (Accessibility API → Cmd+V)
```

---

## Features

### 🚀 Blazing Fast
- **Cloud mode**: Whisper Large v3 on Groq LPU — full transcription in **~1.5 seconds**
- **Local fallback**: MLX Whisper Large v3 Turbo on Apple Silicon Metal GPU — works offline
- **Automatic failover**: If Groq is unreachable, Velox silently switches to local inference

### 🧠 Intelligent Formatting
- **Numbered lists**: Say *"Number 1, review the PR. Number 2, send the invoice"* → clean markdown list
- **Self-correction**: Say *"meet at 10… actually make that 3 PM"* → outputs *"meet at 3 PM"*
- **Filler removal**: Strips *"um"*, *"uh"*, *"you know"* seamlessly
- **Phonetic healing**: Cross-references your custom vocabulary to fix accent-related mishears (e.g. *"half hour abeg"* → *"How far, abeg"*)

### 🎯 Screen Context Awareness
- Reads your **active app name**, **window title**, and **selected text** via macOS Accessibility APIs
- Feeds these as context cues to Whisper and the polisher for domain-specific accuracy
- Variable names, file names, and technical terms from your screen are transcribed correctly

### ⚡ Flow Mode (Focus Timer)
- Right-click the desktop mascot anytime to trigger **Flow Mode** (Pomodoro / Deep Work)
- Presets: **25 min Focus**, **45 min Deep Work**, **60 min Flow State**, **15 min Quick Sprint**
- Real-time countdown clock stays pinned beside your pet, keeping you locked in
- Smoothly morphs into voice waveform when dictating, and morphs back when finished
- Native macOS chime and banner notification when sessions complete

### 🎛️ De-Cluttered Two-Pane Control Center
- High-end sidebar navigation with 4 dedicated panes: **Dictate**, **Flow**, **Companion**, **Settings**
- Ultra-clean first impression on click with zero visual clutter
- Tactile frosted microphone orb with live reactive audio pulse
- Fast toggle between 0ms offline rules and cloud LLM polish

### 🤖 Desktop Pet Companion
- A floating animated character (Gearbot, Birb, Neko, or Orb) lives on your desktop
- Reacts to hover and clicks with cute animations
- Morphing voice waveform animation during dictation
- Snaps to left, center, or right of screen with smooth dock-aware positioning
- 6 vibrant accent color themes (Amber, Rose, Emerald, Cyan, Purple, Monochrome)

### 🎛️ Web Dashboard
- Beautiful dark-mode dashboard at `http://localhost:18765`
- Full transcription history with latency stats and cost tracking
- Live provider connection testing
- HUD customization preview

### 🔌 Multi-Provider LLM Support
| Provider | Type | Speed | Cost |
|----------|------|-------|------|
| **Groq** (default) | Cloud LPU | ~400ms | Free tier |
| **OpenRouter** | Cloud | ~800ms | Pay-per-token |
| **Ollama** | Local | ~2–5s | Free |
| **LM Studio** | Local | ~2–5s | Free |
| **Local Rules** | Offline | 0ms | Free |

---

## Demo

> **Spoken input:**
> *"Test number one, here are three tasks for today. Number one, review the pull request on GitHub. Number two, send the updated invoice to the client. Number three, prepare the slide deck for our afternoon meeting."*

**Output:**

```
Test 1: Here are three tasks for today.
1. Review the pull request on GitHub.
2. Send the updated invoice to the client.
3. Prepare the slide deck for our afternoon meeting.
```

⏱️ Total latency: **2.3 seconds** (STT: 1.7s + Polish: 0.5s)

---

## Installation

### Prerequisites

- **macOS 26+** on Apple Silicon (M1/M2/M3/M4)
- **Xcode Command Line Tools**: `xcode-select --install`
- **Python 3.11+** with pip
- **A Groq API key** (free): [console.groq.com](https://console.groq.com)

### Quick Install

```bash
# 1. Clone the repository
git clone https://github.com/YOUR_USERNAME/Velox.git
cd Velox

# 2. Set up the Python environment
python3 -m venv .venv
source .venv/bin/activate
pip install mlx mlx-whisper httpx numpy soundfile

# 3. Configure your API key
mkdir -p ~/.parakeetflow
cat > ~/.parakeetflow/config.json << 'EOF'
{
  "stt_engine": "groq",
  "groq_key": "YOUR_GROQ_API_KEY_HERE",
  "provider": "groq",
  "use_llm_polish": true,
  "groq_model": "whisper-large-v3",
  "groq_polish_model": "qwen/qwen3.8-27b",
  "custom_vocab": "GitHub, PR",
  "hud_position": "bottom_center",
  "hud_character": "gearbot",
  "hud_color": "amber",
  "hud_always_show": true
}
EOF

# 4. Build and install the native app
chmod +x build.sh
./build.sh

# 5. Start the inference daemon
nohup .venv/bin/python parakeet_daemon.py > /tmp/parakeet_daemon.log 2>&1 &

# 6. Launch Velox
open /Applications/Velox.app
```

### First Launch Permissions

Velox will request two macOS permissions on first launch:

1. **Microphone** — Required to capture audio for dictation
2. **Accessibility** — Required for global hotkeys and auto-paste

Grant both in **System Settings → Privacy & Security**.

---

## Usage

### Global Shortcuts

| Shortcut | Action |
|----------|--------|
| **⌥ Space** | Toggle recording (default) |
| **F8** | Toggle recording |
| **⌃ Space** | Toggle recording |
| **⌘⇧D** | Toggle recording |
| **Hold ⌥** | Hold-to-talk (release to transcribe) |

### Menu Bar

Click the Velox icon in the menu bar to access:
- Quick record button
- Engine selector (Local Rules / LLM Polish)
- Companion mascot picker
- Position & dock snapping controls
- Dashboard link

### CLI Trigger

```bash
# Toggle recording from any terminal or script
touch /tmp/parakeet_toggle
```

### Web Dashboard

Open `http://localhost:18765` in your browser for:
- Full transcription history
- Provider settings & connection testing
- HUD customization
- Cost analytics

---

## Configuration

All settings are stored in `~/.parakeetflow/config.json`:

```jsonc
{
  // Speech-to-Text Engine
  "stt_engine": "groq",           // "groq" (cloud) or "local_mlx" (offline)
  "groq_key": "",                 // Your Groq API key (free at console.groq.com)
  "groq_model": "whisper-large-v3",

  // LLM Polish Engine
  "provider": "groq",            // "groq", "openrouter", "ollama", "lmstudio", "local_rules"
  "use_llm_polish": true,
  "groq_polish_model": "qwen/qwen3.8-27b",

  // Custom Vocabulary (comma-separated)
  // Add domain-specific terms to improve accuracy
  "custom_vocab": "GitHub, PR, Velox, model, models",

  // Floating HUD
  "hud_position": "bottom_center", // "left", "bottom_center", "right"
  "hud_size": "compact",           // "mini", "compact", "spacious"
  "hud_character": "gearbot",      // "gearbot", "birb", "neko", "orb_gears"
  "hud_color": "amber",            // "amber", "rose", "emerald", "cyan", "purple", "monochrome"
  "hud_always_show": true           // Desktop pet companion mode
}
```

### Getting a Groq API Key (Free)

1. Go to [console.groq.com](https://console.groq.com)
2. Sign up (no credit card required)
3. Create an API key
4. Paste it in `~/.parakeetflow/config.json` or via the web dashboard

**Free tier limits**: ~2 hours of dictation per day, 25 requests/min — more than enough for daily use.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Velox.app (Swift/SwiftUI)             │
│                                                         │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ Menu Bar │  │ Floating HUD │  │ Accessibility API │  │
│  │ Popover  │  │ (Pet + Waves)│  │ (Context Capture) │  │
│  └──────────┘  └──────────────┘  └───────────────────┘  │
│         │              │                  │              │
│         └──────────────┼──────────────────┘              │
│                        │                                │
│              POST /transcribe                           │
│              {audio, context, config}                    │
└────────────────────────┼────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              parakeet_daemon.py (Python)                 │
│              http://127.0.0.1:18765                      │
│                                                         │
│  ┌─────────────────┐    ┌──────────────────────────┐    │
│  │   STT Engine     │    │   LLM Polish Engine       │    │
│  │                 │    │                          │    │
│  │ Groq LPU ──────┤    │ Groq Qwen 27B ──────────┤    │
│  │ (whisper-large- │    │ (phonetic healing,       │    │
│  │  v3, ~1.5s)     │    │  list formatting,        │    │
│  │                 │    │  self-correction)         │    │
│  │ MLX Metal ──────┤    │                          │    │
│  │ (local fallback,│    │ Local Rules ─────────────┤    │
│  │  ~8–15s on M1)  │    │ (offline, 0ms)           │    │
│  └─────────────────┘    └──────────────────────────┘    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Web Dashboard (Golden Gate Glass Studio)        │    │
│  │  History · Settings · Analytics · Provider Test  │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### File Structure

```
ParakeetFlow/
├── Sources/
│   ├── main.swift          # Native SwiftUI app (menu bar, HUD, hotkeys, paste)
│   └── cli.swift           # CLI toggle via DistributedNotificationCenter
├── parakeet_daemon.py      # Python inference daemon (STT + LLM + web dashboard)
├── build.sh                # Build, code-sign, and install script
├── Info.plist              # macOS app bundle configuration
├── AppIcon.icns            # App icon
├── assets/
│   └── banner.jpg          # GitHub banner
├── .gitignore
└── README.md
```

---

## Offline Mode

Velox works fully offline with zero cloud dependencies:

```json
{
  "stt_engine": "local_mlx",
  "provider": "local_rules",
  "use_llm_polish": false
}
```

This uses the MLX Whisper Large v3 Turbo model running entirely on your Apple Silicon GPU. No data leaves your machine.

For local LLM polish, run [Ollama](https://ollama.com) and set:
```json
{
  "stt_engine": "local_mlx",
  "provider": "ollama",
  "ollama_model": "llama3.2"
}
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **"Model is warming up"** | Wait ~5 seconds after starting the daemon for the local model to load |
| **No audio detected** | Grant microphone permission in System Settings → Privacy & Security |
| **Hotkey doesn't work** | Grant accessibility permission and restart Velox |
| **Groq returns errors** | Check your API key in `~/.parakeetflow/config.json` or the web dashboard |
| **Slow local transcription** | Expected on M1 (~8–15s). Use Groq cloud mode for ~1.5s latency |

---

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Test locally with `./build.sh && open /Applications/Velox.app`
5. Submit a pull request

### Development Setup

```bash
# Start the daemon in foreground for debugging
.venv/bin/python parakeet_daemon.py

# Rebuild and restart the app
./build.sh && open /Applications/Velox.app

# Test the transcribe endpoint directly
curl -s -X POST http://127.0.0.1:18765/transcribe \
  -H "Content-Type: application/json" \
  -d '{"audio_path": "/tmp/test.wav", "stt_engine": "groq", "groq_key": "YOUR_KEY"}'
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with ❤️ on Apple Silicon<br>
  <sub>Whisper Large v3 · Groq LPU · MLX Metal · SwiftUI</sub>
</p>
