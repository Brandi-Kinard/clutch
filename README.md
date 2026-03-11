<p align="center">
  <img src="docs/clutch-banner.png" alt="Clutch Banner" width="100%">
</p>

<h1 align="center">🔧 Clutch</h1>

<p align="center">
  <strong>The only tool in your box that tells you what to do next.</strong>
</p>

<p align="center">
  <a href="https://clutch-vyt2xlbryq-uc.a.run.app">Live Demo</a> · <a href="#demo-video">Demo Video</a> · <a href="#architecture">Architecture</a> · <a href="#quick-start">Quick Start</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Gemini_Live_API-Bidi_Streaming-4285F4?style=flat-square&logo=google" alt="Gemini">
  <img src="https://img.shields.io/badge/Google_ADK-Agent_Framework-34A853?style=flat-square&logo=google-cloud" alt="ADK">
  <img src="https://img.shields.io/badge/Cloud_Run-Deployed-FF6F00?style=flat-square&logo=google-cloud" alt="Cloud Run">
  <img src="https://img.shields.io/badge/Imagen_4-Fast-EA4335?style=flat-square&logo=google" alt="Imagen 4">
  <img src="https://img.shields.io/badge/Ray--Ban_Meta-Smart_Glasses-0668E1?style=flat-square&logo=meta" alt="Meta">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT">
</p>

---

## What is Clutch?

Clutch is an AI agent that **sees real-world tasks through smart glasses** and provides **step-by-step how-to guidance** with voice narration, AI-generated images, and YouTube tutorials.

Put on your Ray-Ban Meta smart glasses (or point your phone camera), ask *"How do I check my oil?"*, and Clutch:

1. **Sees** your environment through the glasses camera
2. **Generates** a step-by-step wizard with AI images for each step
3. **Narrates** instructions via real-time voice conversation
4. **Finds** relevant YouTube tutorials
5. **Speaks your language** — switch between English, Spanish, Vietnamese, French, and Mandarin mid-conversation

> **Built for the [Gemini Live Agent Challenge](https://geminiliveagentchallenge.devpost.com/)** — breaking the "text box" paradigm with immersive, multimodal AI.

---

## Demo Video

<!-- TODO: Replace with actual YouTube embed -->
[![Clutch Demo](docs/demo-thumbnail.png)](https://youtube.com/watch?v=YOUR_VIDEO_ID)

*4-minute demo showing: oil check guidance via smart glasses, kitchen knife techniques, and live language switching to Spanish.*

---

## Key Features

| Feature | Description |
|---------|-------------|
| 🗣️ **Real-time Voice** | Bidi-streaming audio via Gemini Live API — talk naturally, interrupt anytime |
| 👓 **Smart Glasses Vision** | Ray-Ban Meta Wayfarer camera streams through Meta DAT SDK → Gemini sees what you see |
| 📋 **Step-by-Step Wizard** | AI-generated procedures with Back/Next navigation and progress tracking |
| 🎨 **AI Step Images** | Imagen 4 Fast generates reference images for each step in parallel (~2s for 4 images) |
| 🎬 **YouTube Integration** | Relevant video tutorials surfaced at task completion via YouTube Data API v3 |
| 🌍 **Cross-Lingual** | Switch languages mid-conversation — EN, ES, VI, FR, ZH with forced language compliance |
| 📱 **Dual Interface** | Native iOS app (SwiftUI + Meta DAT SDK) and responsive web app (WebRTC fallback) |
| 📄 **PDF Export** | Download your step-by-step guide as a portable PDF |

---

## Architecture

<p align="center">
  <img src="docs/architecture.svg" alt="Clutch Architecture Diagram" width="100%">
</p>

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER DEVICES                             │
│                                                                 │
│  ┌──────────────────┐     ┌──────────────────────────────────┐  │
│  │ Ray-Ban Meta      │     │ iPhone Companion App             │  │
│  │ Wayfarer Gen 2    │ BT  │ (SwiftUI + Meta DAT SDK v0.4)   │  │
│  │ • 12MP Camera     ├────►│ • Audio capture/playback (16kHz) │  │
│  │ • 5-mic array     │     │ • Camera frame streaming         │  │
│  │ • BT speakers     │     │ • Wizard UI + Chat bubbles       │  │
│  └──────────────────┘     └──────────┬───────────────────────┘  │
│                                      │ WebSocket (wss://)       │
│  ┌───────────────────────────────────┼───────────────────────┐  │
│  │ Safari / Chrome Web App           │ (WebRTC fallback)     │  │
│  │ • Responsive dark UI              │                       │  │
│  │ • Camera preview + voice          │                       │  │
│  └───────────────────────────────────┘                       │  │
└──────────────────────────────────────┼───────────────────────┘──┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │     GOOGLE CLOUD RUN                 │
                    │     (us-central1, min-instances=1)   │
                    │                                      │
                    │  ┌────────────────────────────────┐  │
                    │  │  Python WebSocket Server        │  │
                    │  │  (server.py + websockets)       │  │
                    │  └──────────┬─────────────────────┘  │
                    │             │                         │
                    │  ┌──────────▼─────────────────────┐  │
                    │  │  ADK Agent (agent.py)           │  │
                    │  │  Model: gemini-2.0-flash-exp    │  │
                    │  │  Mode: bidi-streaming AUDIO     │  │
                    │  │                                 │  │
                    │  │  Tools:                         │  │
                    │  │  ├── generate_steps             │  │
                    │  │  ├── search_youtube             │  │
                    │  │  └── advance_step               │  │
                    │  └──────────┬─────────────────────┘  │
                    └─────────────┼─────────────────────────┘
                                  │
              ┌───────────────────┼───────────────────────┐
              │                   │                       │
    ┌─────────▼──────┐  ┌────────▼───────┐  ┌───────────▼──────┐
    │ Gemini 2.5      │  │ Imagen 4 Fast  │  │ YouTube Data     │
    │ Flash           │  │ (image gen)    │  │ API v3           │
    │ (step planning) │  │ 4 images in    │  │ (tutorial search)│
    │                 │  │ parallel ~2s   │  │                  │
    └─────────────────┘  └────────────────┘  └──────────────────┘
```

### Data Flow

1. **Audio In** — User speaks → 16kHz PCM captured on device → sent as base64 chunks over WebSocket
2. **Video In** — Glasses camera (720p/30fps via DAT SDK) or phone camera (500ms JPEG frames) → base64 over WebSocket
3. **Agent Processing** — ADK agent receives audio+video → Gemini Live API processes multimodally → returns audio response + tool calls
4. **Tool Execution** — `generate_steps` calls Gemini 2.5 Flash for step planning + Imagen 4 Fast for parallel image generation → returns structured wizard data
5. **Audio Out** — Agent voice response streamed back as PCM chunks → played through device speakers/glasses

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **AI Models** | Gemini 2.0 Flash (live streaming), Gemini 2.5 Flash (step generation), Imagen 4 Fast (step images) |
| **Agent Framework** | Google Agent Development Kit (ADK) v1.26 |
| **Backend** | Python 3.11, WebSockets (websockets lib), asyncio |
| **Cloud** | Google Cloud Run (session affinity, 3600s timeout), Cloud Build CI/CD |
| **iOS App** | SwiftUI, AVAudioEngine (16kHz PCM), AVCaptureSession, Meta Wearables DAT SDK v0.4 |
| **Web App** | Vanilla HTML/CSS/JS, WebRTC getUserMedia, Web Audio API, Material Symbols |
| **APIs** | Gemini Live API (bidiGenerateContent), YouTube Data API v3, Imagen 4 API |

---

## Quick Start

### Prerequisites

- Python 3.11+
- Google Cloud API key with Gemini, YouTube, and Imagen enabled
- (Optional) Xcode 26+ for iOS app
- (Optional) Ray-Ban Meta Wayfarer Gen 2 + Meta AI app

### 1. Clone and Configure

```bash
git clone https://github.com/Brandi-Kinard/clutch.git
cd clutch

# Copy env template and add your keys
cp backend/.env.example backend/.env
# Edit backend/.env with your API keys:
#   GOOGLE_API_KEY=your_gemini_api_key
#   YOUTUBE_API_KEY=your_youtube_api_key
```

### 2. Run Locally

```bash
cd backend
pip install -r requirements.txt
python3 server.py
# Server starts on http://localhost:8080
```

Open `http://localhost:8080` in your browser. Allow microphone and camera access.

### 3. Test on Phone (HTTPS required for camera/mic)

```bash
# In a new terminal
ngrok http 8080
# Open the ngrok HTTPS URL on your phone
```

### 4. Deploy to Cloud Run

```bash
cd clutch
./scripts/deploy.sh
# Builds remotely via Cloud Build, deploys with:
#   min-instances=1, session-affinity, timeout=3600s
#   Reads API keys from backend/.env → Cloud Run env vars
```

### 5. iOS App (Optional)

```bash
cd ios-app/Clutch
open Clutch.xcodeproj
# Build and run on a physical iPhone (camera required)
# For Ray-Ban Meta glasses: enable Developer Mode in Meta AI app
```

---

## Project Structure

```
clutch/
├── backend/
│   ├── agent/
│   │   └── agent.py              # ADK Agent with 11-rule system prompt
│   ├── tools/
│   │   ├── generate_steps.py     # Step planning + Imagen 4 parallel image gen
│   │   ├── search_youtube.py     # YouTube Data API v3 search
│   │   └── advance_step.py       # Wizard navigation signal
│   ├── server.py                 # WebSocket server + HTTP static serving
│   └── requirements.txt
├── web-app/
│   └── index.html                # Full responsive web client (~1200 lines)
├── ios-app/
│   └── Clutch/
│       ├── ClutchApp.swift       # App entry point + DAT SDK init
│       ├── SessionView.swift     # Live session UI with chat + wizard
│       ├── WebSocketManager.swift # Full WS client with auto-reconnect
│       ├── AudioManager.swift    # 16kHz PCM capture + BT routing
│       ├── DATManager.swift      # Meta DAT SDK: registration, streaming, retry
│       └── ...
├── scripts/
│   └── deploy.sh                 # Cloud Run deployment (IaC)
├── cloudbuild.yaml               # CI/CD pipeline
├── Dockerfile                    # Cloud Run container
└── README.md
```

---

## How It Works

### The Agent

Clutch's agent uses a carefully crafted 11-rule system prompt that enforces:
- **Concise responses** (1-2 sentences max per step)
- **Tool-first behavior** (generate steps before narrating)
- **Language compliance** (forced switching on user request)
- **Safety awareness** (warns about dangerous situations)
- **No JSON leakage** (never speaks formatting characters)

### Smart Glasses Integration

The Meta DAT SDK integration includes:
- **Auto-registration** with retry logic for device discovery
- **Camera permission** flow via deep link (`clutch://` URL scheme)
- **Stream session** with 3-attempt retry on `internalError`
- **30fps video** forwarded as JPEG over WebSocket to Gemini

### Image Generation Pipeline

```
User asks "How do I check my oil?"
    ↓
generate_steps tool called
    ↓
Gemini 2.5 Flash → 6 structured steps (JSON)
    ↓
Imagen 4 Fast → 4 images generated in parallel (~2s)
    ↓
Steps + images sent to frontend as wizard card
```

---

## Deployment

The app is deployed on Google Cloud Run with automated CI/CD:

- **Cloud Build** (`cloudbuild.yaml`) — builds Docker image remotely
- **deploy.sh** — orchestrates API enablement, Artifact Registry, build, and deployment
- **Configuration** — min-instances=1, session-affinity (WebSocket), 3600s timeout, unauthenticated access

**Live URL:** [https://clutch-vyt2xlbryq-uc.a.run.app](https://clutch-vyt2xlbryq-uc.a.run.app)

**GCP Project:** `clutch-489301`

---

## Hackathon Details

- **Hackathon:** [Gemini Live Agent Challenge](https://geminiliveagentchallenge.devpost.com/)
- **Track:** Live Agents
- **Builder:** [Brandi Kinard](https://github.com/Brandi-Kinard)
- **GDG Profile:** [gdg.community.dev/u/m2afcw](https://gdg.community.dev/u/m2afcw/#/about)

*Created for the Gemini Live Agent Challenge hackathon. #GeminiLiveAgentChallenge*

---

## License

MIT — see [LICENSE](LICENSE) for details.
