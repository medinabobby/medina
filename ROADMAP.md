# Medina Roadmap

**Last Updated:** December 30, 2025

---

## Current Status

| Platform | Version | Status |
|----------|---------|--------|
| iOS | v226 | TestFlight (passthrough client) |
| Web | v226 | Production |
| Backend | v226 | **22/22 handlers complete** |

---

## Handler Migration Progress

**22 of 22 handlers complete (100%)**

All tool handlers now run on Firebase Functions. iOS is a pure passthrough client.

### Complete (All Phases)

| Phase | Handler | Description |
|-------|---------|-------------|
| 0 | `show_schedule` | Query and display workout schedule |
| 0 | `update_profile` | Update user profile fields |
| 0 | `skip_workout` | Mark workout as skipped |
| 0 | `suggest_options` | Return suggestion chips |
| 0 | `delete_plan` | Delete plan and associated workouts |
| 1 | `reset_workout` | Clear workout set data |
| 1 | `activate_plan` | Set plan as active |
| 1 | `abandon_plan` | Cancel a plan |
| 1 | `start_workout` | Begin workout session |
| 1 | `end_workout` | Complete workout session |
| 1 | `create_workout` | Create single workout |
| 1 | `create_plan` | Create multi-week plan |
| 2 | `add_to_library` | Add exercise to user library |
| 2 | `remove_from_library` | Remove exercise from library |
| 2 | `update_exercise_target` | Save 1RM/working weight |
| 2 | `get_substitution_options` | Suggest exercise substitutes |
| 2 | `get_summary` | Workout/plan summary |
| 2 | `send_message` | Create message with threading |
| 2 | `reschedule_plan` | Update plan schedule |
| 3 | `modify_workout` | Edit workout parameters |
| 3 | `change_protocol` | Swap exercise protocols |
| 3 | `analyze_training_data` | Training analytics (text MVP) |

---

## Platform Features

### iOS
- Pure passthrough client (all logic on server)
- Claude-style login (Google, Apple, magic link email)
- Full workout execution with voice mode
- Apple Health integration
- Workout history and analytics
- Plan management

### Web
- Chat interface with AI coach
- Workout/plan creation via chat
- Sidebar with plans, workouts, library
- Google and Apple Sign-in

### Parity Status

| Feature | iOS | Web |
|---------|-----|-----|
| Create workout | Yes | Yes |
| Create plan | Yes | Yes |
| Start/end workout | Yes | Yes |
| Modify workout | Yes | Yes |
| Change protocol | Yes | Yes |
| Training analytics | Yes | Yes (text) |
| Workout execution UI | Yes | No |
| Voice mode | Yes | No |
| Apple Health | Yes | N/A |
| View schedule | Yes | Yes |
| Message trainer | Yes | Yes |

---

## Next Priorities

1. **Web workout execution UI** - Start workout from card, log sets
2. **Analytics charts** - Add visualization to analyze_training_data
3. **Delete AuthenticationService.swift** - Legacy beta code cleanup (unused)

---

## Future Features

| Feature | Priority | Notes |
|---------|----------|-------|
| Android app | High | After web parity |
| Web workout execution | High | Log sets, see progress |
| Apple Watch | Medium | Workout tracking companion |
| Push notifications | Medium | Workout reminders |
| Home Screen widgets | Low | iOS-specific |
| Siri Shortcuts | Low | iOS-specific |

---

## Backlog (Deferred)

| Feature | Notes |
|---------|-------|
| .edu student free tier | Auto-detect .edu emails, apply free tier on sign-up |
| Payment tiers | Stripe integration, subscription management |
| Phone/SMS OTP auth | Alternative auth method (~$0.01-0.05/SMS cost) |

---

## White-Label / B2B (Future)

Infrastructure exists for gym white-labeling. UI removed for B2C launch, retrievable from git history.

| Feature | Status | Notes |
|---------|--------|-------|
| Gym white-labeling | Planned | Fork codebase per gym contract |
| Classes booking | Deferred | UI removed (v214), backend infrastructure exists |
| Kisi door access | Deferred | UI removed (v214), no backend implemented |
| Trainer-member pairing | Ready | Backend exists, UI via chat |
| Gym data model | Ready | `seed.ts` has Gym interface, Firestore collection |
| Trainer context | Ready | `trainerContext.ts` builds trainer-specific prompts |

**Data model preserved:** `gymId`, `trainerId`, `membershipTiers`, `classTypes` fields remain in types for future B2B2C support.

---

## Technical Debt

Issues identified in documentation audit (Dec 29, 2025).

### Critical (Pre-Production)

| Issue | Location | Notes |
|-------|----------|-------|
| ~~Hardcoded API key~~ | ~~`ios/Services/Assistant/Config.swift`~~ | **COMPLETE** - All 6 services migrated to Firebase endpoints |
| Firestore security rules | `web/firestore.rules` | Still has TODO comment, allows any auth user to read/write anything |
| Orphaned tool definition | `definitions.ts` | `createCustomWorkout` defined but no handler exists |

### iOS Services Cleanup (Dec 29, 2025 Audit)

| Issue | Location | Action |
|-------|----------|--------|
| Empty folder | `ios/Services/Message/` | Deleted |
| Unused handlers | `ios/Services/Assistant/ToolHandling/Handlers/` | Deleted |
| Voice fragmentation | `ios/Services/Voice/` (7 files) | Merge to 3 |
| Metrics duplication | `TimeAdjustedMetricsCalculator` | Merge into `MetricsCalculator` |
| Misplaced files | `ProtocolResolver`, `ProtocolChangeService` | Move to Resolvers/, Exercise/ |

### iOS Services → Server Migration (COMPLETE)

All iOS business logic migrated to Firebase Functions. iOS is pure passthrough client.

| Service | LOC | Status | Firebase Endpoint |
|---------|-----|--------|-------------------|
| Calculations | ~730 | **COMPLETE** | `/api/calculate` |
| Import | ~1,500 | **COMPLETE** | `/api/import` |
| Exercise Selection | ~2,500 | **COMPLETE** | `/api/selectExercises` |
| Plan Operations | ~1,850 | **COMPLETE** | `/api/activatePlan`, `/api/abandonPlan`, `/api/deletePlan`, `/api/reschedulePlan` |
| Suggestion Chips | ~326 | **COMPLETE** | `/api/initialChips` |

**Deleted iOS files (v225):**
- `PeriodizationEngine.swift` (743 LOC)
- `PlanActivationService.swift` (~300 LOC)
- `PlanDeletionService.swift` (~150 LOC)
- `PlanAbandonmentService.swift` (~90 LOC)
- `PlanRescheduleService.swift` (~200 LOC)
- `PlanTemplateService.swift` (376 LOC)

**Deleted iOS files (v226):**
- `Services/Greeting/GreetingContext.swift` (95 LOC)
- `Services/Greeting/GreetingContextBuilder.swift` (231 LOC)

### Documentation Fixes

| Issue | Location | Notes |
|-------|----------|-------|
| Broken doc links | ARCHITECTURE.md lines 568-570 | References deleted `/docs/` folder |
| Web parity table | ROADMAP.md | "Start/end workout: Yes" misleading - web has no execution UI |
| Test docs outdated | TESTING.md | Backend now has 5,600+ lines of tests |

### Code Cleanup

| Issue | Location | Notes |
|-------|----------|-------|
| Duplicate file | `web/lib/firestore 2.ts` | File with space in name, untracked |

---

## Recently Completed

| Feature | Date | Notes |
|---------|------|-------|
| **Server-side suggestion chips (v226)** | Dec 30 | Created `/api/initialChips` endpoint. Deleted iOS Greeting folder (~326 LOC). iOS + Web now share identical chip logic from server. |
| **iOS Plan services → Firebase (v225)** | Dec 30 | Deleted 6 files (~1,850 LOC): PeriodizationEngine, PlanActivationService, PlanDeletionService, PlanAbandonmentService, PlanRescheduleService, PlanTemplateService. Added /api/plan endpoints. |
| Web settings UX parity | Dec 30 | Compact dropdown like Claude (v224) |
| Web CSV import UX | Dec 30 | UploadModal with Firebase /api/import (v221) |
| Web service layer | Dec 30 | `lib/api.ts` typed helpers for all Firebase endpoints (v220) |
| **API key migration (COMPLETE)** | Dec 29 | All 6 services migrated: VoiceService, VisionExtractionService, URLExtractionService, VoiceAnnouncementService, VoiceModeManager. Config.openAIKey removed. |
| Firebase /api/tts, /vision, /chatSimple | Dec 29 | New endpoints for proxying OpenAI calls |
| iOS Services audit | Dec 29 | Full audit of Services folder, documented cleanup + migration plan |
| Magic link domain fix | Dec 29 | district.fitness → medinaintelligence.web.app |
| Web /auth, /terms, /privacy | Dec 29 | Added legal pages and magic link callback |
| District → Medina rebrand | Dec 29 | Removed B2B demo UI (Classes, Kisi), updated branding |
| Apple Sign-in for web | Dec 29 | Firebase Auth with Apple provider |
| iOS Login Redesign | Dec 29 | Claude-style UI, magic links, social auth at top |
| Web detail pages | Dec 29 | Right-side panel with Plan/Program/Workout/Exercise views |
| Handler migration | Dec 29 | All 22 handlers now on server (100%) |
| iOS parity fixes | Dec 29 | Chevrons, status colors, sidebar structure |

---

## Architecture

```
iOS App ───┐
           ├──► Firebase Functions ──► OpenAI API
Web App ───┘         │
                     └── Firestore (shared data)
```

Tool handlers (22/22) run on Firebase Functions. iOS Services folder: 79 files, ~30,128 LOC (reduced from 87 files via v225/v226 migrations).

See [ARCHITECTURE.md](ARCHITECTURE.md) for technical details.

---

## Deployment

### iOS
```bash
# Xcode → Product → Archive → Distribute App → TestFlight
```

### Web
```bash
cd web
npm run build
firebase deploy --only hosting
```

### Backend
```bash
cd web/functions
npm run build && npm test
firebase deploy --only functions
```

---

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design, data flow
- [TESTING.md](TESTING.md) - Test strategy
- [docs/archive/](docs/archive/) - Completed proposals
