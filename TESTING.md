# Medina Testing Strategy

**Last updated:** December 29, 2025

Cross-platform testing strategy for iOS, Web, and Backend.

---

## Testing Philosophy

### Principle: Test at the Right Layer

```
┌─────────────────────────────────────────────┐
│         BACKEND (Firebase Functions)         │
│  ════════════════════════════════════════   │
│  Server handlers, Firestore operations,      │
│  AI tool execution, data validation          │
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
- Server handlers run the same code for iOS and Web
- Testing once at the backend covers both platforms
- Client tests focus on platform-specific UI/UX

---

## Current State (December 2025)

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

## Handler Migration Testing

As handlers move from iOS to server:

### Before Migration (iOS Passthrough)
```
User → Firebase Function → OpenAI → Tool Call
                                        ↓
                              Passthrough to iOS
                                        ↓
                              iOS executes handler
                              iOS updates Firestore
```
**Test in:** iOS (`MedinaTests/ToolHandlerTests/`)

### After Migration (Server Handler)
```
User → Firebase Function → OpenAI → Tool Call
                                        ↓
                              Server executes handler
                              Server updates Firestore
```
**Test in:** Backend (`web/functions/src/handlers/*.test.ts`)

### Migration Checklist
When migrating a handler:
1. [ ] Write backend unit tests
2. [ ] Write backend integration tests (Firestore Emulator)
3. [ ] Deploy to Firebase
4. [ ] Verify iOS passthrough disabled
5. [ ] Mark iOS tests as deprecated (don't delete yet)
6. [ ] Monitor for regressions

---

## Manual Testing Checklist

### After Prompt Changes

AI tool selection can't be unit tested. Verify manually:

| Say This | Expected Tool | Verify In |
|----------|---------------|-----------|
| "I'm 30 years old" | `update_profile` | Firestore |
| "Show my schedule" | `show_schedule` | Functions logs |
| "Skip today's workout" | `skip_workout` | Firestore |
| "Create a push workout" | `create_workout` | Firestore |

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
