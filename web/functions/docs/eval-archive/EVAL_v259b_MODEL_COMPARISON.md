# AI Model Evaluation - Executive Summary

**Date:** January 2, 2026
**Version:** v259b - Vision Import Flow Fix
**Models Tested:** gpt-4o-mini (baseline) vs gpt-4o
**Test Cases:** 85 (including 7 vision import tests)

---

## Key Findings

### Multi-Dimensional Scoring (v259b)

| Metric | gpt-4o-mini | gpt-4o | Delta |
|--------|-------------|--------|-------|
| **Tool Accuracy Rate** | 65% | 69% | +4% |
| **Intent Detection Rate** | 78% | 73% | -5% |
| **Combined Score** | 71% | 71% | 0% |

> **Tool Accuracy Rate**: % of tests where the correct tool was called
> **Intent Detection Rate**: % of tests where AI correctly understood when to ask vs execute

### Performance & Cost

| Metric | gpt-4o-mini | gpt-4o | Delta |
|--------|-------------|--------|-------|
| Avg Response Time | 4,278ms | 3,014ms | -1,264ms (30% faster) |
| Speed Pass Rate | 60% | 100% | +40% |
| Avg Cost per Request | $0.002 | $0.016 | 8x more |
| Total Eval Cost | $0.17 | $1.36 | 8x more |

### Latency by Category

| Category | gpt-4o-mini | gpt-4o | Delta |
|----------|-------------|--------|-------|
| Basic Queries (36 tests) | 3,649ms avg | 2,400ms avg | 34% faster |
| Tool Calls (27 tests) | 4,414ms avg | 3,559ms avg | 19% faster |
| Basic Outliers (>3s) | 17 | 8 | 9 fewer |
| Tool Call Outliers (>10s) | 1 | 0 | 1 fewer |

---

## v259b Vision Import Fix

### What Was Fixed

The evaluation now replicates the actual production web flow:

```
BEFORE (v259 - broken):
  1. Call vision API
  2. Look for tool in vision response  <-- WRONG
  3. Fail (vision never calls tools)

AFTER (v259b - fixed):
  1. Call vision API → extract exercises
  2. Call chat API with prompt + extracted content
  3. Parse SSE for tool_executed event  <-- CORRECT
```

### Vision Test Results (VIS01-VIS07)

| Test | Expected | gpt-4o-mini | gpt-4o |
|------|----------|-------------|--------|
| VIS01 | update_exercise_target | update_exercise_target ✅ | none ❌ |
| VIS02 | create_plan | show_schedule ❌ | none ❌ |
| VIS03 | (historical import) | Vision API 500 | Vision API 500 |
| VIS04 | create_plan | create_custom_workout ❌ | none ❌ |
| VIS05 | create_workout | create_custom_workout ❌ | create_custom_workout ❌ |
| VIS06 | create_workout | create_workout ✅ | none ❌ |
| VIS07 | (ask first) | update_exercise_target ❌ | none ✅ |

**Key Insight:** gpt-4o-mini is more aggressive at calling tools (6/7 called a tool), while gpt-4o is more conservative (1/7 called a tool). For vision import use cases, **gpt-4o-mini is preferred** as it takes action rather than just describing.

---

## Cost Projection (1,000 requests/day)

| Model | Monthly Cost | Annual Cost |
|-------|--------------|-------------|
| gpt-4o-mini | $61 | $730 |
| gpt-4o | $480 | $5,760 |
| **Difference** | +$419/mo | +$5,030/yr |

---

## Tool Calling Comparison

### By Test Category

| Category | gpt-4o-mini | gpt-4o |
|----------|-------------|--------|
| Core Tool Calling (TC01-TC12) | 10/12 | 11/12 |
| Plan Management (PL01-PL02) | 1/2 | 2/2 |
| Edge Cases (ED01-ED04) | 2/4 | 2/4 |
| Metrics/Tracking (MT01-MT08) | 2/8 | 5/8 |
| Vision Import (VIS01-VIS07) | 2/7 | 1/7 |

### Notable Differences

| Test | gpt-4o-mini | gpt-4o | Notes |
|------|-------------|--------|-------|
| TC08 | get_substitution_options ✅ | none ❌ | Mini correctly calls tool |
| OB07 | create_workout ✅ | create_workout ✅ | Both correct |
| MT03 | none ❌ | analyze_training_data ✅ | 4o uses analytics |
| MT04 | update_exercise_target ❌ | analyze_training_data ✅ | 4o uses analytics |
| MT05 | none ❌ | analyze_training_data ✅ | 4o uses analytics |
| VIS01 | update_exercise_target ✅ | none ❌ | Mini takes action |
| VIS06 | create_workout ✅ | none ❌ | Mini takes action |

---

## Recommendation

**Hybrid Approach**

| Use Case | Recommended Model | Rationale |
|----------|-------------------|-----------|
| General chat/knowledge | **gpt-4o** | Faster, better at complex reasoning |
| Tool calling (workouts) | **gpt-4o-mini** | More aggressive at taking action |
| Vision import | **gpt-4o-mini** | Calls tools instead of just describing |
| Analytics/metrics | **gpt-4o** | Better at data analysis |
| Cost-sensitive | **gpt-4o-mini** | 8x cheaper |

### Current Default: gpt-4o-mini

The current default of gpt-4o-mini is appropriate for most use cases:
- Better at vision import (takes action)
- Comparable tool accuracy (65% vs 69%)
- 8x cheaper
- Acceptable latency

### When to Consider gpt-4o

- Analytics/progress tracking queries
- Complex multi-step reasoning
- When speed is critical (30% faster)

---

## Test Infrastructure Status

### Working
- 63 text-based tests (74% pass rate)
- 6 vision tests with fixtures (VIS01-VIS07)
- Vision → Chat → Tool flow verified

### Missing Fixtures (10 tests skipped)
- IM01-IM10: Various image import scenarios
- TT06: Spreadsheet screenshot

### API Issues
- VIS03: CSV import returns 500 (server-side issue)

---

## Next Steps

1. **Add missing image fixtures** for IM01-IM10 tests
2. **Investigate VIS03** CSV import 500 error
3. **Tune prompts** for vision tests to improve tool selection:
   - VIS04: Should call `create_plan` not `create_custom_workout`
   - VIS05: Should call `create_workout` not `create_custom_workout`
4. **Consider hybrid routing** based on query type

---

*Generated by Medina AI Evaluation Suite v259b*
