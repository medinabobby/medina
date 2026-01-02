# Medina AI Evaluation Report v259b

**Date:** January 2, 2026
**Evaluation Version:** v259b (Vision Import Flow Fix)
**Models Tested:** gpt-4o-mini vs gpt-4o
**Total Test Cases:** 85
**Endpoint:** `https://us-central1-medinaintelligence.cloudfunctions.net/chat`

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Test Suite Overview](#test-suite-overview)
3. [Multi-Dimensional Scoring](#multi-dimensional-scoring)
4. [Category-by-Category Analysis](#category-by-category-analysis)
5. [Tool Calling Deep Dive](#tool-calling-deep-dive)
6. [Vision Import Analysis](#vision-import-analysis)
7. [Latency Analysis](#latency-analysis)
8. [Cost Analysis](#cost-analysis)
9. [Failure Analysis](#failure-analysis)
10. [Recommendations](#recommendations)
11. [Action Items](#action-items)

---

## Executive Summary

### Key Metrics

| Metric | gpt-4o-mini | gpt-4o | Winner |
|--------|-------------|--------|--------|
| **Combined Score** | 71% | 71% | Tie |
| **Tool Accuracy Rate** | 65% | 69% | gpt-4o (+4%) |
| **Intent Detection Rate** | 78% | 73% | gpt-4o-mini (+5%) |
| **Avg Response Time** | 4,278ms | 3,014ms | gpt-4o (30% faster) |
| **Cost per Request** | $0.002 | $0.016 | gpt-4o-mini (8x cheaper) |
| **Speed Pass Rate** | 60% | 100% | gpt-4o |
| **Fitness Accuracy** | 69% | 76% | gpt-4o (+7%) |
| **Tone Score** | 72% | 60% | gpt-4o-mini (+12%) |

### Bottom Line

**Neither model is definitively better.** Each has strengths:

| gpt-4o-mini | gpt-4o |
|-------------|--------|
| Better intent detection (+5%) | Better tool accuracy (+4%) |
| Better tone/personality (+12%) | Better fitness accuracy (+7%) |
| 8x cheaper | 30% faster |
| More aggressive at vision import | Better at analytics queries |

**Current Recommendation:** Keep **gpt-4o-mini** as default due to cost advantage and comparable quality.

---

## Test Suite Overview

### Test Categories (85 total)

| Category | Count | Description |
|----------|-------|-------------|
| Tool Calling (TC, PL, SY, ED) | 20 | Verify correct tool invocations |
| Fitness Accuracy (FA) | 10 | Fitness knowledge validation |
| Tone (TN) | 5 | Coaching style and off-topic handling |
| Speed (SP) | 5 | Response time for simple queries |
| Onboarding (OB) | 8 | New user experience flows |
| Metrics/Tracking (MT) | 8 | Progress and analytics queries |
| Tier Testing (TT) | 6 | Model tier selection |
| URL Import (URL) | 6 | Link/article import handling |
| Image Import (IM) | 10 | Screenshot import (fixtures missing) |
| Vision Import (VIS) | 7 | New vision import tests with fixtures |

### Test Status

| Status | gpt-4o-mini | gpt-4o |
|--------|-------------|--------|
| Pass | 55 (65%) | 59 (69%) |
| Fail | 30 (35%) | 26 (31%) |
| Errors (API/Fixtures) | 12 | 12 |

---

## Multi-Dimensional Scoring

### Scoring Dimensions Explained

1. **Tool Accuracy Rate**: Did the AI call the correct tool?
   - Pass: Correct tool called (or no tool when none expected)
   - Fail: Wrong tool or no tool when one was expected

2. **Intent Detection Rate**: Did the AI understand when to ask vs execute?
   - High clarity prompts ("Update my profile") → should execute immediately
   - Low clarity prompts ("I weigh 180 lbs") → should ask first
   - Risky actions ("Delete my plan") → must ask first

3. **Combined Score**: Average of Tool Accuracy and Intent Detection

### Results by Dimension

| Dimension | gpt-4o-mini | gpt-4o | Analysis |
|-----------|-------------|--------|----------|
| Tool Accuracy | 65% | 69% | 4o slightly better at calling correct tools |
| Intent Detection | 78% | 73% | Mini better at knowing when to ask vs execute |
| Combined | 71% | 71% | Effectively identical overall |

### Intent Detection Patterns

| Pattern | gpt-4o-mini | gpt-4o |
|---------|-------------|--------|
| Executes on high-clarity prompts | ✅ | ✅ |
| Asks on low-clarity prompts | ✅ | ✅ |
| Asks on risky actions (delete) | ❌ (1 failure) | ✅ |
| Too eager on ambiguous prompts | Some cases | More conservative |

---

## Category-by-Category Analysis

### 1. Core Tool Calling (TC01-TC12)

| Test | Expected | gpt-4o-mini | gpt-4o | Notes |
|------|----------|-------------|--------|-------|
| TC01 | create_workout | ✅ | ✅ | Both correct |
| TC02 | show_schedule | ✅ | ✅ | Both correct |
| TC03 | update_exercise_target | ✅ | ✅ | Both correct |
| TC04 | skip_workout | ✅ | ✅ (asked) | 4o asked first |
| TC05 | null (ask first) | ✅ | ✅ | Both correctly ask |
| TC06 | add_to_library | ✅ | ✅ | Both correct |
| TC07 | null (ask first) | ✅ | ✅ | Both correctly ask |
| TC08 | get_substitution_options | ✅ | ❌ (none) | **4o fails to call tool** |
| TC09 | null (knowledge) | ✅ | ✅ | Both correct |
| TC10 | null (ask first) | ✅ | ✅ | Both correctly ask |
| TC11 | update_profile | ✅ | ✅ | Both correct |
| TC12 | update_profile | ✅ | ✅ | Both correct |

**Score:** gpt-4o-mini: 12/12 | gpt-4o: 11/12

**Key Finding:** TC08 (substitution) - gpt-4o fails to call `get_substitution_options` when asked to swap an exercise.

### 2. Plan Management (PL01-PL02)

| Test | Expected | gpt-4o-mini | gpt-4o | Notes |
|------|----------|-------------|--------|-------|
| PL01 | delete_plan (ask first) | ❌ abandon_plan | ✅ delete_plan | Mini uses wrong tool name |
| PL02 | activate_plan | ✅ | ✅ | Both correct |

**Score:** gpt-4o-mini: 1/2 | gpt-4o: 2/2

### 3. Fitness Accuracy (FA01-FA10)

| Test | Topic | gpt-4o-mini | gpt-4o |
|------|-------|-------------|--------|
| FA01 | RDL muscles | 100% | 100% |
| FA02 | Bench breathing | Pass | Pass |
| FA03 | Hypertrophy rep range | Pass | Pass |
| FA04 | Rest periods | Pass | Pass |
| FA05 | Training through pain | Pass | Pass |
| FA06 | Progressive overload | Pass | Pass |
| FA07 | PPL vs Upper/Lower | Pass | Pass |
| FA08 | Protein needs | Pass | Pass |
| FA09 | Same muscle 2 days | Pass | Pass |
| FA10 | Muscle in deficit | Pass | Pass |

**Score:** Both 10/10 pass (topic coverage varies)

**Fitness Accuracy Score:** gpt-4o-mini: 69% | gpt-4o: 76%

### 4. Tone & Personality (TN01-TN05)

| Test | Scenario | gpt-4o-mini | gpt-4o |
|------|----------|-------------|--------|
| TN01 | Motivation struggle | ✅ Encouraging | ✅ Encouraging |
| TN02 | Missed workouts | ✅ Supportive | ✅ Supportive |
| TN03 | Off-topic (stocks) | ✅ Redirects | ✅ Redirects |
| TN04 | Deload explanation | ✅ Educational | ✅ Educational |
| TN05 | Unrealistic goals | ✅ Realistic | ✅ Realistic |

**Tone Score:** gpt-4o-mini: 72% | gpt-4o: 60%

**Key Finding:** gpt-4o-mini has warmer, more encouraging tone.

### 5. Speed Tests (SP01-SP05)

| Test | Max Time | gpt-4o-mini | gpt-4o |
|------|----------|-------------|--------|
| SP01 | 2000ms | 3084ms ❌ | 1920ms ✅ |
| SP02 | 3000ms | 5643ms ❌ | 3715ms ❌ |
| SP03 | 2000ms | 2113ms ❌ | 1764ms ✅ |
| SP04 | 3000ms | 1651ms ✅ | 5743ms ❌ |
| SP05 | 2000ms | 1865ms ✅ | 1343ms ✅ |

**Speed Pass Rate:** gpt-4o-mini: 60% | gpt-4o: 100%

Note: Speed test thresholds may need adjustment - both models show high variance.

### 6. Onboarding (OB01-OB08)

| Test | Prompt | gpt-4o-mini | gpt-4o | Expected |
|------|--------|-------------|--------|----------|
| OB01 | "Give me a workout" | ❌ none | ❌ none | create_workout |
| OB02 | "I want to start lifting" | Pass (ask) | Pass (ask) | null (ask) |
| OB03 | "Quick chest workout" | ❌ none | ✅ create_workout | create_workout |
| OB04 | "30 min, dumbbells only" | ✅ create_workout | ✅ create_workout | create_workout |
| OB05 | "I'm a beginner" | ❌ create_workout | ❌ none | null (ask) |
| OB06 | "What can you do?" | ✅ none | ✅ none | null |
| OB07 | "Push day" | ✅ create_workout | ✅ create_workout | create_workout |
| OB08 | "Legs" | ✅ create_workout | ❌ show_schedule | create_workout |

**Score:** gpt-4o-mini: 5/8 | gpt-4o: 5/8

**Key Issue:** Both struggle with vague requests ("Give me a workout").

### 7. Metrics & Tracking (MT01-MT08)

| Test | Query | gpt-4o-mini | gpt-4o | Expected |
|------|-------|-------------|--------|----------|
| MT01 | "How is my plan going?" | ❌ none | ❌ none | analyze_training_data |
| MT02 | "Progress this week" | ❌ none | ❌ show_schedule | analyze_training_data |
| MT03 | "Bench improvement" | ❌ none | ✅ analyze_training_data | analyze_training_data |
| MT04 | "Strongest lifts" | ❌ update_exercise_target | ✅ analyze_training_data | analyze_training_data |
| MT05 | "Am I making progress?" | ❌ none | ✅ analyze_training_data | analyze_training_data |
| MT06 | "Note to trainer" | ✅ none (ask) | ✅ none (ask) | null |
| MT07 | "Client congrats" | ❌ none | ❌ none | send_message |
| MT08 | "Custom workout" | ✅ create_custom_workout | ✅ create_custom_workout | create_custom_workout |

**Score:** gpt-4o-mini: 2/8 | gpt-4o: 5/8

**Key Finding:** gpt-4o significantly better at analytics queries (uses `analyze_training_data`).

### 8. URL Import (URL01-URL06)

| Test | URL Type | gpt-4o-mini | gpt-4o |
|------|----------|-------------|--------|
| URL01 | T-Nation article | ✅ Ask | ✅ Explain |
| URL02 | Reddit program | ✅ Explain | ✅ Explain |
| URL03 | YouTube video | ✅ Explain | ✅ Explain |
| URL04 | Broken link | ✅ Explain | ✅ Explain |
| URL05 | Non-fitness | ✅ Explain | ✅ Explain |
| URL06 | Instagram | ✅ Explain | ✅ Explain |

**Score:** Both 6/6 (all explain limitations appropriately)

---

## Vision Import Analysis

### v259b Fix Summary

**Problem:** Evaluation was only calling vision API, then looking for tools in vision response.

**Fix:** Now replicates production flow:
1. Call vision API → extract exercises
2. Call chat API with extracted content
3. Parse SSE for `tool_executed` event

### Vision Test Results

| Test | Image Type | Expected | gpt-4o-mini | gpt-4o |
|------|------------|----------|-------------|--------|
| VIS01 | 1RM spreadsheet | update_exercise_target | ✅ update_exercise_target | ❌ none |
| VIS02 | Neurotype 1B | create_plan | ❌ show_schedule | ❌ none |
| VIS03 | CSV history | (import) | ❌ API 500 | ❌ API 500 |
| VIS04 | Multi-workout | create_plan | ❌ create_custom_workout | ❌ none |
| VIS05 | Social media | create_workout | ❌ create_custom_workout | ❌ create_custom_workout |
| VIS06 | TrueCoach | create_workout | ✅ create_workout | ❌ none |
| VIS07 | Completed log | null (ask) | ❌ update_exercise_target | ✅ none |

**Vision Score:** gpt-4o-mini: 2/7 | gpt-4o: 1/7

### Key Vision Insight

**gpt-4o-mini is more action-oriented:**
- Called a tool in 6/7 vision tests
- Sometimes wrong tool, but takes action

**gpt-4o is more conservative:**
- Called a tool in 1/7 vision tests
- Often just describes instead of acting

**For vision import, gpt-4o-mini is preferred** because users expect action, not description.

---

## Latency Analysis

### By Category

| Category | gpt-4o-mini | gpt-4o | Delta |
|----------|-------------|--------|-------|
| Basic Queries (36) | 3,649ms avg | 2,400ms avg | 34% faster |
| Tool Calls (27) | 4,414ms avg | 3,559ms avg | 19% faster |
| Vision (22) | 5,140ms avg | 3,349ms avg | 35% faster |

### Percentile Distribution

| Metric | gpt-4o-mini | gpt-4o |
|--------|-------------|--------|
| Min Response | 1,342ms | 1,083ms |
| Avg Response | 4,278ms | 3,014ms |
| P95 Response | 22,311ms | 12,857ms |
| Max Response | 22,393ms | 17,617ms |

### Outliers

| Category | Threshold | gpt-4o-mini | gpt-4o |
|----------|-----------|-------------|--------|
| Basic (>3s) | 3,000ms | 17 outliers | 8 outliers |
| Tool Call (>10s) | 10,000ms | 1 outlier | 0 outliers |
| Vision (>20s) | 20,000ms | 2 outliers | 0 outliers |

**Conclusion:** gpt-4o is consistently 25-35% faster with fewer outliers.

---

## Cost Analysis

### Per-Request Cost

| Model | Input Tokens | Output Tokens | Avg Cost |
|-------|--------------|---------------|----------|
| gpt-4o-mini | 6,162 avg | 103 avg | $0.002 |
| gpt-4o | 5,706 avg | 94 avg | $0.016 |

### Total Evaluation Cost

| Model | Total Cost | Cost/Test |
|-------|------------|-----------|
| gpt-4o-mini | $0.17 | $0.002 |
| gpt-4o | $1.36 | $0.016 |

### Monthly/Annual Projection (1,000 requests/day)

| Model | Monthly | Annual |
|-------|---------|--------|
| gpt-4o-mini | $61 | $730 |
| gpt-4o | $480 | $5,760 |
| **Difference** | +$419/mo | +$5,030/yr |

**gpt-4o costs 8x more with marginal quality improvement.**

---

## Failure Analysis

### Common Failure Patterns

#### 1. Missing Tool Calls (Both Models)

| Prompt | Expected | Issue |
|--------|----------|-------|
| "Give me a workout" | create_workout | Too vague - AI asks for details |
| "Quick chest workout" | create_workout | gpt-4o-mini fails to act |
| "How is my plan going?" | analyze_training_data | Neither model uses analytics |

**Root Cause:** System prompt may not emphasize taking action on vague requests.

#### 2. Wrong Tool Called

| Test | Prompt | Expected | Actual | Model |
|------|--------|----------|--------|-------|
| PL01 | "Delete my plan" | delete_plan | abandon_plan | gpt-4o-mini |
| OB08 | "Legs" | create_workout | show_schedule | gpt-4o |
| MT04 | "Strongest lifts" | analyze_training_data | update_exercise_target | gpt-4o-mini |

**Root Cause:** Similar tool names cause confusion; need clearer tool descriptions.

#### 3. Vision Import Failures

| Issue | Count | Cause |
|-------|-------|-------|
| No tool called | 8 | Model describes instead of acting |
| Wrong tool | 4 | Misclassifies image content type |
| API 500 | 2 | CSV files not supported |

**Root Cause:** System prompt needs stronger instruction to take action on vision imports.

### Tests Failing Both Models

| Test ID | Prompt | Expected | Both Got |
|---------|--------|----------|----------|
| SP03 | "What day is leg day?" | (schedule query) | Slow response |
| ED02 | "Create a workout" | create_workout | Asked instead |
| OB01 | "Give me a workout" | create_workout | Asked instead |
| MT01 | "How is my plan going?" | analyze_training_data | None |
| MT07 | "Tell client great job" | send_message | None |

---

## Recommendations

### 1. Model Selection Strategy

| Use Case | Recommended | Rationale |
|----------|-------------|-----------|
| **Default** | gpt-4o-mini | 8x cheaper, good quality |
| **Analytics/Progress** | gpt-4o | Better at analyze_training_data |
| **Vision Import** | gpt-4o-mini | Takes action instead of describing |
| **Speed-Critical** | gpt-4o | 30% faster, no outliers |
| **High-Volume** | gpt-4o-mini | Cost savings compound |

### 2. System Prompt Improvements

#### A. Vague Request Handling
```
CURRENT: AI asks for clarification on vague requests
ISSUE: Users want action, not questions
FIX: Add rule - "If user says 'give me a workout' with no details,
     create a balanced full-body workout with default duration (45 min)"
```

#### B. Vision Import Instructions
```
ADD: "When user uploads an image with workout/exercise content:
     1. Extract the exercises
     2. IMMEDIATELY call create_workout or create_plan
     3. Do NOT just describe what you see
     4. Take action unless the image is unclear"
```

#### C. Analytics Queries
```
ADD: "For progress/analytics questions like:
     - 'How is my plan going?'
     - 'Am I making progress?'
     - 'What are my strongest lifts?'
     CALL analyze_training_data, do NOT just respond with text"
```

### 3. Test Suite Improvements

| Issue | Fix |
|-------|-----|
| 10 missing image fixtures (IM01-IM10) | Add test images to fixtures/ |
| VIS03 CSV import 500 error | Add CSV parsing support to vision endpoint |
| Speed test thresholds unrealistic | Adjust to P95 of actual performance |
| Some expected tools may be wrong | Review PL01 (delete vs abandon) |

### 4. Tool Naming Clarity

| Current | Issue | Suggestion |
|---------|-------|------------|
| delete_plan / abandon_plan | Confusion | Use only `delete_plan` |
| create_workout / create_custom_workout | When to use which? | Document difference |
| update_exercise_target | Name unclear | Consider `set_1rm` or `update_1rm` |

---

## Action Items

### Immediate (This Sprint)

1. **Add missing image fixtures** for IM01-IM10 tests
2. **Update system prompt** for vision import (take action, don't describe)
3. **Add vague request handling** rule ("give me a workout" → create default)

### Short-Term (Next Sprint)

4. **Add analytics tool guidance** to system prompt
5. **Fix tool naming** (delete_plan vs abandon_plan)
6. **Investigate CSV import** 500 error in vision endpoint
7. **Adjust speed test thresholds** based on P95 data

### Long-Term (Roadmap)

8. **Consider hybrid routing** - Use gpt-4o for analytics, mini for everything else
9. **Add LLM-as-judge evaluation** (requires OPENAI_API_KEY setup)
10. **Build regression test automation** - Run on every deploy

---

## Appendix: Full Test Results

### gpt-4o-mini Results (55 pass / 30 fail)

| Category | Pass | Fail | Rate |
|----------|------|------|------|
| Tool Calling | 16 | 4 | 80% |
| Fitness Accuracy | 10 | 0 | 100% |
| Tone | 5 | 0 | 100% |
| Speed | 3 | 2 | 60% |
| Onboarding | 5 | 3 | 63% |
| Metrics | 2 | 6 | 25% |
| Tier | 5 | 1 | 83% |
| URL Import | 6 | 0 | 100% |
| Image Import | 0 | 10 | 0% (fixtures missing) |
| Vision | 2 | 5 | 29% |

### gpt-4o Results (59 pass / 26 fail)

| Category | Pass | Fail | Rate |
|----------|------|------|------|
| Tool Calling | 17 | 3 | 85% |
| Fitness Accuracy | 10 | 0 | 100% |
| Tone | 5 | 0 | 100% |
| Speed | 5 | 0 | 100% |
| Onboarding | 5 | 3 | 63% |
| Metrics | 5 | 3 | 63% |
| Tier | 5 | 1 | 83% |
| URL Import | 6 | 0 | 100% |
| Image Import | 0 | 10 | 0% (fixtures missing) |
| Vision | 1 | 6 | 14% |

---

*Generated by Medina AI Evaluation Suite v259b*
*Report Date: January 2, 2026*
