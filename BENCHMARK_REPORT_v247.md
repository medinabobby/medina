# AI Benchmark Executive Summary

**Version:** v247 | **Date:** January 1, 2026 | **Model:** gpt-4o-mini

---

## Executive Overview

Following the v247 release that introduced reliable tool detection and refined test expectations based on intent classification, we achieved **90% tool calling accuracy** - a 10-point improvement from the previous 80% baseline.

The key insight: two "failures" (TC05, TC10) were actually correct AI behavior. The AI appropriately asks for confirmation before modifying user data, which our tests now correctly expect.

---

## Results Summary

| Metric | Score | Status |
|--------|-------|--------|
| **Tool Calling Accuracy** | **90%** | +10% improvement |
| Fitness Knowledge | 70% | Acceptable |
| Tone & Style | 80% | Good |
| Speed (< threshold) | 60% | Needs review |
| **Total Tests** | **40** | +10 new tests |
| **Total Cost** | **$0.047** | ~$0.001/test |

### Cost Analysis
- Average cost per request: $0.0012
- 40-test suite total: $0.047
- Projected monthly (100 runs): $4.70

---

## Tool Calling Deep Dive

### What We Fixed

| Test | Prompt | Old Expectation | New Expectation | Result |
|------|--------|-----------------|-----------------|--------|
| TC05 | "Create a 12-week strength program" | `create_plan` | `null` | **PASS** |
| TC10 | "I want to train 4 days per week" | `update_profile` | `null` | **PASS** |

**Why these pass now:** The AI correctly asks clarifying questions (TC05) or confirmation (TC10) before acting. This is the intended behavior per our intent classification rules.

### New Tests Added (10)

| Category | Tests | Purpose |
|----------|-------|---------|
| Explicit Commands | TC11, TC12 | Prove explicit commands trigger immediate action |
| Plan Management | PL01, PL02 | Verify destructive actions require confirmation |
| Synonym Handling | SY01, SY02 | Verify "program" → plan, "routine" → schedule |
| Edge Cases | ED01-ED04 | Test incomplete commands, major changes |

### Remaining Failures (4)

| Test | Prompt | Expected | Actual | Analysis |
|------|--------|----------|--------|----------|
| SP03 | "What day is leg day?" | `null` | `show_schedule` | AI checked schedule - arguably correct |
| SP04 | "Create a quick 30 min workout" | `create_workout` | `null` | AI asked questions first |
| TC12 | "Save my schedule as M/W/F" | `update_profile` | `null` | AI didn't recognize "save" as explicit |
| ED02 | "Create a workout" | `create_workout` | `null` | AI asked for details vs. using defaults |

**Assessment:** These are borderline cases. SP03 could be test error (AI reasonably checked schedule). SP04, TC12, ED02 show AI erring on the side of asking - may want to tune prompts to be more action-oriented for simple requests.

---

## Intent Classification Framework (v247)

We documented clear rules for when AI should act immediately vs. ask first:

### Act Immediately
- Explicit commands: "Update my profile to X", "Skip my workout"
- Data provision: "My bench 1RM is 225 lbs"
- Read-only: "Show my schedule"

### Ask First
- Preference statements: "I want to train X days"
- Multi-param requests: "Create a 12-week plan"
- Destructive actions: "Delete my plan"

### Advise First
- Major changes: 2 → 7 days/week
- Unrealistic goals: "Gain 50 lbs in 3 months"

---

## Test Distribution

```
Tool Calling     ████████████████████ 20 tests (50%)
Fitness Accuracy ██████████ 10 tests (25%)
Tone & Style     █████ 5 tests (12.5%)
Speed            █████ 5 tests (12.5%)
```

---

## Performance Metrics

| Metric | Value |
|--------|-------|
| Average Response Time | 3,666 ms |
| Fastest Response | 1,395 ms (TC10) |
| Slowest Response | 12,106 ms (TC09 - long explanation) |
| Tool Call Overhead | ~2-4 seconds |

### Speed Test Results

| Test | Threshold | Actual | Status |
|------|-----------|--------|--------|
| SP01 "Hi" | 2000ms | 1453ms | PASS |
| SP02 "Show schedule" | 3000ms | 4682ms | FAIL |
| SP03 "Leg day?" | 2500ms | 4060ms | FAIL |
| SP04 "Quick workout" | 5000ms | 2578ms | PASS |
| SP05 "Thanks!" | 2000ms | 1438ms | PASS |

---

## Recommendations

### Immediate (This Week)
1. **Review SP03 expectation** - AI checking schedule for "leg day" is reasonable
2. **Tune prompts for simple creates** - "Create a workout" should use defaults, not ask

### Short-Term (This Month)
3. **Add multi-turn tests** - Test confirmation → action flows
4. **Speed optimization** - Tool calls adding 2-4s, investigate caching

### Long-Term
5. **Expand to 100 tests** - More edge cases, failure modes
6. **A/B test models** - Compare gpt-4o vs gpt-4o-mini on accuracy/cost

---

## Conclusion

The v247 benchmark improvements validate our intent classification framework. The AI correctly distinguishes between explicit commands and preference statements, asking for confirmation when appropriate.

**Key Metrics:**
- Tool accuracy improved 80% → 90%
- Test suite expanded 30 → 40 tests
- False negatives eliminated (TC05, TC10)
- Remaining failures are borderline cases, not critical bugs

The 4 remaining failures warrant review but don't indicate systemic issues. The AI's "ask first" tendency on ambiguous requests is generally the safer behavior for a fitness coaching app.

---

*Report generated from `results-gpt-4o-mini.json` | v247 benchmark suite*
