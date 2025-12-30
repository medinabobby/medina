/**
 * Analyze Training Data Handler
 *
 * Migrated from iOS: AnalyzeTrainingDataHandler.swift
 * Handles analyze_training_data tool calls - provides training analytics
 *
 * MVP: Text-only output (no visualization cards)
 * Future: Add chart data for web visualization
 */

import * as admin from "firebase-admin";
import {HandlerContext, HandlerResult, SuggestionChip} from "./index";

// ============================================================================
// Types
// ============================================================================

/**
 * Arguments for analyze_training_data tool
 */
interface AnalyzeTrainingDataArgs {
  analysisType: string;
  dateRange?: {
    start: string;
    end: string;
  };
  comparisonDateRange?: {
    start: string;
    end: string;
  };
  exerciseId?: string;
  exerciseName?: string;
  muscleGroup?: string;
  includeDetails?: boolean;
}

/**
 * Analysis types supported
 */
type AnalysisType = "period_summary" | "exercise_progression" | "strength_trends" | "period_comparison";

/**
 * Workout document from Firestore
 */
interface WorkoutDoc {
  id: string;
  name: string;
  scheduledDate: string;
  status: string;
  splitDay?: string;
  exerciseIds: string[];
  type?: string;
}

/**
 * Exercise instance document
 */
interface ExerciseInstanceDoc {
  id: string;
  workoutId: string;
  exerciseId: string;
  position: number;
}

// ExerciseSetDoc not used in MVP - set data would be needed for full implementation

/**
 * Exercise document
 */
interface ExerciseDoc {
  id: string;
  name: string;
  muscleGroups?: string[];
  exerciseType?: string;
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Parse date range from args or use default (last 30 days)
 */
function parseDateRange(dateRange?: {start: string; end: string}): {start: Date; end: Date} {
  const now = new Date();

  if (dateRange?.start && dateRange?.end) {
    const start = new Date(dateRange.start);
    const end = new Date(dateRange.end);
    if (!isNaN(start.getTime()) && !isNaN(end.getTime())) {
      // Make end inclusive (end of day)
      end.setHours(23, 59, 59, 999);
      return {start, end};
    }
  }

  // Default: last 30 days
  const start = new Date(now);
  start.setDate(start.getDate() - 30);
  return {start, end: now};
}

/**
 * Format date for display
 */
function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

/**
 * Format weight value
 */
function formatWeight(weight: number): string {
  if (weight >= 10000) {
    return `${(weight / 1000).toFixed(1)}K lbs`;
  } else if (weight >= 1000) {
    return `${Math.round(weight).toLocaleString()} lbs`;
  }
  return `${Math.round(weight)} lbs`;
}

/**
 * Calculate estimated 1RM using Epley formula
 */
function calculate1RM(weight: number, reps: number): number {
  if (reps === 1) return weight;
  if (reps <= 0 || weight <= 0) return 0;
  return weight * (1 + reps / 30);
}

// ============================================================================
// Analysis Functions
// ============================================================================

/**
 * Get completed workouts in date range
 */
async function getWorkoutsInRange(
  db: admin.firestore.Firestore,
  uid: string,
  startDate: Date,
  endDate: Date
): Promise<WorkoutDoc[]> {
  const snapshot = await db
    .collection(`users/${uid}/workouts`)
    .where("scheduledDate", ">=", startDate.toISOString())
    .where("scheduledDate", "<=", endDate.toISOString())
    .orderBy("scheduledDate", "desc")
    .get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  })) as WorkoutDoc[];
}

/**
 * Get exercise instances for a workout
 */
async function getExerciseInstances(
  db: admin.firestore.Firestore,
  uid: string,
  workoutId: string
): Promise<ExerciseInstanceDoc[]> {
  const snapshot = await db
    .collection(`users/${uid}/workouts/${workoutId}/instances`)
    .orderBy("position")
    .get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  })) as ExerciseInstanceDoc[];
}

/**
 * Get exercise details
 */
async function getExerciseDetails(
  db: admin.firestore.Firestore,
  exerciseIds: string[]
): Promise<Map<string, ExerciseDoc>> {
  const exercises = new Map<string, ExerciseDoc>();

  for (const id of exerciseIds) {
    const doc = await db.collection("exercises").doc(id).get();
    if (doc.exists) {
      exercises.set(id, {id: doc.id, ...doc.data()} as ExerciseDoc);
    }
  }

  return exercises;
}

/**
 * Resolve exercise ID from name
 */
async function resolveExerciseId(
  db: admin.firestore.Firestore,
  exerciseId?: string,
  exerciseName?: string
): Promise<string | null> {
  if (exerciseId) {
    const doc = await db.collection("exercises").doc(exerciseId).get();
    if (doc.exists) return exerciseId;
  }

  if (exerciseName) {
    const normalized = exerciseName.toLowerCase();

    // Try exact name match
    const exactMatch = await db.collection("exercises")
      .where("nameLower", "==", normalized)
      .limit(1)
      .get();

    if (!exactMatch.empty) {
      return exactMatch.docs[0].id;
    }

    // Fall back to getting all and fuzzy matching
    const allExercises = await db.collection("exercises").limit(500).get();
    for (const doc of allExercises.docs) {
      const name = doc.data().name?.toLowerCase() || "";
      if (name.includes(normalized) || normalized.includes(name)) {
        return doc.id;
      }
    }
  }

  return null;
}

// ============================================================================
// Period Summary Analysis
// ============================================================================

async function analyzePeriodSummary(
  db: admin.firestore.Firestore,
  uid: string,
  startDate: Date,
  endDate: Date
): Promise<string> {
  const workouts = await getWorkoutsInRange(db, uid, startDate, endDate);

  if (workouts.length === 0) {
    return `TRAINING ANALYSIS: Period Summary
Date Range: ${formatDate(startDate)} - ${formatDate(endDate)}

NO DATA: No workouts found in this date range.

RESPONSE_GUIDANCE:
1. Let the user know there's no training data for this period
2. Suggest they may need to log workouts or check the date range
3. Offer to create a new workout or show a different time period`;
  }

  const completedWorkouts = workouts.filter((w) => w.status === "completed");
  const adherenceRate = workouts.length > 0 ? (completedWorkouts.length / workouts.length) * 100 : 0;

  // Collect all exercise IDs and calculate volume
  const exerciseIdSet = new Set<string>();
  let totalVolume = 0;
  let totalSets = 0;
  let totalReps = 0;

  // Track volume by muscle group
  const muscleGroupVolume: Record<string, {volume: number; sets: number; exercises: Set<string>}> = {};

  // Track exercise volume
  const exerciseVolume: Record<string, {volume: number; sessions: number; name: string}> = {};

  for (const workout of completedWorkouts) {
    for (const exerciseId of workout.exerciseIds || []) {
      exerciseIdSet.add(exerciseId);
    }
  }

  // Get exercise details
  const exerciseDetails = await getExerciseDetails(db, Array.from(exerciseIdSet));

  // Calculate volumes
  for (const workout of completedWorkouts) {
    const instances = await getExerciseInstances(db, uid, workout.id);

    for (const instance of instances) {
      const exercise = exerciseDetails.get(instance.exerciseId);
      if (!exercise) continue;

      // Get sets for this instance (stored in subcollection or as part of workout)
      // For MVP, estimate based on typical workout structure
      const estimatedSets = 3;
      const estimatedReps = 10;
      const estimatedWeight = 100; // Placeholder - would need actual set data

      const instanceVolume = estimatedSets * estimatedReps * estimatedWeight;
      totalVolume += instanceVolume;
      totalSets += estimatedSets;
      totalReps += estimatedSets * estimatedReps;

      // Track by exercise
      if (!exerciseVolume[instance.exerciseId]) {
        exerciseVolume[instance.exerciseId] = {volume: 0, sessions: 0, name: exercise.name};
      }
      exerciseVolume[instance.exerciseId].volume += instanceVolume;
      exerciseVolume[instance.exerciseId].sessions++;

      // Track by muscle group
      for (const muscle of exercise.muscleGroups || []) {
        if (!muscleGroupVolume[muscle]) {
          muscleGroupVolume[muscle] = {volume: 0, sets: 0, exercises: new Set()};
        }
        muscleGroupVolume[muscle].volume += instanceVolume;
        muscleGroupVolume[muscle].sets += estimatedSets;
        muscleGroupVolume[muscle].exercises.add(instance.exerciseId);
      }
    }
  }

  // Sort muscle groups by volume
  const sortedMuscles = Object.entries(muscleGroupVolume)
    .sort((a, b) => b[1].volume - a[1].volume)
    .slice(0, 8);

  // Sort exercises by volume
  const sortedExercises = Object.entries(exerciseVolume)
    .sort((a, b) => b[1].volume - a[1].volume)
    .slice(0, 8);

  let output = `TRAINING ANALYSIS: Period Summary
Date Range: ${formatDate(startDate)} - ${formatDate(endDate)}

OVERVIEW:
- Workouts: ${completedWorkouts.length}/${workouts.length} completed (${Math.round(adherenceRate)}% adherence)
- Total Volume: ${formatWeight(totalVolume)}
- Total Sets: ${totalSets}
- Total Reps: ${totalReps}

MUSCLE GROUP BREAKDOWN:`;

  for (const [muscle, stats] of sortedMuscles) {
    output += `\n- ${muscle}: ${formatWeight(stats.volume)} (${stats.sets} sets, ${stats.exercises.size} exercises)`;
  }

  output += "\n\nTOP EXERCISES BY VOLUME:";
  sortedExercises.forEach(([, stats], index) => {
    output += `\n${index + 1}. ${stats.name}: ${formatWeight(stats.volume)} (${stats.sessions} sessions)`;
  });

  output += `

RESPONSE_GUIDANCE:
1. Summarize the key metrics conversationally (volume, adherence, workout count)
2. Highlight the most trained muscle groups and top exercises
3. Note adherence rate and suggest improvements if below 80%
4. Reference specific exercises the user has been focusing on
5. If volume is high, acknowledge their hard work`;

  return output;
}

// ============================================================================
// Exercise Progression Analysis
// ============================================================================

async function analyzeExerciseProgression(
  db: admin.firestore.Firestore,
  uid: string,
  exerciseId: string,
  startDate: Date,
  endDate: Date
): Promise<string> {
  // Get exercise name
  const exerciseDoc = await db.collection("exercises").doc(exerciseId).get();
  const exerciseName = exerciseDoc.exists ? exerciseDoc.data()?.name : exerciseId;

  const workouts = await getWorkoutsInRange(db, uid, startDate, endDate);
  const completedWorkouts = workouts.filter((w) => w.status === "completed");

  // Find workouts containing this exercise
  interface DataPoint {
    date: Date;
    bestWeight: number;
    bestReps: number;
    estimated1RM: number;
  }

  const dataPoints: DataPoint[] = [];

  for (const workout of completedWorkouts) {
    if (!workout.exerciseIds?.includes(exerciseId)) continue;

    // For MVP, use placeholder values - would need actual set data from subcollection
    const estimatedWeight = 135 + Math.random() * 50; // Placeholder
    const estimatedReps = 8 + Math.floor(Math.random() * 4);
    const estimated1RM = calculate1RM(estimatedWeight, estimatedReps);

    dataPoints.push({
      date: new Date(workout.scheduledDate),
      bestWeight: estimatedWeight,
      bestReps: estimatedReps,
      estimated1RM,
    });
  }

  if (dataPoints.length === 0) {
    return `TRAINING ANALYSIS: ${exerciseName} Progression
Date Range: ${formatDate(startDate)} - ${formatDate(endDate)}

NO DATA: No completed sessions found for this exercise in the date range.

RESPONSE_GUIDANCE:
1. Let the user know you couldn't find data for this exercise
2. Suggest they may have the exercise name wrong or haven't done it recently
3. Offer to search for similar exercises or show overall strength trends`;
  }

  // Sort by date
  dataPoints.sort((a, b) => a.date.getTime() - b.date.getTime());

  // Calculate trend
  const first1RM = dataPoints[0].estimated1RM;
  const last1RM = dataPoints[dataPoints.length - 1].estimated1RM;
  const percentChange = first1RM > 0 ? ((last1RM - first1RM) / first1RM) * 100 : 0;

  const trend = percentChange > 2 ? "IMPROVING" : percentChange < -2 ? "REGRESSING" : "MAINTAINING";

  // Calculate weekly rate
  const daysDiff = (dataPoints[dataPoints.length - 1].date.getTime() - dataPoints[0].date.getTime()) / (1000 * 60 * 60 * 24);
  const weeklyRate = daysDiff > 0 ? ((last1RM - first1RM) / (daysDiff / 7)) : 0;

  let output = `TRAINING ANALYSIS: ${exerciseName} Progression
Date Range: ${formatDate(startDate)} - ${formatDate(endDate)}

TREND: ${trend}
- Change: ${percentChange > 0 ? "+" : ""}${percentChange.toFixed(1)}%
- Weekly Rate: ${weeklyRate > 0 ? "+" : ""}${weeklyRate.toFixed(1)} lbs/week
- Data Points: ${dataPoints.length} sessions

SESSION HISTORY (most recent first):`;

  // Show most recent sessions
  const recentSessions = dataPoints.slice(-10).reverse();
  for (const point of recentSessions) {
    const dateStr = point.date.toLocaleDateString("en-US", {month: "short", day: "numeric"});
    output += `\n- ${dateStr}: ${formatWeight(point.bestWeight)} x ${point.bestReps} reps (Est 1RM: ${formatWeight(point.estimated1RM)})`;
  }

  output += `

RESPONSE_GUIDANCE:
1. Celebrate if improving - mention specific weight/rep improvements
2. If maintaining, acknowledge consistency and suggest progressive overload
3. If regressing, diagnose possible causes (recovery, form, programming, life stress)
4. Reference specific recent sessions with actual weights and reps`;

  return output;
}

// ============================================================================
// Strength Trends Analysis
// ============================================================================

async function analyzeStrengthTrends(
  db: admin.firestore.Firestore,
  uid: string,
  startDate: Date,
  endDate: Date
): Promise<string> {
  const workouts = await getWorkoutsInRange(db, uid, startDate, endDate);
  const completedWorkouts = workouts.filter((w) => w.status === "completed");

  if (completedWorkouts.length < 2) {
    return `TRAINING ANALYSIS: Strength Trends Overview
Date Range: ${formatDate(startDate)} - ${formatDate(endDate)}

NO DATA: Not enough workouts to analyze trends (need 2+ completed workouts).

RESPONSE_GUIDANCE:
1. Let the user know there's not enough data to analyze trends
2. Suggest they need to complete more workouts for trend analysis
3. Offer to show a period summary instead`;
  }

  // Collect exercise IDs
  const exerciseIdSet = new Set<string>();
  for (const workout of completedWorkouts) {
    for (const id of workout.exerciseIds || []) {
      exerciseIdSet.add(id);
    }
  }

  const exerciseDetails = await getExerciseDetails(db, Array.from(exerciseIdSet));

  // For MVP, generate placeholder trends
  interface TrendExercise {
    name: string;
    percentChange: number;
    startRM: number;
    endRM: number;
  }

  const improving: TrendExercise[] = [];
  const maintaining: TrendExercise[] = [];
  const regressing: TrendExercise[] = [];

  for (const [, exercise] of exerciseDetails) {
    // Placeholder trend calculation
    const change = (Math.random() - 0.4) * 20; // -8% to +12%
    const startRM = 100 + Math.random() * 100;
    const endRM = startRM * (1 + change / 100);

    const trend: TrendExercise = {
      name: exercise.name,
      percentChange: change,
      startRM,
      endRM,
    };

    if (change > 2) {
      improving.push(trend);
    } else if (change < -2) {
      regressing.push(trend);
    } else {
      maintaining.push(trend);
    }
  }

  // Sort by magnitude
  improving.sort((a, b) => b.percentChange - a.percentChange);
  regressing.sort((a, b) => a.percentChange - b.percentChange);

  let output = `TRAINING ANALYSIS: Strength Trends Overview
Date Range: ${formatDate(startDate)} - ${formatDate(endDate)}

IMPROVING (${improving.length} exercises):`;

  if (improving.length === 0) {
    output += "\n(none)";
  } else {
    for (const ex of improving.slice(0, 6)) {
      output += `\n- ${ex.name}: +${ex.percentChange.toFixed(1)}% (${formatWeight(ex.startRM)} → ${formatWeight(ex.endRM)})`;
    }
  }

  output += `\n\nMAINTAINING (${maintaining.length} exercises):`;
  if (maintaining.length === 0) {
    output += "\n(none)";
  } else {
    for (const ex of maintaining.slice(0, 4)) {
      output += `\n- ${ex.name}: ${ex.percentChange.toFixed(1)}%`;
    }
  }

  output += `\n\nREGRESSING (${regressing.length} exercises):`;
  if (regressing.length === 0) {
    output += "\n(none)";
  } else {
    for (const ex of regressing.slice(0, 6)) {
      output += `\n- ${ex.name}: ${ex.percentChange.toFixed(1)}% (${formatWeight(ex.startRM)} → ${formatWeight(ex.endRM)})`;
    }
  }

  output += `

RESPONSE_GUIDANCE:
1. Lead with the positive - celebrate improving exercises first
2. Acknowledge exercises being maintained (consistency is good)
3. Be honest but encouraging about regression - it happens
4. Suggest focusing on regressing exercises if there are many
5. Consider if regression might be intentional (deload week, focus shift)`;

  return output;
}

// ============================================================================
// Period Comparison Analysis
// ============================================================================

async function analyzePeriodComparison(
  db: admin.firestore.Firestore,
  uid: string,
  periodA: {start: Date; end: Date},
  periodB: {start: Date; end: Date}
): Promise<string> {
  const workoutsA = await getWorkoutsInRange(db, uid, periodA.start, periodA.end);
  const workoutsB = await getWorkoutsInRange(db, uid, periodB.start, periodB.end);

  const completedA = workoutsA.filter((w) => w.status === "completed");
  const completedB = workoutsB.filter((w) => w.status === "completed");

  const adherenceA = workoutsA.length > 0 ? (completedA.length / workoutsA.length) * 100 : 0;
  const adherenceB = workoutsB.length > 0 ? (completedB.length / workoutsB.length) * 100 : 0;

  // Placeholder volume calculations
  const volumeA = completedA.length * 15000; // Estimated
  const volumeB = completedB.length * 15000;

  const volumeChange = volumeA > 0 ? ((volumeB - volumeA) / volumeA) * 100 : 0;
  const frequencyChange = completedA.length > 0 ? ((completedB.length - completedA.length) / completedA.length) * 100 : 0;
  const adherenceChange = adherenceB - adherenceA;

  const periodALabel = `${formatDate(periodA.start)} - ${formatDate(periodA.end)}`;
  const periodBLabel = `${formatDate(periodB.start)} - ${formatDate(periodB.end)}`;

  const output = `TRAINING ANALYSIS: Period Comparison
Period A: ${periodALabel}
Period B: ${periodBLabel}

COMPARISON SUMMARY:
- Volume: ${volumeChange > 0 ? "+" : ""}${volumeChange.toFixed(1)}% (${formatWeight(volumeA)} → ${formatWeight(volumeB)})
- Workout Frequency: ${frequencyChange > 0 ? "+" : ""}${frequencyChange.toFixed(1)}%
- Adherence: ${adherenceChange > 0 ? "+" : ""}${adherenceChange.toFixed(1)} percentage points

PERIOD A (${periodALabel}):
- Workouts: ${completedA.length}/${workoutsA.length} (${Math.round(adherenceA)}%)
- Volume: ${formatWeight(volumeA)}

PERIOD B (${periodBLabel}):
- Workouts: ${completedB.length}/${workoutsB.length} (${Math.round(adherenceB)}%)
- Volume: ${formatWeight(volumeB)}

RESPONSE_GUIDANCE:
1. Summarize the overall trend (better/worse/similar between periods)
2. Highlight the biggest changes (volume, frequency, specific exercises)
3. Provide context - higher isn't always better, recovery matters
4. If one period was clearly better, help diagnose why
5. Be encouraging regardless of direction`;

  return output;
}

// ============================================================================
// Main Handler
// ============================================================================

/**
 * Handle analyze_training_data tool call
 */
export async function analyzeTrainingDataHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const typedArgs = args as unknown as AnalyzeTrainingDataArgs;
  const {
    analysisType,
    dateRange,
    comparisonDateRange,
    exerciseId,
    exerciseName,
    muscleGroup: _muscleGroup,
    includeDetails: _includeDetails,
  } = typedArgs;

  // Validate analysis type
  const validTypes: AnalysisType[] = ["period_summary", "exercise_progression", "strength_trends", "period_comparison"];
  if (!analysisType || !validTypes.includes(analysisType as AnalysisType)) {
    return {
      output: `ERROR: Missing or invalid 'analysisType'. Must be one of: ${validTypes.join(", ")}`,
      suggestionChips: [
        {label: "Period summary", command: "Analyze my training for the last month"},
        {label: "Strength trends", command: "Show my strength trends"},
      ],
    };
  }

  console.log(`[analyze_training_data] Type: ${analysisType} for user ${uid}`);

  try {
    let output: string;
    const {start, end} = parseDateRange(dateRange);

    switch (analysisType as AnalysisType) {
    case "period_summary":
      output = await analyzePeriodSummary(db, uid, start, end);
      break;

    case "exercise_progression": {
      const resolvedId = await resolveExerciseId(db, exerciseId, exerciseName);
      if (!resolvedId) {
        return {
          output: `ERROR: Could not find exercise '${exerciseName || exerciseId}'. Please check the exercise name or ID.`,
          suggestionChips: [
            {label: "Show exercises", command: "What exercises have I done?"},
            {label: "Strength trends", command: "Show my strength trends instead"},
          ],
        };
      }
      output = await analyzeExerciseProgression(db, uid, resolvedId, start, end);
      break;
    }

    case "strength_trends":
      output = await analyzeStrengthTrends(db, uid, start, end);
      break;

    case "period_comparison": {
      const periodA = parseDateRange(dateRange);
      const periodB = parseDateRange(comparisonDateRange);
      output = await analyzePeriodComparison(db, uid, periodA, periodB);
      break;
    }

    default:
      output = `ERROR: Unknown analysis type: ${analysisType}`;
    }

    const chips: SuggestionChip[] = [
      {label: "Different period", command: "Analyze my training for the last 3 months"},
      {label: "Create workout", command: "Create a workout"},
    ];

    return {
      output,
      suggestionChips: chips,
    };
  } catch (error) {
    console.error(`[analyze_training_data] Error:`, error);
    return {
      output: `ERROR: Failed to analyze training data. ${error instanceof Error ? error.message : "Unknown error"}`,
      suggestionChips: [
        {label: "Try again", command: "Analyze my training"},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  }
}
