# iOS Test Status & Deprecation Plan

**Version:** December 28, 2025

> **See also:** [TESTING.md](../../../TESTING.md) for cross-platform testing strategy

---

## Overview

With the shift to server-side handlers and Firestore as source of truth, some iOS tests are now testing patterns that no longer match the architecture. This document tracks test status and deprecation plans.

---

## Test File Status

### ✅ KEEP - Still Valid

These tests cover iOS-only features or patterns that remain relevant:

| File | Tests | Reason to Keep |
|------|-------|----------------|
| **WorkoutExecutionTests/** | | |
| `FocusedExecutionViewModelTests.swift` | ~50 | iOS-only workout execution UI |
| **ViewModelTests/** | | |
| `ChatViewModelTests.swift` | ~30 | iOS-specific view model logic |
| **ServiceTests/** | | |
| `DeltaStoreTests.swift` | ~20 | Local state still used for workout progress |
| `WorkoutCreationServiceTests.swift` | ~15 | Until create_workout fully on server |
| `UserContextBuilderTests.swift` | ~10 | Context building logic |
| **UITests/** | | |
| `ChipResolutionTests.swift` | ~12 | iOS-specific chip rendering |
| **PromptValidationTests.swift** | ~20 | Validates prompt content |

### ⚠️ KEEP FOR NOW - Deprecate After Handler Migration

These tests cover tool handlers that are still in iOS passthrough mode. Deprecate each as its handler moves to server:

| File | Tests | Migrate When |
|------|-------|--------------|
| **ToolHandlerTests/** | | |
| `CreateWorkoutHandlerTests.swift` | ~25 | After server handler deployed |
| `PlanCreationTests.swift` | ~20 | After create_plan migrated |
| `StartWorkoutHandlerTests.swift` | ~33 | After start_workout migrated |
| `EndWorkoutHandlerTests.swift` | ~10 | After end_workout migrated |
| `ResetWorkoutHandlerTests.swift` | ~8 | After reset_workout migrated |
| `AbandonPlanHandlerTests.swift` | ~10 | After abandon_plan migrated |
| `DeletePlanHandlerTests.swift` | ~8 | After delete_plan migrated |
| `GetSubstitutionHandlerTests.swift` | ~12 | After substitution migrated |
| `ExerciseLibraryHandlerTests.swift` | ~15 | After library handlers migrated |
| `SendMessageHandlerTests.swift` | ~8 | After messaging migrated |
| `AnalyzeTrainingDataTests.swift` | ~10 | After analysis migrated |
| `CardioWorkoutTests.swift` | ~8 | After cardio support migrated |
| `SupersetTests.swift` | ~15 | Part of create_workout |
| `ProtocolChangeTests.swift` | ~10 | Part of modify_workout |
| `MovementPatternTests.swift` | ~8 | Part of exercise selection |
| `LibraryParityTests.swift` | ~10 | Library sync logic |
| `WorkoutScenarioTests.swift` | ~29 | Integration scenarios |
| `SidebarTests.swift` | ~8 | UI scenarios |

### ⚠️ DEPRECATE NOW - Already Migrated to Server

These test handlers that are now on the server. The backend tests cover this:

| File | Tests | Reason to Deprecate |
|------|-------|---------------------|
| `SkipWorkoutHandlerTests.swift` | ~19 | `skip_workout` is on server |

**Action:** Mark as `@available(*, deprecated)` or move to `Deprecated/` folder.

### ❌ DEPRECATE - Testing Wrong Pattern

These tests use patterns that no longer match the architecture:

| File | Tests | Reason to Deprecate |
|------|-------|---------------------|
| **RepositoryTests/** | | |
| `PlanRepositoryTests.swift` | ~15 | Tests mock repos, not real Firestore |
| `WorkoutRepositoryTests.swift` | ~10 | Tests mock repos, not real Firestore |
| **AIIntegrationTests/** | | |
| `AIIntegrationTests.swift` | ~6 | Live API tests - move to backend |
| `AITestHelpers.swift` | N/A | Helper for deprecated tests |
| **ServiceTests/** | | |
| `EntityActionCoordinatorTests.swift` | ~10 | Coordinator pattern changed |
| `FileAttachmentTests.swift` | ~5 | Feature not in current arch |
| `ImportServiceTests.swift` | ~8 | Import flow changed |

---

## Migration Checklist

When a handler moves from iOS to server:

### 1. Before Migration
- [ ] Handler has tests in `ios/MedinaTests/ToolHandlerTests/`
- [ ] Document test scenarios

### 2. During Migration
- [ ] Create backend tests in `web/functions/src/handlers/`
- [ ] Port test scenarios to TypeScript
- [ ] Add Firestore emulator tests

### 3. After Migration
- [ ] Verify backend tests pass
- [ ] Verify handler works via iOS app (manual test)
- [ ] Mark iOS tests as deprecated:
  ```swift
  @available(*, deprecated, message: "Handler migrated to server - see web/functions/src/handlers/")
  ```
- [ ] Move to `MedinaTests/Deprecated/` folder (don't delete yet)

---

## Test Count Summary

| Category | Files | Tests | Status |
|----------|-------|-------|--------|
| Keep (iOS-only) | 7 | ~157 | ✅ Valid |
| Keep for now (passthrough) | 18 | ~237 | ⚠️ Deprecate incrementally |
| Deprecate (migrated) | 1 | ~19 | ⚠️ Mark deprecated |
| Deprecate (wrong pattern) | 6 | ~54 | ❌ Remove/archive |
| **Total** | **35** | **~467** | |

---

## Recommended Actions

### Immediate (This Week)
1. Create `MedinaTests/Deprecated/` folder
2. Move `SkipWorkoutHandlerTests.swift` to Deprecated (handler on server)
3. Move repository tests to Deprecated (mock-based, not useful)
4. Move AI integration tests to Deprecated (should be at backend)

### Short-term (With Each Handler Migration)
5. As each handler migrates, move its iOS tests to Deprecated
6. Add equivalent tests at backend

### Long-term
7. Delete Deprecated folder contents after 2 release cycles
8. Keep only iOS-only feature tests

---

## Helpers & Fixtures

| File | Status | Notes |
|------|--------|-------|
| `Helpers/MockToolContext.swift` | ⚠️ Keep for now | Used by passthrough handler tests |
| `Helpers/TestFixtures.swift` | ✅ Keep | General test data |

---

## Running Tests

```bash
# Run all tests
xcodebuild test -project Medina.xcodeproj -scheme Medina -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test file
xcodebuild test -project Medina.xcodeproj -scheme Medina -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MedinaTests/FocusedExecutionViewModelTests

# Run in Xcode
Cmd+U
```
