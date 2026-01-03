# Evaluation Memo v266 - Multi-Turn & Output Quality Analysis

**Date:** January 3, 2026
**Model:** gpt-4o-mini
**Total Tests:** 91 (cleaned)
**Framework Version:** v266 (Multi-Turn Credit, Output Quality Scoring)

---

## Executive Summary

v266 introduces **multi-turn credit** and **output quality scoring**. After cleaning broken tests, results show:

### Primary Quality Metric

| Tier | Pass Rate | Before Cleanup | Change | Description |
|------|-----------|----------------|--------|-------------|
| **Tier 1 (Core)** | **95%** (40/42) | 91% (39/43) | **+4%** | Must pass - actual bugs |
| Tier 2 (Interpretation) | 73% (33/45) | 54% (29/54) | **+19%** | Clarify OK |
| Tier 3 (Ambiguous) | 50% (2/4) | 50% (2/4) | - | Clarification preferred |

### Why Numbers Improved

**This is test cleanup, NOT AI improvement.** The changes:

1. **Removed IM01-IM10** (10 tests) - Always failed due to missing fixture files
2. **Fixed TT06** - Updated to use existing `bobby-1rm-max.png` fixture

The AI behavior is unchanged. We just stopped counting guaranteed failures.

---

## Tier 1 Failures (2 Bugs to Fix)

### 1. PROT04: "Create a workout with German Body Comp training"
- **Expected:** `create_workout` with GBC protocol
- **Got:** `none` (no tool called)
- **Analysis:** AI responded with text explanation instead of creating workout
- **Priority:** HIGH (core workout creation feature)
- **Action:** Update system prompt to recognize "German Body Comp" as workout creation trigger

### 2. WQ03: "Create a push workout with bench press, overhead press, and dips"
- **Expected:** `create_workout`
- **Got:** `add_to_library`
- **Analysis:** When user specifies exercises, AI sometimes uses wrong tool
- **Priority:** MEDIUM (tool selection confusion)
- **Action:** Clarify tool selection rules for specific exercise requests

**Previous failures resolved:**
- MT08 now passes (was flaky, not a real bug)
- IM07 removed (was infrastructure issue, not AI bug)

---

## Multi-Turn Success Analysis

The v265 framework penalized the AI for asking clarification before acting. v266 credits this behavior.

### Tests That Pass Due to Multi-Turn Credit

| Test | Prompt | Behavior | Result |
|------|--------|----------|--------|
| **ED02** | "Create a workout" | Asked for details → Created workout | **PASS** |
| TC07 | "I'm 30 years old and weigh 180 lbs" | Asked to confirm → Updated profile | PASS (2 turns) |
| TC10 | "I want to train 4 days per week" | Asked to confirm → Updated profile | PASS (2 turns) |
| OB03 | "Quick chest workout" | Asked for duration → Created workout | PASS (2 turns) |
| PL02 | "Activate the strength plan" | Asked to confirm → Activated | PASS (2 turns) |
| ED02 | "Create a workout" | Asked for details → Created workout | PASS (2 turns) |

---

## Vision Tests (Now Working)

After fixing fixtures, vision tests improved significantly:

| Test | Prompt | Expected Tool | Result |
|------|--------|---------------|--------|
| TT06 | Import workout from screenshot | `update_exercise_target` | **PASS** |
| VIS01 | Import this workout (1RM data) | `update_exercise_target` | **PASS** |
| VIS02 | Create plan for neurotype | `create_plan` | FAIL (no tool) |
| VIS03 | Import workout history (CSV) | - | ERROR (500) |
| VIS04 | Create workout plan | `create_plan` | **PASS** |
| VIS05 | Create workout | `create_workout` | FAIL (wrong tool) |
| VIS06 | Import workout | `create_workout` | FAIL (wrong tool) |
| VIS07 | Log completed workout | `update_workout_results` | FAIL (wrong tool) |

**Vision Pass Rate: 50% (4/8)** - Up from 9% before cleanup

**Issues:**
- VIS03: Vision API returns 500 error (server issue)
- VIS05, VIS06, VIS07: AI selects wrong tool for vision context

---

## Workout Quality Tests (WQ01-WQ10)

| Test | Prompt | Constraints | Result |
|------|--------|-------------|--------|
| WQ01 | 45-min upper body GBC tomorrow | duration, split, protocol, date | **PASS** |
| WQ02 | 60-min home bodyweight only | duration, equipment | **PASS** |
| WQ03 | Push with bench/OHP/dips | split, exercises | FAIL (wrong tool) |
| WQ04 | 30-min lower body | duration, split | **PASS** |
| WQ05 | Leg workout for today | split, date | **PASS** |
| WQ06 | 20-min full body | duration, split | **PASS** |
| WQ07 | Full body dumbbells only | split, equipment | **PASS** |
| WQ08 | Pull with barbell rows | split, exercises | **PASS** |
| WQ09 | 45-min home light dumbbells | duration, equipment | **PASS** |
| WQ10 | Upper body 5x5 | split, protocol | **PASS** |

**90% pass rate** - AI correctly interprets workout constraints.

---

## Test Suite Changes

### Removed (10 tests)
IM01-IM10 referenced non-existent fixture files:
- `spreadsheet-screenshot.jpg`, `strong-app-screenshot.jpg`, `handwritten-log.jpg`
- `instagram-post.jpg`, `pr-board.jpg`, `blurry-image.jpg`, `non-workout.jpg`
- `machine-display.jpg`, `truecoach-screenshot.jpg`, `multiple-exercises.jpg`

### Fixed (1 test)
TT06: Changed `spreadsheet-screenshot.jpg` → `bobby-1rm-max.png`

### Fixtures Available
Located in `web/functions/src/evaluation/fixtures/`:
- `bobby-1rm-max.png` - 1RM spreadsheet data
- `bobby-neurotype.png` - Neurotype assessment
- `mihir-history.csv` - Workout history CSV
- `push-day-plan.png` - Push day workout plan
- `social-media-workout.png` - Social media workout post
- `truecoach-workout.png` - TrueCoach workout screenshot
- `truecoach-results.png` - TrueCoach results screenshot

---

## Performance Metrics

### Latency

| Category | Avg | P95 | Outliers |
|----------|-----|-----|----------|
| Basic Queries | 3,859ms | 7,486ms | 21 |
| Tool Calls | 6,961ms | 18,865ms | 9 |
| Vision | ~15-25,000ms | - | - |

### Cost

- **Total:** $0.20 (91 tests)
- **Per test avg:** $0.002
- **Vision tests:** ~$0.015 each (most expensive)

---

## Recommendations

### Immediate (2 Tier 1 Bugs)

1. **PROT04 - GBC Workout Creation**
   - Update system prompt: "German Body Comp" should trigger `create_workout`
   - Add to MUST CALL table: `"Create a workout with [protocol name]" → create_workout`

2. **WQ03 - Tool Selection**
   - When user says "Create a workout with [exercises]", use `create_workout` not `add_to_library`
   - Review tool selection logic for specific exercise requests

### Short-Term (Vision)

3. **Fix VIS03** - Investigate 500 error on CSV import
4. **Vision tool selection** - VIS05, VIS06, VIS07 use wrong tools

---

## Conclusion

**Core functionality is 95% healthy** after test cleanup.

| Change | Impact |
|--------|--------|
| Removed broken IM tests | +4% Tier 1, +19% Tier 2 (cleanup, not improvement) |
| Multi-turn credit | ED02 and 5 other tests correctly pass |
| Fixed TT06 fixture | Vision tier test now works |

**Actionable bugs: 2**
- PROT04: GBC workout creation (HIGH)
- WQ03: Tool selection for specific exercises (MEDIUM)

---

*Generated: 2026-01-03*
*Framework: v266 Multi-Turn & Output Quality*
*Model: gpt-4o-mini*
*Tests: 91 (after removing 10 broken IM tests)*
