# v268 Prompt Engineering Optimization Results

## Summary

Optimized system prompts and tool definitions to reduce token usage and improve response time while maintaining 100% Tier 1 pass rate.

## Results

| Metric | v267 Baseline | v268 Optimized | Change |
|--------|---------------|----------------|--------|
| **Tier 1 (Core)** | 42/42 (100%) | 42/42 (100%) | No regression |
| Tier 2 (Interpret) | 33/45 (73%) | 33/45 (73%) | No change |
| Tier 3 (Ambiguous) | 4/4 (100%) | 4/4 (100%) | No change |
| **Avg Response Time** | 6,174ms | 5,050ms | **-18.2%** |
| **Cost per Eval** | $0.20 | $0.189 | **-5.5%** |
| Tool Accuracy | 85% | 86% | +1% |
| Intent Detection | 92% | 91% | -1% |

## Changes Implemented

### Phase 1: toolInstructions.ts (SUCCESS)

Reduced verbosity in tool instructions:

- **CREATE_WORKOUT**: 22 lines → 9 lines (59% reduction)
  - Consolidated trigger examples from 7 to 3
  - Condensed Wrong/Right pattern to inline format

- **CREATE_PLAN**: 24 lines → 11 lines (54% reduction)
  - Simplified vision/image instructions
  - Shortened confirmation example

- **Other tools**: Minor consolidations across SKIP_WORKOUT, GET_SUBSTITUTION_OPTIONS, ADD_TO_LIBRARY, UPDATE_EXERCISE_TARGET, UPDATE_PROFILE

**Impact**: 12% response time improvement

### Phase 2: definitions.ts (SUCCESS)

Extracted shared constants and reduced redundant descriptions:

- **Shared constants added**:
  - `SPLIT_DAY_ENUM` - used by createWorkout, modifyWorkout
  - `EFFORT_LEVEL_ENUM` - used by createWorkout, modifyWorkout
  - `TRAINING_LOCATION_ENUM` - used by createWorkout, modifyWorkout, createPlan
  - `PROTOCOL_ID_DESC` - shared protocol description
  - `PROTOCOL_CUSTOMIZATION_SCHEMA` - shared schema object

- **createWorkout description**: 20 lines → 3 lines (85% reduction)
- **modifyWorkout description**: 5 lines → 1 line (80% reduction)
- **createPlan description**: 5 lines → 2 lines (60% reduction)
- **changeProtocol namedProtocol**: Removed verbose alias explanations

**Impact**: Additional 6% response time improvement (18% cumulative)

### Phase 3: coreRules.ts (REVERTED)

Attempted to remove WRONG EXAMPLES section and consolidate FITNESS_WARNINGS.

**Result**: Caused Tier 1 regression (41/42 = 98%). Test WQ10 incorrectly called show_schedule instead of create_workout.

**Learning**: The WRONG EXAMPLES section is critical for preventing tool call errors. Negative examples help the model avoid incorrect behavior patterns.

## Files Modified

| File | Lines Before | Lines After | Change |
|------|--------------|-------------|--------|
| `src/prompts/toolInstructions.ts` | ~235 | ~204 | -13% |
| `src/tools/definitions.ts` | ~1143 | ~1100 | -4% |
| `src/prompts/coreRules.ts` | (unchanged) | (unchanged) | 0% |

## Key Learnings

1. **Positive examples work best for instructions** - Can be heavily consolidated
2. **Negative examples are critical for tool selection** - Removing them causes regressions
3. **Shared schema constants work well** - TypeScript spreads enum arrays correctly
4. **Tool descriptions can be extremely terse** - 3 lines is sufficient for most tools

## Recommendations for Future Optimization

1. **Do NOT remove WRONG EXAMPLES** - They prevent tool calling errors
2. **Focus on tool definitions** - Biggest token savings with lowest risk
3. **Test incrementally** - Phase-by-phase approach caught the Phase 3 regression early
4. **Profile context costs** - Dynamic context (user profile, schedules) likely has more optimization potential than static prompts

## Conclusion

Successfully reduced response time by 18% and costs by 5.5% while maintaining 100% Tier 1 pass rate. Phase 3 optimization was reverted to preserve quality.

---
Generated: 2026-01-03
Baseline: v267
Optimized: v268
