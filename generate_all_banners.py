import os
import base64
import subprocess
import tempfile

BASE_DIR = "/Users/macbookair/Documents/GitHub/mumblr"
MASCOT_JPG = os.path.join(BASE_DIR, "assets/mascots/velox_finch_a1.jpg")
MASCOT_PNG = os.path.join(BASE_DIR, "assets/mascots/velox_finch_a1_transparent.png")
OUTPUT_DIR = os.path.join(BASE_DIR, "assets/banners")
CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

os.makedirs(OUTPUT_DIR, exist_ok=True)

with open(MASCOT_JPG, "rb") as f:
    b64_jpg = f"data:image/jpeg;base64,{base64.b64encode(f.read()).decode('utf-8')}"

with open(MASCOT_PNG, "rb") as f:
    b64_png = f"data:image/png;base64,{base64.b64encode(f.read()).decode('utf-8')}"

banners = [
    # -------------------------------------------------------------
    # 1. Warm Editorial Minimalist
    # -------------------------------------------------------------
    {
        "filename": "banner_style1_editorial.jpg",
        "html": f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    width: 1600px;
    height: 900px;
    background: #F8F5EB;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 100px;
    position: relative;
    overflow: hidden;
    color: #1A1D36;
  }}
  .bg-decor {{
    position: absolute;
    width: 800px;
    height: 800px;
    background: radial-gradient(circle, rgba(245, 219, 123, 0.45) 0%, rgba(248, 245, 235, 0) 70%);
    top: -200px;
    right: -100px;
    z-index: 1;
  }}
  .left-content {{
    max-width: 800px;
    z-index: 2;
  }}
  .eyebrow {{
    display: inline-flex;
    align-items: center;
    gap: 8px;
    background: #EDE6D3;
    padding: 8px 18px;
    border-radius: 999px;
    font-size: 15px;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #3B3F63;
    margin-bottom: 28px;
  }}
  .eyebrow-dot {{
    width: 8px;
    height: 8px;
    background: #E87A36;
    border-radius: 50%;
  }}
  h1 {{
    font-size: 96px;
    font-weight: 800;
    letter-spacing: -0.04em;
    line-height: 1.02;
    color: #151833;
    margin-bottom: 24px;
  }}
  .tagline {{
    font-size: 28px;
    font-weight: 450;
    line-height: 1.45;
    color: #4C5175;
    margin-bottom: 44px;
    max-width: 680px;
  }}
  .badges {{
    display: flex;
    flex-wrap: wrap;
    gap: 14px;
  }}
  .badge {{
    background: #FFFFFF;
    border: 1.5px solid #E4DCB8;
    box-shadow: 0 4px 16px rgba(0,0,0,0.04);
    padding: 12px 22px;
    border-radius: 14px;
    font-size: 17px;
    font-weight: 600;
    color: #24294A;
    display: flex;
    align-items: center;
    gap: 10px;
  }}
  .right-visual {{
    z-index: 2;
    display: flex;
    flex-direction: column;
    align-items: center;
    position: relative;
  }}
  .card-container {{
    width: 480px;
    height: 480px;
    border-radius: 44px;
    overflow: hidden;
    box-shadow: 0 30px 70px rgba(40, 45, 80, 0.15), 0 0 0 1px rgba(0,0,0,0.06);
    background: #EFCD6B;
    position: relative;
  }}
  .card-container img {{
    width: 100%;
    height: 100%;
    object-fit: cover;
  }}
  .floating-pill {{
    position: absolute;
    bottom: -24px;
    background: #FFFFFF;
    border-radius: 999px;
    padding: 14px 26px;
    font-size: 16px;
    font-weight: 700;
    color: #1A1D36;
    box-shadow: 0 16px 36px rgba(0,0,0,0.12);
    display: flex;
    align-items: center;
    gap: 10px;
    border: 1px solid rgba(0,0,0,0.06);
  }}
  .pulse {{
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: #27AE60;
  }}
</style>
</head>
<body>
  <div class="bg-decor"></div>
  <div class="left-content">
    <div class="eyebrow">
      <span class="eyebrow-dot"></span>
      Mumblr Desktop Dictation • Whisper Large v3
    </div>
    <h1>Mumblr</h1>
    <p class="tagline">
      Blazing-fast macOS dictation that turns your voice into publication-ready prose in under 2 seconds.
    </p>
    <div class="badges">
      <div class="badge">⌨️ ⌥ Space anywhere</div>
      <div class="badge">⚡ Groq LPU & Local Metal</div>
      <div class="badge">✨ Qwen 27B Polish</div>
      <div class="badge">🍎 Apple Silicon Native</div>
    </div>
  </div>
  <div class="right-visual">
    <div class="card-container">
      <img src="{b64_jpg}" alt="Mumblr Finch">
    </div>
    <div class="floating-pill">
      <span class="pulse"></span>
      Your Mac's favorite voice companion
    </div>
  </div>
</body>
</html>"""
    },

    # -------------------------------------------------------------
    # 2. Sleek Dark Mode / Cyber Pro
    # -------------------------------------------------------------
    {
        "filename": "banner_style2_dark_pro.jpg",
        "html": f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    width: 1600px;
    height: 900px;
    background: #0B0D14;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 110px;
    position: relative;
    overflow: hidden;
    color: #FFFFFF;
  }}
  .glow-1 {{
    position: absolute;
    width: 700px;
    height: 700px;
    background: radial-gradient(circle, rgba(58, 77, 184, 0.28) 0%, rgba(11, 13, 20, 0) 70%);
    top: -150px;
    left: 200px;
    z-index: 1;
  }}
  .glow-2 {{
    position: absolute;
    width: 600px;
    height: 600px;
    background: radial-gradient(circle, rgba(232, 122, 54, 0.22) 0%, rgba(11, 13, 20, 0) 70%);
    bottom: -150px;
    right: 150px;
    z-index: 1;
  }}
  .left-content {{
    max-width: 750px;
    z-index: 2;
  }}
  .status-badge {{
    display: inline-flex;
    align-items: center;
    gap: 10px;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid rgba(255, 255, 255, 0.12);
    padding: 8px 18px;
    border-radius: 999px;
    font-size: 14px;
    font-weight: 600;
    color: #A0AEC0;
    margin-bottom: 28px;
    backdrop-filter: blur(16px);
  }}
  .live-dot {{
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #38EF7D;
    box-shadow: 0 0 10px #38EF7D;
  }}
  h1 {{
    font-size: 92px;
    font-weight: 800;
    letter-spacing: -0.04em;
    line-height: 1.05;
    margin-bottom: 22px;
    background: linear-gradient(135deg, #FFFFFF 40%, #A5B4FC 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }}
  .subtitle {{
    font-size: 26px;
    font-weight: 400;
    line-height: 1.5;
    color: #94A3B8;
    margin-bottom: 40px;
  }}
  .spec-grid {{
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 16px;
    max-width: 640px;
  }}
  .spec-item {{
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 16px;
    padding: 16px 20px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }}
  .spec-val {{
    font-size: 20px;
    font-weight: 700;
    color: #F8FAFC;
  }}
  .spec-lbl {{
    font-size: 13px;
    color: #64748B;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }}
  .right-visual {{
    z-index: 2;
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
  }}
  .hud-card {{
    background: rgba(20, 24, 38, 0.7);
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 36px;
    padding: 36px;
    box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
    backdrop-filter: blur(28px);
    display: flex;
    flex-direction: column;
    align-items: center;
    position: relative;
  }}
  .mascot-avatar {{
    width: 320px;
    height: 320px;
    border-radius: 32px;
    overflow: hidden;
    margin-bottom: 24px;
    box-shadow: 0 12px 30px rgba(0, 0, 0, 0.4);
  }}
  .mascot-avatar img {{
    width: 100%;
    height: 100%;
    object-fit: cover;
  }}
  .wave-bar {{
    display: flex;
    align-items: center;
    gap: 6px;
    height: 32px;
    background: rgba(0, 0, 0, 0.35);
    padding: 6px 18px;
    border-radius: 999px;
    border: 1px solid rgba(255, 255, 255, 0.08);
  }}
  .bar {{
    width: 4px;
    border-radius: 2px;
    background: #E87A36;
  }}
</style>
</head>
<body>
  <div class="glow-1"></div>
  <div class="glow-2"></div>
  <div class="left-content">
    <div class="status-badge">
      <span class="live-dot"></span>
      Whisper Large v3 • Groq LPU Engine
    </div>
    <h1>Mumblr</h1>
    <p class="subtitle">
      Zero latency speech-to-text with intelligent LLM punctuation, self-correction, and auto-paste at cursor.
    </p>
    <div class="spec-grid">
      <div class="spec-item">
        <span class="spec-val">&lt; 1.5s</span>
        <span class="spec-lbl">Full Transcription Latency</span>
      </div>
      <div class="spec-item">
        <span class="spec-val">Whisper Large v3</span>
        <span class="spec-lbl">Cloud LPU + MLX Fallback</span>
      </div>
      <div class="spec-item">
        <span class="spec-val">Qwen 27B</span>
        <span class="spec-lbl">Context-Aware Polish Engine</span>
      </div>
      <div class="spec-item">
        <span class="spec-val">0ms Latency</span>
        <span class="spec-lbl">Offline Regex Rules Mode</span>
      </div>
    </div>
  </div>
  <div class="right-visual">
    <div class="hud-card">
      <div class="mascot-avatar">
        <img src="{b64_jpg}" alt="Mumblr Finch">
      </div>
      <div class="wave-bar">
        <span style="font-size:13px; font-weight:600; color:#CBD5E1; margin-right:8px;">MIC LIVE</span>
        <div class="bar" style="height: 14px;"></div>
        <div class="bar" style="height: 24px;"></div>
        <div class="bar" style="height: 18px;"></div>
        <div class="bar" style="height: 28px;"></div>
        <div class="bar" style="height: 12px;"></div>
        <div class="bar" style="height: 20px;"></div>
        <div class="bar" style="height: 8px;"></div>
      </div>
    </div>
  </div>
</body>
</html>"""
    },

    # -------------------------------------------------------------
    # 3. Playful Voice Companion & Soundwave Pop
    # -------------------------------------------------------------
    {
        "filename": "banner_style3_playful.jpg",
        "html": f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    width: 1600px;
    height: 900px;
    background: #181926;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Rounded", "Comic Neue", sans-serif;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 120px;
    position: relative;
    overflow: hidden;
    color: #FFFFFF;
  }}
  .sparkle {{
    position: absolute;
    color: #F6C177;
    font-size: 32px;
  }}
  .left-mascot-side {{
    z-index: 2;
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
  }}
  .mascot-frame {{
    width: 440px;
    height: 440px;
    border-radius: 50%;
    background: #EFCD6B;
    overflow: hidden;
    box-shadow: 0 25px 60px rgba(0, 0, 0, 0.4), 0 0 0 12px rgba(255, 255, 255, 0.08);
    position: relative;
  }}
  .mascot-frame img {{
    width: 100%;
    height: 100%;
    object-fit: cover;
  }}
  .speech-bubble {{
    position: absolute;
    top: -20px;
    right: -30px;
    background: #FFFFFF;
    color: #181926;
    font-size: 20px;
    font-weight: 800;
    padding: 14px 26px;
    border-radius: 26px;
    box-shadow: 0 12px 30px rgba(0,0,0,0.25);
    border: 3px solid #181926;
    display: flex;
    align-items: center;
    gap: 8px;
  }}
  .right-info {{
    max-width: 760px;
    z-index: 2;
  }}
  .title-row {{
    display: flex;
    align-items: baseline;
    gap: 20px;
    margin-bottom: 16px;
  }}
  h1 {{
    font-size: 100px;
    font-weight: 900;
    letter-spacing: -0.03em;
    color: #F8F5EB;
    text-shadow: 0 4px 20px rgba(0,0,0,0.3);
  }}
  .alt-name {{
    font-size: 38px;
    font-weight: 700;
    color: #E87A36;
    background: rgba(232, 122, 54, 0.15);
    padding: 6px 18px;
    border-radius: 14px;
  }}
  .lead {{
    font-size: 32px;
    font-weight: 600;
    color: #CAD3F5;
    line-height: 1.35;
    margin-bottom: 38px;
  }}
  .companion-features {{
    display: flex;
    flex-direction: column;
    gap: 14px;
  }}
  .feat-row {{
    display: flex;
    align-items: center;
    gap: 16px;
    background: rgba(255, 255, 255, 0.06);
    padding: 14px 24px;
    border-radius: 20px;
    font-size: 19px;
    font-weight: 600;
    color: #EDEFFB;
    border: 1px solid rgba(255, 255, 255, 0.08);
  }}
  .feat-icon {{
    font-size: 24px;
  }}
</style>
</head>
<body>
  <div class="sparkle" style="top: 80px; left: 140px;">✦</div>
  <div class="sparkle" style="top: 180px; right: 120px;">★</div>
  <div class="sparkle" style="bottom: 100px; left: 480px;">♪</div>
  <div class="sparkle" style="bottom: 80px; right: 280px;">♫</div>

  <div class="left-mascot-side">
    <div class="mascot-frame">
      <img src="{b64_jpg}" alt="Mumblr Finch">
    </div>
    <div class="speech-bubble">
      🎙️ Mumble away!
    </div>
  </div>

  <div class="right-info">
    <div class="title-row">
      <h1>Mumblr</h1>
      <span class="alt-name">Speech-to-Text</span>
    </div>
    <p class="lead">
      Your Mac's favorite voice companion. Press ⌥ Space and speak at the speed of thought.
    </p>
    <div class="companion-features">
      <div class="feat-row">
        <span class="feat-icon">👀</span>
        <span>Live cursor tracking & interactive side-eye reactions</span>
      </div>
      <div class="feat-row">
        <span class="feat-icon">⚡</span>
        <span>Whisper Large v3 transcription in under 2 seconds</span>
      </div>
      <div class="feat-row">
        <span class="feat-icon">📋</span>
        <span>Auto-pastes polished text directly into any macOS app</span>
      </div>
    </div>
  </div>
</body>
</html>"""
    },

    # -------------------------------------------------------------
    # 4. macOS Native Glassmorphic
    # -------------------------------------------------------------
    {
        "filename": "banner_style4_glassmorphic.jpg",
        "html": f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    width: 1600px;
    height: 900px;
    background: linear-gradient(135deg, #7FA0FB 0%, #B99AF7 50%, #F5CE9B 100%);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
    overflow: hidden;
  }}
  .window-card {{
    width: 1360px;
    height: 680px;
    background: rgba(255, 255, 255, 0.72);
    border-radius: 36px;
    border: 1.5px solid rgba(255, 255, 255, 0.85);
    box-shadow: 0 40px 100px rgba(28, 35, 75, 0.22), 0 10px 30px rgba(0, 0, 0, 0.05);
    backdrop-filter: blur(50px);
    display: flex;
    flex-direction: column;
    padding: 32px 50px;
    position: relative;
  }}
  .traffic-lights {{
    display: flex;
    gap: 10px;
    margin-bottom: 24px;
  }}
  .light {{
    width: 14px;
    height: 14px;
    border-radius: 50%;
  }}
  .red {{ background: #FF5F56; }}
  .yellow {{ background: #FFBD2E; }}
  .green {{ background: #27C93F; }}
  .window-body {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex: 1;
  }}
  .text-side {{
    max-width: 680px;
  }}
  .pill-status {{
    display: inline-flex;
    align-items: center;
    gap: 8px;
    background: rgba(255, 255, 255, 0.9);
    padding: 8px 18px;
    border-radius: 999px;
    font-size: 15px;
    font-weight: 600;
    color: #334155;
    margin-bottom: 24px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.06);
  }}
  h1 {{
    font-size: 78px;
    font-weight: 800;
    color: #1E293B;
    letter-spacing: -0.03em;
    line-height: 1.05;
    margin-bottom: 20px;
  }}
  .desc {{
    font-size: 24px;
    color: #475569;
    line-height: 1.45;
    margin-bottom: 36px;
  }}
  .shortcut-card {{
    display: inline-flex;
    align-items: center;
    gap: 14px;
    background: #0F172A;
    color: #FFFFFF;
    padding: 14px 26px;
    border-radius: 18px;
    font-size: 18px;
    font-weight: 600;
    box-shadow: 0 10px 25px rgba(15, 23, 42, 0.25);
  }}
  .keycap {{
    background: #334155;
    padding: 6px 12px;
    border-radius: 8px;
    font-size: 16px;
    border: 1px solid #475569;
  }}
  .mascot-side {{
    display: flex;
    align-items: center;
    justify-content: center;
  }}
  .mascot-bubble {{
    width: 440px;
    height: 440px;
    border-radius: 36px;
    overflow: hidden;
    box-shadow: 0 20px 50px rgba(0, 0, 0, 0.12);
  }}
  .mascot-bubble img {{
    width: 100%;
    height: 100%;
    object-fit: cover;
  }}
</style>
</head>
<body>
  <div class="window-card">
    <div class="traffic-lights">
      <div class="light red"></div>
      <div class="light yellow"></div>
      <div class="light green"></div>
    </div>
    <div class="window-body">
      <div class="text-side">
        <div class="pill-status">
          🎙️ Menu Bar Resident • Native macOS App
        </div>
        <h1>Speak naturally.<br>Paste instantly.</h1>
        <p class="desc">
          Mumblr captures your voice, polishes punctuation and filler words via LLM, and inserts publication-ready prose at your cursor.
        </p>
        <div class="shortcut-card">
          <span>Global Hotkey:</span>
          <span class="keycap">⌥ Option</span>
          <span class="keycap">Space</span>
        </div>
      </div>
      <div class="mascot-side">
        <div class="mascot-bubble">
          <img src="{b64_jpg}" alt="Mumblr Finch">
        </div>
      </div>
    </div>
  </div>
</body>
</html>"""
    },

    # -------------------------------------------------------------
    # 5. Flow Mode & Deep Work Sprint
    # -------------------------------------------------------------
    {
        "filename": "banner_style5_flow_focus.jpg",
        "html": f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    width: 1600px;
    height: 900px;
    background: #0E1324;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 110px;
    position: relative;
    overflow: hidden;
    color: #F8FAFC;
  }}
  .halo {{
    position: absolute;
    width: 800px;
    height: 800px;
    background: radial-gradient(circle, rgba(239, 205, 107, 0.18) 0%, rgba(14, 19, 36, 0) 70%);
    left: -100px;
    top: 50px;
    z-index: 1;
  }}
  .left-side {{
    z-index: 2;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 24px;
  }}
  .mascot-wrapper {{
    width: 380px;
    height: 380px;
    border-radius: 40px;
    overflow: hidden;
    background: #EFCD6B;
    box-shadow: 0 25px 70px rgba(0, 0, 0, 0.5), 0 0 0 2px rgba(239, 205, 107, 0.3);
  }}
  .mascot-wrapper img {{
    width: 100%;
    height: 100%;
    object-fit: cover;
  }}
  .timer-pill {{
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.15);
    border-radius: 999px;
    padding: 12px 28px;
    display: flex;
    align-items: center;
    gap: 12px;
    font-size: 20px;
    font-weight: 700;
    color: #F8FAFC;
    backdrop-filter: blur(20px);
  }}
  .timer-dot {{
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: #E87A36;
    box-shadow: 0 0 12px #E87A36;
  }}
  .right-side {{
    max-width: 800px;
    z-index: 2;
  }}
  .eyebrow-tag {{
    font-size: 15px;
    font-weight: 700;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: #EFCD6B;
    margin-bottom: 20px;
  }}
  h1 {{
    font-size: 88px;
    font-weight: 850;
    line-height: 1.05;
    letter-spacing: -0.04em;
    margin-bottom: 24px;
    color: #FFFFFF;
  }}
  .flow-desc {{
    font-size: 26px;
    color: #94A3B8;
    line-height: 1.45;
    margin-bottom: 44px;
  }}
  .flow-presets {{
    display: flex;
    gap: 14px;
    margin-bottom: 36px;
  }}
  .preset {{
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    padding: 14px 22px;
    border-radius: 16px;
    font-size: 16px;
    font-weight: 600;
    color: #E2E8F0;
  }}
  .active-preset {{
    background: rgba(239, 205, 107, 0.15);
    border-color: #EFCD6B;
    color: #EFCD6B;
  }}
  .quote {{
    border-left: 3px solid #E87A36;
    padding-left: 18px;
    font-size: 18px;
    font-style: italic;
    color: #CBD5E1;
  }}
</style>
</head>
<body>
  <div class="halo"></div>
  <div class="left-side">
    <div class="mascot-wrapper">
      <img src="{b64_jpg}" alt="Mumblr Finch">
    </div>
    <div class="timer-pill">
      <span class="timer-dot"></span>
      <span>25:00 • Focus Sprint</span>
    </div>
  </div>
  <div class="right-side">
    <div class="eyebrow-tag">⚡ Flow Mode & Pomodoro Companion</div>
    <h1>Lock in.<br>Stay in flow.</h1>
    <p class="flow-desc">
      Right-click your companion to launch focus sessions. Dictate insights without breaking mental immersion or touching your keyboard.
    </p>
    <div class="flow-presets">
      <div class="preset active-preset">25m Focus Sprint</div>
      <div class="preset">45m Deep Work</div>
      <div class="preset">60m Flow State</div>
    </div>
    <div class="quote">
      "Your desktop pet keeps you anchored while transcribing thoughts in real-time."
    </div>
  </div>
</body>
</html>"""
    }
]

for idx, b in enumerate(banners, 1):
    html_content = b["html"]
    out_path = os.path.join(OUTPUT_DIR, b["filename"])
    
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as tmp:
        tmp.write(html_content)
        tmp_path = tmp.name
        
    cmd = [
        CHROME_BIN,
        "--headless=new",
        "--disable-gpu",
        "--screenshot=" + out_path,
        "--window-size=1600,900",
        "--default-background-color=00000000",
        f"file://{tmp_path}"
    ]
    subprocess.run(cmd, check=True)
    os.remove(tmp_path)
    print(f"Generated Style {idx}: {out_path}")

print("All 5 banners successfully generated!")
