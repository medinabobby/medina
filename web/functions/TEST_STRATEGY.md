# Backend Test Strategy

**Version:** v242 (December 31, 2025)

> **See also:** [TESTING.md](../../../TESTING.md) for cross-platform testing strategy

---

## Overview

This document covers testing for Firebase Functions (server-side handlers). These tests are critical because **server handlers run the same code for iOS and Web** - testing here covers both platforms.

---

## Test Layers

### 1. Unit Tests (Current: 44 tests)

**Location:** `src/**/*.test.ts`
**Framework:** Vitest v2.1.9

| File | Tests | Purpose |
|------|-------|---------|
| `index.test.ts` | 11 | Endpoint validation, auth headers |
| `chat.test.ts` | 21 | Auth verification, system prompt, tool definitions |
| `handlers/e2e.test.ts` | 12 | Handler integration (mocked Firestore) |

### 2. Integration Tests (TODO: Add Firestore Emulator)

**Status:** Not yet implemented - HIGH PRIORITY

```bash
# Target setup
firebase emulators:exec "npm test"
```

**What to test:**
- [ ] Handler + real Firestore operations
- [ ] Data persistence verification
- [ ] Query correctness
- [ ] Error handling with real DB

### 3. Manual Testing (Required for AI behavior)

Unit tests verify handlers work **when called**. Manual tests verify **AI decides to call them**.

---

## Handler Coverage

**All 22 handlers are now deployed to server (Dec 2025).**

See ROADMAP.md for complete handler list. All handlers have basic E2E mock tests.

| Priority | Action |
|----------|--------|
| High | Add Firestore Emulator integration tests |
| Medium | Add coverage thresholds (80%) |

---

## Running Tests

```bash
cd web/functions

# Watch mode (development)
npm test

# Single run (CI)
npm run test:run

# With coverage report
npm run test:coverage

# With Firestore Emulator (when configured)
firebase emulators:exec "npm run test:run"
```

---

## Adding Handler Tests

When adding a new server handler:

### 1. Unit Test (Required)

```typescript
// src/handlers/newHandler.test.ts
import { describe, it, expect, vi } from 'vitest';
import { newHandler } from './newHandler';

describe('newHandler', () => {
  it('success case', async () => {
    const mockDb = createMockDb({ /* setup */ });
    const result = await newHandler(args, { uid: 'test', db: mockDb });
    expect(result.output).toContain('expected');
  });

  it('error case - invalid input', async () => {
    // Test validation
  });

  it('error case - not found', async () => {
    // Test missing data
  });
});
```

### 2. Integration Test (Required for Firestore ops)

```typescript
// src/handlers/newHandler.integration.test.ts
import { describe, it, expect, beforeEach } from 'vitest';

describe('newHandler (integration)', () => {
  beforeEach(async () => {
    // Clear emulator data
  });

  it('persists data to Firestore', async () => {
    // Use real Firestore emulator
    // Verify data written correctly
  });
});
```

### 3. Update Handler Registry

Add to `handlers/index.ts` and update this doc.

---

## Test Scenarios by Handler

### show_schedule
- Empty schedule → "No workouts scheduled"
- Week period → Correct date range
- Month period → Calendar month
- Workout formatting → Name, date, status

### update_profile
- Single field → Only that field updated
- Multiple fields → All fields merged
- Empty update → Error message
- All fields → Full profile saved

### skip_workout
- Valid workout → Status = "skipped"
- Already skipped → Error
- Completed workout → Cannot skip
- Non-existent → Not found
- With next workout → Shows next info

### suggest_options
- Valid options → Chips returned
- Empty options → Error
- Long labels → Truncated

### add_to_library (v242)
- Valid exercise → Added to `preferences/exercise.favorites`
- Already in library → "Already in library" message
- Invalid exercise ID → Error message
- Normalized ID → Lowercase, underscores

### remove_from_library (v242)
- Valid exercise → Removed from `preferences/exercise.favorites`
- Not in library → "Not in library" message
- Normalized ID → Matches add normalization

### create_workout (TODO)
- Valid request → Workout created
- Duration-based exercise count
- Equipment filtering
- Protocol assignment
- Superset grouping
- Weight calculation from 1RM

---

## Known Testing Gap: AI Tool Selection

**Issue (v201):** Profile data wasn't saved because AI acknowledged conversationally instead of calling `update_profile`.

**Why tests don't catch it:**
| Test Type | Verifies | Gap |
|-----------|----------|-----|
| Unit tests | Handler works when called | Assumes tool IS called |
| Integration | Handler + Firestore | Assumes tool IS called |
| Manual | Full AI flow | ✅ Catches this |

**Solution:** Manual testing checklist after prompt changes.

---

## Manual Testing Checklist

### After Prompt Changes

| Say This | Expected Tool | Verify In |
|----------|---------------|-----------|
| "I'm 30 years old" | `update_profile` | Firestore |
| "I weigh 175lbs" | `update_profile` | Firestore |
| "Show my schedule" | `show_schedule` | Functions logs |
| "Skip today's workout" | `skip_workout` | Firestore |
| "Create a push workout" | `create_workout` | Firestore |

### Verification Steps

**Firebase Functions Logs:**
```
Firebase Console → Functions → Logs → Filter: "chat"
```

**Firestore:**
```
Firebase Console → Firestore → users/{uid}/
```

---

## CI/CD

Tests run on `firebase deploy` via predeploy script:

```json
{
  "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run build"]
}
```

**Target:** Add `npm test` to predeploy, fail deployment if tests fail.

---

## Priority Improvements

### High Priority
1. **Firestore Emulator tests** - Verify real DB operations
2. **create_workout tests** - Before deployment
3. **Coverage thresholds** - Fail if < 80%

### Medium Priority
4. **create_plan tests** - When migrated
5. **Snapshot tests** - For complex responses
6. **Performance benchmarks** - Handler execution time

### Low Priority
7. **Prompt regression tests** - Expensive but accurate
8. **Recorded response playback** - For AI behavior
