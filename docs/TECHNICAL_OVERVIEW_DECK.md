# Medina Technical Overview - Presentation Content

**Last Updated:** December 30, 2025

---

# CONDENSED VERSION (6 Slides)

---

## SLIDE 1: Platform Overview

### **Medina: AI Fitness Intelligence Platform**

```
┌────────────────────────────────────────────────────────────────┐
│                                                                 │
│    41,000+ LINES OF SERVICE CODE                               │
│                                                                 │
│    ┌─────────────────┐         ┌─────────────────┐            │
│    │    BACKEND      │         │   iOS CLIENT    │            │
│    │   13,000 LOC    │         │   28,000 LOC    │            │
│    │                 │         │                 │            │
│    │  9 API Endpoints│         │  17 Service     │            │
│    │  22 Tool Handlers│        │     Domains     │            │
│    │  6 Prompt Modules│        │  91 Swift Files │            │
│    │  5 Algorithms   │         │  Voice + Exec   │            │
│    └─────────────────┘         └─────────────────┘            │
│                                                                 │
│    ─────────────────────────────────────────────              │
│    OpenAI GPT-4o  •  Firebase  •  Firestore                   │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

---

## SLIDE 2: Backend Intelligence Layer

### **9 API Endpoints + 22 Tool Handlers**

| Layer | Components | Capabilities |
|-------|------------|--------------|
| **Chat API** | `/api/chat` | SSE streaming, tool orchestration |
| **Calculate API** | 5 algorithms | 1RM, recency-weighted, intensity |
| **Import API** | 4-stage pipeline | CSV → Match → Analyze → Persist |
| **Selection API** | Scoring engine | Library-first, diversity, balance |
| **Tool Handlers** | 22 handlers | Workout, Plan, Exercise, Analytics |
| **Prompt Engine** | 6 modules | Context-aware prompt assembly |

**This is not "22 things" — it's a complete fitness intelligence API.**

---

## SLIDE 3: Sophisticated Algorithms

### **What Powers the AI**

**Recency-Weighted 1RM:**
```
weight = Σ(session.best1RM × e^(-days × ln(2)/14)) / Σ(decay)
```
↳ Recent PRs matter more than old ones

**Import Intelligence:**
```
CSV → Parse → Match exercises → Infer experience → Build profile
```
↳ Detects training style, split type, muscle emphasis

**Exercise Selection:**
```
Library(1.2×) + Emphasis(1.5×) + Balance(1.3×) + Diversity
```
↳ Personalized, balanced workouts every time

---

## SLIDE 4: Prompt Engineering

### **Dynamic Context Assembly**

```
SYSTEM PROMPT (built per-request)
├── Base Identity (coach persona)
├── User Context
│   ├── Profile (goals, experience, equipment)
│   ├── Active workout state
│   └── Plan progress
├── Training Data
│   ├── Strength records (1RM history)
│   └── Exercise preferences
├── Behavioral Rules
├── Tool Instructions (22 tools)
└── Safety Warnings
```

**1,200+ LOC of prompt engineering** — not string concatenation.

---

## SLIDE 5: iOS Client Services

### **28,000 LOC Across 17 Domains**

| Domain | Purpose |
|--------|---------|
| **Voice/** | STT → AI → TTS pipeline |
| **WorkoutExecution/** | Live session state machine |
| **Calculations/** | Weight/1RM formulas |
| **Import/** | Photo + CSV extraction |
| **Exercise/** | Selection algorithms |
| **Firebase/** | Auth + Firestore repos |
| **Plan/** | Periodization logic |
| + 10 more... | |

**iOS-only:** Voice mode, Apple Health, offline sync, haptics

---

## SLIDE 6: Technical Summary

### **By The Numbers**

| Metric | Value |
|--------|-------|
| Total Service Code | **41,000+ LOC** |
| API Endpoints | **9** |
| AI Tool Handlers | **22** (100% server-side) |
| Prompt Modules | **6** |
| Calculation Algorithms | **5** |
| Import Pipeline Stages | **4** |
| iOS Service Domains | **17** |
| Exercise Database | **200+** |
| Protocol Library | **50+** |

**Not a chatbot with 22 functions — a full fitness intelligence platform.**

---

---

# FULL VERSION (14 Slides)

---

## SLIDE 1: Service Layer Overview

### **Medina Service Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│                   MEDINA PLATFORM                            │
│                                                              │
│   41,000+ Lines of Service Code                             │
│   ═══════════════════════════════════════════════           │
│                                                              │
│   ┌──────────────────────┐    ┌──────────────────────┐     │
│   │  FIREBASE BACKEND    │    │   iOS SERVICES       │     │
│   │  13,000 LOC          │    │   28,000 LOC         │     │
│   │                      │    │                      │     │
│   │  • 9 API Endpoints   │    │  • 91 Swift Files    │     │
│   │  • 22 Tool Handlers  │    │  • 17 Domains        │     │
│   │  • 6 Prompt Modules  │    │  • Voice Mode        │     │
│   │  • 1,140 LOC Schema  │    │  • Workout Execution │     │
│   └──────────────────────┘    └──────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Key Stats:**
- 9 HTTP API endpoints
- 22 AI-orchestrated tool handlers
- 6 prompt engineering modules
- 5 calculation algorithms
- 4-stage import pipeline
- Real-time SSE streaming

---

## SLIDE 2: API Endpoint Layer

### **Backend API Endpoints**

| Endpoint | Function | Complexity |
|----------|----------|------------|
| `/api/chat` | AI conversation with tool calling | SSE streaming, 22 tools |
| `/api/calculate` | Weight & strength calculations | 5 algorithms |
| `/api/import` | CSV import + analysis | 4-stage pipeline |
| `/api/selectExercises` | Intelligent exercise selection | Scoring engine |
| `/api/tts` | Text-to-speech | OpenAI proxy |
| `/api/vision` | Image analysis | GPT-4o vision |
| `/api/chatSimple` | Simple completions | Non-streaming |
| `/api/getUser` | User data retrieval | Auth-gated |
| `/seed*` | Database seeding | Admin tools |

**Not just a chat endpoint** - A complete fitness intelligence API.

---

## SLIDE 3: Calculation Engine

### **Calculation Service - 5 Algorithms**

```
POST /api/calculate
├── oneRM          → Epley formula: weight × (1 + reps/30)
├── weightForReps  → Inverse Epley: oneRM / (1 + reps/30)
├── best1RM        → Quality-weighted set selection
├── recency1RM     → 14-day half-life weighted average
└── targetWeight   → Intensity-based weight prescription
```

**Recency-Weighted 1RM Algorithm:**
```
weight = Σ(session.best1RM × decay) / Σ(decay)
where decay = e^(-daysAgo × ln(2) / 14)
```

- Handles historical data intelligently
- Accounts for training recency
- Prevents stale PRs from dominating

---

## SLIDE 4: Import Intelligence Pipeline

### **Import Service - 4-Stage Pipeline**

```
CSV Upload
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  STAGE 1: PARSE                                              │
│  • Detect format (Strong, Hevy, custom)                      │
│  • Extract sessions, exercises, sets                         │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  STAGE 2: MATCH                                              │
│  • Fuzzy match to 200+ exercise database                     │
│  • Confidence scoring, variant detection                     │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  STAGE 3: ANALYZE (Intelligence)                             │
│  • Infer experience level (4 indicators)                     │
│  • Detect training style, split pattern                      │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  STAGE 4: PERSIST                                            │
│  • Create strength targets, library entries                  │
│  • Generate historical workouts                              │
└─────────────────────────────────────────────────────────────┘
```

**Intelligence Output:**
```json
{
  "inferredExperience": "intermediate",
  "trainingStyle": "hypertrophy-focused",
  "topMuscleGroups": ["chest", "back", "shoulders"],
  "inferredSplit": "push_pull_legs",
  "confidenceScore": 0.82
}
```

---

## SLIDE 5: Exercise Selection Engine

### **Exercise Selection - Intelligent Matching**

**Algorithm Steps:**

```
1. BUILD POOL
   ├── Start with user's library (★ favorites)
   ├── Filter by available equipment
   └── Expand pool if insufficient

2. SCORE EXERCISES
   ├── Library preference    → 1.2× boost
   ├── Emphasis match        → 1.5× boost
   ├── Muscle balance        → 1.3× boost
   └── Bodyweight preference → 1.4× boost

3. SELECT WITH DIVERSITY
   ├── Compounds: movement pattern diversity
   └── Isolations: muscle balance priority
```

**Not random selection** - Balanced, personalized workouts every time.

---

## SLIDE 6: Prompt Engineering Layer

### **AI Prompt Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│                    SYSTEM PROMPT BUILDER                     │
│                                                              │
│   buildSystemPrompt(options)                                │
│   │                                                          │
│   ├── BASE_IDENTITY                                          │
│   │   "You are Medina, a personal fitness coach..."         │
│   │                                                          │
│   ├── USER CONTEXT                                           │
│   │   ├── Profile (goals, experience, equipment)            │
│   │   ├── Current workout state                             │
│   │   └── Active plan progress                              │
│   │                                                          │
│   ├── TRAINING DATA CONTEXT                                  │
│   │   ├── Strength targets (1RM records)                    │
│   │   └── Exercise affinity (favorites, history)            │
│   │                                                          │
│   ├── CORE RULES (behavioral guardrails)                     │
│   │                                                          │
│   ├── TOOL INSTRUCTIONS (22 tools × detailed guidance)      │
│   │                                                          │
│   └── EXAMPLES + WARNINGS                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**6 Modules, 1,200+ LOC of prompt engineering**

---

## SLIDE 7: Tool Handler Architecture

### **22 AI Tool Handlers**

| Category | Handlers | Purpose |
|----------|----------|---------|
| **Workout** | `create` `start` `end` `reset` `modify` | Full workout lifecycle |
| **Plan** | `create` `activate` `abandon` `delete` `reschedule` | Multi-week programs |
| **Exercise** | `add_to_library` `remove_from_library` `update_target` `change_protocol` `get_substitutions` `get_summary` | Library & customization |
| **Schedule** | `show_schedule` `skip_workout` | Calendar management |
| **Profile** | `update_profile` | User preferences |
| **Analytics** | `analyze_training_data` | Training insights |
| **Communication** | `send_message` `suggest_options` | UX & messaging |

**Each handler:** validation, Firestore ops, SSE events, error handling

---

## SLIDE 8: iOS Service Domains

### **28,000 LOC Across 17 Domains**

```
ios/Medina/Services/
├── Voice/              ← STT, TTS, Voice Mode (7 files)
├── WorkoutExecution/   ← Live session state machine
├── Calculations/       ← 1RM, weights (730 LOC)
├── Import/             ← Photo/CSV extraction (1,500 LOC)
├── Exercise/           ← Selection algorithms (2,500 LOC)
├── Firebase/           ← Auth, Firestore repositories
├── Assistant/          ← AI integration layer
├── Workout/            ← Session coordination
├── Plan/               ← Periodization, scheduling
├── Protocol/           ← Training protocol resolution
├── Resolvers/          ← Entity resolution
├── Metrics/            ← Performance metrics
├── Library/            ← User exercise library
├── Actions/            ← User action handlers
├── Core/               ← Shared utilities
├── Filtering/          ← Exercise filtering
└── Greeting/           ← Personalized greetings
```

**91 Swift files across 17 service domains**

---

## SLIDE 9: iOS-Only Features

### **iOS Exclusive Capabilities**

| Feature | Service | Description |
|---------|---------|-------------|
| **Voice Mode** | `Voice/` | Full STT → AI → TTS pipeline |
| **Workout Execution** | `WorkoutExecution/` | Live set logging, rest timers |
| **Apple Health** | `HealthKit/` | Sync workouts to Health app |
| **Photo Import** | `Import/` | Extract workout data from photos |
| **Offline Support** | `DeltaStore` | Queue changes for sync |

**These remain on iOS because:**
- Platform-specific APIs (HealthKit, Speech)
- Real-time UX requirements
- Hardware integration (microphone, haptics)

---

## SLIDE 10: Data Flow Architecture

### **End-to-End Request Flow**

```
User: "Create a push workout for tomorrow"
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  1. AUTHENTICATION                                           │
│     Verify Firebase ID token, extract uid                   │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  2. CONTEXT ASSEMBLY                                         │
│     Load profile, training data, build 2-4K token prompt    │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  3. OPENAI RESPONSES API                                     │
│     Stream response, receive tool call: create_workout      │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  4. TOOL HANDLER EXECUTION                                   │
│     Validate, resolve protocols, calculate weights, persist │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  5. SSE RESPONSE                                             │
│     Stream text + workout_card event to client              │
└─────────────────────────────────────────────────────────────┘
```

---

## SLIDE 11: Migration Status

### **Server vs Client Distribution**

```
                    MIGRATED TO SERVER
┌─────────────────────────────────────────────────────────────┐
│  ✅ All 22 tool handlers                                     │
│  ✅ Calculate service (5 algorithms)                         │
│  ✅ Import service (4-stage pipeline)                        │
│  ✅ Exercise selection (scoring engine)                      │
│  ✅ Prompt engineering (6 modules)                           │
└─────────────────────────────────────────────────────────────┘

                    REMAINS ON iOS
┌─────────────────────────────────────────────────────────────┐
│  📱 Voice Mode (platform-specific APIs)                      │
│  📱 Workout Execution (real-time UX)                         │
│  📱 Apple Health integration                                 │
│  📱 Photo import (on-device ML)                              │
│  📱 Offline delta sync                                       │
└─────────────────────────────────────────────────────────────┘
```

**100% of AI tool handlers now server-side**

---

## SLIDE 12: Technical Complexity Summary

### **By the Numbers**

| Metric | Value |
|--------|-------|
| **Total Service Code** | 41,000+ LOC |
| **Backend (TypeScript)** | 13,000 LOC |
| **iOS Services (Swift)** | 28,000 LOC |
| **HTTP API Endpoints** | 9 |
| **AI Tool Handlers** | 22 |
| **Prompt Modules** | 6 |
| **Context Builders** | 3 |
| **Calculation Algorithms** | 5 |
| **Import Pipeline Stages** | 4 |
| **Exercise Database** | 200+ exercises |
| **Protocol Library** | 50+ training protocols |
| **iOS Service Domains** | 17 |
| **Swift Service Files** | 91 |
| **Tool Definition Schema** | 1,140 LOC |

---

## SLIDE 13: Competitive Differentiation

### **vs. Generic Fitness Apps**

| Feature | Generic Apps | Medina |
|---------|--------------|--------|
| Workout creation | Template-based | **AI-generated, personalized** |
| Exercise selection | Manual picking | **Intelligent scoring algorithm** |
| Progress tracking | Basic logging | **1RM inference, recency-weighted** |
| Import | None or basic | **4-stage pipeline with intelligence** |
| Personalization | Profile settings | **Dynamic context per request** |

### **vs. "AI-Powered" Competitors**

| Capability | Typical "AI" Apps | Medina |
|------------|-------------------|--------|
| AI usage | Generic prompts | **22 specialized tools** |
| Context | Static profile | **Dynamic per-request context** |
| Tool calling | None | **Full OpenAI tool orchestration** |
| Prompt engineering | Basic | **1,200+ LOC, 6 modules** |

---

## SLIDE 14: Technical Moat

### **What's Hard to Replicate**

| Component | Effort | Why It's Hard |
|-----------|--------|---------------|
| 22 Tool Handlers | 3-4 months | Domain expertise required |
| Prompt Engineering | 2-3 months | Iterative refinement |
| Calculation Algorithms | 1-2 months | Sports science knowledge |
| Import Pipeline | 2-3 months | Format handling, matching |
| Exercise Selection | 1-2 months | Scoring tuning |
| Voice Integration | 2-3 months | Platform APIs, UX polish |
| Cross-Platform Sync | 1-2 months | Edge cases, conflicts |
| **Total** | **12-18 months** | With experienced team |

**41,000 LOC of fitness-specific code is not trivial to replicate.**

---

# APPENDIX: System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MEDINA PLATFORM                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐                          ┌──────────────────┐        │
│  │    iOS APP       │                          │    WEB APP       │        │
│  │    (SwiftUI)     │                          │    (Next.js)     │        │
│  │    28,000 LOC    │                          │                  │        │
│  └────────┬─────────┘                          └────────┬─────────┘        │
│           │                                             │                   │
│           │         Firebase Auth (Apple/Google)        │                   │
│           └─────────────────┬───────────────────────────┘                   │
│                             │                                                │
│                             ▼                                                │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                    FIREBASE BACKEND (13,000 LOC)                      │  │
│  ├──────────────────────────────────────────────────────────────────────┤  │
│  │                                                                       │  │
│  │   API LAYER          PROMPT ENGINE        TOOL HANDLERS              │  │
│  │   ───────────        ─────────────        ─────────────              │  │
│  │   /chat              systemPrompt         22 handlers                │  │
│  │   /calculate         coreRules            ~6,500 LOC                 │  │
│  │   /import            toolInstructions                                │  │
│  │   /selectExercises   contextBuilders                                 │  │
│  │   /tts, /vision                                                      │  │
│  │                                                                       │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                             │                                                │
│                             ▼                                                │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │   OPENAI (GPT-4o-mini)  │  FIRESTORE  │  FIREBASE AUTH               │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```
