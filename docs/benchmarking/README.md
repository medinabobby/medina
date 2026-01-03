# Medina Evaluation Framework

## Overview

This framework tests AI behavior across 90+ test cases covering tool calling, intent classification, fitness domain knowledge, and response quality.

## Running Evaluations

```bash
cd web/functions

# Get fresh auth token (expires in ~1 hour)
# 1. Open https://medinaintelligence.web.app/app
# 2. Open DevTools → Network tab
# 3. Send any chat message
# 4. Copy Authorization header from /chat request

# Run eval
npm run eval -- run \
  --model gpt-4o-mini \
  --endpoint https://us-central1-medinaintelligence.cloudfunctions.net/chat \
  --token "YOUR_TOKEN" \
  --concurrency 5 \
  --output docs/benchmarking/results/vXXX/results-vXXX.json

# Generate memo
npm run eval -- memo --input results.json > docs/benchmarking/memos/vXXX/EVAL_vXXX_MEMO.md
```

## Folder Structure

```
benchmarking/
├── README.md           # This file
├── EVOLUTION.md        # Framework history (v246→v268)
├── memos/              # Evaluation memos by version
│   ├── v264/
│   ├── v265/
│   ├── v266/
│   ├── v267/
│   └── v268/
└── results/            # Raw JSON results by version
    ├── v265/
    ├── v266/
    ├── v267/
    └── v268/
```

## Test Categories

| Category | Tests | Description |
|----------|-------|-------------|
| Tool Calling (TC) | 12 | Correct tool selection |
| Fitness Accuracy (FA) | 10 | Domain knowledge |
| Tone (TN) | 5 | Appropriate responses |
| Social/Polish (SP) | 5 | Greetings, thanks |
| Plan Lifecycle (PL) | 2 | Plan CRUD operations |
| Onboarding (OB) | 8 | New user flows |
| Vision Import (VIS) | 7 | Image processing |
| URL Import (URL) | 6 | Link handling |
| Protocol (PROT) | 6 | Training protocols |
| Workout Quality (WQ) | 10 | Workout creation |

## Tier Classification

- **Tier 1 (Core)**: 42 tests - MUST pass 100%
- **Tier 2 (Interpretation)**: ~45 tests - Reasonable interpretation
- **Tier 3 (Ambiguous)**: ~4 tests - Edge cases

## Key Metrics

| Metric | Target | Description |
|--------|--------|-------------|
| Tier 1 Pass Rate | 100% | Core functionality |
| Tool Accuracy | >85% | Correct tool calls |
| Intent Detection | >90% | Exec vs ask decisions |
| Response Time | <5000ms | Avg latency |

---

## Memo Template

When creating evaluation memos, use this structure:

```markdown
# EVAL_vXXX - [Brief Title]

## Summary

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Tier 1 | X/42 | X/42 | +/- X% |
| Response Time | Xms | Xms | +/- X% |
| Cost | $X.XX | $X.XX | +/- X% |

## Changes Made

- [List of changes]

## Test Results

[Detailed breakdown]

## Key Learnings

- [What worked]
- [What didn't work]
- [Recommendations]
```

---

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| v268 | 2026-01-03 | Prompt optimization (-18% latency) |
| v267 | 2026-01-03 | Stakes-based UX, parallel tests |
| v266 | 2026-01-03 | Multi-turn credit, output quality |
| v265 | 2026-01-03 | Intent classification |
| v264 | 2026-01-02 | Tier-based metrics |

See [EVOLUTION.md](./EVOLUTION.md) for detailed framework history.
