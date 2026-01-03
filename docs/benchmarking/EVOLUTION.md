# Benchmarking Evolution: v246 → v264

**Created:** January 2, 2026

## Timeline Summary

| Version | Date | Tests | Key Changes |
|---------|------|-------|-------------|
| v246 | Dec 31 | 30 | Initial framework - 4 categories |
| v247 | Jan 1 | 40 | Intent detection, tool_executed event |
| v251 | Jan 1 | 40 | Latency categories, model comparison |
| v253 | Jan 1 | 85 | Vision, URL import, onboarding, tiers |
| v259b | Jan 2 | 92 | Vision flow fix, protocol accuracy |
| v263 | Jan 2 | 92 | Cleanup, split type field added |
| v264 | Jan 2 | 92 | **Framework redesign** - flexible pass logic, regression tracking |

---

## Test Suite Growth

### v246: Foundation (30 tests)
```
Tool Calling (10)    ████████████████████████████████████████  33%
Fitness Accuracy (10) ████████████████████████████████████████  33%
Tone (5)             ████████████████████  17%
Speed (5)            ████████████████████  17%
```

### v253: Expansion (85 tests)
```
Tool Calling (29)    ██████████████████████████████████  34%
Fitness Accuracy (10) ████████████  12%
Tone (5)             ██████  6%
Speed (5)            ██████  6%
Onboarding (8)       ██████████  9%
Tier Selection (6)   ████████  7%
URL Import (6)       ████████  7%
Vision Import (10)   ████████████  12%
Vision Intent (7)    ████████  8%
```

### v259b: Current (92 tests)
```
Tool Calling (29)    ████████████████████████████████  32%
Fitness Accuracy (10) ██████████  11%
Tone (5)             ██████  5%
Speed (5)            ██████  5%
Onboarding (8)       ████████  9%
Tier Selection (6)   ██████  7%
URL Import (6)       ██████  7%
Vision Import (10)   ██████████  11%
Vision Intent (7)    ████████  8%
Protocol Accuracy (6) ██████  7%
```

---

## Metrics Evolution

| Version | Metrics Added |
|---------|---------------|
| v246 | Tool score, accuracy score, tone score, LLM-as-judge |
| v247 | Intent detection, multi-turn, tool_executed SSE tracking |
| v251 | Latency categories (basic/tool/vision), per-category timing |
| v252 | Combined score (tool accuracy + intent detection) |
| v253 | Extraction scoring for vision/URL tests |
| v259b | Protocol parameter validation, exercise ID matching |
| v263 | expectedSplitType field (deferred implementation) |
| v264 | **Flexible pass logic**, regression tracking, edge case flags |

---

## v264 Framework Redesign

### Problem Statement
- Regression undetected: Tool accuracy dropped 90% → 60% without alerts
- Overly strict tests: `expectedTool: null` failed reasonable behaviors
- No partial runs: Must run all 92 tests to check one category

### New Features

**1. Flexible Pass Criteria**
```typescript
// Before (too strict)
expectedTool: null  // FAIL if any tool called

// After (realistic)
expectedTool: null,
acceptableTools: ['show_schedule', 'get_summary'],  // Also valid
unacceptableTools: ['delete_plan'],  // These would be wrong
```

**2. Category Filtering**
```bash
npm run eval:run -- --category tool_calling    # Run one category
npm run eval:run -- --exclude vision           # Skip category
npm run eval:run -- --test TC01 --test TC02    # Specific tests
```

**3. Regression Tracking**
```bash
npm run eval:run regression --current v264.json --baseline v252.json
# Alerts on >10% drop from previous (warning)
# Alerts on >20% drop from baseline (critical)
```

**4. Edge Case Flags**
Tests marked `edgeCase: true` are highlighted in reports for human review.
- TC07: "I'm 30 years old..." - preference vs command
- OB08: "Legs" - ambiguous single word
- PL01: "Delete my current plan" - which delete tool?

### Baseline
**v252** is the baseline for regression tracking (first comprehensive test suite).

---

## Model Comparison Results

### Quality Parity Finding

| Version | gpt-4o-mini | gpt-4o | Winner |
|---------|-------------|--------|--------|
| v252 (40 tests) | 89% combined | 91% combined | 4o (+2%) |
| v252b (40 tests) | 91% combined | 94% combined | 4o (+3%) |
| v259b (92 tests) | 71% combined | 71% combined | **TIE** |

**Key Insight:** As test suite expanded to include harder cases (vision, protocol), models converged to equivalent quality.

### Cost Comparison

| Version | mini $/month | 4o $/month | Savings |
|---------|--------------|------------|---------|
| v252 | $34 | $593 | $559 (17x) |
| v252b | $35 | $537 | $502 (15x) |
| v259b | $60 | $480 | $420 (8x) |

*Based on 1,000 requests/day*

### Latency (gpt-4o advantage)

| Category | v252 | v259b |
|----------|------|-------|
| Basic queries | 27% faster | 34% faster |
| Tool calls | 31% faster | 19% faster |
| Vision | N/A | 16% faster |

---

## Key Learnings

### What Works
- **Tool calling:** Both models ≥65% accuracy on standard tools
- **Extraction:** Vision API extracts exercises correctly
- **Intent detection:** gpt-4o-mini slightly better (+5%)

### Known Gaps
- **Vision → Action:** AI extracts data but doesn't know what tool to call
- **Split type recognition:** Only 5 hardcoded splits, no fuzzy matching
- **Protocol passing:** New tests (PROT01-06) added to track this

### Recommendation
**Use gpt-4o-mini as default** - equivalent quality, 8x cheaper, better for vision intent

---

## Infrastructure

### Files
- `evaluation/testSuite.ts` - 92 test cases with flexible pass criteria
- `evaluation/runner.ts` - SSE parsing, multi-turn, LLM judge
- `evaluation/cli.ts` - CLI with category filtering
- `evaluation/memo.ts` - Report generation
- `evaluation/regression.ts` - v264: Regression tracking against v252 baseline
- `evaluation/fixtures/` - Test images and CSVs

### Running Evals
```bash
# Full evaluation
npm run eval:run -- --model gpt-4o-mini --endpoint <url>
npm run eval:run -- --model gpt-4o --endpoint <url>

# Category-specific
npm run eval:run -- --model gpt-4o-mini --category tool_calling

# Regression check
npm run eval:run regression --current results-v264.json --baseline results-v252.json

# Generate memo
npm run eval:memo --baseline results-mini.json --comparison results-4o.json
```

---

## Historical Reports

Archived in `docs/eval-archive/`:
1. EVAL_v252_REPORT.md - First baseline
2. EVAL_v252_MODEL_COMPARISON.md - Initial model comparison
3. EVAL_v252b_MODEL_COMPARISON.md - Refined scoring
4. EVAL_v259_VISION_IMPORT.md - Vision expansion (broken flow)
5. EVAL_v259b_MODEL_COMPARISON.md - Vision flow fixed
