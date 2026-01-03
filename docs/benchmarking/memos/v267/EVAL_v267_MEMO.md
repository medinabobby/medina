# Evaluation Memo v267 - Stakes-Based UX + Parallel Execution

**Date:** January 3, 2026
**Model:** gpt-4o-mini
**Total Tests:** 91
**Framework Version:** v267 (Parallel Execution, Stakes-Based UX)

---

## Executive Summary

v267 introduces **parallel test execution** (5 concurrent) and **stakes-based UX**. Results validate parallel is safe.

### Primary Quality Metric

| Tier | Pass Rate | v266 | Change | Description |
|------|-----------|------|--------|-------------|
| **Tier 1 (Core)** | **98%** (41/42) | 95% (40/42) | **+3%** | Must pass - actual bugs |
| Tier 2 (Interpret) | 78% (35/45) | 73% (33/45) | +5% | Clarify OK |
| Tier 3 (Ambiguous) | 50% (2/4) | 50% (2/4) | - | Clarification preferred |

### Performance Improvement

| Metric | Serial | Parallel (5x) | Improvement |
|--------|--------|---------------|-------------|
| **Runtime** | ~13 min | **~4 min** | **70% faster** |
| Cost | $0.20 | $0.20 | Same |
| Results | Identical | Identical | ✅ Safe |

---

## Key Win: PROT04 Now Passes

The v267 **stakes-based UX framework** fixed PROT04:

**Before (v266 - 3 turns):**
```
User: "Create a GBC workout"
AI: "What duration?" → "What day?" → "Home or gym?" → Creates workout
```

**After (v267 - 1 turn):**
```
User: "Create a GBC workout"
AI: [EXECUTES immediately] "Created your 45-min GBC workout for tomorrow!"
```

### Stakes-Based Pattern

| Action | Stakes | Pattern |
|--------|--------|---------|
| `create_workout` | LOW | Execute → Offer changes |
| `create_plan` | HIGH | Confirm → Execute |
| Destructive | HIGH | Always confirm first |

---

## Tier 1 Failure (1 bug)

### WQ03: "Create a push workout with bench press, overhead press, and dips"
- **Expected:** `create_workout`
- **Got:** `create_custom_workout`
- **Analysis:** When user specifies exercises, AI uses wrong tool
- **Action:** Clarify tool selection rules

---

## Parallel Execution Validation

Ran both serial and parallel (5 concurrent) to validate safety:

| Test | Serial | Parallel | Match |
|------|--------|----------|-------|
| TC01-TC12 | All PASS | All PASS | ✅ |
| PROT04 | PASS | PASS | ✅ |
| WQ03 | FAIL | FAIL | ✅ |
| Vision tests | 4/7 PASS | 4/7 PASS | ✅ |

**Conclusion:** Parallel execution produces identical results, safe to use by default.

---

## Changes in v267

### Code Changes

1. **`toolInstructions.ts`** - Added Execute-Then-Confirm for low-stakes actions
2. **`runner.ts`** - Added parallel batch execution (concurrency=5)
3. **`cli.ts`** - Added `--concurrency` flag

### New CLI Options

```bash
# Run with custom concurrency
npm run eval -- run --concurrency 10

# Run specific tiers quickly
npm run eval -- run --tier 1 --concurrency 5
```

---

## Performance Metrics

### Latency by Category (Parallel)

| Category | Avg | P95 | Outliers |
|----------|-----|-----|----------|
| Basic Queries | 3,762ms | 6,986ms | 22 |
| Tool Calls | 6,035ms | 13,568ms | 6 |
| Vision | ~15-25s | - | - |

### Cost

- **Total:** $0.20 (91 tests)
- **Per test avg:** $0.002
- **Vision tests:** ~$0.015 each

---

## Recommendations

### Immediate

1. **Fix WQ03** - When user says "Create a workout with [exercises]", use `create_workout` not `create_custom_workout`

### Future

2. **Higher concurrency** - Test with 10x concurrency for even faster runs
3. **Vision optimization** - Vision tests dominate runtime (~25s each)

---

## Conclusion

**v267 is production-ready:**
- Tier 1 at 98% (only 1 bug: WQ03)
- PROT04 fixed with stakes-based UX
- 70% faster eval execution with parallel batches
- Parallel validated as safe (identical results)

---

*Generated: 2026-01-03*
*Framework: v267 Parallel Execution + Stakes-Based UX*
*Model: gpt-4o-mini*
*Runtime: ~4 min (parallel) vs ~13 min (serial)*
