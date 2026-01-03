# Medina Intent Framework

Design philosophy for AI-user interaction patterns across all features.

## Core Philosophy

Medina uses a **stakes-based UX framework** that determines when the AI should act immediately vs. confirm first. The goal is to feel responsive for routine actions while being careful with significant commitments.

### The Stakes Principle

| Stakes Level | User Experience | Pattern |
|--------------|-----------------|---------|
| **LOW** | Fast, fluid | Execute → Offer adjustments |
| **MEDIUM** | Responsive, safe | Explicit command = Act; Statement = Ask |
| **HIGH** | Careful, confirming | Confirm params → Wait for OK → Execute |

### Why This Matters

- **Low stakes actions** (creating a single workout) should feel instant - don't make users answer 3 questions before getting started
- **High stakes actions** (multi-week plans, deletions) deserve confirmation to avoid regret
- **Medium stakes** distinguishes between commands ("update to 4 days") and statements ("I want 4 days")

---

## Pattern Matrix

### Workout Domain (Current)

| Action | Stakes | Pattern | Example |
|--------|--------|---------|---------|
| `create_workout` | LOW | Execute → Confirm | "Created your 45-min push workout! Want to adjust?" |
| `create_plan` | HIGH | Confirm → Execute | "I'll create 12-week plan, 4 days/week. Sound good?" |
| `update_profile` | MEDIUM | Command = Act | "Update to 4 days" → executes |
| `update_profile` | MEDIUM | Statement = Ask | "I want 4 days" → "Want me to save that?" |
| `delete_plan` | HIGH | Always confirm | "Are you sure you want to delete?" |
| `activate_plan` | HIGH | Always confirm | Multi-week commitment |
| `skip_workout` | LOW | Execute → Confirm | Reversible, single action |
| `add_to_library` | LOW | Execute immediately | Reversible, single action |
| `show_schedule` | NONE | Execute immediately | Read-only |

### Advisory Actions

Some user requests trigger advice before action:

| Trigger | Why | Response |
|---------|-----|----------|
| Going from 2→7 days/week | Overtraining risk | Advise gradual increase |
| "Gain 50lbs muscle in 3 months" | Unrealistic | Set realistic expectations |
| Training through injury | Safety | Recommend medical clearance |

---

## Extension Template

When adding new features (cardio, nutrition, etc.), follow this classification process:

### Step 1: Identify Action Type

Is this action:
- **Single-item** (one workout, one meal) → Likely LOW stakes
- **Multi-item/commitment** (plan, program) → Likely HIGH stakes
- **Reversible** (add to library, skip) → Lower stakes
- **Destructive** (delete, abandon) → HIGH stakes

### Step 2: Map to Existing Pattern

| New Feature | Similar To | Pattern |
|-------------|------------|---------|
| Create single cardio session | `create_workout` | LOW - Execute → Confirm |
| Create cardio program (8-week) | `create_plan` | HIGH - Confirm → Execute |
| Log single meal | `update_exercise_target` | LOW - Execute immediately |
| Create nutrition plan | `create_plan` | HIGH - Confirm → Execute |
| Update macros preference | `update_profile` | MEDIUM - Command vs Statement |

### Step 3: Define Smart Defaults

For LOW stakes actions, define sensible defaults:

```markdown
## Cardio Session Defaults
- Duration: profile.cardioPreference OR 30 min
- Type: User's most common OR "run"
- Date: Tomorrow

## Single Meal Defaults
- Timing: Next meal in sequence
- Portions: Profile-based
```

### Step 4: Add to Test Suite

Create tier-classified test cases:

```typescript
// Tier 1 (Core) - Must pass
{
  id: "CARDIO01",
  input: "Create a 30-minute run for tomorrow",
  expectedTool: "create_cardio",
  tier: 1
}

// Tier 2 (Interpretation) - Reasonable interpretation
{
  id: "CARDIO02",
  input: "I want to do some cardio",
  // Could ask type or use defaults
  tier: 2
}
```

---

## Learnings Log

Document lessons learned from optimization and testing.

### v268: WRONG EXAMPLES are Critical

**What happened:** Removed the "WRONG EXAMPLES" section from `coreRules.ts` to save tokens. Caused Tier 1 regression (98% instead of 100%).

**Why:** Negative examples help the model avoid incorrect patterns. The AI was confusing "Create upper body workout with 5x5" (should call `create_workout`) with schedule queries.

**Lesson:** Keep negative examples in prompts. They're worth the token cost.

### v267: Stakes-Based UX Success

**What happened:** Implemented LOW/HIGH stakes patterns for workouts vs plans.

**Result:**
- Workouts now created immediately (no 3-question interrogation)
- Plans still get confirmation (appropriate for multi-week commitment)
- User satisfaction improved

**Lesson:** Match confirmation friction to action significance.

---

## Implementation Checklist

When adding a new feature to the AI:

- [ ] Classify stakes level (LOW/MEDIUM/HIGH)
- [ ] Define smart defaults for LOW stakes
- [ ] Define confirmation params for HIGH stakes
- [ ] Add tool definition to `definitions.ts`
- [ ] Add instructions to `toolInstructions.ts`
- [ ] Add test cases to `testSuite.ts` with tier classification
- [ ] Run eval, verify Tier 1 = 100%
- [ ] Document in this file

---

## Related Files

| File | Purpose |
|------|---------|
| `web/functions/src/tools/definitions.ts` | Tool schemas |
| `web/functions/src/prompts/toolInstructions.ts` | Action instructions |
| `web/functions/src/prompts/coreRules.ts` | Behavioral rules |
| `web/functions/src/evaluation/testSuite.ts` | Test cases |
| `CLAUDE.md` | Developer context |
| `docs/benchmarking/` | Evaluation results |
