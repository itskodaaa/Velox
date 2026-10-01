#!/usr/bin/env python3
"""
WhisperFlow High-Accuracy Dictation Daemon & Luxury Golden Gate Glass Studio
Uses OpenAI Whisper Large v3 Turbo on Apple Silicon Metal GPU (MLX)
with Wispr-style smart formatting, Local LLMs (Ollama / LM Studio / Bionic),
OpenRouter live balance tracking, folded accordion UI, and custom HUD controls.
"""
from datetime import datetime
import html
import json
import os
import queue
import re
import sys
import threading
import time
from collections import Counter
from typing import Optional
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse
import httpx
import mlx.core as mx
import mlx_whisper
import numpy as np
import soundfile as sf
import wave

PORT = int(os.environ.get("PARAKEET_PORT", "18765"))
MODEL_ID = "mlx-community/whisper-large-v3-turbo"

HTTP_CLIENT = httpx.Client(timeout=8.0)

HISTORY_DIR = Path.home() / ".parakeetflow"
HISTORY_FILE = HISTORY_DIR / "history.json"
CONFIG_FILE = HISTORY_DIR / "config.json"

DEFAULT_CONFIG = {
    "provider": "groq",  # "groq", "local_rules", "lmstudio", "ollama", "openrouter"
    "use_llm_polish": True,
    "stt_engine": "groq",  # "groq", "local_mlx"
    "groq_key": "",
    "groq_model": "whisper-large-v3",
    "groq_polish_model": "qwen/qwen3.8-27b",
    "openrouter_key": "",
    "openrouter_model": "meta/muse-spark-1.3-contributor",
    "ollama_url": "http://127.0.0.1:11434",
    "ollama_model": "llama3.2",
    "lmstudio_url": "http://127.0.0.1:1234",
    "lmstudio_model": "local-model",
    "custom_vocab": "how far, abeg, naira, GitHub, PR, Velox",
    "hud_position": "bottom_center",  # "left", "bottom_center", "right"
    "hud_size": "compact",     # "mini", "compact", "spacious"
    "hud_character": "gearbot", # "gearbot", "neko", "luna", "kuro", "custom"
    "hud_color": "amber",      # "amber", "rose", "emerald", "cyan", "purple", "monochrome"
    "hud_listening_style": "morph", # "morph", "character", "waveform"
}


def load_config() -> dict:
    if not CONFIG_FILE.exists():
        save_config(DEFAULT_CONFIG)
        return DEFAULT_CONFIG.copy()
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            cfg = json.load(f)
            for k, v in DEFAULT_CONFIG.items():
                if k not in cfg:
                    cfg[k] = v
            return cfg
    except Exception:
        return DEFAULT_CONFIG.copy()


def save_config(cfg: dict):
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[Config] Save error: {e}", flush=True)


def load_history() -> list:
    if not HISTORY_FILE.exists():
        return []
    try:
        with open(HISTORY_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def save_history(items: list):
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with open(HISTORY_FILE, "w", encoding="utf-8") as f:
            json.dump(items, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[History] Save error: {e}", flush=True)


def add_history_entry(item: dict):
    history = load_history()
    history.insert(0, item)
    if len(history) > 400:
        history = history[:400]
    save_history(history)


def delete_history_item(item_id: str):
    history = [h for h in load_history() if str(h.get("id")) != str(item_id)]
    save_history(history)


def clear_all_history():
    save_history([])


def check_openrouter_balance(api_key: str) -> dict:
    key = (api_key or "").strip()
    if not key:
        return {"valid": False, "error": "No API key entered. Paste your key in Settings."}

    headers = {
        "Authorization": f"Bearer {key}",
        "HTTP-Referer": "https://parakeetflow.local",
        "X-Title": "WhisperFlow",
    }

    try:
        r_auth = HTTP_CLIENT.get("https://openrouter.ai/api/v1/auth/key", headers=headers)
        if r_auth.status_code == 401:
            return {
                "valid": False,
                "status_code": 401,
                "error": "HTTP 401: User not found. The key may be revoked, deleted, or mistyped. Get a fresh key at openrouter.ai/keys.",
            }
        elif r_auth.status_code != 200:
            return {
                "valid": False,
                "status_code": r_auth.status_code,
                "error": f"OpenRouter returned HTTP {r_auth.status_code}",
            }

        auth_data = r_auth.json().get("data", {})
        total_usage = float(auth_data.get("usage", 0.0))

        # Check credits
        r_cred = HTTP_CLIENT.get("https://openrouter.ai/api/v1/credits", headers=headers)
        total_credits = 0.0
        if r_cred.status_code == 200:
            cred_data = r_cred.json().get("data", {})
            total_credits = float(cred_data.get("total_credits", 0.0))
            if "total_usage" in cred_data:
                total_usage = float(cred_data.get("total_usage", total_usage))

        remaining = max(0.0, total_credits - total_usage)
        return {
            "valid": True,
            "label": auth_data.get("label", "Primary Key"),
            "total_credits": round(total_credits, 4),
            "total_usage": round(total_usage, 4),
            "balance": round(remaining, 4),
            "limit": auth_data.get("limit"),
            "is_free_tier": auth_data.get("is_free_tier", False),
        }
    except Exception as e:
        return {"valid": False, "error": str(e)}


def test_provider_connection(cfg: dict) -> dict:
    provider = cfg.get("provider", "groq")
    if provider == "groq":
        key = (cfg.get("groq_key") or "").strip()
        if not key:
            return {"valid": False, "error": "Groq API key is missing"}
        try:
            r = HTTP_CLIENT.get("https://api.groq.com/openai/v1/models", headers={"Authorization": f"Bearer {key}"}, timeout=4.0)
            if r.status_code == 200:
                return {
                    "valid": True,
                    "provider": "groq",
                    "message": "Connected to Groq Cloud LPU (Whisper Large v3 + Qwen 3.8-27B ready).",
                }
            return {"valid": False, "error": f"Groq returned HTTP {r.status_code}: {r.text[:100]}"}
        except Exception as e:
            return {"valid": False, "error": f"Could not connect to Groq: {e}"}
    elif provider == "openrouter":
        key = (cfg.get("openrouter_key") or cfg.get("key") or "").strip()
        return check_openrouter_balance(key)
    elif provider == "ollama":
        url = cfg.get("ollama_url", "http://127.0.0.1:11434").rstrip("/")
        try:
            r = HTTP_CLIENT.get(f"{url}/api/tags", timeout=3.0)
            if r.status_code == 200:
                models = [m.get("name") for m in r.json().get("models", [])]
                return {
                    "valid": True,
                    "provider": "ollama",
                    "models": models,
                    "message": f"Connected to Ollama. {len(models)} model(s) available.",
                }
            return {"valid": False, "error": f"Ollama returned HTTP {r.status_code}"}
        except Exception as e:
            return {"valid": False, "error": f"Could not connect to Ollama at {url}: {e}"}
    elif provider == "lmstudio":
        url = cfg.get("lmstudio_url", "http://127.0.0.1:1234").rstrip("/")
        try:
            r = HTTP_CLIENT.get(f"{url}/v1/models", timeout=3.0)
            if r.status_code == 200:
                models = [m.get("id") for m in r.json().get("data", [])]
                return {
                    "valid": True,
                    "provider": "lmstudio",
                    "models": models,
                    "message": f"Connected to LM Studio / Bionic. {len(models)} model(s) loaded.",
                }
            return {"valid": False, "error": f"LM Studio returned HTTP {r.status_code}"}
        except Exception as e:
            return {"valid": False, "error": f"Could not connect to LM Studio at {url}: {e}"}
    else:
        return {"valid": True, "message": "Using local offline Wispr rule-based formatting engine (0ms extra latency)."}


def calculate_cost(word_count: int, model: str, provider: str, used_llm: bool) -> tuple[float, str]:
    if not used_llm or provider in ("local_rules", "ollama", "lmstudio", "groq"):
        label = "⚡ Free (Groq LPU)" if provider == "groq" else ("⚡ Free (Local Metal)" if not used_llm else f"⚡ Free (Local {provider.capitalize()})")
        return 0.0, label
    tokens = int(word_count * 1.33) + 70
    cost = tokens * 0.00000015
    if cost < 0.0001:
        return round(cost, 6), f"💎 <$0.0001 (~${cost:.5f})"
    else:
        return round(cost, 5), f"💎 ${cost:.4f}"


def sanitize_custom_vocab(custom_vocab_raw: str) -> Optional[str]:
    """
    Sanitize custom vocabulary for Whisper's initial_prompt.
    Whisper's autoregressive decoder interprets comma-separated lists of numbers or symbols
    as sequence completion tasks, which induces infinite repetition loops (e.g. '1k, 2k, 4k' -> '3k, 3k, 3k...').
    This function strips numbers, short abbreviations, and formats valid custom terms as a glossary prompt.
    """
    if not custom_vocab_raw or not isinstance(custom_vocab_raw, str):
        return None
    raw_parts = [p.strip() for p in custom_vocab_raw.split(",") if p.strip()]
    cleaned_terms = []
    for part in raw_parts:
        # Reject standalone numbers, prices, or digit combos (e.g. '1k', '2k', '4k', '100', '1st', '50%')
        if re.match(r"^\d+[a-zA-Z%]*$", part):
            continue
        # Reject single character tokens
        if len(part) <= 1:
            continue
        cleaned_terms.append(part)

    if not cleaned_terms:
        return None

    return f"{', '.join(cleaned_terms)}."


def sanitize_transcription(raw_text: str, duration_sec: float = 0.0, rms: float = 100.0) -> str:
    """
    Detect and eliminate Whisper autoregressive repetition loops, silence hallucinations,
    and ghost outputs (e.g. 'The.', 'You.', '3k, 3k, 3k...').
    """
    if not raw_text:
        return ""
    text = raw_text.strip()

    # 1. Hallucination silence patterns: Whisper ghost outputs on silence or background noise
    phantom_exact = {
        "the", "the.", "you", "you.", "a", "a.", "an", "an.", "so", "so.",
        "oh", "oh.", "uh", "um", "ah", "okay", "okay.", "yes", "yes.", "no", "no.",
        "thank you", "thank you.", "thanks for watching", "thanks for watching.",
        "thank you for watching", "thank you for watching.", "subscribe", "subscribe.",
        "please subscribe", "please subscribe.", "bye", "bye.", "bye bye", "bye bye.",
        "...", "..", ".", "♪", "[music]", "(music)", "[applause]", "[laughter]"
    }

    clean_lower = text.lower().strip()
    if clean_lower in phantom_exact:
        # If the recording was longer than 0.9s and produced only a single phantom word, or audio energy was low
        if duration_sec > 0.9 or rms < 85.0 or clean_lower in ("the", "the.", "a", "a.", "an", "an.", "...", "..", ".", "thank you for watching", "thank you for watching.", "subscribe", "subscribe."):
            print(f"[Sanitize] Suppressed phantom silence hallucination '{text}' (duration={duration_sec:.1f}s, rms={rms:.1f})", flush=True)
            return ""

    # Check if text is solely bracketed audio labels e.g. [Music], (Laughter), [Applause]
    if re.match(r"^[\(\[\{].*?[\)\]\}]$", text):
        return ""

    # Strip trailing YouTube silence hallucinations from the end of sentences (common Whisper artifact)
    text = re.sub(r"(?i)\s*(?:thanks|thank you)\s+for\s+watching[!.]*$", "", text).strip()
    text = re.sub(r"(?i)\s*(?:please\s+)?subscribe(?:\s+to\s+(?:the|my)\s+channel)?[!.]*$", "", text).strip()

    # 2. De-loop immediate consecutive identical token repeats (e.g. '3k, 3k, 3k, 3k' -> '3k')
    # Match any word base repeating 3 or more times consecutively with optional punctuation
    def repl_token(m):
        full = m.group(0).rstrip()
        word = m.group(1)
        end_punct = full[-1] if (full and full[-1] in ".,!?;:") else ""
        return word + end_punct

    text = re.sub(r"\b([\w\'-]+)[,\.\?!;:]*(?:\s+\1[,\.\?!;:]*){2,}", repl_token, text, flags=re.IGNORECASE)

    # 3. Multi-word phrase repeats (2 to 8 word phrases repeated 3 or more times consecutively)
    for n in range(8, 1, -1):
        pattern = re.compile(
            r"(\b(?:[\w\'-]+[,\.\?!;:]*\s+){" + str(n - 1) + r"}[\w\'-]+)[,\.\?!;:]*(?:\s+\1[,\.\?!;:]*){2,}",
            re.IGNORECASE,
        )
        def repl_phrase(m):
            full = m.group(0).rstrip()
            word = m.group(1)
            end_punct = full[-1] if (full and full[-1] in ".,!?;:") else ""
            return word + end_punct
        text = pattern.sub(repl_phrase, text)

    # 4. Global repetition density / sequence continuation loops
    # Catches progressions like '3k, 4k, 4k, 4k... 5k, 5k... 6k, 6k...'
    words = [re.sub(r"[^\w]", "", w.lower()) for w in text.split() if re.sub(r"[^\w]", "", w.lower())]
    if len(words) >= 6:
        counts = Counter(words)
        most_common_word, top_freq = counts.most_common(1)[0]
        unique_ratio = len(set(words)) / len(words)

        # If a single word dominates > 35% of a long transcript, or lexical diversity drops below 0.25
        if (top_freq / len(words) > 0.35 and top_freq >= 3) or unique_ratio < 0.25:
            tokens = text.split()
            first_loop_idx = -1
            seen = []
            for i, tok in enumerate(tokens):
                clean_tok = re.sub(r"[^\w]", "", tok.lower())
                if seen.count(clean_tok) >= 2 and i >= 2 and re.sub(r"[^\w]", "", tokens[i - 1].lower()) == clean_tok:
                    first_loop_idx = i - 1
                    break
                seen.append(clean_tok)
            if first_loop_idx > 0:
                print(f"[Sanitize] Truncated repetition loop at word {first_loop_idx} (top_word='{most_common_word}', freq={top_freq}/{len(words)})", flush=True)
                text = " ".join(tokens[:first_loop_idx])
            else:
                text = " ".join(tokens[:3])

    return text.strip()


def wispr_smart_format(text: str) -> str:
    """Enhanced rule-based formatter with natural sentence punctuation, question detection, and list formatting."""
    if not text:
        return ""
    t = text.strip()

    # 1. Strip trailing spoken meta-talk / placeholders
    t = re.sub(r"\s*(in order to\s+)?(blah(\s+blah)*|etc|whatever|and so on)\.?\s*$", "", t, flags=re.IGNORECASE)

    # 2. Remove filler words (um, uh, erm)
    t = re.sub(r"\b(um+|uh+|erm+)\b[,\s]*", "", t, flags=re.IGNORECASE)

    # 3. Fix stuttered repeated words ("I just I just" -> "I just")
    t = re.sub(r"\b(\w+)(?:\s+\1\b)+", r"\1", t, flags=re.IGNORECASE)

    # 4. Clean errant mid-sentence periods after am/pm: "3 pm. instead" -> "3 PM instead"
    t = re.sub(r"\b(\d+)\s*(am|pm)\.\s+([a-z])", r"\1 \2 \3", t, flags=re.IGNORECASE)
    t = re.sub(r"\b(\d+)\s*am\b", r"\1 AM", t, flags=re.IGNORECASE)
    t = re.sub(r"\b(\d+)\s*pm\b", r"\1 PM", t, flags=re.IGNORECASE)

    # 5. Fix acoustic confusion of "module" for "model" in AI/software speech
    t = re.sub(r"\b(bigger|smaller|large|larger|AI|ML|speech|language|Whisper|Qwen|LLM|Muse|foundational|new|this|that|the)\s+module(s)?\b", r"\1 model\2", t, flags=re.IGNORECASE)
    t = re.sub(r"\bmodule(s)?\s+(training|inference|weights|architecture|accuracy|parameters)\b", r"model\1 \2", t, flags=re.IGNORECASE)

    # 6. Fix common developer and technical names
    tech_map = {
        r"\bgithub\b": "GitHub",
        r"\bjavascript\b": "JavaScript",
        r"\btypescript\b": "TypeScript",
        r"\bmacos\b": "macOS",
        r"\bapi\b": "API",
        r"\bui\b": "UI",
        r"\bai\b": "AI",
        r"\bvscode\b": "VSCode",
        r"\bhtml\b": "HTML",
        r"\bcss\b": "CSS",
        r"\bopenrouter\b": "OpenRouter",
        r"\bwhisperflow\b": "WhisperFlow",
        r"\bnaira\b": "Naira",
        r"\bollama\b": "Ollama",
    }
    for pat, repl in tech_map.items():
        t = re.sub(pat, repl, t, flags=re.IGNORECASE)

    # 6. Fix glued punctuation: "professional.But" -> "professional. But", "works.And" -> "works. And"
    t = re.sub(r"([.?!,;:])([A-Za-z])", r"\1 \2", t)

    # 7. First-person pronoun capitalization
    t = re.sub(r"\b(i)\b", "I", t)
    t = re.sub(r"\bi'm\b", "I'm", t, flags=re.IGNORECASE)
    t = re.sub(r"\bi've\b", "I've", t, flags=re.IGNORECASE)
    t = re.sub(r"\bi'll\b", "I'll", t, flags=re.IGNORECASE)
    t = re.sub(r"\bi'd\b", "I'd", t, flags=re.IGNORECASE)

    # 8. Numbered list headers: "Test number 1." or "Test 1."
    t = re.sub(r"(?i)(?:^|[.!?]\s*)(test|scenario|section|part)\s*(?:number\s*)?(\d+)[:\.\s]*", r"\n\n\1 \2:\n", t)
    t = re.sub(r"(?i)\n\n(test|scenario|section|part) ", lambda m: f"\n\n{m.group(1).capitalize()} ", t)

    # 9. List introduction clause: "Here are the three tasks for today:"
    t = re.sub(
        r"(?i)(here (?:are|is) (?:the\s+)?(?:three|four|five|six|several|few|\d+)?\s*(?:tasks|things|items|updates|points|steps)[^\n.!?:]*)[.!?:]*\s*",
        r"\1:\n",
        t,
    )

    # 10. Numbered list items (only when followed by a letter, never decimal numbers like 4.6 or 3.14)
    t = re.sub(r"(?i)(?<=:)\s*\n?\s*(?:number|step|point|item|bullet\s+)?(\d+)[:\.\)]\s+(?=[A-Za-z])", r"\n\1. ", t)
    t = re.sub(r"(?i)(?:^|(?<!\d)[.!?]\s+|\n\s*)(?:number|step|point|item|bullet\s+)?(\d+)[:\.\)]\s+(?=[A-Za-z])", r"\n\1. ", t)

    # Ensure no duplicate colons anywhere
    t = re.sub(r":{2,}", ":", t)
    t = re.sub(r":\s*:\s*", ":", t)
    t = re.sub(r":\s*\n\s*:", ":\n", t)

    # 11. Conversational questions:
    t = re.sub(r"(?i)\b(is it possible\b[^.!?\n]*?)\.(?=\s|$)", r"\1?", t)
    t = re.sub(r"(?i)\b(can we\b[^.!?\n]*?)\.(?=\s|$)", r"\1?", t)
    t = re.sub(r"(?i)\b(could you\b[^.!?\n]*?)\.(?=\s|$)", r"\1?", t)
    t = re.sub(r"(?i)\b(why (?:is|are|did|does|do)\b[^.!?\n]*?)\.(?=\s|$)", r"\1?", t)
    t = re.sub(r"(?i)\b(pretty cheap|isn't it|aren't they|right)\s*[.]?\s*$", r", right?", t)

    # 12. Format each line cleanly & capitalize sentences
    lines = []
    for raw_line in t.split("\n"):
        line = raw_line.strip()
        if not line:
            if lines and lines[-1] != "":
                lines.append("")
            continue
        line = re.sub(r"\s{2,}", " ", line)

        # Capitalize sentences
        line = re.sub(r"(?:^|[.!?]\s+)([a-z])", lambda m: m.group(0).upper(), line)

        # Capitalize first letter of item after "1. "
        m = re.match(r"^(\d+\.\s*)([a-z])(.*)$", line)
        if m:
            line = m.group(1) + m.group(2).upper() + m.group(3)
        elif line and line[0].islower():
            line = line[0].upper() + line[1:]

        # Ensure sentence punctuation at end of list item if missing
        if re.match(r"^\d+\.", line) and not line.endswith((".", "!", "?", ";", ":")):
            line += "."

        lines.append(line)

    if lines and not lines[-1].endswith((".", "!", "?", ":")):
        lines[-1] += "."

    result = "\n".join(lines).strip()
    return result


def polish_text_unified(raw_text: str, cfg: dict) -> tuple[str, float, str]:
    """Unified LLM polisher supporting OpenRouter, Ollama, LM Studio / Bionic, or local rules."""
    if not raw_text.strip():
        return raw_text, 0.0, "skipped_empty"

    provider = cfg.get("provider", "openrouter")
    custom_vocab = cfg.get("custom_vocab", "")

    if provider == "local_rules" or not cfg.get("use_llm_polish", True):
        return wispr_smart_format(raw_text), 0.0, "local_rules"

    sys_msg = (
        "You are an ultra-fast, professional voice dictation post-processor (like Wispr Flow / Apple Intelligence). "
        "Transform raw speech-to-text into publication-quality written text:\n"
        "1. Punctuation: Add natural commas, periods, question marks, and capitalization. Fix run-on sentences into crisp prose.\n"
        "2. Structure: Put numbered lists (1., 2., 3.) and bullet points on separate new lines. Keep short introductory labels like 'Test 1:' or 'Part 1:' inline with their sentence rather than breaking them into orphaned single-word lines.\n"
        "3. Spoken correction: Resolve mid-sentence self-corrections (e.g., 'meet at 10 actually make that 3' -> 'meet at 3 PM').\n"
        "4. Verbal fillers: Seamlessly remove verbal fillers ('um', 'uh', 'you know', 'in order to blah').\n"
        "5. Phonetic & Slang Healing: Acoustic STT often mishears accented words or colloquial slang as similar English words. Cross-reference with the Custom Vocabulary / context hints to repair obvious phonetic STT slips (e.g. 'half hour abeg' -> 'How far, abeg'; 'nearer' near money -> 'naira'; 'wicked' -> 'wicked'; in AI, tech, or programming contexts, restore 'model/models' when STT mishears it as 'module/modules', such as 'bigger module' -> 'bigger model', 'Whisper module' -> 'Whisper model', or 'language module' -> 'language model').\n"
        "6. Tone & Completeness: Retain 100% of the speaker's original vocabulary, colloquialisms, and intent. Never summarize, omit facts, or invent words.\n"
        "7. Output: Return ONLY the polished text with no conversational preamble, no quotes, and no commentary."
    )
    if custom_vocab.strip():
        sys_msg += f"\nCustom vocabulary / context hints: {custom_vocab.strip()}"

    t_start = time.perf_counter()

    if provider == "ollama":
        url = cfg.get("ollama_url", "http://127.0.0.1:11434").rstrip("/")
        model = cfg.get("ollama_model", "llama3.2")
        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": sys_msg},
                {"role": "user", "content": raw_text},
            ],
            "stream": False,
            "options": {"temperature": 0.1, "num_predict": 700},
        }
        try:
            resp = HTTP_CLIENT.post(f"{url}/v1/chat/completions", json=payload, timeout=12.0)
            llm_ms = round((time.perf_counter() - t_start) * 1000, 1)
            if resp.status_code == 200:
                data = resp.json()
                polished = data["choices"][0]["message"]["content"].strip()
                if polished:
                    polished = re.sub(r":{2,}", ":", polished)
                    return polished, llm_ms, f"ok (Ollama {model})"
            return wispr_smart_format(raw_text), llm_ms, f"fallback (Ollama HTTP {resp.status_code})"
        except Exception as e:
            llm_ms = round((time.perf_counter() - t_start) * 1000, 1)
            return wispr_smart_format(raw_text), llm_ms, f"fallback (Ollama error: {str(e)[:50]})"

    elif provider == "lmstudio":
        url = cfg.get("lmstudio_url", "http://127.0.0.1:1234").rstrip("/")
        model = cfg.get("lmstudio_model", "").strip()

        # If model is placeholder or empty, auto-detect loaded model from Bionic/LM Studio
        if not model or model == "local-model":
            try:
                m_resp = HTTP_CLIENT.get(f"{url}/v1/models", timeout=2.0)
                if m_resp.status_code == 200:
                    loaded = [m.get("id") for m in m_resp.json().get("data", []) if "embed" not in m.get("id", "")]
                    if loaded:
                        model = loaded[0]
            except Exception:
                pass
        if not model:
            model = "local-model"

        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": sys_msg},
                {"role": "user", "content": raw_text},
            ],
            "temperature": 0.1,
            "max_tokens": 600,
        }
        try:
            resp = HTTP_CLIENT.post(f"{url}/v1/chat/completions", json=payload, timeout=12.0)
            llm_ms = round((time.perf_counter() - t_start) * 1000, 1)
            if resp.status_code == 200:
                data = resp.json()
                msg = data["choices"][0]["message"]
                polished = (msg.get("content") or "").strip()
                if polished:
                    polished = re.sub(r":{2,}", ":", polished)
                    return polished, llm_ms, f"ok (Bionic {model})"
                return wispr_smart_format(raw_text), llm_ms, f"fallback (Bionic {model} empty content/reasoning)"
            return wispr_smart_format(raw_text), llm_ms, f"fallback (Bionic HTTP {resp.status_code})"
        except Exception as e:
            llm_ms = round((time.perf_counter() - t_start) * 1000, 1)
            return wispr_smart_format(raw_text), llm_ms, f"fallback (Bionic error: {str(e)[:50]})"

    elif provider == "groq":
        key = cfg.get("groq_key", "").strip()
        if not key:
            key = load_config().get("groq_key", "").strip()
        model = cfg.get("groq_polish_model", "qwen/qwen3.8-27b").strip()
        if not key:
            return wispr_smart_format(raw_text), 0.0, "fallback (No Groq key)"
        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": sys_msg},
                {"role": "user", "content": raw_text},
            ],
            "temperature": 0.1,
            "max_tokens": 1024,
        }
        try:
            resp = HTTP_CLIENT.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                },
                json=payload,
                timeout=10.0,
            )
            llm_ms = round((time.perf_counter() - t_start) * 1000, 1)
            if resp.status_code == 200:
                data = resp.json()
                polished = data["choices"][0]["message"]["content"].strip()
                if polished.startswith('"') and polished.endswith('"') and len(polished) > 2:
                    polished = polished[1:-1].strip()
                if polished:
                    polished = re.sub(r":{2,}", ":", polished)
                    return polished, llm_ms, f"ok (Groq {model})"
            err_msg = resp.text[:100]
            try:
                err_msg = resp.json().get("error", {}).get("message", err_msg)
            except Exception:
                pass
            return wispr_smart_format(raw_text), llm_ms, f"fallback (Groq HTTP {resp.status_code}: {err_msg})"
        except Exception as e:
            llm_ms = round((time.perf_counter() - t_start) * 1000, 1)
            return wispr_smart_format(raw_text), llm_ms, f"fallback (Groq error: {str(e)[:50]})"

    else:  # Default OpenRouter
        key = cfg.get("openrouter_key", "").strip()
        model = cfg.get("openrouter_model", "meta/muse-spark-1.3-contributor").strip()
        if not key:
            return wispr_smart_format(raw_text), 0.0, "fallback (No key)"
        payload = {
            "model": model,
            "messages": [
                {"role": "system", "content": sys_msg},
                {"role": "user", "content": raw_text},
            ],
            "temperature": 0.1,
            "max_tokens": 700,
        }
        if "muse" in model.lower() or "spark" in model.lower():
            payload["reasoning"] = {"effort": "none"}
        try:
            resp = HTTP_CLIENT.post(
                "https://openrouter.ai/api/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {key}",
                    "HTTP-Referer": "https://parakeetflow.local",
                    "X-Title": "WhisperFlow",
                },
                json=payload,
                timeout=10.0,
            )
            llm_ms = round((time.perf_counter() - t_start) * 1000, 1)
            if resp.status_code == 200:
                data = resp.json()
                polished = data["choices"][0]["message"]["content"].strip()
                if polished:
                    polished = re.sub(r":{2,}", ":", polished)
                    return polished, llm_ms, f"ok (OpenRouter {model})"
            err_msg = resp.text[:100]
            try:
                err_msg = resp.json().get("error", {}).get("message", err_msg)
            except Exception:
                pass
            return wispr_smart_format(raw_text), llm_ms, f"fallback (OpenRouter HTTP {resp.status_code}: {err_msg})"
        except Exception as e:
            llm_ms = round((time.perf_counter() - t_start) * 1000, 1)
            return wispr_smart_format(raw_text), llm_ms, f"fallback (OpenRouter error: {str(e)[:50]})"


TASK_QUEUE = queue.Queue()
READY_EVENT = threading.Event()
LOAD_TIME_S = 0.0


def transcribe_with_groq(audio_path: str, groq_key: str, prompt: str = "") -> tuple[str, float]:
    t0 = time.perf_counter()
    with open(audio_path, "rb") as f:
        files = {"file": (os.path.basename(audio_path), f, "audio/wav")}
        data = {
            "model": "whisper-large-v3",
            "temperature": "0.0",
            "response_format": "json"
        }
        if prompt.strip():
            data["prompt"] = prompt.strip()[:800]
        resp = HTTP_CLIENT.post(
            "https://api.groq.com/openai/v1/audio/transcriptions",
            headers={"Authorization": f"Bearer {groq_key}"},
            files=files,
            data=data,
            timeout=15.0
        )
    latency_ms = round((time.perf_counter() - t0) * 1000, 1)
    if resp.status_code == 200:
        return resp.json().get("text", "").strip(), latency_ms
    else:
        raise RuntimeError(f"Groq API error {resp.status_code}: {resp.text}")


def inference_worker():
    global LOAD_TIME_S
    print(f"[WhisperWorker] Pre-warming {MODEL_ID} on Apple Silicon Metal GPU...", flush=True)
    t0 = time.perf_counter()
    warmup_wav = np.zeros(16000, dtype="float32")
    _ = mlx_whisper.transcribe(
        warmup_wav,
        path_or_hf_repo=MODEL_ID,
        language="en",
        condition_on_previous_text=False,
        temperature=0.0,
    )
    LOAD_TIME_S = round(time.perf_counter() - t0, 2)
    print(f"[WhisperWorker] Whisper Large v3 Turbo ready in {LOAD_TIME_S}s!", flush=True)
    READY_EVENT.set()

    while True:
        task = TASK_QUEUE.get()
        if task is None:
            break
        audio_path, req_config, res_q = task
        try:
            # 1. Hardware silence & energy gate: check audio energy before running Whisper
            rms = 0.0
            max_amp = 0
            audio_duration = 0.0
            try:
                with wave.open(audio_path, "rb") as w:
                    fr = w.getframerate()
                    nf = w.getnframes()
                    audio_duration = nf / float(fr) if fr > 0 else 0.0
                    raw_frames = w.readframes(nf)
                    samples = np.frombuffer(raw_frames, dtype=np.int16)
                    if len(samples) > 0:
                        rms = float(np.sqrt(np.mean(samples.astype(np.float64) ** 2)))
                        max_amp = int(np.max(np.abs(samples)))
            except Exception as e:
                rms = 100.0
                max_amp = 1000
                audio_duration = 0.0

            # If audio is digital silence or below audible speech threshold, skip Whisper completely
            if max_amp < 60 or rms < 10.0:
                print(f"[WhisperWorker] Silent audio received (max_amp={max_amp}, rms={rms:.1f}). Skipping inference to prevent hallucination.", flush=True)
                res_q.put((True, {
                    "raw_text": "",
                    "final_text": "",
                    "stt_ms": 0.0,
                    "llm_ms": 0.0,
                    "total_ms": 0.0,
                    "word_count": 0,
                    "char_count": 0,
                    "cost_usd": 0.0,
                    "cost_label": "⚡ Silence",
                    "model": "Whisper Large v3 (Groq LPU)" if req_config.get("stt_engine") == "groq" else "Whisper Large v3 Turbo (MLX)",
                    "polish_model": "none",
                    "warning": "No speech detected (silent recording)"
                }))
                continue

            # Screen Context Awareness: extract on-screen cues
            context_app = req_config.get("context_app", "").strip()
            context_title = req_config.get("context_title", "").strip()
            context_text = req_config.get("context_selected_text", "").strip()
            custom_vocab = req_config.get("custom_vocab", "").strip()

            cues = []
            if custom_vocab:
                cues.append(custom_vocab)
            if context_app:
                cues.append(context_app)
            if context_title:
                clean_title = re.sub(r"[\—\-\|\/]", ", ", context_title)
                cues.append(clean_title)
            if context_text:
                cues.append(context_text[:120])
            prompt_str = ", ".join([c.strip() for c in cues if c.strip()])

            groq_key = (req_config.get("groq_key") or "").strip()
            if not groq_key:
                groq_key = (load_config().get("groq_key") or "").strip()
            use_groq = bool(groq_key and req_config.get("stt_engine", "groq") != "local_mlx")
            raw_text = ""
            stt_ms = 0.0
            stt_model_name = "Whisper Large v3 (Groq LPU)"

            if use_groq:
                try:
                    raw_text, stt_ms = transcribe_with_groq(audio_path, groq_key, prompt=prompt_str)
                except Exception as e:
                    print(f"[WhisperWorker] Groq STT error: {e}. Falling back to local MLX...", flush=True)
                    use_groq = False

            if not use_groq:
                stt_model_name = "Whisper Large v3 Turbo (MLX Metal GPU)"
                t_stt = time.perf_counter()
                initial_prompt = sanitize_custom_vocab(custom_vocab)
                result = mlx_whisper.transcribe(
                    audio_path,
                    path_or_hf_repo=MODEL_ID,
                    language="en",
                    initial_prompt=initial_prompt,
                    condition_on_previous_text=False,
                    temperature=0.0,
                    no_speech_threshold=0.6,
                    logprob_threshold=-1.0,
                    compression_ratio_threshold=2.2,
                    hallucination_silence_threshold=1.5,
                )
                raw_text = (result.get("text", "") or "").strip()
                stt_ms = round((time.perf_counter() - t_stt) * 1000, 1)
                mx.clear_cache()

            # Clean hallucinations, silence ghosts, and autoregressive repetition loops
            raw_text = sanitize_transcription(raw_text, duration_sec=audio_duration, rms=rms)

            if not raw_text.strip():
                res_q.put((True, {
                    "raw_text": "",
                    "final_text": "",
                    "stt_ms": stt_ms,
                    "llm_ms": 0.0,
                    "total_ms": stt_ms,
                    "word_count": 0,
                    "char_count": 0,
                    "cost_usd": 0.0,
                    "cost_label": "⚡ Silence",
                    "model": stt_model_name,
                    "polish_model": "none",
                    "warning": "No speech detected"
                }))
                continue

            formatted_text = wispr_smart_format(raw_text)

            used_llm_flag = False
            provider = req_config.get("provider", "groq")
            if req_config.get("use_llm_polish", True) and raw_text:
                cfg_with_ctx = dict(req_config)
                if context_app:
                    cfg_with_ctx["custom_vocab"] = f"{custom_vocab}, App: {context_app}, Window: {context_title}"
                final_text, llm_ms, polish_status = polish_text_unified(raw_text, cfg_with_ctx)
                if polish_status.startswith("ok"):
                    used_llm_flag = True
            else:
                final_text = formatted_text
                llm_ms = 0.0
                polish_status = "local_rules"

            final_text = re.sub(r":{2,}", ":", final_text)
            final_text = re.sub(r":\s*:\s*", ":", final_text)
            final_text = re.sub(r":\s*\n\s*:", ":\n", final_text)

            word_count = len(final_text.split())
            char_count = len(final_text)
            cost_val, cost_label = calculate_cost(
                word_count,
                req_config.get("openrouter_model", ""),
                provider,
                used_llm_flag
            )

            if final_text.strip():
                now_str = datetime.now().strftime("%d %b %Y, %I:%M %p").lstrip("0")
                add_history_entry({
                    "id": str(int(time.time() * 1000)),
                    "timestamp": now_str,
                    "final_text": final_text,
                    "raw_text": raw_text,
                    "stt_ms": stt_ms,
                    "llm_ms": llm_ms,
                    "total_ms": round(stt_ms + llm_ms, 1),
                    "word_count": word_count,
                    "char_count": char_count,
                    "model": stt_model_name,
                    "polish_model": polish_status,
                    "cost_usd": cost_val,
                    "cost_label": cost_label,
                })

            res_q.put((True, {
                "raw_text": raw_text,
                "final_text": final_text,
                "stt_ms": stt_ms,
                "llm_ms": llm_ms,
                "total_ms": round(stt_ms + llm_ms, 1),
                "polish_status": polish_status,
                "cost_label": cost_label,
                "model": stt_model_name,
            }))
        except Exception as e:
            res_q.put((False, {"error": str(e)}))
        finally:
            TASK_QUEUE.task_done()


WORKER_THREAD = threading.Thread(target=inference_worker, daemon=True)
WORKER_THREAD.start()

# --- Precise SVG Icons (Zero Emojis) ---
SVG_ICONS = {
    "mic": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="22"/></svg>',
    "clock": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>',
    "timer": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="14" r="8"/><line x1="12" y1="2" x2="12" y2="4"/><line x1="10" y1="2" x2="14" y2="2"/></svg>',
    "bolt": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>',
    "sparkle": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 3-1.9 5.8a2 2 0 0 1-1.3 1.3L3 12l5.8 1.9a2 2 0 0 1 1.3 1.3L12 21l1.9-5.8a2 2 0 0 1 1.3-1.3L21 12l-5.8-1.9a2 2 0 0 1-1.3-1.3L12 3z"/></svg>',
    "copy": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>',
    "trash": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>',
    "settings": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
    "search": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>',
    "chevron_down": '<svg class="svg-icon chev-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>',
    "eye": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>',
    "refresh": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16"/><path d="M16 16h5v5"/></svg>',
    "check": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>',
    "sliders": '<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/></svg>',
}


def render_history_html() -> str:
    history = load_history()
    config = load_config()

    total_words = sum(h.get("word_count", 0) for h in history)
    avg_latency = (
        round(sum(h.get("total_ms", 0) for h in history) / len(history) / 1000, 1)
        if history else 0.0
    )
    total_cost_usd = sum(h.get("cost_usd", 0.0) for h in history)
    cost_display = f"${total_cost_usd:.4f}" if total_cost_usd >= 0.0001 else "$0.00 (Local)"
    active_prov = config.get("provider", "local_rules")
    if not config.get("use_llm_polish", False) or active_prov == "local_rules":
        active_prov = "local_rules"

    cards_html = []
    for h in history:
        hid = html.escape(str(h.get("id", "")))
        ts = html.escape(str(h.get("timestamp", "")))
        text = html.escape(str(h.get("final_text", "")))
        raw = html.escape(str(h.get("raw_text", "")))
        total_ms = int(h.get("total_ms", 0))
        stt_ms = int(h.get("stt_ms", total_ms))
        llm_ms = int(h.get("llm_ms", 0))
        words = h.get("word_count", len(text.split()))
        chars = h.get("char_count", len(text))
        cost_badge = html.escape(str(h.get("cost_label", "⚡ Free (Local)")))
        polish_model = html.escape(str(h.get("polish_model", "Local Rules")))
        pm_lower = polish_model.lower()
        if "bionic" in pm_lower:
            model_tag = "Bionic"
        elif "ollama" in pm_lower:
            model_tag = "Ollama"
        elif "openrouter" in pm_lower:
            model_tag = "OpenRouter"
        elif "fallback" in pm_lower:
            model_tag = "Local Rules"
        else:
            model_tag = "Local Rules"

        # One-line preview snippet
        preview_snippet = " ".join(text.replace("\n", " ").split())[:75]
        if len(text) > 75:
            preview_snippet += "..."

        cards_html.append(f"""
        <div class="card-shell" id="card-{hid}" data-search="{text.lower()} {raw.lower()}">
            <!-- Compact Folded Row -->
            <div class="card-summary" onclick="toggleCard('{hid}')">
                <div class="summary-left">
                    <span class="chev-wrap" id="chev-{hid}">{SVG_ICONS['chevron_down']}</span>
                    <span class="icon-wrap">{SVG_ICONS['clock']}</span>
                    <span class="timestamp">{ts}</span>
                    <span class="preview-text">{preview_snippet}</span>
                </div>
                <div class="summary-right">
                    <span class="badge badge-model" title="Processing Engine: {polish_model}">{SVG_ICONS['sparkle']} {model_tag}</span>
                    <span class="badge badge-cost">{cost_badge}</span>
                    <span class="badge badge-latency" title="STT: {stt_ms}ms · Polish: {llm_ms}ms">{SVG_ICONS['timer']} {total_ms}ms</span>
                    <span class="badge badge-metrics">{words}w</span>
                    <button class="btn-icon-only" onclick="copyCardFast(event, '{hid}')" title="Copy transcript">
                        {SVG_ICONS['copy']}
                    </button>
                </div>
            </div>

            <!-- Full Expanded Content (Folded by Default) -->
            <div class="card-expanded" id="expand-{hid}" style="display:none;">
                <div class="expanded-inner">
                    <div class="card-meta-bar">
                        <span class="badge badge-model">{SVG_ICONS['sparkle']} {polish_model}</span>
                        <span class="badge badge-metrics">{words} words · {chars} characters</span>
                    </div>

                    <div class="card-body">{text}</div>

                    <div class="raw-speech-drawer">
                        <button class="raw-toggle-btn" onclick="toggleRaw('{hid}')">
                            <span class="raw-toggle-icon" id="raw-icon-{hid}">▸</span> Raw Whisper Speech
                        </button>
                        <div class="raw-content" id="raw-{hid}" style="display:none;">
                            {raw}
                        </div>
                    </div>

                    <div class="card-actions">
                        <button class="btn btn-copy" onclick="copyCard('{hid}')">
                            <span class="btn-icon">{SVG_ICONS['copy']}</span>
                            <span class="btn-text">Copy Formatted</span>
                        </button>
                        <button class="btn btn-delete" onclick="deleteCard('{hid}')">
                            <span class="btn-icon">{SVG_ICONS['trash']}</span>
                            <span class="btn-text">Delete</span>
                        </button>
                    </div>
                </div>
            </div>
        </div>""")

    if not cards_html:
        cards_rendered = f"""
        <div class="empty-state">
            <div class="empty-icon">{SVG_ICONS['mic']}</div>
            <h3>No past transcripts yet</h3>
            <p>Press <strong>⌥ Space</strong> anywhere to record. Your transcripts and numbered lists format, paste, and save here in real-time.</p>
        </div>"""
    else:
        cards_rendered = "\n".join(cards_html)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Velox — Golden Gate Glass Studio</title>
<style>
  :root {{
    --bg-base: #06080d;
    --card-outer: rgba(255, 255, 255, 0.04);
    --card-inner: rgba(18, 22, 34, 0.65);
    --card-border: rgba(255, 255, 255, 0.08);
    --card-hover-border: rgba(245, 158, 11, 0.35);
    --text-primary: #f0f6fc;
    --text-secondary: #919bb0;
    --text-muted: #5e687e;
    --accent-gold: #f59e0b;
    --accent-amber: #d97706;
    --accent-emerald: #10b981;
    --accent-violet: #6366f1;
    --accent-rose: #f43f5e;
  }}

  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  
  body {{
    background-color: var(--bg-base);
    background-image: 
      radial-gradient(1000px 500px at 50% -120px, rgba(245, 158, 11, 0.12), transparent),
      radial-gradient(900px 450px at 95% 85%, rgba(99, 102, 241, 0.08), transparent),
      radial-gradient(600px 350px at 5% 45%, rgba(236, 72, 153, 0.05), transparent);
    color: var(--text-primary);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", system-ui, sans-serif;
    min-height: 100vh;
    padding: 28px 16px 80px 16px;
    -webkit-font-smoothing: antialiased;
    overflow-x: hidden;
  }}

  .container {{
    max-width: 860px;
    margin: 0 auto;
  }}

  /* SVG Icons */
  .svg-icon {{
    width: 14px;
    height: 14px;
    display: inline-block;
    vertical-align: middle;
    flex-shrink: 0;
  }}

  /* Top Island Navigation Bar */
  .nav-island {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    background: rgba(255, 255, 255, 0.035);
    border: 1px solid var(--card-border);
    backdrop-filter: blur(28px);
    -webkit-backdrop-filter: blur(28px);
    border-radius: 9999px;
    padding: 10px 20px;
    margin-bottom: 24px;
    box-shadow: 0 10px 30px -10px rgba(0,0,0,0.5), inset 0 1px 1px rgba(255,255,255,0.1);
  }}

  .brand {{
    display: flex;
    align-items: center;
    gap: 12px;
  }}

  .brand-icon {{
    width: 32px;
    height: 32px;
    border-radius: 9999px;
    background: linear-gradient(135deg, #f59e0b, #d97706);
    display: flex;
    align-items: center;
    justify-content: center;
    color: #fff;
    box-shadow: 0 0 16px rgba(245, 158, 11, 0.35);
  }}
  .brand-icon .svg-icon {{ width: 16px; height: 16px; }}

  .brand-text h1 {{
    font-size: 16px;
    font-weight: 600;
    letter-spacing: -0.02em;
    display: flex;
    align-items: center;
    gap: 8px;
  }}

  .version-tag {{
    font-size: 10px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 9999px;
    background: rgba(255, 255, 255, 0.08);
    color: var(--accent-gold);
    letter-spacing: 0.05em;
  }}

  .brand-text p {{
    font-size: 11px;
    color: var(--text-secondary);
  }}

  .nav-controls {{
    display: flex;
    align-items: center;
    gap: 10px;
  }}

  /* Balance Pill */
  .balance-pill {{
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 9999px;
    padding: 6px 12px;
    font-size: 12px;
    font-weight: 500;
    color: var(--text-primary);
    cursor: pointer;
    transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  }}

  .balance-pill:hover {{
    background: rgba(255, 255, 255, 0.1);
    border-color: var(--accent-gold);
  }}

  .balance-dot {{
    width: 7px;
    height: 7px;
    border-radius: 9999px;
    background: var(--accent-emerald);
    box-shadow: 0 0 8px var(--accent-emerald);
  }}

  .balance-dot.warning {{
    background: var(--accent-gold);
    box-shadow: 0 0 8px var(--accent-gold);
  }}

  .nav-btn {{
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--card-border);
    color: var(--text-primary);
    padding: 7px 14px;
    border-radius: 9999px;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    transition: all 0.2s;
  }}

  .nav-btn:hover {{
    background: rgba(255, 255, 255, 0.12);
  }}

  .nav-btn-delete {{
    color: var(--accent-rose);
  }}
  .nav-btn-delete:hover {{
    background: rgba(244, 63, 94, 0.15);
  }}

  /* Stats Bento Grid */
  .bento-grid {{
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 12px;
    margin-bottom: 22px;
  }}

  @media (max-width: 700px) {{
    .bento-grid {{
      grid-template-columns: repeat(2, 1fr);
    }}
    .nav-island {{
      flex-direction: column;
      gap: 14px;
      border-radius: 24px;
      padding: 16px;
    }}
  }}

  .bento-card {{
    background: var(--card-inner);
    border: 1px solid var(--card-border);
    border-radius: 16px;
    padding: 16px;
    backdrop-filter: blur(20px);
    box-shadow: inset 0 1px 1px rgba(255,255,255,0.06);
  }}

  .bento-title {{
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
    font-weight: 600;
    margin-bottom: 6px;
  }}

  .bento-val {{
    font-size: 20px;
    font-weight: 700;
    letter-spacing: -0.02em;
    color: var(--text-primary);
  }}

  .bento-sub {{
    font-size: 11px;
    color: var(--text-secondary);
    margin-top: 4px;
  }}

  /* Feed Controls Header */
  .feed-controls {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 16px;
    gap: 12px;
  }}

  .search-wrapper {{
    position: relative;
    flex: 1;
  }}

  .search-input {{
    width: 100%;
    padding: 11px 16px 11px 38px;
    background: rgba(255, 255, 255, 0.035);
    border: 1px solid var(--card-border);
    border-radius: 12px;
    color: #fff;
    font-size: 13.5px;
    outline: none;
    backdrop-filter: blur(20px);
    transition: all 0.2s;
  }}

  .search-input:focus {{
    border-color: var(--accent-gold);
    background: rgba(255, 255, 255, 0.06);
    box-shadow: 0 0 0 3px rgba(245, 158, 11, 0.15);
  }}

  .search-icon {{
    position: absolute;
    left: 14px;
    top: 50%;
    transform: translateY(-50%);
    color: var(--text-secondary);
  }}

  .view-toggles {{
    display: flex;
    gap: 8px;
  }}

  .btn-ghost {{
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--card-border);
    color: var(--text-secondary);
    padding: 9px 13px;
    border-radius: 10px;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.15s;
    white-space: nowrap;
  }}
  .btn-ghost:hover {{
    color: #fff;
    background: rgba(255, 255, 255, 0.08);
  }}

  /* Accordion Folded Double-Bezel Card */
  .card-shell {{
    background: var(--card-outer);
    border: 1px solid var(--card-border);
    border-radius: 16px;
    margin-bottom: 10px;
    transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
    overflow: hidden;
  }}

  .card-shell:hover {{
    border-color: var(--card-hover-border);
    box-shadow: 0 8px 24px -6px rgba(0, 0, 0, 0.4);
  }}

  .card-summary {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 13px 18px;
    cursor: pointer;
    background: var(--card-inner);
    backdrop-filter: blur(24px);
    transition: background 0.15s;
  }}

  .card-summary:hover {{
    background: rgba(255, 255, 255, 0.05);
  }}

  .summary-left {{
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    flex: 1;
  }}

  .chev-wrap {{
    display: flex;
    align-items: center;
    color: var(--text-secondary);
    transition: transform 0.25s cubic-bezier(0.16, 1, 0.3, 1);
  }}
  .chev-wrap.expanded {{
    transform: rotate(180deg);
    color: var(--accent-gold);
  }}

  .icon-wrap {{
    display: flex;
    align-items: center;
    color: var(--text-secondary);
  }}

  .timestamp {{
    font-size: 12px;
    color: var(--text-secondary);
    font-weight: 500;
    white-space: nowrap;
  }}

  .preview-text {{
    font-size: 13px;
    color: var(--text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    opacity: 0.88;
    margin-left: 6px;
  }}

  .summary-right {{
    display: flex;
    align-items: center;
    gap: 8px;
    margin-left: 12px;
    flex-shrink: 0;
  }}

  .btn-icon-only {{
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--card-border);
    color: var(--text-secondary);
    width: 28px;
    height: 28px;
    border-radius: 7px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: all 0.15s;
  }}
  .btn-icon-only:hover {{
    background: rgba(245, 158, 11, 0.2);
    color: #fbbf24;
    border-color: rgba(245, 158, 11, 0.4);
  }}

  /* Expanded Card Body */
  .card-expanded {{
    border-top: 1px solid rgba(255, 255, 255, 0.06);
    background: rgba(14, 18, 28, 0.85);
  }}

  .expanded-inner {{
    padding: 18px 22px 20px 22px;
  }}

  .card-meta-bar {{
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-bottom: 14px;
  }}

  .badge {{
    font-size: 11px;
    padding: 3px 8px;
    border-radius: 6px;
    font-weight: 500;
    letter-spacing: 0.01em;
    display: inline-flex;
    align-items: center;
    gap: 4px;
  }}

  .badge-cost {{
    background: rgba(16, 185, 129, 0.12);
    color: #34d399;
    border: 1px solid rgba(16, 185, 129, 0.25);
  }}

  .badge-latency {{
    background: rgba(59, 130, 246, 0.12);
    color: #60a5fa;
    border: 1px solid rgba(59, 130, 246, 0.25);
  }}

  .badge-metrics {{
    background: rgba(255, 255, 255, 0.06);
    color: var(--text-secondary);
  }}

  .badge-model {{
    background: rgba(245, 158, 11, 0.12);
    color: #fbbf24;
    border: 1px solid rgba(245, 158, 11, 0.2);
  }}

  .card-body {{
    font-size: 14.5px;
    line-height: 1.7;
    color: #f3f4f6;
    white-space: pre-wrap;
    word-break: break-word;
    margin-bottom: 16px;
  }}

  /* Collapsible Raw Speech */
  .raw-speech-drawer {{
    margin-bottom: 14px;
    border-top: 1px solid rgba(255, 255, 255, 0.04);
    padding-top: 10px;
  }}

  .raw-toggle-btn {{
    background: none;
    border: none;
    color: var(--text-muted);
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 4px;
    transition: color 0.15s;
  }}

  .raw-toggle-btn:hover {{
    color: var(--text-secondary);
  }}

  .raw-content {{
    margin-top: 8px;
    padding: 10px 14px;
    border-radius: 8px;
    background: rgba(0, 0, 0, 0.35);
    font-size: 12px;
    color: var(--text-secondary);
    line-height: 1.5;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    white-space: pre-wrap;
  }}

  /* Action Buttons */
  .card-actions {{
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 10px;
    border-top: 1px solid rgba(255, 255, 255, 0.04);
    padding-top: 14px;
  }}

  .btn {{
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid var(--card-border);
    color: var(--text-primary);
    padding: 7px 14px;
    border-radius: 8px;
    font-size: 12px;
    font-weight: 500;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  }}

  .btn:hover {{
    background: rgba(255, 255, 255, 0.12);
    border-color: rgba(255, 255, 255, 0.18);
  }}

  .btn:active {{
    transform: scale(0.97);
  }}

  .btn-copy {{
    background: rgba(245, 158, 11, 0.1);
    color: #fbbf24;
    border-color: rgba(245, 158, 11, 0.25);
  }}
  .btn-copy:hover {{
    background: rgba(245, 158, 11, 0.2);
  }}

  .btn-delete {{
    color: var(--accent-rose);
    background: transparent;
    border-color: transparent;
  }}
  .btn-delete:hover {{
    background: rgba(244, 63, 94, 0.1);
  }}

  /* Empty State */
  .empty-state {{
    text-align: center;
    padding: 80px 20px;
    color: var(--text-secondary);
  }}
  .empty-icon {{
    width: 48px;
    height: 48px;
    margin: 0 auto 12px auto;
    color: var(--accent-gold);
    opacity: 0.8;
  }}
  .empty-icon .svg-icon {{ width: 48px; height: 48px; }}
  .empty-state h3 {{ color: #fff; font-size: 18px; margin-bottom: 8px; }}
  .empty-state p {{ font-size: 14px; line-height: 1.6; max-width: 480px; margin: 0 auto; }}

  /* Slide-Over Settings Drawer */
  .drawer-overlay {{
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.7);
    backdrop-filter: blur(8px);
    z-index: 100;
    display: none;
    opacity: 0;
    transition: opacity 0.25s ease;
  }}

  .drawer {{
    position: fixed;
    top: 0;
    right: -520px;
    width: 480px;
    max-width: 95vw;
    height: 100vh;
    background: #0b0f19;
    border-left: 1px solid var(--card-border);
    backdrop-filter: blur(32px);
    z-index: 101;
    padding: 28px;
    display: flex;
    flex-direction: column;
    box-shadow: -10px 0 40px rgba(0,0,0,0.6);
    transition: right 0.3s cubic-bezier(0.16, 1, 0.3, 1);
    overflow-y: auto;
  }}

  .drawer.open {{
    right: 0;
  }}

  .drawer-header {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
    padding-bottom: 14px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  }}

  .drawer-header h2 {{
    font-size: 18px;
    font-weight: 600;
    letter-spacing: -0.02em;
    display: flex;
    align-items: center;
    gap: 8px;
  }}

  .btn-close {{
    background: rgba(255, 255, 255, 0.06);
    border: none;
    color: var(--text-secondary);
    width: 30px;
    height: 30px;
    border-radius: 9999px;
    cursor: pointer;
    font-size: 15px;
    display: flex;
    align-items: center;
    justify-content: center;
  }}

  .btn-close:hover {{ color: #fff; background: rgba(255, 255, 255, 0.12); }}

  .section-title {{
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--accent-gold);
    font-weight: 600;
    margin: 18px 0 10px 0;
  }}

  .form-group {{
    margin-bottom: 16px;
  }}

  .form-label {{
    display: block;
    font-size: 12px;
    font-weight: 500;
    color: var(--text-secondary);
    margin-bottom: 6px;
  }}

  .input-with-button {{
    display: flex;
    gap: 8px;
  }}

  .form-input, .form-select, .form-textarea {{
    width: 100%;
    padding: 9px 12px;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--card-border);
    border-radius: 10px;
    color: #fff;
    font-size: 13px;
    outline: none;
    transition: border-color 0.15s;
  }}

  .form-input:focus, .form-select:focus, .form-textarea:focus {{
    border-color: var(--accent-gold);
    background: rgba(255, 255, 255, 0.06);
  }}

  .form-textarea {{
    height: 70px;
    resize: vertical;
    font-family: inherit;
    line-height: 1.5;
  }}

  /* Provider Selector Buttons */
  .provider-tabs {{
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 6px;
    margin-bottom: 12px;
  }}

  .tab-btn {{
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--card-border);
    color: var(--text-secondary);
    padding: 8px 6px;
    border-radius: 8px;
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    text-align: center;
    transition: all 0.15s;
  }}

  .tab-btn.active {{
    background: rgba(245, 158, 11, 0.15);
    border-color: var(--accent-gold);
    color: #fbbf24;
    font-weight: 600;
  }}

  .live-status-box {{
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 10px;
    padding: 11px;
    margin-top: 8px;
    font-size: 12px;
    line-height: 1.5;
  }}

  /* HUD Preview Card */
  .hud-preview {{
    background: rgba(0, 0, 0, 0.4);
    border: 1px solid var(--card-border);
    border-radius: 12px;
    padding: 16px;
    display: flex;
    justify-content: center;
    align-items: center;
    margin-top: 8px;
  }}

  .toast {{
    position: fixed;
    bottom: 24px;
    left: 50%;
    transform: translateX(-50%) translateY(100px);
    background: #10b981;
    color: #fff;
    padding: 10px 20px;
    border-radius: 9999px;
    font-size: 13px;
    font-weight: 500;
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1);
    z-index: 200;
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }}

  .toast.show {{
    transform: translateX(-50%) translateY(0);
  }}
</style>
</head>
<body>

<div class="container">
    <!-- Top Glass Island Bar -->
    <div class="nav-island">
        <div class="brand">
            <div class="brand-icon">{SVG_ICONS['mic']}</div>
            <div class="brand-text">
                <h1>Velox <span class="version-tag">M1 TURBO</span></h1>
                <p>Velox Turbo Audio Engine (Apple Silicon Metal GPU) · 100% Private</p>
            </div>
        </div>

        <div class="nav-controls">
            <div class="balance-pill" id="nav-balance-pill" onclick="openDrawer()" title="Click to view & configure engine">
                <span class="balance-dot" id="balance-dot"></span>
                <span id="nav-balance-text">Engine Ready</span>
            </div>

            <button class="nav-btn" onclick="openDrawer()">
                {SVG_ICONS['settings']} Settings
            </button>

            <button class="nav-btn nav-btn-delete" onclick="clearAll()" style="{'' if history else 'display:none;'}">
                {SVG_ICONS['trash']} Clear All
            </button>
        </div>
    </div>

    <!-- Bento Stats Grid -->
    <div class="bento-grid">
        <div class="bento-card">
            <div class="bento-title">Transcripts Saved</div>
            <div class="bento-val" id="bento-count">{len(history)}</div>
            <div class="bento-sub">All folded & scannable</div>
        </div>
        <div class="bento-card">
            <div class="bento-title">Avg Latency</div>
            <div class="bento-val">{avg_latency}s</div>
            <div class="bento-sub">Apple Silicon Metal GPU</div>
        </div>
        <div class="bento-card">
            <div class="bento-title">Words Dictated</div>
            <div class="bento-val">{total_words}</div>
            <div class="bento-sub">Formatted & pasted</div>
        </div>
        <div class="bento-card">
            <div class="bento-title">Estimated Cost</div>
            <div class="bento-val">{cost_display}</div>
            <div class="bento-sub">Free local + micro-tier</div>
        </div>
    </div>

    <!-- Feed Controls Header -->
    <div class="feed-controls">
        <div class="search-wrapper">
            <span class="search-icon">{SVG_ICONS['search']}</span>
            <input type="search" class="search-input" id="search-input" placeholder="Search transcripts by keyword (Press / to focus)..." oninput="filterCards()">
        </div>
        <div class="view-toggles">
            <button class="btn-ghost" onclick="expandAll()">Expand All</button>
            <button class="btn-ghost" onclick="collapseAll()">Fold All</button>
        </div>
    </div>

    <!-- Cards Feed (Folded by Default) -->
    <div id="cards-container">
        {cards_rendered}
    </div>
</div>

<!-- Slide-Over Glass Settings Drawer -->
<div class="drawer-overlay" id="drawer-overlay" onclick="closeDrawer()"></div>
<div class="drawer" id="settings-drawer">
    <div class="drawer-header">
        <h2>{SVG_ICONS['sliders']} Studio Settings</h2>
        <button class="btn-close" onclick="closeDrawer()">✕</button>
    </div>

    <!-- Engine Provider Selector -->
    <div class="section-title">Formatting Engine & Provider</div>
    <div class="provider-tabs">
        <button class="tab-btn {'active' if active_prov == 'groq' else ''}" onclick="selectProvider('groq')" id="tab-groq">⚡ Groq Cloud LPU (Whisper v3)</button>
        <button class="tab-btn {'active' if active_prov == 'local_rules' else ''}" onclick="selectProvider('local_rules')" id="tab-local_rules">⚡ Local Rules (0ms)</button>
        <button class="tab-btn {'active' if active_prov == 'lmstudio' else ''}" onclick="selectProvider('lmstudio')" id="tab-lmstudio">🤖 LM Studio / Bionic</button>
        <button class="tab-btn {'active' if active_prov == 'ollama' else ''}" onclick="selectProvider('ollama')" id="tab-ollama">🦙 Ollama (Local)</button>
        <button class="tab-btn {'active' if active_prov == 'openrouter' else ''}" onclick="selectProvider('openrouter')" id="tab-openrouter">🌐 OpenRouter (Cloud)</button>
    </div>

    <!-- Groq Cloud LPU Config Panel -->
    <div id="panel-groq" style="display: {'block' if active_prov == 'groq' else 'none'};">
        <div class="form-group">
            <label class="form-label">Groq API Key</label>
            <div class="input-with-button">
                <input type="password" class="form-input" id="cfg-groq-key" value="{html.escape(config.get('groq_key', ''))}" placeholder="gsk_...">
                <button class="btn" onclick="toggleGroqKeyVisibility()">{SVG_ICONS['eye']}</button>
            </div>
            <button class="btn" style="margin-top: 8px; width: 100%;" onclick="testCurrentProvider()">
                {SVG_ICONS['refresh']} Test Groq API Key & Check Connection
            </button>
        </div>
        <div class="form-group">
            <label class="form-label">Speech-to-Text Model</label>
            <input type="text" class="form-input" id="cfg-groq-stt" value="{html.escape(config.get('groq_model', 'whisper-large-v3'))}" readonly style="opacity: 0.85;">
            <div style="font-size: 11px; color: #94a3b8; margin-top: 4px;">Flagship OpenAI Whisper Large v3 on Groq LPU (~1.5s with context cues).</div>
        </div>
        <div class="form-group">
            <label class="form-label">LLM Polisher Model</label>
            <input type="text" class="form-input" id="cfg-groq-polish" value="{html.escape(config.get('groq_polish_model', 'qwen/qwen3.8-27b'))}" readonly style="opacity: 0.85;">
            <div style="font-size: 11px; color: #94a3b8; margin-top: 4px;">Qwen 3.8-27B instruction polisher formatting lists, numbers, and grammar (~400ms).</div>
        </div>
    </div>

    <!-- Local Rules (Offline Post-Processor) Config Panel -->
    <div id="panel-local_rules" style="display: {'block' if active_prov == 'local_rules' else 'none'};">
        <div style="background: rgba(245, 158, 11, 0.08); border: 1px solid rgba(245, 158, 11, 0.28); border-radius: 8px; padding: 13px; margin-bottom: 14px;">
            <div style="color: #f59e0b; font-weight: 600; font-size: 13px; margin-bottom: 6px;">
                ⚡ Built-in Post-Processor (Offline / 0ms Latency)
            </div>
            <div style="color: #cbd5e1; font-size: 12px; line-height: 1.6;">
                • <strong>No LLM Needed:</strong> Instant rule-based post-processing. Uses 0 additional GPU/RAM and zero network calls.<br>
                • <strong>Nigerian Pidgin & Slang:</strong> Preserves terms like <em>how far, abeg, naira, 1k, 2k, 4k</em> without corruption.<br>
                • <strong>Auto-Punctuation:</strong> Adds capital letters, periods, question marks, commas, and currency formatting automatically.<br>
                • <strong>100% Free & Private:</strong> Runs locally on Apple Silicon Metal GPU.
            </div>
            <button class="btn" style="margin-top: 10px; width: 100%;" onclick="testCurrentProvider()">
                {SVG_ICONS['check']} Verify Built-in Post-Processor
            </button>
        </div>
    </div>

    <!-- OpenRouter Config Panel -->
    <div id="panel-openrouter" style="display: {'block' if active_prov == 'openrouter' else 'none'};">
        <div class="form-group">
            <label class="form-label">OpenRouter API Key</label>
            <div class="input-with-button">
                <input type="password" class="form-input" id="cfg-key" value="{html.escape(config.get('openrouter_key', ''))}" placeholder="sk-or-v1-...">
                <button class="btn" onclick="toggleKeyVisibility()">{SVG_ICONS['eye']}</button>
            </div>
            <button class="btn" style="margin-top: 8px; width: 100%;" onclick="testCurrentProvider()">
                {SVG_ICONS['refresh']} Test Key & Check Live Balance
            </button>
        </div>
        <div class="form-group">
            <label class="form-label">OpenRouter Model</label>
            <select class="form-select" id="cfg-or-model">
                <option value="meta/muse-spark-1.3-contributor" {"selected" if config.get('openrouter_model') == 'meta/muse-spark-1.3-contributor' else ""}>Muse Spark 1.3 Contributor (Ultra-cheap / Fast)</option>
                <option value="google/gemini-2.5-flash" {"selected" if config.get('openrouter_model') == 'google/gemini-2.5-flash' else ""}>Google Gemini 2.5 Flash (Lightning Fast)</option>
                <option value="deepseek/deepseek-chat" {"selected" if config.get('openrouter_model') == 'deepseek/deepseek-chat' else ""}>DeepSeek V3 (High Precision)</option>
                <option value="meta-llama/llama-3.3-70b-instruct" {"selected" if config.get('openrouter_model') == 'meta-llama/llama-3.3-70b-instruct' else ""}>Llama 3.3 70B Instruct</option>
            </select>
        </div>
    </div>

    <!-- Ollama Config Panel -->
    <div id="panel-ollama" style="display: {'block' if active_prov == 'ollama' else 'none'};">
        <div class="form-group">
            <label class="form-label">Ollama Server URL</label>
            <input type="text" class="form-input" id="cfg-ollama-url" value="{html.escape(config.get('ollama_url', 'http://127.0.0.1:11434'))}">
        </div>
        <div class="form-group">
            <label class="form-label">Local Model Name (e.g. llama3.2, qwen2.5)</label>
            <input type="text" class="form-input" id="cfg-ollama-model" value="{html.escape(config.get('ollama_model', 'llama3.2'))}">
            <button class="btn" style="margin-top: 8px; width: 100%;" onclick="testCurrentProvider()">
                {SVG_ICONS['refresh']} Test Ollama & Detect Installed Models
            </button>
        </div>
    </div>

    <!-- LM Studio / Bionic Panel -->
    <div id="panel-lmstudio" style="display: {'block' if active_prov == 'lmstudio' else 'none'};">
        <div class="form-group">
            <label class="form-label">LM Studio / Bionic Server URL</label>
            <input type="text" class="form-input" id="cfg-lmstudio-url" value="{html.escape(config.get('lmstudio_url', 'http://127.0.0.1:1234'))}">
        </div>
        <div class="form-group">
            <label class="form-label">Model Identifier</label>
            <input type="text" class="form-input" id="cfg-lmstudio-model" value="{html.escape(config.get('lmstudio_model', 'local-model'))}">
            <button class="btn" style="margin-top: 8px; width: 100%;" onclick="testCurrentProvider()">
                {SVG_ICONS['refresh']} Test Connection to LM Studio
            </button>
        </div>
    </div>

    <div class="live-status-box" id="drawer-provider-status">
        Ready. Select your engine and click Test.
    </div>

    <!-- Floating HUD Customization Section -->
    <div class="section-title">Floating Listening Bar Customization</div>

    <div class="form-group">
        <label class="form-label">Screen Position</label>
        <select class="form-select" id="cfg-hud-pos">
            <option value="bottom_left" {"selected" if config.get('hud_position') in ['bottom_left', 'left'] else ""}>Dock Left</option>
            <option value="bottom_center" {"selected" if config.get('hud_position') in ['bottom_center', 'center'] else ""}>Dock Middle (Center)</option>
            <option value="bottom_right" {"selected" if config.get('hud_position') in ['bottom_right', 'right'] else ""}>Dock Right</option>
        </select>
    </div>

    <div class="form-group" style="display: flex; align-items: center; justify-content: space-between; padding: 6px 0;">
        <div>
            <label class="form-label" style="margin-bottom: 2px;">Always on Desktop (Pet Companion)</label>
            <div style="font-size: 11px; color: #94a3b8;">Keep character visible on screen, alive with glances and reactions</div>
        </div>
        <input type="checkbox" id="cfg-hud-always" {"checked" if config.get('hud_always_show', True) else ""} style="transform: scale(1.2); cursor: pointer;">
    </div>

    <div class="form-group">
        <label class="form-label">Bar Size & Scale</label>
        <select class="form-select" id="cfg-hud-size">
            <option value="mini" {"selected" if config.get('hud_size') == 'mini' else ""}>Micro Pill (68 × 22 px)</option>
            <option value="compact" {"selected" if config.get('hud_size') == 'compact' else ""}>Compact (76 × 25 px)</option>
            <option value="spacious" {"selected" if config.get('hud_size') == 'spacious' else ""}>Spacious (84 × 28 px)</option>
        </select>
    </div>

    <div class="form-group">
        <label class="form-label">Animated Companion Character</label>
        <select class="form-select" id="cfg-hud-char" onchange="renderHudPreview()">
            <option value="gearbot" {"selected" if config.get('hud_character', 'gearbot') == 'gearbot' else ""}>🤖 GearBot (Curious Cyber Inventor)</option>
            <option value="neko" {"selected" if config.get('hud_character') == 'neko' else ""}>🐱 Neko (Cozy Cat Companion)</option>
            <option value="luna" {"selected" if config.get('hud_character') == 'luna' else ""}>👻 Luna (Gentle Celestial Spirit)</option>
            <option value="kuro" {"selected" if config.get('hud_character') == 'kuro' else ""}>🦊 Kuro (Clever Shadow Fox)</option>
            <option value="custom" {"selected" if config.get('hud_character') == 'custom' else ""}>📁 Custom GIF (~/.parakeetflow/character.gif)</option>
        </select>
        <div style="font-size: 11px; color: #94a3b8; margin-top: 4px;">
            60fps kinetic companion. No text clutter — dances to voice harmonics when listening, meshes gears when processing.
        </div>
    </div>

    <!-- Live Dark HUD Capsule Preview -->
    <div style="margin: 14px 0 18px 0; padding: 14px; background: rgba(0, 0, 0, 0.4); border-radius: 14px; border: 1px solid rgba(255, 255, 255, 0.08); text-align: center;">
        <div style="font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; color: #94a3b8; margin-bottom: 10px; font-weight: 600;">Dark HUD Capsule Preview</div>
        <div id="hud-preview-container" style="display: flex; justify-content: center; align-items: center; min-height: 48px;"></div>
        <div style="display: flex; justify-content: center; gap: 8px; margin-top: 10px;">
            <button type="button" class="btn" style="font-size: 11px; padding: 4px 10px;" onclick="setPreviewState('listening')">🎙️ Listening</button>
            <button type="button" class="btn" style="font-size: 11px; padding: 4px 10px;" onclick="setPreviewState('processing')">⚙️ Processing (Gears)</button>
        </div>
    </div>

    <div class="form-group">
        <label class="form-label">Accent Color Theme</label>
        <select class="form-select" id="cfg-hud-color" onchange="renderHudPreview()">
            <option value="amber" {"selected" if config.get('hud_color') == 'amber' else ""}>Golden Gate Amber (#f59e0b)</option>
            <option value="rose" {"selected" if config.get('hud_color') == 'rose' else ""}>Apple Rose (#f43f5e)</option>
            <option value="emerald" {"selected" if config.get('hud_color') == 'emerald' else ""}>Cyber Emerald (#10b981)</option>
            <option value="cyan" {"selected" if config.get('hud_color') == 'cyan' else ""}>Electric Cyan (#06b6d4)</option>
            <option value="purple" {"selected" if config.get('hud_color') == 'purple' else ""}>Deep Violet (#8b5cf6)</option>
            <option value="monochrome" {"selected" if config.get('hud_color') == 'monochrome' else ""}>Frosted Titanium / White</option>
        </select>
    </div>

    <!-- Custom Vocab Section -->
    <div class="section-title">Vocabulary & Accuracy</div>
    <div class="form-group">
        <label class="form-label">Custom Vocabulary & Context Hints</label>
        <textarea class="form-textarea" id="cfg-vocab" placeholder="e.g. how far, abeg, naira, GitHub, PR, Velox">{html.escape(config.get('custom_vocab', ''))}</textarea>
    </div>

    <button class="btn btn-copy" style="margin-top: 10px; width: 100%; padding: 12px;" onclick="saveSettings()">
        {SVG_ICONS['check']} Save Settings & Sync Across Mac App
    </button>
</div>

<div class="toast" id="toast">
    {SVG_ICONS['check']} <span id="toast-msg">Saved & Synced!</span>
</div>

<script>
let currentProvider = "{active_prov}";

function selectProvider(p) {{
    currentProvider = p;
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    const tabEl = document.getElementById('tab-' + p);
    if (tabEl) tabEl.classList.add('active');

    const groqPanel = document.getElementById('panel-groq');
    if (groqPanel) groqPanel.style.display = (p === 'groq') ? 'block' : 'none';
    document.getElementById('panel-local_rules').style.display = (p === 'local_rules') ? 'block' : 'none';
    document.getElementById('panel-openrouter').style.display = (p === 'openrouter') ? 'block' : 'none';
    document.getElementById('panel-ollama').style.display = (p === 'ollama') ? 'block' : 'none';
    document.getElementById('panel-lmstudio').style.display = (p === 'lmstudio') ? 'block' : 'none';
    testCurrentProvider();
}}

function openDrawer() {{
    document.getElementById('drawer-overlay').style.display = 'block';
    setTimeout(() => {{
        document.getElementById('drawer-overlay').style.opacity = '1';
        document.getElementById('settings-drawer').classList.add('open');
        renderHudPreview();
    }}, 10);
    testCurrentProvider();
}}

function closeDrawer() {{
    document.getElementById('settings-drawer').classList.remove('open');
    document.getElementById('drawer-overlay').style.opacity = '0';
    setTimeout(() => {{
        document.getElementById('drawer-overlay').style.display = 'none';
    }}, 250);
}}

function toggleKeyVisibility() {{
    const el = document.getElementById('cfg-key');
    el.type = el.type === 'password' ? 'text' : 'password';
}}

function toggleGroqKeyVisibility() {{
    const el = document.getElementById('cfg-groq-key');
    if (el) el.type = el.type === 'password' ? 'text' : 'password';
}}

function showToast(msg) {{
    const t = document.getElementById('toast');
    document.getElementById('toast-msg').innerText = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), 2400);
}}

function toggleCard(id) {{
    const exp = document.getElementById('expand-' + id);
    const chev = document.getElementById('chev-' + id);
    if (!exp) return;
    const isHidden = exp.style.display === 'none';
    exp.style.display = isHidden ? 'block' : 'none';
    if (chev) {{
        chev.classList.toggle('expanded', isHidden);
    }}
}}

function expandAll() {{
    document.querySelectorAll('.card-expanded').forEach(el => el.style.display = 'block');
    document.querySelectorAll('.chev-wrap').forEach(el => el.classList.add('expanded'));
}}

function collapseAll() {{
    document.querySelectorAll('.card-expanded').forEach(el => el.style.display = 'none');
    document.querySelectorAll('.chev-wrap').forEach(el => el.classList.remove('expanded'));
}}

function toggleRaw(id) {{
    const el = document.getElementById('raw-' + id);
    const icon = document.getElementById('raw-icon-' + id);
    if (!el) return;
    const isHidden = el.style.display === 'none';
    el.style.display = isHidden ? 'block' : 'none';
    if (icon) icon.innerText = isHidden ? '▾' : '▸';
}}

function testCurrentProvider() {{
    const statusBox = document.getElementById('drawer-provider-status');
    const navText = document.getElementById('nav-balance-text');
    const navDot = document.getElementById('balance-dot');

    if (currentProvider === 'local_rules') {{
        navDot.className = 'balance-dot';
        navText.innerText = '⚡ Local Rules (0ms)';
        statusBox.innerHTML = `
            <div style="color: #34d399; font-weight: 600; margin-bottom: 4px;">✓ Built-in Post-Processor Active</div>
            <div style="color: #a7f3d0; font-size: 12px; line-height: 1.5;">Instant 0ms offline post-processing. Retains Nigerian Pidgin terms (how far, abeg, naira, 1k, 2k, 4k), auto-capitalizes and punctuates without an LLM.</div>
        `;
        return;
    }}

    statusBox.innerHTML = '<em>Testing connection...</em>';

    const groqKeyInput = document.getElementById('cfg-groq-key');
    const payload = {{
        provider: currentProvider,
        groq_key: groqKeyInput ? groqKeyInput.value.trim() : '',
        openrouter_key: document.getElementById('cfg-key').value.trim(),
        ollama_url: document.getElementById('cfg-ollama-url').value.trim(),
        lmstudio_url: document.getElementById('cfg-lmstudio-url').value.trim()
    }};

    fetch('/api/test_provider', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify(payload)
    }})
    .then(r => r.json())
    .then(res => {{
        if (res.valid) {{
            navDot.className = 'balance-dot';
            if (currentProvider === 'groq') {{
                navText.innerText = '⚡ Groq Large v3: Ready';
                statusBox.innerHTML = `
                    <div style="color: #34d399; font-weight: 600; margin-bottom: 4px;">✓ Groq Cloud LPU Connected</div>
                    <div style="color: #cbd5e1; font-size: 12px; line-height: 1.5;">${{res.message}}</div>
                `;
            }} else if (currentProvider === 'openrouter') {{
                navText.innerText = 'OpenRouter: $' + (res.balance || 0).toFixed(2);
                statusBox.innerHTML = `
                    <div style="color: #34d399; font-weight: 600; margin-bottom: 4px;">✓ OpenRouter Connected: ${{res.label || 'Active'}}</div>
                    <div>Remaining Balance: <strong>$${{res.balance.toFixed(2)}}</strong></div>
                    <div style="color: #919bb0;">Total Spent: $${{res.total_usage.toFixed(4)}} · Credits: $${{res.total_credits.toFixed(2)}}</div>
                `;
            }} else if (currentProvider === 'ollama') {{
                navText.innerText = 'Local Ollama: Ready';
                statusBox.innerHTML = `
                    <div style="color: #34d399; font-weight: 600; margin-bottom: 4px;">✓ Local Ollama Connected</div>
                    <div style="color: #919bb0;">${{res.message}}</div>
                    <div style="margin-top: 4px; font-size: 11px;">Available Models: ${{res.models && res.models.length ? res.models.join(', ') : 'None pulled yet (run "ollama run llama3.2")'}}</div>
                `;
            }} else {{
                navText.innerText = 'Local LM Studio: Ready';
                statusBox.innerHTML = `
                    <div style="color: #34d399; font-weight: 600; margin-bottom: 4px;">✓ LM Studio / Bionic Connected</div>
                    <div style="color: #919bb0;">${{res.message}}</div>
                `;
            }}
        }} else {{
            navDot.className = 'balance-dot warning';
            navText.innerText = currentProvider + ': Error';
            statusBox.innerHTML = `
                <div style="color: #f43f5e; font-weight: 600; margin-bottom: 4px;">⚠️ Connection Failed</div>
                <div style="color: #fca5a5;">${{res.error || 'Connection failed'}}</div>
            `;
        }}
    }})
    .catch(err => {{
        statusBox.innerHTML = '<span style="color: #fca5a5;">Error testing provider.</span>';
    }});
}}

function saveSettings() {{
    const isLocalRules = (currentProvider === 'local_rules');
    const groqKeyInput = document.getElementById('cfg-groq-key');
    const payload = {{
        provider: currentProvider,
        stt_engine: (currentProvider === 'groq') ? 'groq' : 'local_mlx',
        groq_key: groqKeyInput ? groqKeyInput.value.trim() : '',
        openrouter_key: document.getElementById('cfg-key').value.trim(),
        openrouter_model: document.getElementById('cfg-or-model').value,
        ollama_url: document.getElementById('cfg-ollama-url').value.trim(),
        ollama_model: document.getElementById('cfg-ollama-model').value.trim(),
        lmstudio_url: document.getElementById('cfg-lmstudio-url').value.trim(),
        lmstudio_model: document.getElementById('cfg-lmstudio-model').value.trim(),
        use_llm_polish: !isLocalRules,
        custom_vocab: document.getElementById('cfg-vocab').value.trim(),
        hud_position: document.getElementById('cfg-hud-pos').value,
        hud_always_show: document.getElementById('cfg-hud-always') ? document.getElementById('cfg-hud-always').checked : true,
        hud_size: document.getElementById('cfg-hud-size').value,
        hud_character: document.getElementById('cfg-hud-char').value,
        hud_color: document.getElementById('cfg-hud-color').value
    }};

    fetch('/api/config', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify(payload)
    }})
    .then(r => r.json())
    .then(res => {{
        showToast(isLocalRules ? 'Saved: ⚡ Local Rules Active (0ms)!' : (currentProvider === 'groq' ? 'Saved: ⚡ Groq Cloud LPU Active!' : 'Saved: 🤖 LLM Polish Active!'));
        testCurrentProvider();
        setTimeout(closeDrawer, 800);
    }});
}}

let previewState = 'listening';

function setPreviewState(st) {{
    previewState = st;
    renderHudPreview();
}}

function renderHudPreview() {{
    const container = document.getElementById('hud-preview-container');
    if (!container) return;
    const charEl = document.getElementById('cfg-hud-char');
    const colorEl = document.getElementById('cfg-hud-color');
    const charType = charEl ? charEl.value : 'gearbot';
    const colorKey = colorEl ? colorEl.value : 'amber';

    const colorMap = {{
        amber: '#f59e0b',
        rose: '#f43f5e',
        emerald: '#10b981',
        cyan: '#06b6d4',
        purple: '#8b5cf6',
        monochrome: '#e2e8f0'
    }};
    const accent = colorMap[colorKey] || '#f59e0b';

    let charSvg = '';
    if (charType === 'luna') {{
        charSvg = '<svg width=\"17\" height=\"17\" viewBox=\"0 0 24 24\"><circle cx=\"12\" cy=\"4\" r=\"2\" fill=\"' + accent + '\" opacity=\"0.9\"/><rect x=\"4\" y=\"8\" width=\"16\" height=\"14\" rx=\"7\" fill=\"' + accent + '\" opacity=\"0.85\"/><circle cx=\"9\" cy=\"13\" r=\"1.8\" fill=\"#fff\"/><circle cx=\"15\" cy=\"13\" r=\"1.8\" fill=\"#fff\"/></svg>';
    }} else if (charType === 'neko') {{
        charSvg = '<svg width=\"17\" height=\"17\" viewBox=\"0 0 24 24\"><polygon points=\"6,9 9,3 12,9\" fill=\"' + accent + '\"/><polygon points=\"12,9 15,3 18,9\" fill=\"' + accent + '\"/><circle cx=\"12\" cy=\"13\" r=\"8\" fill=\"#1e1e24\"/><circle cx=\"9.5\" cy=\"12.5\" r=\"1.8\" fill=\"' + accent + '\"/><circle cx=\"14.5\" cy=\"12.5\" r=\"1.8\" fill=\"' + accent + '\"/></svg>';
    }} else if (charType === 'kuro') {{
        charSvg = '<svg width=\"17\" height=\"17\" viewBox=\"0 0 24 24\"><polygon points=\"5,9 8,2 11,9\" fill=\"#2d3748\"/><polygon points=\"13,9 16,2 19,9\" fill=\"#2d3748\"/><polygon points=\"7,8 8,4 10,8\" fill=\"' + accent + '\"/><polygon points=\"14,8 16,4 17,8\" fill=\"' + accent + '\"/><circle cx=\"12\" cy=\"13\" r=\"8\" fill=\"#1e1e24\"/><circle cx=\"9.5\" cy=\"12.5\" r=\"1.8\" fill=\"' + accent + '\"/><circle cx=\"14.5\" cy=\"12.5\" r=\"1.8\" fill=\"' + accent + '\"/></svg>';
    }} else {{
        charSvg = '<svg width=\"17\" height=\"17\" viewBox=\"0 0 24 24\"><circle cx=\"12\" cy=\"4\" r=\"2\" fill=\"' + accent + '\"/><rect x=\"3\" y=\"8\" width=\"18\" height=\"13\" rx=\"4\" fill=\"#1e1e24\" stroke=\"rgba(255,255,255,0.25)\" stroke-width=\"0.8\"/><rect x=\"5\" y=\"10\" width=\"14\" height=\"9\" rx=\"2.5\" fill=\"#000\"/><circle cx=\"8.5\" cy=\"14.5\" r=\"2\" fill=\"' + accent + '\"/><circle cx=\"15.5\" cy=\"14.5\" r=\"2\" fill=\"' + accent + '\"/></svg>';
    }}

    let rightContent = '';
    if (previewState === 'listening') {{
        rightContent = '<div style=\"display:flex;align-items:center;gap:2px;height:12px;margin-left:3px;\"><span style=\"width:1.8px;height:5px;background:' + accent + ';border-radius:99px;\"></span><span style=\"width:1.8px;height:11px;background:' + accent + ';border-radius:99px;\"></span><span style=\"width:1.8px;height:12px;background:' + accent + ';border-radius:99px;\"></span><span style=\"width:1.8px;height:7px;background:' + accent + ';border-radius:99px;\"></span></div>';
    }} else {{
        rightContent = '<div style=\"width:10px;height:10px;border:1.5px solid ' + accent + ';border-top-color:transparent;border-radius:50%;margin-left:2px;\"></div>';
    }}

    container.innerHTML = '<div style=\"display:inline-flex;align-items:center;gap:5px;padding:0 7px;height:25px;border-radius:9999px;background:#141418;border:1px solid rgba(255,255,255,0.24);box-shadow:0 6px 16px rgba(0,0,0,0.4);\">' + charSvg + rightContent + '</div>';
}}

function copyCardFast(event, id) {{
    event.stopPropagation();
    copyCard(id);
}}

function copyCard(id) {{
    const card = document.getElementById('card-' + id);
    if (!card) return;
    const body = card.querySelector('.card-body').innerText;
    navigator.clipboard.writeText(body).then(() => {{
        showToast('Copied to clipboard');
    }});
}}

function deleteCard(id) {{
    if (!confirm('Delete this transcript from history?')) return;
    fetch('/api/history/delete', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify({{ id: id }})
    }}).then(() => {{
        const card = document.getElementById('card-' + id);
        if (card) card.remove();
        updateCount();
    }});
}}

function clearAll() {{
    if (!confirm('Clear all past transcripts from history?')) return;
    fetch('/api/history/clear', {{ method: 'POST' }}).then(() => {{
        location.reload();
    }});
}}

function filterCards() {{
    const q = document.getElementById('search-input').value.toLowerCase().trim();
    const cards = document.querySelectorAll('.card-shell');
    let visible = 0;
    cards.forEach(c => {{
        const text = c.getAttribute('data-search') || '';
        const match = text.includes(q);
        c.style.display = match ? '' : 'none';
        if (match) visible++;
    }});
}}

function updateCount() {{
    const cards = document.querySelectorAll('.card-shell');
    const badge = document.getElementById('bento-count');
    if (badge) badge.innerText = cards.length;
}}

// Keyboard shortcut '/' to search
document.addEventListener('keydown', (e) => {{
    if (e.key === '/' && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {{
        e.preventDefault();
        document.getElementById('search-input').focus();
    }}
}});

// Initialize on page load
window.addEventListener('DOMContentLoaded', () => {{
    testCurrentProvider();
    if (window.location.hash === '#settings') {{
        setTimeout(openDrawer, 100);
    }}
}});
window.addEventListener('hashchange', () => {{
    if (window.location.hash === '#settings') {{
        openDrawer();
    }}
}});

// Real-time live polling: automatically detect new transcripts and update the page without user refreshing
let lastTopId = "{history[0].get('id', '') if history else ''}";
setInterval(async () => {{
    try {{
        const r = await fetch('/api/history');
        if (!r.ok) return;
        const d = await r.json();
        const list = d.history || [];
        if (list.length > 0) {{
            const currentTop = String(list[0].id || '');
            if (lastTopId && currentTop !== lastTopId) {{
                location.reload();
            }} else if (!lastTopId) {{
                lastTopId = currentTop;
            }}
        }}
    }} catch (e) {{}}
}}, 2200);
</script>
</body>
</html>"""


class DaemonHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _send_json(self, code: int, obj: dict):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, code: int, html_str: str):
        body = html_str.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path == "/health":
            is_ready = READY_EVENT.is_set()
            self._send_json(
                200 if is_ready else 503,
                {
                    "status": "ready" if is_ready else "warming_up",
                    "model": "Whisper Large v3 Turbo (Apple MLX Metal GPU)",
                    "load_time_s": LOAD_TIME_S,
                },
            )
        elif path in ("/history", "/", "/transcripts"):
            self._send_html(200, render_history_html())
        elif path == "/api/history":
            self._send_json(200, {"history": load_history()})
        elif path == "/api/config":
            self._send_json(200, load_config())
        elif path == "/api/openrouter/balance":
            api_key = query.get("key", [""])[0] or load_config().get("openrouter_key", "")
            res = check_openrouter_balance(api_key)
            self._send_json(200, res)
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length) if length > 0 else b"{}"
        try:
            req = json.loads(raw_body.decode("utf-8"))
        except Exception:
            req = {}

        if self.path == "/transcribe":
            if not READY_EVENT.is_set():
                self._send_json(503, {"error": "Model is warming up on Apple Silicon GPU"})
                return

            cfg = load_config()
            audio_path = req.get("audio_path", "")

            # Merge request overrides with stored config (only non-empty values)
            merged_config = cfg.copy()
            for k in ("provider", "openrouter_key", "openrouter_model", "ollama_url", "ollama_model",
                      "lmstudio_url", "lmstudio_model", "use_llm_polish", "custom_vocab",
                      "stt_engine", "groq_key", "groq_model", "groq_polish_model",
                      "context_app", "context_title", "context_selected_text"):
                if k in req and req[k] is not None and str(req[k]).strip() != "":
                    merged_config[k] = req[k]

            if not audio_path or not os.path.exists(audio_path):
                self._send_json(400, {"error": f"Audio file not found: {audio_path}"})
                return

            res_q = queue.Queue()
            TASK_QUEUE.put((audio_path, merged_config, res_q))
            try:
                success, data = res_q.get(timeout=90.0)
                self._send_json(200 if success else 500, data)
            except queue.Empty:
                self._send_json(504, {"error": "Inference timed out"})
        elif self.path == "/api/config":
            cfg = load_config()
            for k, v in req.items():
                cfg[k] = v
            save_config(cfg)
            self._send_json(200, {"status": "ok", "config": cfg})
        elif self.path == "/api/test_provider":
            res = test_provider_connection(req)
            self._send_json(200, res)
        elif self.path == "/api/openrouter/balance":
            api_key = req.get("key") or load_config().get("openrouter_key", "")
            res = check_openrouter_balance(api_key)
            self._send_json(200, res)
        elif self.path == "/api/history/delete":
            item_id = req.get("id")
            if item_id:
                delete_history_item(str(item_id))
            self._send_json(200, {"status": "ok"})
        elif self.path == "/api/history/clear":
            clear_all_history()
            self._send_json(200, {"status": "ok"})
        else:
            self._send_json(404, {"error": "not found"})


if __name__ == "__main__":
    READY_EVENT.wait()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), DaemonHandler)
    print(f"[WhisperDaemon] Serving Golden Gate Glass on http://127.0.0.1:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        TASK_QUEUE.put(None)
