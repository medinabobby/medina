# Medina Architecture

**Last updated:** December 30, 2025 | **Version:** v232

Medina is an AI fitness coach with iOS and web clients sharing a Firebase backend.

---

## Vision

**Server-first, dumb clients.**

All business logic lives on Firebase Functions. Clients are thin UI layers that:
- Display data from Firestore
- Send user actions to server
- Render responses

This enables:
- **Cross-platform parity** - iOS, Android, Web share identical logic
- **Instant updates** - No app store approval for bug fixes
- **Single optimization point** - Improve once, benefit all platforms

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          CLIENTS                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────────┐         ┌──────────────────┐             │
│   │   iOS App        │         │   Web App        │             │
│   │   (SwiftUI)      │         │   (Next.js)      │             │
│   │                  │         │                  │             │
│   │ - UI/Views       │         │ - Chat UI        │             │
│   │ - Workout exec   │         │ - View data      │             │
│   │ - Local state    │         │ - Basic actions  │             │
│   └────────┬─────────┘         └────────┬─────────┘             │
│            │                            │                        │
│            │  Firebase Auth             │  Firebase Auth         │
│            │  (Apple + Google)          │  (Apple + Google)      │
│            │                            │                        │
└────────────┼────────────────────────────┼────────────────────────┘
             │                            │
             ▼                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     FIREBASE BACKEND                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                   Service Layer                           │  │
│   │                                                           │  │
│   │   AI Services          Workout Services     Auth Services │  │
│   │   ├── /api/chat        ├── /api/createWorkout  Firebase   │  │
│   │   ├── /api/tts         ├── /api/modifyWorkout  Auth       │  │
│   │   ├── /api/vision      ├── /api/calculate                 │  │
│   │   └── /api/chatSimple  └── /api/selectExercises           │  │
│   │                                                           │  │
│   │   Data Services        Utility Services                   │  │
│   │   ├── /api/import      ├── /api/initialChips              │  │
│   │   └── Plan endpoints   └── Tool handlers (22)             │  │
│   │                                                           │  │
│   └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                     Firestore                             │  │
│   │                                                           │  │
│   │   users/{uid}/                                            │  │
│   │   ├── profile, library, targets                          │  │
│   │   ├── plans/{planId}/programs/{programId}                 │  │
│   │   └── workouts/{workoutId}/instances/sets                 │  │
│   │                                                           │  │
│   │   exercises/ (global catalog)                             │  │
│   │   protocols/ (global catalog)                             │  │
│   │                                                           │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      EXTERNAL SERVICES                           │
├─────────────────────────────────────────────────────────────────┤
│   OpenAI API (gpt-4o-mini, TTS, Vision)                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Design Principles

1. **Server-first** - Business logic on Firebase, clients display only
2. **Cloud-only** - Firestore is sole source of truth
3. **Voice-ready** - If TTS can't read it, don't return it
4. **Cross-platform** - Same endpoints for iOS, Web, future Android

---

## Service Layer

### AI Services

| Endpoint | Purpose | OpenAI API |
|----------|---------|------------|
| `/api/chat` | Main chat with tool calling | Responses API |
| `/api/tts` | Text-to-speech | TTS-1 |
| `/api/vision` | Image analysis | GPT-4V |
| `/api/chatSimple` | Simple completions | Chat Completions |

### Workout Services

| Endpoint | Purpose | Status |
|----------|---------|--------|
| `/api/calculate` | 1RM, weight targets | Live |
| `/api/selectExercises` | Exercise selection | Live |
| `/api/createWorkout` | Full workout creation | Planned |
| `/api/modifyWorkout` | Workout modifications | Planned |

### Data Services

| Endpoint | Purpose |
|----------|---------|
| `/api/import` | CSV/URL workout import |
| `/api/initialChips` | Context-aware suggestion chips |
| `/api/activatePlan` | Plan activation |
| `/api/abandonPlan` | Plan abandonment |
| `/api/deletePlan` | Plan deletion |
| `/api/reschedulePlan` | Plan rescheduling |

### Tool Handlers (22 total)

AI-invokable tools that execute server-side:

| Category | Tools |
|----------|-------|
| Schedule | `show_schedule`, `skip_workout` |
| Profile | `update_profile` |
| Plan | `create_plan`, `activate_plan`, `abandon_plan`, `delete_plan`, `reschedule_plan` |
| Workout | `create_workout`, `modify_workout`, `start_workout`, `end_workout`, `reset_workout` |
| Exercise | `change_protocol`, `get_substitution_options` |
| Library | `add_to_library`, `remove_from_library`, `update_exercise_target` |
| Analytics | `analyze_training_data`, `get_summary` |
| UI | `suggest_options` |
| Messaging | `send_message` |

---

## Client Architecture

### iOS (`ios/`)

**Role:** UI shell + local execution state

| Layer | Responsibility |
|-------|----------------|
| **UI** | SwiftUI views, navigation |
| **ViewModels** | UI state, user interactions |
| **Services** | Firebase API calls, voice coordination |
| **Data** | In-memory cache (LocalDataStore) |

**Key Services:**
- `FirebaseChatClient` - Chat API calls
- `FirebaseAPIClient` - Service endpoint calls
- `VoiceCoordination` - TTS/STT during workouts
- `WorkoutSessionCoordinator` - Local execution state

### Web (`web/`)

**Role:** React UI + Firebase client

| Layer | Responsibility |
|-------|----------------|
| **Pages** | Next.js routes |
| **Components** | React UI components |
| **Lib** | Firebase client, API helpers |

### Backend (`web/functions/`)

**Role:** All business logic

| Layer | Responsibility |
|-------|----------------|
| **API** | HTTP endpoints (`/api/*`) |
| **Tools** | AI tool handlers |
| **Services** | Business logic (calculations, selection) |
| **Types** | Shared TypeScript definitions |

---

## Data Architecture

### Entity Hierarchy

```
Plan
 └── isSingleWorkout: Bool
 └── name, goal, splitType
      │
      └── Program (1+ per Plan)
           └── focus, intensity range
                │
                └── Workout
                     └── date, splitDay, exerciseIds
                          │
                          └── ExerciseInstance
                               └── exerciseId, protocolId
                                    │
                                    └── ExerciseSet
                                         └── targetWeight, targetReps, actual*
```

### Data Flow

```
Server creates data → Firestore → Client reads via listener
                                         ↓
                              LocalDataStore (cache)
                                         ↓
                                   UI renders
```

**Critical:** Clients never create authoritative data. Server writes to Firestore, clients read.

---

## Authentication

Firebase Auth with multiple providers:

| Provider | iOS | Web |
|----------|-----|-----|
| Apple Sign-In | Yes | Yes |
| Google Sign-In | Yes | Yes |
| Magic Link Email | Yes | Yes |

All platforms share the same Firebase UID.

---

## Voice Architecture

Voice features run locally on iOS for latency:

| Component | Purpose |
|-----------|---------|
| `VoiceInput.swift` | Apple Speech STT |
| `VoiceOutput.swift` | Firebase TTS proxy |
| `VoiceCoordination.swift` | Workout announcements |

TTS audio generated server-side (`/api/tts`), played locally.

---

## Intensity & Periodization

### Program Intensity Progression

```
Program.startingIntensity = 0.60
Program.endingIntensity   = 0.85
                |
                v
Week 1: 0.60 → Week 2: 0.68 → Week 3: 0.77 → Week 4: 0.85
```

### Training Focus

| Focus | Intensity | Purpose |
|-------|-----------|---------|
| Foundation | 60-70% | Movement quality |
| Development | 70-80% | Progressive overload |
| Peak | 80-90% | Test limits |
| Maintenance | 65-75% | Sustain gains |
| Deload | 50-60% | Recovery |

---

## User Roles

| Role | Scope | Capabilities |
|------|-------|--------------|
| Member | Personal | Own data, workouts |
| Trainer | Assigned members | Client management |

Trainer functionality includes member context in sidebar and chat.

---

## Deployment

### iOS
```bash
# Xcode → Product → Archive → Distribute App → TestFlight
```

### Web + Backend
```bash
cd web
npm run build
firebase deploy --only hosting,functions
```

---

## Adding Features

1. **Define types** in `functions/src/types/`
2. **Implement service** in `functions/src/services/`
3. **Create endpoint** in `functions/src/api/`
4. **Update client** to call endpoint
5. **Update docs**

---

## Related Documentation

- [ROADMAP.md](ROADMAP.md) - Priorities, migration status
- [TESTING.md](TESTING.md) - Test strategy
- [CLAUDE.md](CLAUDE.md) - AI assistant context
