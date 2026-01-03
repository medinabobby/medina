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

The AI assistant follows a **stakes-based UX framework** for when to act vs ask.

### Stakes-Based Action Pattern

| Action Type | Stakes | Pattern | Example |
|-------------|--------|---------|---------|
| **create_workout** | LOW | Execute → Confirm | Create immediately, offer changes after |
| **create_plan** | HIGH | Confirm → Execute | Propose params, wait for OK, then create |
| **update_profile** | MEDIUM | Explicit = Act, Statement = Ask | "Update to 4 days" = act; "I want 4 days" = ask |
| **destructive** | HIGH | Always confirm | "Delete my plan" = must confirm |

### LOW Stakes: Execute Then Confirm (v267)

For single workout creation, **execute immediately** with smart defaults:
- Duration: Use profile.preferredSessionDuration OR 45 min
- Location: Use profile.trainingLocation OR "gym"
- Date: Tomorrow (or next available day)

**After creating:** Offer to adjust: "Created your 45-min workout! Want me to change duration, location, or exercises?"

```
User: "Create a GBC workout"
AI: [EXECUTES immediately] "Created your 45-min GBC workout for tomorrow! Want me to change anything?"
```

### HIGH Stakes: Confirm Then Execute

For multi-week plans, **confirm key params first**:
- Duration (weeks), days/week, session duration, goal

```
User: "Create a strength plan"
AI: "I'll create a 12-week strength plan, 4 days/week. Sound good?"
User: "Make it 8 weeks"
AI: [EXECUTES with 8 weeks]
```

### When to ACT Immediately

| User Says | Tool | Why |
|-----------|------|-----|
| "Create a push workout" | `create_workout` | Low stakes, use defaults |
| "Create a GBC workout" | `create_workout` | Low stakes, use defaults |
| "Update my profile to 4 days" | `update_profile` | Explicit command |
| "Skip today's workout" | `skip_workout` | Explicit, reversible |
| "Add bench press to my library" | `add_to_library` | Explicit, reversible |
| "My bench 1RM is 225" | `update_exercise_target` | User providing data |
| "Show my schedule" | `show_schedule` | Read-only |

### When to ASK/CONFIRM First

| User Says | Why Confirm |
|-----------|-------------|
| "Create a 12-week plan" | High stakes, multi-week commitment |
| "I want to train 4 days" | Preference statement, not command |
| "I'm 5'11 and 180 lbs" | User stating info, not requesting save |
| "Delete my plan" | Destructive action |
| "Activate this plan" | Multi-week commitment |

### When to ADVISE First

| User Says | Why Advise |
|-----------|------------|
| Going from 2→7 days/week | Major change, overtraining risk |
| "Gain 50lbs muscle in 3 months" | Unrealistic expectation |
| Training through injury | Safety concern |

### Synonym Handling

User terms are silently mapped to Medina concepts (no correction needed):

| User Says | Maps To | Example Response |
|-----------|---------|------------------|
| "program" | plan | "I'll create a training plan..." |
| "routine" | workout/plan | Context determines which |
| "schedule" | show_schedule | "Here's your schedule..." |
| "proposal" | plan | "Let me build a plan..." |

## Running Evaluations

The eval framework tests AI behavior across 100+ test cases. To run:

```bash
cd web/functions

# Get FRESH auth token from browser (via Claude Chrome plugin)
# Token expires in ~1 hour, so must capture fresh from network request
# 1. Open https://medinaintelligence.web.app/app in browser
# 2. Install fetch interceptor in DevTools console:
#    const origFetch = window.fetch;
#    window._freshToken = null;
#    window.fetch = async function(url, opts) {
#      if (opts?.headers?.Authorization) {
#        window._freshToken = opts.headers.Authorization.replace('Bearer ', '');
#      }
#      return origFetch.apply(this, arguments);
#    };
# 3. Send any message in the chat to trigger an API call
# 4. Download the fresh token:
#    const blob = new Blob([window._freshToken], { type: 'text/plain' });
#    const a = document.createElement('a');
#    a.href = URL.createObjectURL(blob);
#    a.download = 'fresh_token.txt';
#    a.click();

# Run eval (use fresh token immediately - expires in ~1 hour)
export EVAL_AUTH_TOKEN=$(cat ~/Downloads/fresh_token.txt)
npm run eval -- run --model gpt-4o-mini \
  --endpoint https://us-central1-medinaintelligence.cloudfunctions.net/chat \
  --output docs/benchmarking/results-v266.json

# Generate memo
npm run eval -- memo --input results.json > EVAL_MEMO.md
```

Key eval files:
| Purpose | Path |
|---------|------|
| Test cases | `web/functions/src/evaluation/testSuite.ts` |
| Runner | `web/functions/src/evaluation/runner.ts` |
| CLI | `web/functions/src/evaluation/cli.ts` |
| Results | `docs/benchmarking/results-*.json` |

## Current Version

v267

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
