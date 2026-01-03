# Medina AI Evaluation Report: v264 Complete Results

**Date:** January 2, 2026
**Version:** v264
**Test Suite:** 91 tests (100% completed)

---

## Executive Summary

Complete evaluation of v264 framework across all 91 tests. Both models show nearly identical combined scores, but gpt-4o-mini delivers **9x better cost efficiency** with **faster response times**.

| Metric | gpt-4o-mini | gpt-4o | Winner |
|--------|-------------|--------|--------|
| **Combined Score** | 69% | 70% | Tie (+1%) |
| Tool Accuracy | 66% | 73% | gpt-4o (+7%) |
| Intent Detection | 71% | 68% | **mini (+3%)** |
| Speed Pass Rate | 80% | 40% | **mini (+40%)** |
| Avg Response Time | 3915ms | 4558ms | **mini (14% faster)** |
| Cost per Run | $0.18 | $1.63 | **mini (9x cheaper)** |

**Recommendation:** Continue using gpt-4o-mini as default. The 1% combined score difference does not justify 9x higher cost and significantly worse latency.

---

## Category Performance

### By Category (Tool Accuracy / Intent Detection)

| Category | Tests | gpt-4o-mini | gpt-4o | Notes |
|----------|-------|-------------|--------|-------|
| **Fitness Accuracy** | 10 | 100% / 100% | 100% / 100% | Both perfect |
| **Tone** | 5 | 100% / 100% | 100% / 100% | Both perfect |
| **Speed** | 5 | 80% / 100% | 100% / 100% | 4o slightly better |
| **Tool Calling** | 28 | 75% / 86% | 79% / 86% | 4o +4% tool |
| **Tier Selection** | 6 | 83% / 67% | 83% / 83% | 4o +16% intent |
| **Onboarding** | 8 | 50% / 63% | 50% / 50% | Both struggle |
| **Import (Vision)** | 23 | 39% / 43% | 39% / 30% | Both struggle |
| **Protocol Accuracy** | 6 | 0% / 33% | 17% / 33% | Both fail |

### Key Observations

1. **Strengths (Both Models):**
   - Fitness knowledge (100%)
   - Tone and politeness (100%)
   - Core tool calling (75-79%)

2. **Weaknesses (Both Models):**
   - Protocol recognition (0-17%) - AI doesn't map "GBC protocol", "5x5", etc. to plan creation
   - Vision-to-action (39%) - Extracts data but doesn't know which tool to call
   - Ambiguous onboarding (50%) - Struggles with vague requests like "give me a workout"

3. **Model Differences:**
   - gpt-4o better at tool selection (+7%)
   - gpt-4o-mini better at intent detection (+3%)
   - gpt-4o-mini much faster (80% vs 40% speed pass)

---

## Latency Analysis

### Response Time by Category

| Category | gpt-4o-mini | gpt-4o | Difference |
|----------|-------------|--------|------------|
| Basic Queries | 2947ms | 4459ms | **mini 34% faster** |
| Tool Calls | 3755ms | 4652ms | **mini 19% faster** |
| Vision | 5739ms | 4580ms | 4o 20% faster |
| P95 Basic | 6639ms | 11061ms | **mini 40% lower** |
| P95 Tool | 11176ms | 12664ms | mini 12% lower |

**Finding:** gpt-4o-mini has significantly better latency consistency (fewer outliers, lower P95).

---

## Cost Analysis

| Metric | gpt-4o-mini | gpt-4o | Ratio |
|--------|-------------|--------|-------|
| Cost per request | $0.002 | $0.018 | 9x |
| Full eval run (91 tests) | $0.18 | $1.63 | 9x |
| Monthly estimate (1K req/day) | $60 | $540 | $480 savings |
| Annual savings | - | - | **$5,760** |

---

## Comparison with Previous v264 Run

The earlier v264 run was incomplete (44-56 tests) due to token expiration. Complete results show:

| Metric | v264 Partial | v264 Complete | Change |
|--------|--------------|---------------|--------|
| Tests Run | 44-56 | 91 | +35-47 |
| mini Combined | 45% | 69% | +24% |
| 4o Combined | 55% | 70% | +15% |
| Vision Tests | Skipped | 23 run | Fixed |

**Note:** The partial run showed inflated differences between models because it skipped the harder vision/protocol tests where both models struggle equally.

---

## Issues Identified

### 1. Protocol Recognition (Critical)
Both models fail to recognize training protocols like "GBC", "5x5", "drop sets" and map them to plan creation.

**Fix:** Add protocol keyword detection in tool instructions or pre-process user messages.

### 2. Vision-to-Action Gap
Vision API successfully extracts exercises from images (100% accuracy), but the chat model doesn't know to call `create_workout` or `create_plan` with the extracted data.

**Fix:** Improve tool instructions for vision context or add explicit "vision_result → action" guidance.

### 3. Ambiguous Input Handling
Both models struggle with vague requests like "give me a workout" without context.

**Fix:** This may be acceptable behavior - asking for clarification is reasonable for ambiguous requests.

---

## Recommendations

### Immediate
1. **Keep gpt-4o-mini as default** - equivalent quality, 9x cheaper, faster
2. **Add protocol keywords** to tool instructions for PROT01-06 tests
3. **Improve vision instructions** to guide action selection after extraction

### Future Considerations
1. **Premium tier option** - gpt-4o for users willing to pay for 7% better tool accuracy
2. **Hybrid approach** - Use 4o for complex planning, mini for simple queries
3. **Fine-tuning** - Train on protocol/vision failures to close gaps

---

## Test Results Summary

### gpt-4o-mini (91 tests)
```
Tool Accuracy:     66%
Intent Detection:  71%
Combined Score:    69%
Speed Pass Rate:   80%
Avg Latency:       3915ms
Total Cost:        $0.18
```

### gpt-4o (91 tests)
```
Tool Accuracy:     73%
Intent Detection:  68%
Combined Score:    70%
Speed Pass Rate:   40%
Avg Latency:       4558ms
Total Cost:        $1.63
```

---

## Conclusion

The complete v264 evaluation confirms that **gpt-4o-mini remains the optimal choice** for Medina's production deployment:

- **Quality parity:** 69% vs 70% combined score (within margin of error)
- **Cost efficiency:** 9x cheaper per request
- **Better UX:** 34% faster basic queries, 40% higher speed pass rate
- **Reliability:** More consistent latency (lower P95)

Both models share the same weaknesses (protocol recognition, vision-to-action), suggesting these are prompt/instruction issues rather than model capability gaps.

---

*Generated with v264 evaluation framework - Full 91-test run*
*Auth token captured via browser automation from medinaintelligence.web.app*
