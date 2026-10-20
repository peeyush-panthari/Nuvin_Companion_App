# NUVIN: Unified Product & Engineering System
*A Trusted, Consent-First AI Companion & Assistant for Everyday Life (Elder 55+ and Ear 20–50)*

Formerly referred to in early planning documents as *Saathi*, officially rebranded and architected as **Nuvin**.

---

## 1. System Architecture Overview

```
+----------------------------------------------------------------------------------+
|                                  CLIENT LAYER                                    |
|  +----------------------------------------------------------------------------+  |
|  | Single-Window Shell (Voice Orb + OpenUI Chat + Persistent SOS)             |  |
|  | - Mode 1: Open Speaker (Ambient Voice Orb with sub-600ms TTFA)            |  |
|  | - Mode 2: Chat with OpenUI (Interactive dynamic cards for Memory/Reminders)|  |
|  | - Mode 3: Call & Smart Speaker (Hardware Proximity Sensor earpiece routing)|  |
|  | - 100% Offline Local Engine: SQLite + native OS AlarmManager               |  |
|  +----------------------------------------------------------------------------+  |
+---------------------------------------+------------------------------------------+
                                        | (WebSocket Voice Chunks / REST API)
                                        v
+----------------------------------------------------------------------------------+
|                         BACKEND MODULAR MONOLITH                                 |
|  +----------------------------------------------------------------------------+  |
|  | 1. INDEPENDENT TRUST PLANE (Deterministic Gatekeeper)                       |  |
|  |    - Sub-15ms deterministic guardrails (Explicit, Self-harm, Violence)     |  |
|  |    - Dual-language crisis intercept (KIRAN 1800-599-0019 & Tele-MANAS 14416)|  |
|  |    - Coercion & Abuse Defense: Stealth Pause (duress PIN / safe phrase)   |  |
|  |    - WORM (Write-Once-Read-Many) Audit Event Logger                        |  |
|  +----------------------------------------------------------------------------+  |
|  | 2. DUAL PERSONA & WAKE-WORD ENGINE                                         |  |
|  |    - Elder (55+): Respectful honorifics ("Aap/Ji"), 3500ms VAD, 0.85x TTS   |  |
|  |    - Ear (20–50): Peer warmth ("Tum"), 1500ms VAD, anti-sycophantic stance|  |
|  |    - Custom Companion Name + 3-sample Voice Enrollment ("Hey <Name>")      |  |
|  +----------------------------------------------------------------------------+  |
|  | 3. LONGITUDINAL MEMORY & OPENUI VAULT                                      |  |
|  |    - Episodic life threads + discrete facts with sub-10ms turn injection  |  |
|  |    - User-facing Memory Inspection & instant "Forget this" soft-purge      |  |
|  +----------------------------------------------------------------------------+  |
|  | 4. DETERMINISTIC SOS & 8-HOUR LIVE TRACKING                                |  |
|  |    - Immediate siren trigger + SMS/WhatsApp alerts with Google Maps URL    |  |
|  |    - Browser-viewable 8-hour live tracker (/sos/live/{token})              |  |
|  +----------------------------------------------------------------------------+  |
+----------------------------------------------------------------------------------+
```

---

## 2. Directory Structure

```
Nuvin/
├── backend/
│   ├── app/
│   │   ├── config.py                       # App settings, helplines & live tracking URLs
│   │   ├── main.py                         # FastAPI monolith assembly & Static Web Mount
│   │   ├── db/
│   │   │   ├── session.py                  # Async SQLAlchemy Engine & Session Generator
│   │   │   └── schema.sql                  # Complete 12-table PostgreSQL + pgvector DDL
│   │   ├── modules/
│   │   │   ├── trust_plane/
│   │   │   │   ├── guardrails.py           # Sub-15ms Safety Guardrails (Porn, Crisis, Scams)
│   │   │   │   ├── stealth_pause.py        # Coercion Defense & Masked Benign Status
│   │   │   │   └── audit.py                # WORM Audit Event Recorder
│   │   │   ├── users/
│   │   │   │   ├── models.py               # Dual Persona & Age-Band Schemas
│   │   │   │   ├── router.py               # Onboarding & Profile REST Endpoints
│   │   │   │   └── wakeword.py             # 3-Sample Voice Enrollment & Speaker Verification
│   │   │   ├── memory/
│   │   │   │   ├── models.py               # Memory Items, Threads & OpenUI Schemas
│   │   │   │   └── service.py              # Context Retrieval & "Forget this" Purge API
│   │   │   ├── reminders/
│   │   │   │   ├── models.py               # Recurring Reminders & Occurrence Actions
│   │   │   │   └── service.py              # Offline-Sync Manifest Export (for SQLite)
│   │   │   ├── sos/
│   │   │   │   ├── models.py               # Emergency Incident & Location Ping Schemas
│   │   │   │   └── service.py              # 8-Hour Google Maps Web View & Live Coordinates
│   │   │   ├── agent/
│   │   │   │   ├── persona.py              # Persona Prompter (Aap vs Tum, Anti-Robot Rules)
│   │   │   │   └── orchestrator.py         # Conversational Turn Coordinator
│   │   │   └── voice/
│   │   │       ├── pipeline.py             # Streaming Voice Chunker & Barge-In Handler
│   │   │       └── router.py               # WebSocket Voice Gateway & Chat REST API
│   │   └── static/
│   │       └── index.html                  # Interactive Single-Window Web Simulator
│   └── tests/
│       ├── evals/
│       │   └── test_eval_suite.py          # 6 AI Evaluation Benchmarks (TTFA, Pacing, Tropes)
│       ├── test_milestone1.py              # Core Services & Guardrail Tests
│       ├── test_client_web.py              # Web Simulator Delivery Test
│       └── test_milestone4_e2e.py          # E2E Voice Enrollment, Stealth Pause & SOS Tests
└── mobile/                                 # Cross-Platform Flutter Client Codebase
    ├── pubspec.yaml                        # Dependencies (duplex audio, proximity, sqflite)
    └── lib/
        ├── main.dart                       # App entrypoint & Onboarding router
        ├── models/                         # UserProfile & OpenUICard models
        ├── services/                       # AudioManager (proximity/earpiece) & OfflineRemindersDb
        ├── widgets/                        # Glowing VoiceOrb & OpenUICardWidget
        └── screens/                        # OnboardingScreen ("Talk" vs "Type") & MainScreen
```

---

## 3. How to Run & Verify

### Quickstart: Start the Server & Test Simulator
```bash
# In project root
PYTHONPATH=. ./backend/.venv/bin/python backend/app/main.py
```
1. Open **`http://localhost:8000/`** to interact with the **Single-Window Web Companion**:
   - Tap the glowing **Voice Orb** to talk.
   - Switch between **Speaker**, **Chat**, and **Call Mode** (simulating phone held to ear).
   - Ask *"What do you remember about me?"* to see the **OpenUI Memory Vault card** with live *Forget* buttons.
   - Ask *"Remind me to take medicine at 8 AM"* to see the **Reminder card** with *Taken*, *Snooze*, and *Skip* buttons.
   - Tap **🚨 SOS** to trigger the emergency broadcast and open the **8-Hour Google Maps Live Tracker**.
2. Open **`http://localhost:8000/docs`** for interactive Swagger API documentation.

### Run the Full 16-Test Suite & AI Evaluation Benchmarks
```bash
PYTHONPATH=. ./backend/.venv/bin/pytest backend/app/tests/ -v -s
```
*Executes all 16 tests in <0.5 seconds:*
- **TTFA Latency Benchmark**: Verifies conversational response latency is <600ms (tested at ~8ms).
- **Senior Pacing & VAD**: Verifies 3500ms pause tolerance & 0.85x TTS speech rate for 55+.
- **Anti-Robot Naturalness**: Verifies 0% robotic tropes (*"As an AI..."*) and 0% bullet points in spoken output.
- **Honorific Register**: Verifies strict *Aap/Ji* enforcement for 55+ and *Tum* for 20–50.
- **Anti-Sycophancy**: Verifies reality-check grounding for Ear persona.
- **Barge-In Speed**: Verifies instant stream truncation upon client interruption.
- **Trust Plane Safety**: Verifies 100% interception of porn, self-harm (KIRAN helpline), violence, and OTP scams.
- **Custom Wake-Word Enrollment**: Verifies 3-sample voiceprint enrollment.
- **Stealth Pause Defense**: Verifies silent safety ops alert and masked benign status for coercive family members.
- **Deterministic SOS**: Verifies 8-hour live location link and Google Maps breadcrumbs.
