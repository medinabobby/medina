# AI Model Evaluation - Executive Summary

**Date:** January 1, 2026
**Models Tested:** gpt-4o-mini (baseline) vs gpt-4o
**Test Cases:** 40

---

## Key Findings

### Multi-Dimensional Scoring (v252)

| Metric | gpt-4o-mini | gpt-4o | Delta |
|--------|-------------------|---------------------|-------|
| **Tool Accuracy Rate** | 90% | 90% | 0.0% |
| **Intent Detection Rate** | 88% | 93% | +5.0% |
| **Combined Score** | 89% | 91% | +2.5% |

> **Tool Accuracy Rate**: % of tests where the right tool eventually executed (after multi-turn if needed)
> **Intent Detection Rate**: % of tests where AI correctly read the user's intent clarity (when to ask vs execute)

### Legacy Quality Metrics

| Metric | gpt-4o-mini | gpt-4o | Delta |
|--------|-------------------|---------------------|-------|
| Tool Calling Accuracy | 95% | 85% | -10.0% |
| Fitness Accuracy Score | 76% | 80% | +4.0% |
| Tone Score | 72% | 64% | -8.0% |
| Speed Pass Rate | 60% | 100% | +40.0% |
| Avg Response Time | 3434ms | 2455ms | -978.70ms |
| Avg Cost per Request | $0.001143 | $0.0198 | +0.02 |

### Latency by Category (v251)

| Category | gpt-4o-mini | gpt-4o | Improvement |
|----------|-------------------|---------------------|-------------|
| Basic Queries (27 tests) | 3147ms avg | 2306ms avg | 27% faster |
| Tool Calls (13 tests) | 4028ms avg | 2765ms avg | 31% faster |
| Basic Outliers (>3000ms) | 16 | 7 | 9 fewer |
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
| gpt-4o-mini | $34 | $411 |
| gpt-4o | $593 | $7112 |
| **Difference** | +$558/mo | +$6700/yr |

---

## Side-by-Side Examples

### TC01: "Create a 45-minute push workout for tomorrow"

| | gpt-4o-mini | gpt-4o |
|-|-------------------|---------------------|
| Tool Called | create_workout ✅ | create_workout ✅ |
| Response Time | 8930ms | 4838ms |
| LLM Overall Score | N/A/5 | N/A/5 |

**gpt-4o-mini Response:** ### Push Workout for Tomorrow

**Date:** Friday, January 2  
**Duration:** ~45 minutes  
**Exercises:** 5  

#### Exercises:
1. **Bench Press** - 3 se...



**gpt-4o Response:** Your 45-minute push workout for tomorrow has been created! Here's the plan:

**Date:** Friday, January 2

**Exercises:**
1. Barbell Bench Press
2. Dum...



### TC02: "Show my schedule for this week"

| | gpt-4o-mini | gpt-4o |
|-|-------------------|---------------------|
| Tool Called | show_schedule ✅ | show_schedule ✅ |
| Response Time | 4092ms | 2487ms |
| LLM Overall Score | N/A/5 | N/A/5 |

**gpt-4o-mini Response:** Here's your schedule for this week:

### Thursday, Jan 1:
- **Push Day**
- **45-Minute Push Workout**
- **Quick Full Body Blast**

### Friday, Jan 2:
...



**gpt-4o Response:** Here's your schedule for this week:

**Thursday (Jan 1):**
- Push Day
- 45-Minute Push Workout
- Quick Full Body Blast

**Friday (Jan 2):**
- Push Wor...



### TC04: "Skip today's workout"

| | gpt-4o-mini | gpt-4o |
|-|-------------------|---------------------|
| Tool Called | skip_workout ✅ | none ❌ |
| Response Time | 3770ms | 2830ms |
| LLM Overall Score | N/A/5 | N/A/5 |

**gpt-4o-mini Response:** It looks like I can't officially skip a workout for you. However, it's perfectly okay to take a break when you need it! Listen to your body and rest i...



**gpt-4o Response:** I need to know which workout you'd like to skip. Can you help me with the workout ID or some details about which one you mean?...



---

## Recommendation

**⏸️ KEEP CURRENT**

### Rationale
- No significant quality improvement detected
- Tool accuracy: -10.0%, Fitness accuracy: +4.0%

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
| TC04 | Skip today's workout... | skip_workout ✅ | none ❌ |
| TC05 | Create a 12-week strength program... | none ✅ | none ✅ |
| TC06 | Add bench press to my library... | add_to_library ✅ | add_to_library ✅ |
| TC07 | I'm 30 years old and weigh 180 lbs... | none ✅ | none ✅ |
| TC08 | Swap the barbell row for something else... | get_substitution_options ✅ | none ❌ |
| TC09 | What's the difference between strength a... | none ✅ | none ✅ |
| TC10 | I want to train 4 days per week... | none ✅ | none ✅ |
| TC11 | Update my profile to train 4 days per we... | update_profile ✅ | update_profile ✅ |
| TC12 | Save my schedule preference as Monday, W... | update_profile ✅ | update_profile ✅ |
| PL01 | Delete my current plan... | none ✅ | none ✅ |
| PL02 | Activate the strength plan... | none ✅ | none ✅ |
| SY01 | Create a 12-week program for muscle gain... | none ✅ | none ✅ |
| SY02 | Show my routine for this week... | show_schedule ✅ | show_schedule ✅ |
| ED01 | Update my profile... | none ✅ | none ✅ |
| ED02 | Create a workout... | none ❌ | none ❌ |
| ED03 | I want to go from 2 to 7 days per week... | none ✅ | none ✅ |
| ED04 | Remove bench press from my library... | remove_from_library ✅ | remove_from_library ✅ |

### Fitness Accuracy Tests (10 tests)

| Test ID | Prompt | gpt-4o-mini | gpt-4o |
|---------|--------|-------------------|---------------------|
| FA01 | What muscles does the Romanian deadlift ... | 100% | 100% |
| FA02 | How should I breathe during a bench pres... | 80% | 80% |
| FA03 | What rep range builds the most muscle?... | 75% | 100% |
| FA04 | How long should I rest between heavy com... | 100% | 83% |
| FA05 | Should I lift through lower back pain?... | 40% | 60% |
| FA06 | What's progressive overload?... | 60% | 60% |
| FA07 | Push pull legs vs upper lower split - wh... | 100% | 100% |
| FA08 | How much protein do I need per day?... | 86% | 57% |
| FA09 | Is it bad to train the same muscle two d... | 60% | 100% |
| FA10 | Can I build muscle in a calorie deficit?... | 60% | 60% |

---

*Generated by Medina AI Evaluation Suite v252*
