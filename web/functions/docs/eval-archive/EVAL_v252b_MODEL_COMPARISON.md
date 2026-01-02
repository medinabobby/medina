# AI Model Evaluation - Executive Summary

**Date:** January 1, 2026
**Models Tested:** gpt-4o-mini (baseline) vs gpt-4o
**Test Cases:** 40

---

## Key Findings

### Multi-Dimensional Scoring (v252)

| Metric | gpt-4o-mini | gpt-4o | Delta |
|--------|-------------------|---------------------|-------|
| **Tool Accuracy Rate** | 90% | 95% | +5.0% |
| **Intent Detection Rate** | 93% | 93% | 0.0% |
| **Combined Score** | 91% | 94% | +2.5% |

> **Tool Accuracy Rate**: % of tests where the right tool eventually executed (after multi-turn if needed)
> **Intent Detection Rate**: % of tests where AI correctly read the user's intent clarity (when to ask vs execute)

### Legacy Quality Metrics

| Metric | gpt-4o-mini | gpt-4o | Delta |
|--------|-------------------|---------------------|-------|
| Tool Calling Accuracy | 90% | 90% | 0.0% |
| Fitness Accuracy Score | 79% | 80% | +0.7% |
| Tone Score | 76% | 64% | -12.0% |
| Speed Pass Rate | 40% | 100% | +60.0% |
| Avg Response Time | 3345ms | 3004ms | -340.50ms |
| Avg Cost per Request | $0.001181 | $0.0179 | +0.02 |

### Latency by Category (v251)

| Category | gpt-4o-mini | gpt-4o | Improvement |
|----------|-------------------|---------------------|-------------|
| Basic Queries (27 tests) | 3106ms avg | 2918ms avg | 6% faster |
| Tool Calls (13 tests) | 3842ms avg | 3183ms avg | 17% faster |
| Basic Outliers (>3000ms) | 14 | 10 | 4 fewer |
| Tool Call Outliers (>10000ms) | 0 | 0 | 0 fewer |

### LLM-as-Judge Scores (1-5 scale)

| Dimension | gpt-4o-mini | gpt-4o | Delta |
|-----------|-------------------|---------------------|-------|
| Tool Appropriateness | 0.0 | 0.0 | 0.00 |
| Fitness Accuracy | 0.0 | 0.0 | 0.00 |
| Tone & Style | 0.0 | 0.0 | 0.00 |
| **Overall** | **0.0** | **0.0** | **0.00** |

---

## Cost Projection (1,000 requests/day)

| Model | Monthly Cost | Annual Cost |
|-------|--------------|-------------|
| gpt-4o-mini | $35 | $425 |
| gpt-4o | $536 | $6436 |
| **Difference** | +$501/mo | +$6011/yr |

---

## Side-by-Side Examples

### TC01: "Create a 45-minute push workout for tomorrow"

| | gpt-4o-mini | gpt-4o |
|-|-------------------|---------------------|
| Tool Called | create_workout ✅ | create_workout ✅ |
| Response Time | 8824ms | 5405ms |
| LLM Overall Score | N/A/5 | N/A/5 |

**gpt-4o-mini Response:** ### Push Workout for Tomorrow

**Date**: January 2  
**Duration**: ~45 minutes  
**Focus**: Chest, Shoulders, Triceps  
**Exercises**: 5

#### Workout...



**gpt-4o Response:** Your 45-minute push workout for tomorrow has been created. Here’s what you’ll be doing:

**Date:** Saturday, January 3  
**Exercises:** 4  
**Duration...



### TC02: "Show my schedule for this week"

| | gpt-4o-mini | gpt-4o |
|-|-------------------|---------------------|
| Tool Called | show_schedule ✅ | show_schedule ✅ |
| Response Time | 3988ms | 2470ms |
| LLM Overall Score | N/A/5 | N/A/5 |

**gpt-4o-mini Response:** Here's your schedule for this week:

### Thursday (Jan 1)
- Push Day
- 45-Minute Push Workout
- Quick Full Body Blast
- Quick 30 Min Full Body

### Fr...



**gpt-4o Response:** Here's your schedule for this week:

**Friday (Jan 2):**
- Push Workout (repeated 9 times)
- Push Day
- 45-Minute Push Workout

**Saturday (Jan 3):**
...



### TC04: "Skip today's workout"

| | gpt-4o-mini | gpt-4o |
|-|-------------------|---------------------|
| Tool Called | skip_workout ✅ | skip_workout ✅ |
| Response Time | 3783ms | 2347ms |
| LLM Overall Score | N/A/5 | N/A/5 |

**gpt-4o-mini Response:** It seems there might have been a mix-up with the workout details. If you want to skip today’s workout, you can simply take a rest day or adjust your s...



**gpt-4o Response:** It seems there was an error skipping the workout. Would you like help rescheduling or setting a reminder instead?...



---

## Recommendation

**⏸️ KEEP CURRENT**

### Rationale
- No significant quality improvement detected
- Tool accuracy: 0.0%, Fitness accuracy: +0.7%

### Next Steps
1. Keep current model (gpt-4o-mini)
2. Focus on prompt improvements
3. Consider testing alternative models (Claude, Grok)

---

## Detailed Results

### Tool Calling Tests (20 tests)

| Test ID | Prompt | gpt-4o-mini | gpt-4o |
|---------|--------|-------------------|---------------------|
| TC01 | Create a 45-minute push workout for tomo... | create_workout ✅ | create_workout ✅ |
| TC02 | Show my schedule for this week... | show_schedule ✅ | show_schedule ✅ |
| TC03 | My bench press 1RM is 225 lbs... | update_exercise_target ✅ | update_exercise_target ✅ |
| TC04 | Skip today's workout... | skip_workout ✅ | skip_workout ✅ |
| TC05 | Create a 12-week strength program... | none ✅ | none ✅ |
| TC06 | Add bench press to my library... | add_to_library ✅ | add_to_library ✅ |
| TC07 | I'm 30 years old and weigh 180 lbs... | none ✅ | none ✅ |
| TC08 | Swap the barbell row for something else... | get_substitution_options ✅ | get_substitution_options ✅ |
| TC09 | What's the difference between strength a... | none ✅ | none ✅ |
| TC10 | I want to train 4 days per week... | none ✅ | none ✅ |
| TC11 | Update my profile to train 4 days per we... | none ❌ | update_profile ✅ |
| TC12 | Save my schedule preference as Monday, W... | update_profile ✅ | update_profile ✅ |
| PL01 | Delete my current plan... | none ✅ | none ✅ |
| PL02 | Activate the strength plan... | none ✅ | none ✅ |
| SY01 | Create a 12-week program for muscle gain... | none ✅ | none ✅ |
| SY02 | Show my routine for this week... | show_schedule ✅ | show_schedule ✅ |
| ED01 | Update my profile... | none ✅ | none ✅ |
| ED02 | Create a workout... | none ❌ | none ❌ |
| ED03 | I want to go from 2 to 7 days per week... | none ✅ | update_profile ❌ |
| ED04 | Remove bench press from my library... | remove_from_library ✅ | remove_from_library ✅ |

### Fitness Accuracy Tests (10 tests)

| Test ID | Prompt | gpt-4o-mini | gpt-4o |
|---------|--------|-------------------|---------------------|
| FA01 | What muscles does the Romanian deadlift ... | 100% | 75% |
| FA02 | How should I breathe during a bench pres... | 80% | 80% |
| FA03 | What rep range builds the most muscle?... | 75% | 75% |
| FA04 | How long should I rest between heavy com... | 100% | 83% |
| FA05 | Should I lift through lower back pain?... | 60% | 80% |
| FA06 | What's progressive overload?... | 80% | 80% |
| FA07 | Push pull legs vs upper lower split - wh... | 100% | 100% |
| FA08 | How much protein do I need per day?... | 57% | 86% |
| FA09 | Is it bad to train the same muscle two d... | 80% | 80% |
| FA10 | Can I build muscle in a calorie deficit?... | 60% | 60% |

---

*Generated by Medina AI Evaluation Suite v252*
