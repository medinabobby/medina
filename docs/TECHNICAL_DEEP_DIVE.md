# Medina Technical Deep Dive

**Last Updated:** December 30, 2025

Detailed technical documentation for each service layer component.

---

## 1. Calculate API - All 5 Algorithms

### Endpoint
```
POST /api/calculate
Authorization: Bearer <firebase_id_token>
```

### Algorithm 1: oneRM (Epley Formula)
Most accurate for 1-10 rep ranges.

```typescript
oneRM = weight × (1 + reps / 30)

// Example: 185 lbs × 5 reps
oneRM = 185 × (1 + 5/30) = 185 × 1.167 = 216 lbs
```

### Algorithm 2: weightForReps (Inverse Epley)
"What weight should I use for 8 reps?"

```typescript
weight = oneRM / (1 + targetReps / 30)

// Example: 1RM of 225, target 8 reps
weight = 225 / (1 + 8/30) = 225 / 1.267 = 178 lbs
```

### Algorithm 3: best1RM (Quality-Weighted Selection)
Selects best set from a workout, weighted by quality factors.

```typescript
interface SetData {
  weight: number;
  reps: number;
  setIndex: number;
}

function calculateBest1RM(sets: SetData[]): number {
  let bestScore = 0;
  let best1RM = 0;

  for (const set of sets) {
    const estimated1RM = set.weight * (1 + set.reps / 30);

    // Quality multipliers
    let quality = 1.0;

    // Fatigue factor (earlier sets are fresher)
    if (set.setIndex <= 2) quality *= 1.0;
    else if (set.setIndex <= 4) quality *= 0.95;
    else quality *= 0.90;

    // Rep range factor (moderate reps most accurate)
    if (set.reps > 12) quality *= 0.9;   // High rep penalty
    if (set.reps < 3) quality *= 0.95;   // Low rep penalty

    const score = estimated1RM * quality;

    if (score > bestScore) {
      bestScore = score;
      best1RM = estimated1RM;
    }
  }

  return Math.round(best1RM);
}
```

### Algorithm 4: recency1RM (Time-Decay Weighted Average)
Prevents stale PRs from dominating.

```typescript
interface SessionData {
  date: string;      // ISO date
  best1RM: number;
}

const HALF_LIFE_DAYS = 14;  // 2 weeks = 50% weight

function calculateRecency1RM(sessions: SessionData[]): number {
  const now = new Date();
  let weightedSum = 0;
  let totalWeight = 0;

  for (const session of sessions) {
    const sessionDate = new Date(session.date);
    const daysAgo = (now.getTime() - sessionDate.getTime()) / (1000 * 60 * 60 * 24);

    // Exponential decay: e^(-daysAgo × ln(2) / halfLife)
    const decay = Math.exp(-daysAgo * Math.log(2) / HALF_LIFE_DAYS);

    weightedSum += session.best1RM * decay;
    totalWeight += decay;
  }

  return Math.round(weightedSum / totalWeight);
}

// Example:
// Session 1: 3 days ago, 225 lbs → decay = 0.86
// Session 2: 10 days ago, 220 lbs → decay = 0.61
// Session 3: 21 days ago, 230 lbs → decay = 0.35
// Result: (225×0.86 + 220×0.61 + 230×0.35) / (0.86+0.61+0.35) = 223 lbs
```

### Algorithm 5: targetWeight (Intensity-Based Prescription)
Different logic for compound vs isolation exercises.

```typescript
interface TargetWeightParams {
  oneRM: number;
  exerciseType: 'compound' | 'isolation';
  baseIntensity: number;      // 0.0 - 1.0
  intensityOffset?: number;   // Fine-tuning
  rpe?: number;               // For isolation: 6-10
  workingWeight?: number;     // Fallback if no 1RM
}

function calculateTargetWeight(params: TargetWeightParams): number {
  const { oneRM, exerciseType, baseIntensity, intensityOffset = 0, rpe = 8 } = params;

  let target: number;

  if (exerciseType === 'compound') {
    // Compound: straight percentage of 1RM
    target = oneRM * baseIntensity * (1 + intensityOffset);
  } else {
    // Isolation: RPE-based positioning in working range
    const range = { min: 0.40, max: 0.70 };  // 40-70% of 1RM
    const rpePosition = (rpe - 6) / 4;       // RPE 6-10 → 0.0-1.0
    target = oneRM * (range.min + rpePosition * (range.max - range.min));
  }

  // Round to plate increments
  const increment = exerciseType === 'compound' ? 5 : 2.5;
  return Math.round(target / increment) * increment;
}
```

---

## 2. Import Pipeline - Full 4 Stages

### Endpoint
```
POST /api/import
Authorization: Bearer <firebase_id_token>
Content-Type: application/json

{
  "csvData": "<base64-encoded-csv>",
  "createHistoricalWorkouts": true,
  "userWeight": 180
}
```

### Stage 1: Parse

```typescript
interface ParsedSet {
  reps: number;
  weight: number;
  equipment?: string;
}

interface ParsedExercise {
  name: string;
  sets: ParsedSet[];
  estimated1RM?: number;
}

interface ParsedWorkout {
  workoutNumber: number;
  date: Date;
  exercises: ParsedExercise[];
}

// Format detection
function detectFormat(headers: string[]): 'strong' | 'hevy' | 'custom' {
  const headerStr = headers.join(',').toLowerCase();

  if (headerStr.includes('workout name') && headerStr.includes('set order')) {
    return 'strong';
  }
  if (headerStr.includes('duration') && headerStr.includes('exercise_title')) {
    return 'hevy';
  }
  return 'custom';
}

// Parse Strong format
function parseStrong(rows: string[][]): ParsedWorkout[] {
  // Strong columns: Date, Workout Name, Exercise Name, Set Order, Weight, Reps, ...
  const workouts = new Map<string, ParsedWorkout>();

  for (const row of rows) {
    const [date, workoutName, exerciseName, setOrder, weight, reps] = row;

    const key = `${date}-${workoutName}`;
    if (!workouts.has(key)) {
      workouts.set(key, {
        workoutNumber: workouts.size + 1,
        date: parseDate(date),
        exercises: []
      });
    }

    // Add set to exercise...
  }

  return Array.from(workouts.values());
}
```

### Stage 2: Match

```typescript
interface MatchResult {
  exerciseName: string;
  matchedExerciseId?: string;
  matchConfidence: number;
  matchMethod: 'exact' | 'fuzzy' | 'variant' | 'alias' | 'unmatched';
}

async function matchExercise(
  name: string,
  exerciseDb: Exercise[]
): Promise<MatchResult> {
  const normalized = name.toLowerCase().trim();

  // 1. Exact match
  const exact = exerciseDb.find(e =>
    e.name.toLowerCase() === normalized ||
    e.baseExercise?.toLowerCase() === normalized
  );
  if (exact) {
    return { exerciseName: name, matchedExerciseId: exact.id,
             matchConfidence: 1.0, matchMethod: 'exact' };
  }

  // 2. Alias lookup
  const aliasMap: Record<string, string> = {
    'skull crushers': 'lying_tricep_extension',
    'skullcrushers': 'lying_tricep_extension',
    'ez bar curl': 'barbell_curl',
    // ... 50+ aliases
  };
  if (aliasMap[normalized]) {
    return { exerciseName: name, matchedExerciseId: aliasMap[normalized],
             matchConfidence: 0.95, matchMethod: 'alias' };
  }

  // 3. Equipment prefix detection
  const equipmentPrefixes: Record<string, string> = {
    'db ': 'dumbbells',
    'bb ': 'barbell',
    'cable ': 'cable_machine',
    'machine ': 'machine'
  };
  for (const [prefix, equipment] of Object.entries(equipmentPrefixes)) {
    if (normalized.startsWith(prefix)) {
      const baseName = normalized.slice(prefix.length);
      const match = exerciseDb.find(e =>
        e.baseExercise?.toLowerCase().includes(baseName) &&
        e.equipment === equipment
      );
      if (match) {
        return { exerciseName: name, matchedExerciseId: match.id,
                 matchConfidence: 0.9, matchMethod: 'variant' };
      }
    }
  }

  // 4. Fuzzy match (Levenshtein distance)
  let bestMatch: Exercise | null = null;
  let bestDistance = Infinity;

  for (const exercise of exerciseDb) {
    const distance = levenshteinDistance(normalized, exercise.name.toLowerCase());
    if (distance < bestDistance && distance <= 3) {
      bestDistance = distance;
      bestMatch = exercise;
    }
  }

  if (bestMatch) {
    return { exerciseName: name, matchedExerciseId: bestMatch.id,
             matchConfidence: 0.7, matchMethod: 'fuzzy' };
  }

  // 5. Unmatched
  return { exerciseName: name, matchedExerciseId: undefined,
           matchConfidence: 0, matchMethod: 'unmatched' };
}
```

### Stage 3: Analyze (Intelligence)

```typescript
interface ImportIntelligence {
  inferredExperience: 'beginner' | 'intermediate' | 'advanced' | 'expert';
  trainingStyle: string;
  topMuscleGroups: MuscleGroup[];
  inferredSplit: string | null;
  estimatedSessionDuration: number;
  confidenceScore: number;
  indicators: ExperienceIndicators;
}

interface ExperienceIndicators {
  strengthScore: number;    // 0-100
  historyScore: number;     // 0-100
  volumeScore: number;      // 0-100
  varietyScore: number;     // 0-100
}

function analyzeTrainingData(
  workouts: ParsedWorkout[],
  userWeight?: number
): ImportIntelligence {

  // 1. Strength Score (relative to bodyweight)
  const strengthScore = calculateStrengthScore(workouts, userWeight);
  // - Bench 1RM / BW > 1.5 → advanced
  // - Squat 1RM / BW > 2.0 → advanced
  // - Deadlift 1RM / BW > 2.5 → advanced

  // 2. History Score (consistency)
  const historyScore = calculateHistoryScore(workouts);
  // - Sessions per week (3-5 = high)
  // - Total months of history
  // - Gap analysis (missed weeks)

  // 3. Volume Score (training volume)
  const volumeScore = calculateVolumeScore(workouts);
  // - Sets per session (15-25 = intermediate+)
  // - Exercises per session (5-8 = intermediate+)

  // 4. Variety Score (exercise diversity)
  const varietyScore = calculateVarietyScore(workouts);
  // - Unique exercises used
  // - Movement pattern coverage
  // - Equipment variety

  // Combine scores
  const combinedScore = (strengthScore + historyScore + volumeScore + varietyScore) / 4;

  const inferredExperience =
    combinedScore > 85 ? 'expert' :
    combinedScore > 60 ? 'advanced' :
    combinedScore > 30 ? 'intermediate' : 'beginner';

  // Detect training style
  const repRanges = analyzeRepRanges(workouts);
  const trainingStyle =
    repRanges.avgReps > 10 ? 'hypertrophy-focused' :
    repRanges.avgReps < 6 ? 'strength-focused' : 'balanced';

  // Detect split pattern
  const inferredSplit = detectSplitPattern(workouts);
  // - Analyze which muscles trained together
  // - Look for push/pull/legs, upper/lower patterns

  return {
    inferredExperience,
    trainingStyle,
    topMuscleGroups: getTopMuscleGroups(workouts),
    inferredSplit,
    estimatedSessionDuration: calculateAvgDuration(workouts),
    confidenceScore: calculateConfidence(workouts),
    indicators: { strengthScore, historyScore, volumeScore, varietyScore }
  };
}
```

### Stage 4: Persist

```typescript
async function persistImportData(
  uid: string,
  workouts: ParsedWorkout[],
  matches: MatchResult[],
  intelligence: ImportIntelligence,
  options: { createHistoricalWorkouts: boolean }
): Promise<ImportSummary> {

  const db = getFirestore();
  const batch = db.batch();

  // 1. Create exercise targets (1RM records)
  for (const match of matches.filter(m => m.matchedExerciseId)) {
    const best1RM = findBest1RM(workouts, match.exerciseName);
    if (best1RM) {
      const targetRef = db
        .collection('users').doc(uid)
        .collection('exerciseTargets').doc(match.matchedExerciseId!);

      batch.set(targetRef, {
        exerciseId: match.matchedExerciseId,
        oneRepMax: best1RM,
        lastPerformed: findLastDate(workouts, match.exerciseName),
        source: 'import',
        importedAt: new Date().toISOString()
      }, { merge: true });
    }
  }

  // 2. Create exercise library entries
  for (const match of matches.filter(m => m.matchedExerciseId)) {
    const libraryRef = db
      .collection('users').doc(uid)
      .collection('exerciseLibrary').doc(match.matchedExerciseId!);

    batch.set(libraryRef, {
      exerciseId: match.matchedExerciseId,
      addedAt: new Date().toISOString(),
      source: 'import',
      usageCount: countUsage(workouts, match.exerciseName)
    }, { merge: true });
  }

  // 3. Create historical workouts (optional)
  if (options.createHistoricalWorkouts) {
    for (const workout of workouts) {
      const workoutRef = db
        .collection('users').doc(uid)
        .collection('workouts').doc();

      batch.set(workoutRef, {
        id: workoutRef.id,
        name: `Imported Session #${workout.workoutNumber}`,
        scheduledDate: workout.date.toISOString().slice(0, 10),
        status: 'completed',
        source: 'import',
        exercises: workout.exercises.map(e => ({
          exerciseName: e.name,
          matchedExerciseId: matches.find(m => m.exerciseName === e.name)?.matchedExerciseId,
          sets: e.sets
        }))
      });
    }
  }

  await batch.commit();

  return {
    sessionsImported: workouts.length,
    exercisesMatched: matches.filter(m => m.matchedExerciseId).length,
    exercisesUnmatched: matches.filter(m => !m.matchedExerciseId).map(m => m.exerciseName),
    targetsCreated: matches.filter(m => m.matchedExerciseId).length,
    workoutsCreated: options.createHistoricalWorkouts ? workouts.length : 0
  };
}
```

---

## 3. Exercise Selection - Scoring Engine

### Endpoint
```
POST /api/selectExercises
Authorization: Bearer <firebase_id_token>
```

### Request
```typescript
interface SelectionRequest {
  splitDay: SplitDay;
  muscleTargets: MuscleGroup[];
  compoundCount: number;
  isolationCount: number;
  emphasizedMuscles?: MuscleGroup[];
  availableEquipment: Equipment[];
  excludedExerciseIds?: string[];
  userExperienceLevel: ExperienceLevel;
  libraryExerciseIds: string[];
  preferBodyweightCompounds?: boolean;
}
```

### Full Algorithm

```typescript
async function selectExercises(
  request: SelectionRequest,
  exerciseDb: Exercise[]
): Promise<SelectionResult> {

  // 1. BUILD INITIAL POOL
  let pool = exerciseDb.filter(e => {
    // Filter by equipment
    if (!request.availableEquipment.includes(e.equipment)) return false;

    // Filter by experience level
    if (!isAppropriateLevel(e.experienceLevel, request.userExperienceLevel)) return false;

    // Filter by split day
    if (!matchesSplitDay(e, request.splitDay)) return false;

    // Exclude specific exercises
    if (request.excludedExerciseIds?.includes(e.id)) return false;

    return true;
  });

  // 2. EXPAND POOL IF INSUFFICIENT
  const minRequired = request.compoundCount + request.isolationCount;
  if (pool.length < minRequired * 2) {
    // Relax experience level filter
    pool = exerciseDb.filter(e => {
      if (!request.availableEquipment.includes(e.equipment)) return false;
      if (!matchesSplitDay(e, request.splitDay)) return false;
      if (request.excludedExerciseIds?.includes(e.id)) return false;
      return true;
    });
  }

  // 3. SPLIT INTO COMPOUND/ISOLATION POOLS
  const compounds = pool.filter(e => e.type === 'compound');
  const isolations = pool.filter(e => e.type === 'isolation');

  // 4. SCORE ALL EXERCISES
  const scoredCompounds = compounds.map(e => ({
    exercise: e,
    score: scoreExercise(e, request)
  }));

  const scoredIsolations = isolations.map(e => ({
    exercise: e,
    score: scoreExercise(e, request)
  }));

  // 5. SELECT COMPOUNDS WITH MOVEMENT DIVERSITY
  const selectedCompounds = selectCompoundsWithDiversity(
    scoredCompounds,
    request.compoundCount
  );

  // 6. SELECT ISOLATIONS WITH MUSCLE BALANCE
  const selectedIsolations = selectIsolationsWithBalance(
    scoredIsolations,
    request.isolationCount,
    selectedCompounds
  );

  // 7. COMBINE AND RETURN
  const allSelected = [...selectedCompounds, ...selectedIsolations];

  return {
    exerciseIds: allSelected.map(e => e.id),
    fromLibrary: allSelected.filter(e =>
      request.libraryExerciseIds.includes(e.id)
    ).map(e => e.id),
    introduced: allSelected.filter(e =>
      !request.libraryExerciseIds.includes(e.id)
    ).map(e => e.id),
    usedFallback: pool.length < minRequired * 2
  };
}

function scoreExercise(exercise: Exercise, request: SelectionRequest): number {
  let score = 1.0;

  // Library preference (20% boost)
  if (request.libraryExerciseIds.includes(exercise.id)) {
    score *= 1.2;
  }

  // Emphasis boost (50% boost)
  if (request.emphasizedMuscles?.some(m => exercise.muscleGroups.includes(m))) {
    score *= 1.5;
  }

  // Bodyweight preference (40% boost)
  if (request.preferBodyweightCompounds && exercise.equipment === 'bodyweight') {
    score *= 1.4;
  }

  // Target muscle match
  const targetMatch = exercise.muscleGroups.filter(m =>
    request.muscleTargets.includes(m)
  ).length;
  score *= (1 + targetMatch * 0.1);

  return score;
}

function selectCompoundsWithDiversity(
  scored: ScoredExercise[],
  count: number
): Exercise[] {
  const selected: Exercise[] = [];
  const usedPatterns = new Set<MovementPattern>();

  // Sort by score
  scored.sort((a, b) => b.score - a.score);

  for (const { exercise } of scored) {
    if (selected.length >= count) break;

    // Enforce movement pattern diversity
    if (exercise.movementPattern && usedPatterns.has(exercise.movementPattern)) {
      continue;  // Already have this pattern
    }

    selected.push(exercise);
    if (exercise.movementPattern) {
      usedPatterns.add(exercise.movementPattern);
    }
  }

  return selected;
}

function selectIsolationsWithBalance(
  scored: ScoredExercise[],
  count: number,
  compounds: Exercise[]
): Exercise[] {
  // Calculate muscle coverage from compounds
  const coverage = new Map<MuscleGroup, number>();
  for (const compound of compounds) {
    for (const muscle of compound.muscleGroups) {
      coverage.set(muscle, (coverage.get(muscle) || 0) + 1);
    }
  }

  // Boost score for under-covered muscles
  for (const item of scored) {
    const primaryMuscle = item.exercise.muscleGroups[0];
    const currentCoverage = coverage.get(primaryMuscle) || 0;

    if (currentCoverage === 0) {
      item.score *= 1.3;  // 30% boost for uncovered
    }
  }

  // Sort and select
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, count).map(s => s.exercise);
}
```

---

## 4. Prompt Engineering - Module Breakdown

### systemPrompt.ts (Main Builder)
```typescript
export function buildSystemPrompt(options: SystemPromptOptions): string {
  const sections: string[] = [];

  sections.push(BASE_IDENTITY);
  sections.push(buildFullUserContext(options.user, options.workoutContext, options.planContext));

  const trainingData = buildTrainingDataContext(options.strengthTargets, options.exerciseAffinity);
  if (trainingData) sections.push(trainingData);

  if (isTrainer(options.user.roles)) {
    sections.push(buildTrainerContext(options.trainerMembers, options.selectedMember));
  }

  sections.push(buildCoreRules());
  sections.push(buildToolInstructions());
  sections.push(buildExamples());
  sections.push(buildWarnings());
  sections.push(`## Current Date\nToday is ${new Date().toISOString().slice(0, 10)}`);

  return sections.filter(s => s?.length > 0).join('\n\n');
}

const BASE_IDENTITY = `You are Medina, a personal fitness coach and training companion.

## Your Role
You help members with:
- Creating custom workouts and training plans
- Answering questions about exercises, techniques, and programming
- Providing motivation and guidance throughout their fitness journey
- Explaining training concepts in simple, practical terms

## Communication Style
- Be conversational, friendly, and encouraging
- Use clear, simple language - avoid excessive jargon
- Keep responses concise (2-3 paragraphs max for explanations)
- When creating workouts, be specific about exercises, sets, reps, and rest periods
- Always prioritize safety and proper form

## Important Guidelines
1. **Safety First**: Never recommend dangerous exercises without proper supervision
2. **Progressive Overload**: Respect the user's experience level
3. **Personalization**: Consider their goals, schedule, and preferences
4. **Practical**: Focus on actionable advice they can use immediately`;
```

### userContext.ts (User Context Builder)
```typescript
export function buildFullUserContext(
  user: UserProfile,
  workoutContext?: WorkoutContext,
  planContext?: PlanContext
): string {
  const lines: string[] = [];

  lines.push('## About the User');
  lines.push(`Name: ${user.displayName || user.email?.split('@')[0] || 'User'}`);

  if (user.profile) {
    const p = user.profile;
    if (p.experienceLevel) lines.push(`Experience: ${capitalize(p.experienceLevel)}`);
    if (p.fitnessGoal) lines.push(`Goal: ${formatGoal(p.fitnessGoal)}`);
    if (p.preferredDuration) lines.push(`Preferred Duration: ${p.preferredDuration} minutes`);
    if (p.trainingFrequency) lines.push(`Training Days: ${p.trainingFrequency}x per week`);
    if (p.availableEquipment?.length) {
      lines.push(`Equipment: ${formatEquipment(p.availableEquipment)}`);
    }
  }

  if (workoutContext?.activeWorkout) {
    lines.push('');
    lines.push('## Active Workout Session');
    lines.push(`ACTIVE SESSION: ${workoutContext.activeWorkout.name} (ID: ${workoutContext.activeWorkout.id})`);
    lines.push(`Progress: ${workoutContext.completedExercises}/${workoutContext.totalExercises} exercises`);
    lines.push(`Started: ${workoutContext.startTime}`);
  }

  if (planContext?.activePlan) {
    lines.push('');
    lines.push('## Active Training Plan');
    lines.push(`Plan: ${planContext.activePlan.name} (ID: ${planContext.activePlan.id})`);
    lines.push(`Progress: Week ${planContext.currentWeek} of ${planContext.totalWeeks}`);
    lines.push(`Goal: ${planContext.activePlan.goal}`);
  }

  if (workoutContext?.todayWorkout) {
    lines.push('');
    lines.push(`Today's Workout: ${workoutContext.todayWorkout.name} (ID: ${workoutContext.todayWorkout.id})`);
  }

  return lines.join('\n');
}
```

### toolInstructions.ts (Tool Guidance)
```typescript
export function buildToolInstructions(): string {
  return `## Tool Usage Instructions

${SHOW_SCHEDULE}

${START_WORKOUT}

${SKIP_WORKOUT}

${CREATE_WORKOUT}

${CREATE_PLAN}

${MODIFY_WORKOUT}

${UPDATE_PROFILE}

${SUGGEST_OPTIONS}

${ANALYZE_TRAINING_DATA}
`;
}

export const CREATE_WORKOUT = `**create_workout**: Create a workout with automatic exercise selection
- Use by DEFAULT for workout requests
- System selects exercises based on split day and preferences
- Parameters: name, splitDay, scheduledDate, duration, effortLevel

SPLIT DAY MAPPING:
- "leg day" / "lower body" / "legs" → splitDay: "legs"
- "upper body" → splitDay: "upper"
- "arms workout" → splitDay: "arms"
- "back and biceps" → splitDay: "pull"
- "chest and triceps" → splitDay: "push"

EXERCISE COUNT BY DURATION:
- 30 min → 3 exercises
- 45 min → 4 exercises
- 60 min → 5 exercises
- 75 min → 6 exercises
- 90 min → 7 exercises

CRITICAL - Don't Pre-Describe:
NEVER describe exercises BEFORE calling create_workout.
Wait for the result, then describe what was ACTUALLY created.`;

export const START_WORKOUT = `**start_workout**: Start or continue a workout session
- Call IMMEDIATELY when user says "start my workout", "continue workout"
- DO NOT ask clarifying questions if there's exactly ONE scheduled workout today
- Shows tappable workout card for user to begin/continue

WORKOUT ID RULES - NEVER FABRICATE:
- ONLY use workout IDs from context:
  - "ACTIVE SESSION: ... (ID: xyz)" → use xyz
  - "Today's Workout: ... (ID: xyz)" → use xyz
- NEVER guess or construct IDs - validation WILL fail

WHEN NO WORKOUT TODAY:
- Tell user briefly: "No workout today. Your next is [name] on [date]."
- THEN call suggest_options with choices`;
```

---

## 5. Tool Handler - createWorkout.ts

### Full Handler Flow (647 LOC simplified)

```typescript
export async function handleCreateWorkout(
  args: CreateWorkoutArgs,
  context: HandlerContext
): Promise<HandlerResult> {
  const { uid, db } = context;

  // ─────────────────────────────────────────────────────────
  // 1. VALIDATE EXERCISE IDs
  // ─────────────────────────────────────────────────────────
  const exercisesSnapshot = await db.collection('exercises').get();
  const validExercises = new Map<string, Exercise>();
  exercisesSnapshot.forEach(doc => validExercises.set(doc.id, doc.data() as Exercise));

  const invalidIds: string[] = [];
  const validatedExercises: Exercise[] = [];

  for (const id of args.exerciseIds) {
    if (validExercises.has(id)) {
      validatedExercises.push(validExercises.get(id)!);
    } else {
      invalidIds.push(id);
    }
  }

  if (invalidIds.length > 0) {
    return {
      error: `Invalid exercise IDs: ${invalidIds.join(', ')}. Please select from the available exercises in your context.`
    };
  }

  // ─────────────────────────────────────────────────────────
  // 2. LOAD USER PROFILE AND TARGETS
  // ─────────────────────────────────────────────────────────
  const userDoc = await db.collection('users').doc(uid).get();
  const profile = userDoc.data()?.profile || {};

  const targetsSnapshot = await db
    .collection('users').doc(uid)
    .collection('exerciseTargets').get();

  const targets = new Map<string, ExerciseTarget>();
  targetsSnapshot.forEach(doc => targets.set(doc.id, doc.data() as ExerciseTarget));

  // ─────────────────────────────────────────────────────────
  // 3. RESOLVE PROTOCOLS FOR EACH EXERCISE
  // ─────────────────────────────────────────────────────────
  const protocolsSnapshot = await db.collection('protocols').get();
  const protocols = new Map<string, Protocol>();
  protocolsSnapshot.forEach(doc => protocols.set(doc.id, doc.data() as Protocol));

  const exerciseInstances = await Promise.all(
    validatedExercises.map(async (exercise) => {
      const protocol = resolveProtocol(
        exercise,
        args.effortLevel || 'standard',
        profile.experienceLevel || 'intermediate',
        protocols
      );

      return {
        id: generateId(),
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        protocolId: protocol.id,
        protocolName: protocol.name,
        sets: generateSets(protocol)
      };
    })
  );

  // ─────────────────────────────────────────────────────────
  // 4. CALCULATE TARGET WEIGHTS
  // ─────────────────────────────────────────────────────────
  for (const instance of exerciseInstances) {
    const target = targets.get(instance.exerciseId);
    const exercise = validatedExercises.find(e => e.id === instance.exerciseId)!;

    if (target?.oneRepMax) {
      instance.sets = instance.sets.map(set => ({
        ...set,
        targetWeight: calculateTargetWeight({
          oneRM: target.oneRepMax,
          exerciseType: exercise.type,
          baseIntensity: set.targetIntensity || 0.7,
        })
      }));
    }
  }

  // ─────────────────────────────────────────────────────────
  // 5. CREATE WORKOUT DOCUMENT
  // ─────────────────────────────────────────────────────────
  const workoutRef = db.collection('users').doc(uid).collection('workouts').doc();
  const workoutId = workoutRef.id;

  const workout = {
    id: workoutId,
    name: args.name,
    splitDay: args.splitDay,
    scheduledDate: args.scheduledDate,
    duration: args.duration || profile.preferredDuration || 45,
    effortLevel: args.effortLevel || 'standard',
    status: 'scheduled',
    exercises: exerciseInstances,
    createdAt: new Date().toISOString(),
    isSingleWorkout: true,
    source: 'ai_created'
  };

  await workoutRef.set(workout);

  // ─────────────────────────────────────────────────────────
  // 6. AUTO-ADD NEW EXERCISES TO LIBRARY
  // ─────────────────────────────────────────────────────────
  const librarySnapshot = await db
    .collection('users').doc(uid)
    .collection('exerciseLibrary').get();

  const existingLibrary = new Set<string>();
  librarySnapshot.forEach(doc => existingLibrary.add(doc.id));

  const newExercises = validatedExercises.filter(e => !existingLibrary.has(e.id));

  if (newExercises.length > 0) {
    const batch = db.batch();
    for (const exercise of newExercises) {
      const libRef = db
        .collection('users').doc(uid)
        .collection('exerciseLibrary').doc(exercise.id);
      batch.set(libRef, {
        exerciseId: exercise.id,
        addedAt: new Date().toISOString(),
        source: 'workout_creation'
      });
    }
    await batch.commit();
  }

  // ─────────────────────────────────────────────────────────
  // 7. RETURN RESULT
  // ─────────────────────────────────────────────────────────
  return {
    success: true,
    message: `Created "${args.name}" with ${exerciseInstances.length} exercises for ${args.scheduledDate}`,
    cardData: {
      type: 'workout_card',
      workoutId: workoutId,
      workoutName: args.name,
      exerciseCount: exerciseInstances.length,
      duration: workout.duration,
      scheduledDate: args.scheduledDate
    },
    workoutDetails: {
      exercises: exerciseInstances.map(e => ({
        name: e.exerciseName,
        sets: e.sets.length,
        reps: e.sets[0]?.targetReps,
        protocol: e.protocolName
      }))
    },
    newLibraryExercises: newExercises.map(e => e.name)
  };
}
```

---

## 6. SSE Streaming Implementation

### Server-Side (index.ts)
```typescript
export const chat = onRequest(
  { cors: true, invoker: 'public', timeoutSeconds: 120 },
  async (req, res) => {
    // ... auth and setup ...

    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    // Helper to send SSE events
    function sendSSE(event: string, data: any) {
      res.write(`event: ${event}\n`);
      res.write(`data: ${JSON.stringify(data)}\n\n`);
    }

    // Stream from OpenAI
    const stream = await openai.responses.create({
      model: 'gpt-4o-mini',
      input: messages,
      instructions: systemPrompt,
      tools: toolDefinitions,
      stream: true
    });

    let fullText = '';
    let currentToolCall: any = null;

    for await (const event of stream) {
      switch (event.type) {
        case 'response.output_text.delta':
          fullText += event.delta;
          sendSSE('text', { delta: event.delta });
          break;

        case 'response.function_call_arguments.delta':
          // Accumulate tool arguments
          break;

        case 'response.output_item.done':
          if (event.item.type === 'function_call') {
            // Execute tool handler
            const result = await executeHandler(event.item.name, event.item.arguments, context);

            // Send card events if applicable
            if (result.cardData?.type === 'workout_card') {
              sendSSE('workout_card', result.cardData);
            }
            if (result.cardData?.type === 'plan_card') {
              sendSSE('plan_card', result.cardData);
            }
          }
          break;

        case 'response.completed':
          sendSSE('done', { responseId: event.response.id });
          break;
      }
    }

    res.end();
  }
);
```

### Client-Side (iOS)
```swift
func streamChat(messages: [Message]) async {
    let url = URL(string: "https://us-central1-medinaintelligence.cloudfunctions.net/chat")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ChatRequest(messages: messages.map { ... })
    request.httpBody = try JSONEncoder().encode(body)

    let (stream, _) = try await URLSession.shared.bytes(for: request)

    var currentEvent = ""
    var currentData = ""

    for try await line in stream.lines {
        if line.hasPrefix("event: ") {
            currentEvent = String(line.dropFirst(7))
        } else if line.hasPrefix("data: ") {
            currentData = String(line.dropFirst(6))

            switch currentEvent {
            case "text":
                let delta = try JSONDecoder().decode(TextDelta.self, from: currentData.data(using: .utf8)!)
                await MainActor.run {
                    self.currentMessage += delta.delta
                }

            case "workout_card":
                let cardData = try JSONDecoder().decode(WorkoutCardData.self, from: currentData.data(using: .utf8)!)
                // Fetch full workout from Firestore
                if let workout = try await FirestoreWorkoutRepository.shared.fetchWorkout(id: cardData.workoutId, memberId: uid) {
                    await MainActor.run {
                        LocalDataStore.shared.workouts[cardData.workoutId] = workout
                        self.pendingCard = .workout(cardData)
                    }
                }

            case "done":
                await MainActor.run {
                    self.isStreaming = false
                }
            }
        }
    }
}
```
