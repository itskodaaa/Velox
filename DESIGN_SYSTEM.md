# Mumblr &bull; Brand & Design System Specification

## 1. Brand Identity & Product Archetype

* **Brand Name:** Mumblr
* **Product Archetype:** High-End Desktop Voice Intelligence & Speech Studio (Desktop App for macOS & Googlebook OS)
* **Core Personality:** Elegant, soft, approachable, modern luxury, tactile, organized, and tranquil.
* **Design Motif:** Soft rounded cards (22px), pastel tinted surfaces, smooth diffused ambient occlusion, low-contrast dark charcoal typography on warm tinted porcelain backgrounds, and deep charcoal anchor badges (`#121214`).

---

## 2. Color Palette System

### 2.1 Base & Surfaces
| Token Name | Hex Code | Purpose / Usage |
| :--- | :--- | :--- |
| **Canvas Backdrop Start** | `#F3C7B5` | Window surrounding backdrop gradient top-left |
| **Canvas Backdrop End** | `#EBBFA9` | Window surrounding backdrop gradient bottom-right |
| **Main App Surface** | `#FAF4EB` | App window body, navigation rail, and primary background |
| **Subtle App Surface** | `#FDF8F0` | Warm porcelain white for alternate panels and sidebars |
| **Card Surface (Default)** | `#F6EFE3` | Soft warm beige for timeline cards, settings modules, and bento containers |
| **Card Surface (Alt/Muted)** | `#F3ECE0` | Secondary inner containers and grouped modules |
| **Pure Contrast Surface** | `#FFFFFF` | Reserved strictly for active navigation pills, input fields, and micro-action circular chips |

### 2.2 Typography & Structural Accents
| Token Name | Hex Code | Purpose / Usage |
| :--- | :--- | :--- |
| **Primary Text** | `#1A1A1E` | Soft carbon black for headlines, card titles, and transcribed copy |
| **Muted / Secondary Text** | `#686460` | Neutral stone gray for timestamps, metadata, and hints |
| **Anchor Badge Fill** | `#121214` | Deep charcoal circular badges anchoring card headers and section titles |
| **Anchor Badge Icon** | `#FFFFFF` | Pure white micro-icons inside charcoal badges |
| **Border / Rule Line** | `rgba(0, 0, 0, 0.03)` | Micro-fine divider lines and card borders |

### 2.3 Metric & Status Tint System (Pastel Palette)
Every pastel wash is paired with an exact high-contrast foreground tone:

| Pastel Name | Background Hex | Contrast Text Hex | Semantic Role in App |
| :--- | :--- | :--- | :--- |
| **Soft Peach / Amber** | `#FCE3B4` | `#7A4C18` | Total Words Spoken metric, active pet highlights, amber badges |
| **Pastel Sky Blue** | `#BCE2F9` | `#1C5578` | Words Per Minute (WPM) speed metric, Groq LPU latency tags, active license status |
| **Pastel Lilac / Purple** | `#D5B8F6` | `#4D2A78` | Week streak record, Phonetic Healing indicators, acoustic tags |
| **Pastel Salmon / Coral** | `#F8C6BC` | `#7D2F22` | Quota & usage warnings, alert pills, upgrade prompts |
| **Pastel Rose / Blush** | `#F9C0CC` | `#832239` | Notetaker tags, creative transforms, voice emotion signals |
| **Pastel Lavender / Orchid**| `#E2B2E6` | `#65256D` | Acoustic voice profile progress track and personalized insights |

---

## 3. Typography System

* **Primary Font Family:** `Plus Jakarta Sans`, `-apple-system`, `BlinkMacSystemFont`, sans-serif (Geometric Humanist)
* **Secondary / Metric Font:** `Plus Jakarta Sans` (or `Newsreader` for editorial numeric highlights)
* **Monospace Font:** `Geist Mono`, `SF Mono`, `monospace` (for API keys and audio latency readouts)

### Hierarchy & Scale Specifications
* **Brand Title:** Bold / Semi-bold, `19px`, tracking `-0.02em` (`Mumblr`)
* **Welcome / Section Headline:** Bold, `26px–28px`, tracking `-0.02em` (`Welcome back, Aura`)
* **Card & Module Title:** Bold / Semi-bold, `15px–16px`, tracking `0`
* **KPI / Metric Numbers:** Bold, `24px–28px`, tracking `-0.02em` (`40.9K`, `132 wpm`)
* **Body / Transcribed Text:** Regular, `14px`, line-height `1.65` (`#1A1A1E`)
* **Metadata & Secondary Hints:** Medium / Regular, `11px–12px`, stone gray (`#686460`)
* **Pills & Badges:** Bold / Semi-bold, `10px–11px`, tracking `0.04em`, uppercase or title case

---

## 4. UI Geometry & Component Standards

### 4.1 Corner Radii
* **Main Shell Container:** `36px` continuous curvature
* **Hero Promo Banners:** `24px`
* **Major Content & History Cards:** `22px`
* **Metric Tiles & Voice Profile Modules:** `20px`
* **Inner Module Cards:** `18px`
* **Interactive Pills, Badges & Nav Tabs:** `9999px` (Full continuous pill shape)
* **Avatars & Anchor Badges:** `50%` (Circular)

### 4.2 Elevation & Shadows
* **Main App Window:** `box-shadow: 0 24px 80px rgba(70, 50, 40, 0.14)` (Warm ambient diffused shadow)
* **Content Cards:** `box-shadow: 0 4px 20px rgba(70, 50, 40, 0.04)`
* **Active Navigation Pills:** `box-shadow: 0 4px 14px rgba(70, 50, 40, 0.05)`
* **Micro-Actions & Buttons:** `box-shadow: 0 2px 6px rgba(70, 50, 40, 0.03)`

### 4.3 Component Anatomy Rules
1. **Navigation Item:**
   - Default: Transparent background, `#686460` text, `9999px` pill radius, `10px 16px` padding.
   - Hover: `#F6EFE3` background, `#1A1A1E` text.
   - Active: Pure `#FFFFFF` background, `#1A1A1E` bold text, ambient diffused shadow.
2. **Card Heading Anchor:**
   - Every major card starts with a `24px × 24px` circular badge filled with `#121214` containing a pure white (`#FFFFFF`) micro-icon.
3. **Pill Action Chips:**
   - Background `#FFFFFF`, text `#1A1A1E`, border `1px solid rgba(0,0,0,0.03)`, radius `9999px`, padding `6px 14px`.
4. **Form Controls:**
   - Text inputs and dropdowns use `#FFFFFF` background, `1px solid rgba(0,0,0,0.06)` border, and full `9999px` pill radius.
   - Toggle switches use `#EBBFA9` track off, `#121214` track on, and white circular thumbs.

---

## 5. Unbreakable Design Directives

1. **Banned Harsh White Backgrounds:** Never use harsh stark white (`#FFFFFF`) as a full window, section, or card background. Always use warm porcelain ivory (`#FAF4EB`) for surfaces and soft warm beige (`#F6EFE3`) for cards.
2. **Tonal Contrast Over Heavy Borders:** Do not use dark, heavy borders. Rely on subtle shifts across the pastel system (peach, sky blue, lilac, salmon, blush) and micro-fine borders (`1px solid rgba(0, 0, 0, 0.03)`).
3. **Full-Radius Pill Geometry:** All interactive triggers, status chips, search bars, and active navigation indicators must use `9999px` continuous pill radius.
4. **Generous Boutique Padding:** Maintain a minimum of `20px–26px` inner padding inside content cards to preserve an airy, comfortable, luxury aesthetic.
5. **Charcoal Visual Anchors:** Always pair `#121214` circular badges with white micro-icons to anchor card titles and create clear, grounded visual focal points.
