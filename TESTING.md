# Medina Testing Strategy

**Last updated:** January 3, 2026 | **Version:** v266

Cross-platform testing strategy for iOS, Web, and Backend.

---

## Testing Philosophy

### Principle: Test Where the Logic Lives

With our **server-first architecture**, most business logic runs on Firebase Functions. This means:

- **Backend tests** cover business logic for ALL platforms (iOS, Web, future Android)
- **Client tests** focus on platform-specific UI and real-time features only

```
┌─────────────────────────────────────────────┐
│         BACKEND (Firebase Functions)         │
│  ════════════════════════════════════════   │
│  AI Services: chat, tts, vision             │
│  Workout Services: calculate, select        │
│  Data Services: import, plan endpoints      │
│  Tool Handlers: 22 AI-invokable tools       │
│                                              │
│  TEST HERE: All shared business logic        │
│  Framework: Vitest + Firestore Emulator      │
└─────────────────────────────────────────────┘
              ↑                    ↑
         ┌────┴────┐          ┌────┴────┐
         │  iOS    │          │  Web    │
         │ Client  │          │ Client  │
         └─────────┘          └─────────┘
         TEST: UI,            TEST: React
         Voice, Workout       components,
         Execution            Chat UI
```

**Why this matters:**
- Server code runs the same for iOS and Web
- Testing once at the backend covers both platforms
- Client tests focus on platform-specific UI/UX
- Future Android app gets tested logic for free

---

## AI Behavior Expectations (v247)

Tests must account for multi-turn confirmation flows. Not every user message should trigger an immediate tool call.

### Intent Classification → Test Expectations

| User Intent Type | Example | Expected First Response | Test Expectation |
|------------------|---------|------------------------|------------------|
| Explicit Command | "Update my profile to 4 days" | Tool execution | `expectedTool: "update_profile"` |
| Data Provision | "My bench 1RM is 225 lbs" | Tool execution | `expectedTool: "update_exercise_target"` |
| Preference Statement | "I want to train 4 days" | Confirmation request | `expectedTool: null` |
| Multi-param Request | "Create a 12-week plan" | Clarifying questions | `expectedTool: null` |
| Destructive Action | "Delete my plan" | Confirmation request | `expectedTool: null` |

### Single-Turn vs Multi-Turn Tests

**Single-turn tests** expect immediate tool execution:
- User gives explicit command → AI executes tool
- Example: "Skip today's workout" → `skip_workout` tool called

**Multi-turn tests** expect confirmation or clarification first:
- User states preference → AI asks to confirm
- User requests complex action → AI gathers required parameters
- Example: "I want to train 4 days" → AI asks "Want me to update your profile?"

### Why This Matters

A test that expects `update_profile` for "I want to train 4 days" will fail - but that's a **test bug**, not an AI bug. The AI correctly asks for confirmation before modifying user data.

---

## AI Performance Evaluation (v266)

### Overview

The AI evaluation framework benchmarks model performance across **91 tests** in 8 categories.

**Location:** `web/functions/src/evaluation/`

### v266 Framework Improvements

| Feature | Description |
|---------|-------------|
| **Multi-turn credit** | 2-turn success (ask → execute) now passes |
| **Output quality scoring** | Validates workout constraints (duration, split, equipment) |
| **Cleaned fixtures** | Removed 10 broken IM tests, fixed TT06 |
| **Temperature=0** | More reproducible eval runs |

### Current Results (Jan 3, 2026)

| Tier | Pass Rate | Description |
|------|-----------|-------------|
| **Tier 1 (Core)** | **95%** (40/42) | Must pass - actual bugs |
| Tier 2 (Interpretation) | 73% (33/45) | Clarification OK |
| Tier 3 (Ambiguous) | 50% (2/4) | Clarification preferred |

### Test Categories

| Category | Tests | Description |
|----------|-------|-------------|
| `tool_calling` | 28 | Core tool invocation accuracy |
| `fitness_accuracy` | 10 | Fitness knowledge quality |
| `tone` | 5 | Coaching tone and style |
| `speed` | 5 | Response latency |
| `onboarding` | 8 | New user flows |
| `tier` | 6 | Subscription tier behavior |
| `import` | 14 | CSV/URL/Vision import (7 vision tests) |
| `protocol_accuracy` | 6 | Protocol parameter matching (GBC, 5x5, etc.) |
| `workout_quality` | 10 | Output constraint validation (NEW in v266) |

### Running Evaluations

```bash
cd web/functions

# Show test suite info
npm run eval:info

# Run full evaluation against production
EVAL_AUTH_TOKEN="<firebase-token>" npm run eval:run -- --model gpt-4o-mini --endpoint https://us-central1-medinaintelligence.cloudfunctions.net/chat

# Compare two result files
npm run eval:compare -- results-a.json results-b.json
```

### Latency Categories

**Key insight:** Different query types have fundamentally different latency profiles. Measure and optimize within each category, not overall averages.

| Category | Tests | Expected Latency | Outlier Threshold |
|----------|-------|------------------|-------------------|
| **Basic Queries** | 36 | 1-2.5s | >3s |
| **Tool Calls** | 33 | 3-8s | >10s |
| **Vision** | 22 | 5-15s | >20s |

### Basic Query Tests (No Tools)

Tests that should be fast - AI generates text response only:

| Test ID | Prompt Type | Notes |
|---------|-------------|-------|
| SP01, SP05 | Greetings/Thanks | Simplest, fastest |
| SP03 | Simple question | No Firestore lookup |
| TC05, TC07, TC10 | Confirmation prompts | AI asks before acting |
| TC09, PL01-02, ED01, ED03, SY01 | Complex requests | May need clarification |
| FA01-FA10 | Fitness knowledge | No tools needed |
| TN01-TN05 | Tone/style | Coaching responses |

### Tool Call Tests (Firestore Operations)

Tests where AI executes tools - includes Firestore read/write latency:

| Test ID | Tool | Notes |
|---------|------|-------|
| TC01, SP04 | `create_workout` | Slowest - many Firestore writes |
| TC02, SP02, SY02 | `show_schedule` | Firestore reads |
| TC03 | `update_exercise_target` | Single write |
| TC04 | `skip_workout` | Single write |
| TC06 | `add_to_library` | Single write |
| TC08 | `get_substitution_options` | Firestore reads |
| TC11-12 | `update_profile` | Single write |
| ED02, ED04 | Various | Edge cases |

### Success Metrics

| Metric | Target | Current |
|--------|--------|---------|
| Tool Accuracy Rate | ≥95% | TBD |
| Intent Detection Rate | ≥90% | TBD |
| Protocol Accuracy Rate | ≥90% | TBD |
| Exercise Accuracy Rate | ≥90% | TBD |
| Basic Query Avg Latency | <2s | TBD |
| Tool Call Avg Latency | <5s | TBD |
| Speed Test Pass Rate | ≥80% | TBD |

### Model Comparison Strategy

1. **Baseline**: Run all 91 tests against current model (gpt-4o-mini)
2. **Compare**: Run same tests against alternative (gpt-4o)
3. **Analyze**: Compare by category - tool accuracy, intent detection, protocol accuracy, latency, cost
4. **Guard**: No regression in tool accuracy (<90% = fail)

### Optimization Priority

Focus on **outliers within each category**:

1. **Basic query outliers (>3s)**: TC09 (12s - long explanation), review prompt for conciseness
2. **Tool call outliers (>10s)**: TC01 (7.7s - create_workout), optimize Firestore operations

### Results Storage

Evaluation results saved as JSON in `web/functions/`:
- `results-<model>-<timestamp>.json` - Raw results
- `EVAL_BASELINE.md` - Human-readable analysis

---

## Current State (January 2026)

### iOS Tests
| Category | Files | Tests | Status |
|----------|-------|-------|--------|
| Tool Handlers | 19 | 253 | Mostly valid |
| Services | 6 | 62 | Partially stale |
| Repositories | 2 | 25 | Uses mocks only |
| ViewModels | 1 | 30 | Valid |
| Workout Execution | 1 | 50 | Valid |
| AI Integration | 2 | 6 | Flaky (live API) |
| **Total** | **35** | **411+** | |

### Web Tests
| Category | Files | Tests | Status |
|----------|-------|-------|--------|
| API/Auth | 2 | 32 | Valid |
| Handler E2E | 1 | 12 | Valid |
| React Components | 0 | 0 | Missing |
| **Total** | **3** | **44** | |

---

## Critical Gaps

### 1. Firestore Integration (HIGH RISK)

**Problem:** iOS has 8 Firebase repositories with 0 integration tests. Web handlers write to Firestore but only test with mocks.

**Risk:** Data sync failures, conflicts, and data loss go undetected.

**Solution:** Add Firestore Emulator tests for:
- [ ] User profile CRUD
- [ ] Plan/workout creation and retrieval
- [ ] Workout status updates (skip, complete)
- [ ] Offline → online sync
- [ ] Conflict resolution

### 2. AI Tool Selection (MEDIUM RISK)

**Problem:** Unit tests verify handlers work *when called*. Nothing verifies AI *decides to call* them.

**Risk:** AI acknowledges info conversationally instead of calling tools (v201 bug).

**Solution:**
- [ ] Prompt regression tests (recorded expected tool calls)
- [ ] Manual testing checklist after prompt changes

### 3. React Components (LOW RISK - Web not primary)

**Problem:** Zero tests for web UI components.

**Risk:** UI regressions on web.

**Solution:** Add component tests when web becomes primary focus.

---

## What to Test Where

### Backend (Firebase Functions)

**Location:** `web/functions/src/`

| Handler | Current | Target | Priority |
|---------|---------|--------|----------|
| All 22 handlers | E2E mock | + Firestore emulator | High |

**All handlers migrated to server (Dec 2025).** See ROADMAP.md for complete list.

**Test Types:**
1. **Unit tests** - Handler logic in isolation
2. **Integration tests** - Handler + Firestore Emulator
3. **E2E tests** - Full chat flow (expensive, run sparingly)

### iOS Client

**Location:** `ios/MedinaTests/`

| Category | Current | Recommendation |
|----------|---------|----------------|
| Tool Handlers (253) | Good coverage | Keep, update for server migration |
| DeltaStore | Good coverage | Keep (local state still used) |
| Firebase Repos | Zero tests | **Deprecate** - test at backend instead |
| Workout Execution | Good coverage | Keep (iOS-only feature) |
| Voice Mode | Minimal | Add tests (iOS-only feature) |
| AI Integration | Live API | Move to backend tests |

**iOS-Only Features (keep testing here):**
- Workout execution UI
- Voice mode (STT → GPT → TTS)
- Rest timer
- Apple Watch (future)
- Home Screen widgets (future)

### Web Client

**Location:** `web/` (tests not yet created)

| Category | Current | Recommendation |
|----------|---------|----------------|
| React Components | None | Add when web is primary |
| Chat UI | None | Add basic smoke tests |
| Auth Flow | None | Test at backend |

---

## Test Pyramid

```
                    ╱╲
                   ╱  ╲
                  ╱ E2E╲         Few: Full user flows
                 ╱──────╲        (expensive, slow)
                ╱        ╲
               ╱Integration╲     More: Handler + Firestore
              ╱────────────╲     (Firestore Emulator)
             ╱              ╲
            ╱   Unit Tests   ╲   Most: Pure functions,
           ╱──────────────────╲  handlers in isolation
```

**Target Distribution:**
- Unit: 70% of tests
- Integration: 25% of tests
- E2E: 5% of tests

---

## Running Tests

### Backend
```bash
cd web/functions

# Watch mode (development)
npm test

# Single run (CI)
npm run test:run

# With coverage
npm run test:coverage

# With Firestore Emulator (when added)
firebase emulators:exec "npm test"
```

### iOS
```bash
# Xcode
Cmd+U

# Command line
xcodebuild test -project Medina.xcodeproj -scheme Medina -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Core Use Cases & Test Ownership

| Use Case | Primary Test Location | Why |
|----------|----------------------|-----|
| User authentication | Backend | Same for iOS/Web |
| Chat with AI | Backend | Server handles |
| All tool handlers | Backend | All 22 migrated to server |
| Execute workout | iOS | iOS-only feature |
| Voice mode | iOS | iOS-only feature |
| Workout cards | iOS (UI) + Backend (data) | Split |

---

## Tool Testing (All 22 on Server)

All 22 AI-invokable tools now run on Firebase Functions. iOS is a passthrough client.

### Current Flow
```
User → Firebase Function → OpenAI → Tool Call
                                        ↓
                              Server executes tool
                              Server updates Firestore
                                        ↓
                              iOS reads via Firestore listener
```

**Test in:** Backend (`web/functions/src/tools/*.test.ts`)

### Test Location by Category
| Tool Category | Test Files |
|---------------|------------|
| Schedule tools | `show_schedule.test.ts`, `skip_workout.test.ts` |
| Profile tools | `update_profile.test.ts` |
| Plan tools | `create_plan.test.ts`, `activate_plan.test.ts`, etc. |
| Workout tools | `create_workout.test.ts`, `modify_workout.test.ts`, etc. |
| Library tools | `add_to_library.test.ts`, `remove_from_library.test.ts`, etc. |

### Legacy iOS Tests
iOS tool handler tests in `MedinaTests/ToolHandlerTests/` are now deprecated. They tested the passthrough pattern which is no longer used.

### Test Scenarios by Handler

| Handler | Test Cases |
|---------|------------|
| `show_schedule` | Empty schedule → "No workouts scheduled"; Week/month periods → correct date range; Workout formatting → name, date, status |
| `update_profile` | Single field → only that field updated; Multiple fields → all merged; Empty update → error |
| `skip_workout` | Valid → status="skipped"; Already skipped → error; Completed → cannot skip; Non-existent → not found |
| `suggest_options` | Valid options → chips returned; Empty → error; Long labels → truncated |
| `add_to_library` | Valid exercise → added to favorites; Already in library → message; Invalid ID → error |
| `remove_from_library` | Valid → removed from favorites; Not in library → message |
| `create_workout` | Valid → workout created; Duration-based exercise count; Equipment filtering; Protocol assignment |

---

## Manual Testing Checklist

### Library Functionality (v242)

**Critical: Web & iOS use same Firestore path** - `users/{uid}/preferences/exercise.favorites`

| Test Case | iOS | Web | Verify |
|-----------|-----|-----|--------|
| Star button shows filled when exercise is in library | ✓ | ✓ | Star icon filled yellow |
| Star button toggle adds to library | ✓ | ✓ | Firestore `favorites` array updated |
| Star button toggle removes from library | ✓ | ✓ | Firestore `favorites` array updated |
| Sidebar shows library exercises | ✓ | ✓ | Exercises appear under Library > Exercises |
| Sidebar refreshes after star toggle | ✓ | ✓ | New exercise appears/disappears in sidebar |
| Chat "add [exercise] to library" works | ✓ | ✓ | Sidebar updates, Firestore updated |
| Cross-platform sync: iOS → Web | Add on iOS | Check web | Exercise appears in web sidebar |
| Cross-platform sync: Web → iOS | Add on web | Check iOS | Exercise appears in iOS sidebar |

### Plan Detail Panel (v239-v241)

| Test Case | iOS | Web | Verify |
|-----------|-----|-----|--------|
| Programs show in plan detail | ✓ | ✓ | Programs list is not empty |
| Programs ordered by startDate | ✓ | ✓ | Order matches chronological sequence |
| Programs show workout count | ✓ | ✓ | Each program shows "N workouts" |
| Workouts show in program detail | ✓ | ✓ | Workouts list is not empty |
| Workouts ordered by scheduledDate | ✓ | ✓ | Order matches schedule sequence |
| Exercises show in workout detail | ✓ | ✓ | Exercises list is not empty |
| Breadcrumb truncates gracefully | - | ✓ | Long names truncate with ellipsis |
| Breadcrumb works in resized panel | - | ✓ | Text truncates at any panel width |

### Cross-Client Verification (v242)

**ALWAYS test changes on both iOS and Web** when fixing bugs or adding features that affect shared behavior.

| Change Type | iOS Test | Web Test |
|-------------|----------|----------|
| Status colors | Check sidebar plan dots | Check sidebar plan dots |
| Data creation (plan/workout) | Verify detail view shows data | Verify detail view shows data |
| Sidebar refresh | Create plan via chat, check sidebar updates | Create plan via chat, check sidebar updates |
| Entity actions | Check ... menu options match | Check ... menu options match |

**Common cross-client bugs:**
- Fix works on one platform but not the other (different code paths)
- Status colors don't match between platforms
- Sidebar doesn't refresh after data creation
- Actions menu shows different options

### After Prompt Changes

AI tool selection can't be unit tested. Verify manually:

| Say This | Expected Tool | Verify In |
|----------|---------------|-----------|
| "I'm 30 years old" | `update_profile` | Firestore |
| "Show my schedule" | `show_schedule` | Functions logs |
| "Skip today's workout" | `skip_workout` | Firestore |
| "Create a push workout" | `create_workout` | Firestore |
| "Add bench press to my library" | `add_to_library` | Firestore `preferences/exercise.favorites` |
| "Remove deadlift from library" | `remove_from_library` | Firestore `preferences/exercise.favorites` |

### After Handler Deployment

| Test | How |
|------|-----|
| Handler executes | Check Functions logs |
| Data persists | Check Firestore |
| iOS receives response | Test in app |
| Web receives response | Test in browser |

---

## CI/CD Integration

### Current
- Backend: Tests run on `firebase deploy` (predeploy script)
- iOS: Manual test runs

### Target
- [ ] GitHub Actions for backend tests
- [ ] Firestore Emulator in CI
- [ ] iOS tests on PR (if feasible)
- [ ] Coverage thresholds (80% for handlers)

---

## Stale Tests to Address

### iOS Tests to Deprecate
These test patterns that no longer match the architecture:

| Test File | Reason | Action |
|-----------|--------|--------|
| Repository tests (mock-based) | Firestore is source of truth | Move to backend |
| Firebase repository tests | Should test at backend | Deprecate |
| AI Integration tests | Flaky, expensive | Move to backend |

### iOS Tests to Keep
| Test File | Reason |
|-----------|--------|
| Tool Handler tests | Still valid for passthrough handlers |
| DeltaStore tests | Local state management still used |
| Workout Execution tests | iOS-only feature |
| ViewModel tests | iOS-specific UI logic |

---

## Next Steps

1. **Immediate:** Add Firestore Emulator tests for all 22 handlers
2. **Short-term:** Deprecate stale iOS handler tests (all handlers now on server)
3. **Medium-term:** Add React component tests when web is priority
4. **Long-term:** GitHub Actions CI for automated test runs

---

## Related Documentation

- [ROADMAP.md](ROADMAP.md) - Handler migration schedule
- [ARCHITECTURE.md](ARCHITECTURE.md) - System design
- [docs/guides/DEVELOPMENT.md](docs/guides/DEVELOPMENT.md) - Dev workflow
