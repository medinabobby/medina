# AI Model Evaluation - Executive Summary

**Date:** January 2, 2026
**Version:** v259 - Vision Import Intent Detection
**Models Tested:** gpt-4o-mini (baseline) vs gpt-4o
**Test Cases:** 85 (including 7 new vision import tests)

---

## Key Findings

### Multi-Dimensional Scoring (v259)

| Metric | gpt-4o-mini | gpt-4o | Delta |
|--------|-------------|--------|-------|
| **Tool Accuracy Rate** | 62% | 71% | +9.4% |
| **Intent Detection Rate** | 74% | 67% | -7.1% |
| **Combined Score** | 68% | 69% | +1.2% |

> **Tool Accuracy Rate**: % of tests where the correct tool was called
> **Intent Detection Rate**: % of tests where AI correctly understood when to ask vs execute

### Performance & Cost

| Metric | gpt-4o-mini | gpt-4o | Delta |
|--------|-------------|--------|-------|
| Avg Response Time | 3,552ms | 2,393ms | -1,159ms (33% faster) |
| Vision Latency (avg) | 2,580ms | 2,161ms | -419ms (16% faster) |
| Vision Latency (p95) | 9,123ms | 8,901ms | -222ms |
| Avg Cost per Request | $0.0017 | $0.016 | +$0.014 |
| Total Eval Cost | $0.14 | $1.07 | 7.6x more |

---

## Vision Import Tests (VIS01-VIS07)

### New v259 Test Cases

| Test | Content Type | Expected Action | GPT-4o-mini | GPT-4o |
|------|--------------|-----------------|-------------|--------|
| VIS01 | 1RM spreadsheet | `update_exercise_target` | ❌ | ❌ |
| VIS02 | Neurotype 1B results | `create_plan` | ❌ | ❌ |
| VIS03 | CSV workout history | Import historical | ❌ | ❌ |
| VIS04 | Multi-workout plan | `create_plan` | ❌ | ❌ |
| VIS05 | Social media workout | `create_workout` | ❌ | ❌ |
| VIS06 | TrueCoach workout | `create_workout` | ❌ | ❌ |
| VIS07 | Completed log | Historical import | ✅ | ✅ |

### Critical Finding: Extraction Works, Action Does Not

**VIS01 (1RM Data) - Actual Response:**
```
"Here's the extracted workout information:
- Squat: Target 220
- Deadlift: Target 240
- Bench Press: Target 200
- Overhead Press: Target 105..."
```

**What Should Happen:**
```
"I've updated your 1RM targets:
✅ Squat: 220 lbs
✅ Deadlift: 240 lbs
✅ Bench Press: 200 lbs..."
[Calls update_exercise_target tool]
```

### Extraction Quality (v259 Fix Verified)

The extraction scoring fix is working - numeric values now extracted:

| Test | Extracted Content |
|------|-------------------|
| VIS01 | squat, deadlift, bench press, overhead press, **220**, **240**, **200**, **105** |
| VIS02 | neurotype, **1b**, press, squat |
| VIS05 | incline, bench press, shoulder press, lateral raise, tricep, dips |

---

## Cost Projection (1,000 requests/day)

| Model | Monthly Cost | Annual Cost |
|-------|--------------|-------------|
| gpt-4o-mini | $51 | $612 |
| gpt-4o | $480 | $5,760 |
| **Difference** | +$429/mo | +$5,148/yr |

---

## Root Cause Analysis

### Why Vision Tests Fail

Both models correctly extract content from images but **do not take action**. The AI treats vision import as a "describe what you see" task rather than an "import and save this data" task.

**Current Flow:**
1. User uploads image + prompt "Import this workout"
2. Vision API extracts content correctly
3. AI returns text description of extracted content
4. ❌ No tool is called to save/create the data

**Expected Flow:**
1. User uploads image + prompt "Import this workout"
2. Vision API extracts content
3. AI analyzes content type (1RM data, workout, plan, etc.)
4. ✅ AI calls appropriate tool (`update_exercise_target`, `create_workout`, `create_plan`)
5. AI confirms action was taken

---

## Recommendation

**🔧 FIX REQUIRED: Update Vision Import Pipeline**

### Immediate Actions

1. **Update system prompt** for vision/chat to instruct model to take action after extraction
2. **Add post-vision orchestration** logic to auto-detect content type and invoke tools
3. **Content type detection rules:**
   - 1RM/target data → `update_exercise_target`
   - Neurotype results → `create_plan` with neurotype-optimized programming
   - Multi-workout image → `create_plan`
   - Single workout → `create_workout`
   - Completed workout with weights → historical import

### Model Selection

| Use Case | Recommendation |
|----------|----------------|
| General chat/tool calling | **gpt-4o** (faster, more accurate) |
| High volume/cost sensitive | **gpt-4o-mini** (10x cheaper, acceptable quality) |
| Vision extraction | **Either** (both extract well, neither acts) |

---

## Test Infrastructure Improvements (v259)

### Added
- Numeric value extraction (1RM weights: 220, 240, 200)
- Neurotype indicator detection (1A, 1B, 2A, 2B, Type 3)
- Content type markers (1rm_data, split_day, multi_workout)
- Intent detection scoring (action taken vs just described)

### Vision Test Fixtures Added
- `bobby-1rm-max.png` - 1RM target spreadsheet
- `bobby-neurotype.png` - Neurotype 1B test results
- `mihir-history.csv` - 24 historical workouts
- `push-day-plan.png` - Multi-workout push/leg plan
- `social-media-workout.png` - Twitter workout post
- `truecoach-workout.png` - Coaching app screenshot
- `truecoach-results.png` - Completed workout log

---

## Detailed Vision Test Results

### VIS01: 1RM Spreadsheet
| Metric | gpt-4o-mini | gpt-4o |
|--------|-------------|--------|
| Tool Called | none ❌ | none ❌ |
| Expected | update_exercise_target | update_exercise_target |
| Extraction Score | 0.83 | 0.83 |
| Response Time | 4,274ms | 4,065ms |

### VIS02: Neurotype 1B
| Metric | gpt-4o-mini | gpt-4o |
|--------|-------------|--------|
| Tool Called | none ❌ | none ❌ |
| Expected | create_plan | create_plan |
| Response Time | 12,201ms | 9,123ms |

### VIS05: Social Media Workout
| Metric | gpt-4o-mini | gpt-4o |
|--------|-------------|--------|
| Tool Called | none ❌ | none ❌ |
| Expected | create_workout | create_workout |
| Extraction Score | 0.67 | 0.67 |
| Response Time | 4,274ms | 3,874ms |

---

*Generated by Medina AI Evaluation Suite v259*
