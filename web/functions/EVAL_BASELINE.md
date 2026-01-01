# AI Performance Baseline Report

**Date:** January 1, 2026
**Model:** gpt-4o-mini
**Test Suite:** v247 (40 tests)
**Endpoint:** Firebase Functions `/chat`

---

## Executive Summary

| Metric | Score | Target |
|--------|-------|--------|
| Tool Calling Accuracy | **90%** (18/20) | 95% |
| Fitness Accuracy | **70.5%** | 80% |
| Tone Score | **80%** | 85% |
| Speed Pass Rate | **60%** (3/5) | 80% |
| Avg Response Time | **3,666ms** | <3,000ms |
| Avg Time to First Token | **515ms** | <500ms |
| Cost per Request | **$0.00117** | - |

---

## Test Breakdown by Category

### Tool Calling (20 tests) - 90% accuracy

| Status | Count | Tests |
|--------|-------|-------|
| PASS | 18 | TC01-TC11, PL01-PL02, SY01-SY02, ED01, ED03-ED04 |
| FAIL | 2 | TC12, ED02 |

**Failing Tests:**
| Test | Prompt | Expected | Actual | Issue |
|------|--------|----------|--------|-------|
| TC12 | "Save my schedule preference as Monday, Wednesday, Friday" | `update_profile` | none | AI asked confirmation instead of executing |
| ED02 | "Create a workout" | `create_workout` | none | AI asked for clarification instead of using defaults |

### Fitness Accuracy (10 tests) - 70.5% topic coverage

All tests passed tool check (correctly no tool called), but topic coverage varies:

| Test | Score | Missing Topics |
|------|-------|----------------|
| FA01 | 75% | Some posterior chain terms |
| FA02 | 80% | Bracing technique |
| FA03 | 100% | - |
| FA04 | 60% | Specific minute ranges |
| FA05 | 100% | - |
| FA06 | 80% | Volume concept |
| FA07 | 60% | Frequency trade-offs |
| FA08 | 50% | Specific gram ranges |
| FA09 | 80% | 48-hour specifics |
| FA10 | 60% | Recomp concept |

### Tone (5 tests) - 80% topic coverage

All pass - AI maintains encouraging, supportive tone.

### Speed (5 tests) - 60% pass rate

| Test | Prompt | Time | Threshold | Status |
|------|--------|------|-----------|--------|
| SP01 | "Hi" | 1,453ms | 2,000ms | PASS |
| SP02 | "Show my schedule" | 4,682ms | 3,000ms | **FAIL** |
| SP03 | "What day is leg day?" | 4,060ms | 2,500ms | **FAIL** |
| SP04 | "Create a quick 30 min workout" | 2,578ms | 5,000ms | PASS |
| SP05 | "Thanks!" | 1,438ms | 2,000ms | PASS |

---

## Response Time Analysis (Slowest to Fastest)

### Slowest 10 Tests

| Rank | Test | Category | Time | Prompt |
|------|------|----------|------|--------|
| 1 | TC09 | tool_calling | **12,106ms** | "What's the difference between strength and hypertrophy?" |
| 2 | TC01 | tool_calling | 7,740ms | "Create a 45-minute push workout for tomorrow" |
| 3 | SY02 | tool_calling | 6,655ms | "Show my routine for this week" |
| 4 | FA07 | fitness_accuracy | 6,409ms | "Push pull legs vs upper lower split - which is better?" |
| 5 | TC02 | tool_calling | 5,106ms | "Show my schedule for this week" |
| 6 | TC08 | tool_calling | 4,864ms | "Swap the barbell row for something else" |
| 7 | FA10 | fitness_accuracy | 4,834ms | "Can I build muscle in a calorie deficit?" |
| 8 | TN01 | tone | 4,711ms | "I'm struggling to stay motivated" |
| 9 | SP02 | speed | 4,682ms | "Show my schedule" |
| 10 | TN04 | tone | 4,676ms | "Explain deload weeks" |

### Fastest 10 Tests

| Rank | Test | Category | Time | Prompt |
|------|------|----------|------|--------|
| 1 | SP05 | speed | **1,438ms** | "Thanks!" |
| 2 | SP01 | speed | 1,453ms | "Hi" |
| 3 | TC05 | tool_calling | 1,647ms | "Create a 12-week strength program" |
| 4 | ED01 | tool_calling | 1,660ms | "Update my profile" |
| 5 | TC07 | tool_calling | 1,740ms | "I'm 30 years old and weigh 180 lbs" |
| 6 | PL02 | tool_calling | 1,760ms | "Activate the strength plan" |
| 7 | TC10 | tool_calling | 1,792ms | "I want to train 4 days per week" |
| 8 | TN03 | tone | 2,012ms | "What stocks should I buy?" |
| 9 | ED03 | tool_calling | 2,030ms | "I want to go from 2 to 7 days per week" |
| 10 | TN02 | tone | 2,050ms | "I missed 3 workouts this week" |

---

## Performance Patterns

### What's Fast (< 2s)
- Simple greetings/acknowledgments ("Hi", "Thanks")
- Requests that trigger confirmation prompts (no tool execution)
- Off-topic redirects

### What's Slow (> 4s)
- **Tool executions** - especially `show_schedule`, `create_workout`
- **Complex explanations** - strength vs hypertrophy, PPL vs upper/lower
- **Motivational responses** - requires more thoughtful, longer text

### Key Insight
The slowest tests involve **actual tool execution** (show_schedule: 5-6s, create_workout: 7-8s). The AI response itself is fast (~500ms to first token), but waiting for Firestore operations adds latency.

---

## Priority Improvements

### P0: Speed Optimization
1. **show_schedule** - 4-6 seconds. Consider caching or pre-fetching schedule data.
2. **create_workout** - 7-8 seconds. Optimize Firestore writes and exercise selection.

### P1: Tool Calling Fixes
1. **TC12** - "Save my schedule preference..." should immediately call `update_profile`
2. **ED02** - "Create a workout" should use profile defaults, not ask questions

### P2: Fitness Accuracy
1. Add specific numeric ranges to responses (grams of protein, rest minutes)
2. Ensure all posterior chain muscles mentioned for RDL
3. Explain recomp concept for calorie deficit question

---

## Cost Analysis

| Metric | Value |
|--------|-------|
| Total Input Tokens | 296,405 |
| Total Output Tokens | 3,794 |
| Total Cost (40 tests) | $0.0467 |
| Avg Cost per Request | $0.00117 |
| Estimated Monthly (1000 req/day) | $35.10 |

---

## Next Steps

1. **Run comparative baseline** with gpt-4o to compare quality vs cost
2. **Optimize tool execution latency** - profile Firestore operations
3. **Fix TC12/ED02** - adjust prompt to handle explicit save commands
4. **Adjust speed thresholds** - current thresholds may be too aggressive for tool-calling tests

---

## Appendix: Test Suite Reference

```
40 tests total:
├── tool_calling (20)
│   ├── TC01-TC12: Core tool tests
│   ├── PL01-PL02: Plan management
│   ├── SY01-SY02: Synonym handling
│   └── ED01-ED04: Edge cases
├── fitness_accuracy (10)
│   └── FA01-FA10: Knowledge questions
├── tone (5)
│   └── TN01-TN05: Coaching style
└── speed (5)
    └── SP01-SP05: Response time
```
