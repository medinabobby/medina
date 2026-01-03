# Medina

AI fitness coach with iOS and web clients sharing a Firebase backend.

## Vision

**Server-first, dumb clients.** All business logic lives on Firebase Functions. Clients are thin UI layers that display data from Firestore, send user actions to server, and render responses.

## Architecture

```
iOS App ───┐
           ├──► Firebase Functions ──► OpenAI API
Web App ───┘         │
                     └── Firestore (shared data)
```

### Service Layer (Firebase Functions)

| Category | Endpoints |
|----------|-----------|
| AI Services | `/api/chat`, `/api/tts`, `/api/vision`, `/api/chatSimple` |
| Workout Services | `/api/calculate`, `/api/selectExercises` |
| Data Services | `/api/import`, `/api/initialChips`, plan endpoints |
| Tool Handlers | 22 AI-invokable tools (`web/functions/src/tools/`) |

### Client Layer

| Platform | Role | Key Features |
|----------|------|--------------|
| iOS | UI shell + workout execution | SwiftUI, voice mode, Apple Health |
| Web | Chat UI + data views | Next.js, React components |

## Key Files

| Purpose | Path |
|---------|------|
| Chat endpoint | `web/functions/src/index.ts` |
| Tool registry | `web/functions/src/tools/index.ts` |
| Tool definitions | `web/functions/src/tools/definitions.ts` |
| API endpoints | `web/functions/src/api/` |
| iOS services | `ios/Medina/Services/` (75 files) |
| Web client | `web/lib/`, `web/components/` |

## Data Flow

```
Server creates data → Firestore → Client reads via listener → UI renders
```

Clients never create authoritative data. Server writes to Firestore, clients read.

## Development Guidelines

### Cross-Client Verification (v235)

**Always verify changes across both iOS and web clients.**

When fixing bugs or implementing features:
1. Check if the change affects shared behavior (data display, status colors, API calls)
2. Implement the fix on BOTH platforms if needed
3. Test on both iOS simulator and web browser

Common areas requiring cross-client sync:
- **Status colors** - Both platforms must use same color scheme (see `StatusHelpers.swift` and `colors.ts`)
- **Sidebar/navigation refresh** - When data is created via chat, both platforms need to refresh
- **Entity actions** - Available actions should match across platforms (delete, activate, etc.)
- **API token handling** - Both platforms should get tokens on-demand, not rely on cached state

Files to check for parity:
| Feature | iOS | Web |
|---------|-----|-----|
| Status colors | `StatusHelpers.swift`, `SelectablePlansFolder.swift` | `lib/colors.ts` |
| Entity actions | `EntityActionProvider.swift` | `PlanDetailModal.tsx` |
| Sidebar refresh | `ChatViewModel.swift` | `Sidebar.tsx`, `ChatLayout.tsx` |
| API auth | `FirebaseAPIClient.swift` | Uses `getIdToken()` directly |

## AI Behavior Rules (v267)

The AI follows a **stakes-based UX framework** for when to act vs ask.

**See [INTENT.md](./INTENT.md) for the complete design philosophy and extension guide.**

### Quick Reference

| Stakes | Pattern | Example |
|--------|---------|---------|
| **LOW** | Execute → Offer adjustments | Single workout: create immediately |
| **MEDIUM** | Command = Act, Statement = Ask | "Update to 4 days" vs "I want 4 days" |
| **HIGH** | Confirm → Execute | Plans, deletions: confirm first |

### Key Behaviors

- **create_workout**: LOW stakes - execute immediately with smart defaults
- **create_plan**: HIGH stakes - confirm params before executing
- **destructive actions**: Always confirm
- **user statements**: Ask before saving to profile

## Running Evaluations

**See [docs/benchmarking/README.md](./docs/benchmarking/README.md) for full evaluation guide.**

Quick start:
```bash
cd web/functions

# Get fresh auth token from browser DevTools (Network tab → /chat request → Authorization header)
npm run eval -- run \
  --model gpt-4o-mini \
  --endpoint https://us-central1-medinaintelligence.cloudfunctions.net/chat \
  --token "YOUR_TOKEN" \
  --concurrency 5 \
  --output docs/benchmarking/results/vXXX/results.json
```

Key files:
| Purpose | Path |
|---------|------|
| Test cases | `web/functions/src/evaluation/testSuite.ts` |
| Framework docs | `docs/benchmarking/README.md` |
| Results | `docs/benchmarking/results/` |

## Current Version

v268

## Recent Changes (v268)

### Prompt Optimization
- Response time: 6,174ms → 5,050ms (-18%)
- Cost: $0.20 → $0.189 (-5.5%)
- Tier 1 pass rate: 100% (no regression)

Key changes:
- Consolidated tool instruction triggers
- Extracted shared enum constants in definitions.ts
- Added INTENT.md for design philosophy documentation

### Key Learning
WRONG EXAMPLES section in `coreRules.ts` is critical - removing it caused Tier 1 regression.

## Recent Changes (v267)

### Stakes-Based UX Framework
- **Execute Then Confirm** for low-stakes actions (single workout)
- **Confirm Then Execute** for high-stakes actions (plans, destructive)
- AI now creates workouts immediately with smart defaults instead of asking 3 questions
- After creating, offers to adjust: "Want me to change duration, location, or exercises?"

### Key Files Changed
- `web/functions/src/prompts/toolInstructions.ts` - Added LOW/HIGH stakes patterns

## Recent Changes (v248-250)

### iOS/Web Sidebar Parity
- Both platforms now have: Messages, Schedule, Plans, Library folders
- Schedule shows this week's workouts with day labels (Today, Tomorrow, Wed)
- Plans folder always visible (even when empty)
- Web Exercises subfolder has dumbbell icon matching iOS

### iOS/Web Settings Parity
- Web settings dropdown now has Gym/Trainer/Plan rows (matching iOS)
- iOS Settings shows member NAME (not email)
- iOS Profile header simplified (48px avatar in edit mode)
- Web Profile converted to centered modal

### Key Files Added
- `ios/Medina/UI/Components/Sidebar/ScheduleFolder.swift`
- `web/components/chat/folders/ScheduleFolder.tsx`
- `web/components/detail-views/ScheduleDetailModal.tsx`
