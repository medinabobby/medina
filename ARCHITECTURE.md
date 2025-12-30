# Medina Architecture

**Last updated:** December 30, 2025 | **iOS:** v226 | **Web:** v226 | **Backend:** v226

Medina is an AI fitness coach with iOS and web clients sharing a Firebase backend.

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
│   │ - Full features  │         │ - Chat UI        │             │
│   │ - Workout exec   │         │ - View data      │             │
│   │ - Voice mode     │         │ - Basic actions  │             │
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
│   │                   Cloud Functions                         │  │
│   │                                                           │  │
│   │   /api/chat                                               │  │
│   │   ├── Verify Firebase ID token                            │  │
│   │   ├── Call OpenAI Responses API (streaming)               │  │
│   │   ├── Execute server handlers                             │  │
│   │   │   └── show_schedule, update_profile, skip_workout     │  │
│   │   └── OR passthrough to iOS (client-side tools)           │  │
│   │                                                           │  │
│   └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │                     Firestore                             │  │
│   │                                                           │  │
│   │   users/{uid}/                                            │  │
│   │   ├── profile                                             │  │
│   │   ├── plans/{planId}/programs/{programId}                 │  │
│   │   ├── workouts/{workoutId}/instances/sets                 │  │
│   │   └── exerciseLibrary/, exerciseTargets/                  │  │
│   │                                                           │  │
│   │   exercises/ (global)                                     │  │
│   │   protocols/ (global)                                     │  │
│   │   gyms/ (global)                                          │  │
│   │                                                           │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      EXTERNAL SERVICES                           │
├─────────────────────────────────────────────────────────────────┤
│   ┌──────────────────┐                                          │
│   │   OpenAI API     │                                          │
│   │   - gpt-4o-mini  │                                          │
│   │   - Responses API│                                          │
│   │   - Tool calling │                                          │
│   └──────────────────┘                                          │
└─────────────────────────────────────────────────────────────────┘
```

**Vision:** Shared backend, dumb clients, cross-platform parity.

---

## Design Principles

1. **Code enables, AI guides, User decides** - Guard rails, not hardcoded blocks
2. **Cloud-first** - Firestore is sole source of truth
3. **Voice-ready** - If TTS can't read it, don't return it
4. **Empty libraries by default** - Users build libraries through usage

---

## Platform Components

### iOS Client (`ios/`)

| Area | Responsibility | Key Files |
|------|----------------|-----------|
| UI | Sidebar navigation, workout execution | `Medina/UI/Screens/` |
| Services | Business logic, AI integration | `Medina/Services/` |
| Data | Models, in-memory cache | `Medina/Data/` |
| Firebase | Auth, Firestore repos, chat client | `Services/Firebase/` |

**Architecture:**
```
SwiftUI UI → ViewModels → Services → Firebase Chat Client → OpenAI
                                  ↘ Firestore (user data)
```

### Web Client (`web/`)

| Area | Responsibility | Key Files |
|------|----------------|-----------|
| Pages | Login, chat app | `app/` |
| Components | Chat UI, sidebar | `components/` |
| Lib | Firebase, API client | `lib/` |
| Functions | Server handlers | `functions/src/` |

**Architecture:**
```
Next.js Pages → React Components → Chat API → Firebase Functions → OpenAI
                                           ↘ Firestore (user data)
```

### Backend (`web/functions/`)

| Area | Responsibility | Key Files |
|------|----------------|-----------|
| Handlers | Server-side tool execution | `src/handlers/` |
| Types | Shared TypeScript types | `src/types/` |
| Prompts | AI system prompts | `src/prompts/` |

---

## Tool Handler Architecture

### Server vs Passthrough

```
User message → Firebase Function → OpenAI → Tool call
                                              ↓
                                    Server has handler?
                                      ↓ yes      ↓ no
                                   Execute    Passthrough
                                      ↓           ↓
Client ← SSE Stream ←←←←←←←←←←←←←←←←←←←←←←←←←←←┘
```

### Current Handler Status

| Handler | Location | Status |
|---------|----------|--------|
| `show_schedule` | Server | Live |
| `update_profile` | Server | Live |
| `skip_workout` | Server | Live |
| `suggest_options` | Server | Live |
| `delete_plan` | Server | Live |
| `reset_workout` | Server | Live |
| `activate_plan` | Server | Live |
| `abandon_plan` | Server | Live |
| `start_workout` | Server | Live |
| `end_workout` | Server | Live |
| `create_workout` | Server | Live |
| `create_plan` | Server | Live |
| `add_to_library` | Server | Live |
| `remove_from_library` | Server | Live |
| `update_exercise_target` | Server | Live |
| `get_substitution_options` | Server | Live |
| `get_summary` | Server | Live |
| `send_message` | Server | Live |
| `reschedule_plan` | Server | Live |
| `modify_workout` | Server | Live |
| `change_protocol` | Server | Live |
| `analyze_training_data` | Server | Live |

**Status:** 22 of 22 handlers on server (100%)

### Handler Migration Checklist

When migrating a handler from iOS to server:

1. **Create server handler** in `web/functions/src/handlers/`
2. **Register in toolRegistry** at `web/functions/src/handlers/index.ts`
3. **Test server-side execution** - verify Firestore writes succeed
4. **Send card events** - if handler creates workout/plan, emit SSE event:
   ```typescript
   sendSSE(res, 'workout_card', { cards: [{ workoutId, workoutName }] });
   ```
5. **iOS: Sync on card receipt** - ChatViewModel must fetch from Firestore:
   ```swift
   case .workoutCard(let cardData):
       // Fetch from Firestore → LocalDataStore
       if let userId = LocalDataStore.shared.currentUserId {
           Task {
               if let workout = try await FirestoreWorkoutRepository.shared.fetchWorkout(
                   id: cardData.workoutId, memberId: userId
               ) {
                   LocalDataStore.shared.workouts[cardData.workoutId] = workout
               }
           }
       }
   ```
6. **Remove iOS handler** from `ToolHandlerRouter.swift` (or mark as passthrough)
7. **Update this doc** with new handler status

### Server vs iOS Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    OLD: iOS Handler (Local)                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   iOS Tool Handler                                                   │
│   ├── 1. Create workout object locally                              │
│   ├── 2. Add to LocalDataStore.workouts[id] = workout   ◄── SYNC   │
│   ├── 3. Save to Firestore (async)                                  │
│   └── 4. Show card → User taps → Found ✅                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    NEW: Server Handler (Remote)                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Server Handler                                                     │
│   ├── 1. Create workout in Firestore                                │
│   └── 2. Send workout_card SSE event (id + name only)               │
│                    │                                                 │
│                    ▼                                                 │
│   iOS ChatViewModel receives card                                    │
│   ├── 3. Fetch workout from Firestore                ◄── NEW STEP   │
│   ├── 4. Add to LocalDataStore.workouts[id]         ◄── SYNC       │
│   └── 5. Show card → User taps → Found ✅                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Critical:** Server handlers don't populate `LocalDataStore`. iOS must sync.

---

## Entity Hierarchy

```
Plan
 └── isSingleWorkout: Bool
 └── name, goal, splitType, startDate, endDate
      │
      └── Program (1 or more per Plan)
           └── focus: TrainingFocus (foundation/development/peak/maintenance/deload)
           └── startingIntensity, endingIntensity (0.0-1.0)
                │
                └── Workout
                     └── scheduledDate, splitDay, exerciseIds
                          │
                          └── ExerciseInstance
                               └── exerciseId, protocolVariantId
                                    │
                                    └── ExerciseSet
                                         └── targetWeight, targetReps, actualWeight, actualReps
```

**Key insight:** A "Single Workout" is a 1-day Plan with `isSingleWorkout=true`.

---

## Intensity System

### Program → Weekly Intensity

```
Program.startingIntensity = 0.60
Program.endingIntensity   = 0.85
                |
                v
Week 1: 0.60 → Week 2: 0.68 → Week 3: 0.77 → Week 4: 0.85
```

### Intensity → Protocol Selection

| Intensity | Compound | Isolation |
|-----------|----------|-----------|
| 0.50-0.65 | 3x5 moderate | 3x12 light |
| 0.65-0.80 | 3x5 heavy | 3x10 moderate |
| 0.80+ | 3x3 peak | 3x8 heavy |

### Effort Levels (Single Workout)

| Effort | Intensity | RPE | Use Case |
|--------|-----------|-----|----------|
| Recovery | 0.55-0.65 | 6-7 | Active recovery, deload |
| Standard | 0.65-0.75 | 7-8 | Regular training |
| Push It | 0.75-0.85 | 8-9+ | High intensity day |

---

## Periodization

Plans generate multiple programs based on duration:

| Duration | Programs |
|----------|----------|
| 4-8 weeks | Foundation → Development |
| 12 weeks | Foundation → Development → Peak |
| 24+ weeks | Foundation → Development → Peak → Maintenance |

### Training Focus

| Focus | Intensity | RPE | Purpose |
|-------|-----------|-----|---------|
| Foundation | 60-70% | 6-7 | Movement quality, work capacity |
| Development | 70-80% | 7-8 | Progressive overload |
| Peak | 80-90% | 8-9+ | Test limits |
| Maintenance | 65-75% | 7-8 | Sustain gains |
| Deload | 50-60% | 5-6 | Active recovery |

---

## Data Persistence

### Cloud-Only Architecture

```
Firestore = Source of Truth
   │
   └──► iOS: LocalDataStore (in-memory cache)
   │         └──► DeltaStore (workout progress, UserDefaults)
   │
   └──► Web: React state (in-memory)
```

**Design Decision:** No local file persistence. Firestore is the sole source of truth.

### Data Loading Flow (iOS)

```
1. Load reference data (protocols, exercises, gyms)
2. Firebase Auth (Apple or Google Sign-in)
3. Fetch user data from Firestore → populate LocalDataStore
4. Apply DeltaStore (workout progress)
```

---

## User Roles

| Role | Scope | Capabilities |
|------|-------|--------------|
| Member | Personal | View own data, book classes |
| Trainer | Assigned members | Manage clients, set availability |
| Admin | Single gym | Manage gym operations |
| GymOwner | Multi-gym | Cross-gym analytics |

---

## Chat Architecture

### Message Types

```typescript
interface Message {
  content: string;                    // Markdown text
  isUser: boolean;
  workoutCreatedData?: WorkoutCard;   // Tap-to-start card
  planCreatedData?: PlanCard;         // Tap-to-activate card
  suggestionChipsData?: Chip[];       // Quick actions
}
```

### Suggestion Chip Sources

1. **Initial chips** - Server-side via `/api/initialChips` (context-aware based on user state)
2. **Handler-provided** - Tool returns chips after execution
3. **AI-invoked** - `suggest_options` tool for dynamic suggestions

**Note:** As of v226, all clients (iOS + Web) fetch initial chips from server for consistency.

---

## Exercise Selection

1. Start with user's library
2. Filter by equipment (gym/home)
3. Filter by split day
4. Split compound/isolation pools
5. If insufficient, expand to experience-appropriate
6. Select based on duration
7. Auto-add to library

### Selection Ranking

- Library preference: 1.2x boost
- Emphasis boost: 1.5x for emphasized muscles
- Muscle balance: 1.3x for under-represented
- Movement diversity: Avoid repeating patterns

---

## Key iOS Services

| Service | Purpose |
|---------|---------|
| `ResponsesManager` | OpenAI lifecycle, streaming |
| `ToolHandlerRouter` | Dispatch tool calls to handlers |
| `UserContextBuilder` | Build AI context from profile/history |
| `WorkoutSessionCoordinator` | Workout execution state |
| `FirebaseChatClient` | HTTP client for `/api/chat` |

### LocalDataStore (In-Memory Cache)

Central cache for user data. **Firestore is source of truth** - this is just a local cache.

```swift
// Key properties
LocalDataStore.shared.currentUserId: String?     // Firebase UID
LocalDataStore.shared.workouts: [String: Workout]  // workoutId → Workout
LocalDataStore.shared.plans: [String: Plan]        // planId → Plan
LocalDataStore.shared.users: [String: UnifiedUser] // userId → User
LocalDataStore.shared.programs: [String: Program]  // programId → Program

// After server creates entity, sync it:
LocalDataStore.shared.workouts[workoutId] = fetchedWorkout
LocalDataStore.shared.plans[planId] = fetchedPlan
```

**Note:** No `currentUser` property - use `currentUserId` to look up user.

---

## Key Backend Services

| Service | Purpose |
|---------|---------|
| `exerciseRepository.ts` | Query exercises collection |
| `protocolRepository.ts` | Query protocols (5-min cache) |
| `weightCalculationService.ts` | 1RM-based weight targets |
| `workoutCreationService.ts` | Full workout creation flow |

---

## Web Client Critical Knowledge

### Firebase Hosting Configuration

**CRITICAL:** `firebase.json` must have these settings for Next.js static export:

```json
{
  "hosting": {
    "public": "out",
    "cleanUrls": true,        // /app serves app.html
    "trailingSlash": false,
    "rewrites": [
      { "source": "/api/chat", "function": "chat" }
    ]
  }
}
```

**Without `cleanUrls: true`:** URLs like `/app` return 404 (must use `/app.html`).

### Build Output Gotcha

Next.js creates both `app.html` AND `app/` directory. The directory conflicts with Firebase Hosting's clean URLs.

**Fix:** After `npm run build`, remove conflicting directories:
```bash
rm -rf out/app out/login
# Keep app.html, login.html
```

Or add to build script in `package.json`:
```json
"build": "next build && rm -rf out/app out/login"
```

### SSE Event Structure (OpenAI Responses API)

**CRITICAL:** OpenAI events have fields at **root level**, not nested in `data`:

```typescript
// ❌ WRONG - how iOS was parsing it
event.data.delta
event.data.response.id

// ✅ CORRECT - OpenAI's actual format
event.delta
event.response.id
```

**Event examples:**
```json
{"type": "response.output_text.delta", "delta": "Hello", "output_index": 0}
{"type": "response.created", "response": {"id": "resp_123..."}}
{"type": "response.completed", "response": {...}}
```

### Web Chat Debugging

Add these console logs to diagnose issues:

```typescript
// In app/app/page.tsx
console.log('[Chat] SSE event:', event.type, event);
console.log('[Chat] Stream complete. fullText length:', fullText.length);

// In components/chat/Sidebar.tsx
console.log('[Sidebar] Plans loaded:', plansData.length, plansData);
console.log('[Sidebar] Workouts loaded:', workoutsData.length);
```

### Common Web Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| 404 on /app or /login | Missing `cleanUrls` in firebase.json | Add `"cleanUrls": true` |
| 404 after deploy | /app/ directory conflicts with app.html | Remove out/app/ directory |
| Chat shows no response | SSE parsing wrong (event.data.delta) | Use event.delta directly |
| Sidebar empty | Firestore query error (silent) | Check console for errors |
| Auth works but no data | Wrong UID (Apple vs Google) | Verify user.uid matches Firestore |

### Web Deployment Checklist

Before every deployment:

1. [ ] `npm run build` succeeds
2. [ ] `rm -rf out/app out/login` (remove conflicting dirs)
3. [ ] `firebase deploy --only hosting`
4. [ ] Test: https://medinaintelligence.web.app/login loads
5. [ ] Test: https://medinaintelligence.web.app/app loads (when logged in)
6. [ ] Test: Send chat message, response appears
7. [ ] Test: Sidebar shows workouts (if user has any)

### Web Test Strategy

**Smoke tests (run after every deploy):**
```bash
# 1. Check hosting is live
curl -I https://medinaintelligence.web.app/login
# Should return 200

# 2. Check API endpoint
curl -I https://medinaintelligence.web.app/api/chat
# Should return 401 (no auth) or 200

# 3. Check static assets load
curl -I https://medinaintelligence.web.app/_next/static/chunks/*.js
```

**Manual tests:**
1. Login with Google → should reach /app
2. Click "Show my schedule" → should get AI response
3. Check sidebar loads plans/workouts

---

## Adding Features

1. **Model** - Add struct in `Medina/Data/Models/` or `shared/types/`
2. **Persistence** - Update Firestore schema
3. **Business logic** - Add service in `Medina/Services/` or `functions/src/`
4. **UI** - Update views/components
5. **Documentation** - Update this file

---

## Related Documentation

- [ROADMAP.md](ROADMAP.md) - Migration status, priorities
- [TESTING.md](TESTING.md) - Test strategy
- [docs/api/](docs/api/README.md) - API reference
- [docs/data-models/](docs/data-models/README.md) - Firestore schema
- [docs/guides/](docs/guides/DEVELOPMENT.md) - Development workflow
