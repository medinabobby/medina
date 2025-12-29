# Deprecated Tests

**Moved:** December 28, 2025

These tests are deprecated and excluded from the main test suite. They remain here for reference during the transition period.

---

## Why Deprecated

| File/Folder | Reason |
|-------------|--------|
| `SkipWorkoutHandlerTests.swift` | Handler migrated to server (`web/functions/src/handlers/skipWorkout.ts`) |
| `RepositoryTests/` | Tests mock repositories, not real Firestore. Backend tests now cover this. |
| `AIIntegrationTests/` | Live API tests are expensive and flaky. AI behavior tested at backend. |
| `EntityActionCoordinatorTests.swift` | Coordinator pattern no longer used |
| `FileAttachmentTests.swift` | Feature not in current architecture |
| `ImportServiceTests.swift` | Import flow changed significantly |

---

## When to Delete

These files can be deleted after:
1. Backend tests fully cover the equivalent functionality
2. 2 release cycles have passed without needing to reference them
3. No regressions reported in the areas they covered

**Target deletion:** February 2026

---

## If You Need These Tests

If a regression occurs in an area covered by these tests:
1. Check if backend tests exist (`web/functions/src/handlers/*.test.ts`)
2. If not, add backend tests first
3. Only restore iOS tests if the functionality is iOS-specific
