/**
 * Import endpoint - CSV parsing, exercise matching, intelligence analysis
 *
 * POST /api/import
 * Requires: Authorization header with Firebase ID token
 *
 * Request body:
 * {
 *   csvData: string,              // Base64-encoded CSV
 *   createHistoricalWorkouts?: boolean,  // Default: true
 *   userWeight?: number           // For strength-based intelligence
 * }
 *
 * Migrated from iOS:
 * - CSVImportService.swift (452 lines)
 * - ImportProcessingService.swift (408 lines)
 * - HistoricalWorkoutService.swift (244 lines)
 * - ImportIntelligenceService.swift (602 lines)
 */

import {onRequest} from "firebase-functions/v2/https";

// Lazy-loaded admin module
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminModule: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminApp: any = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getAdmin(): any {
  if (!adminModule) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    adminModule = require("firebase-admin");
  }
  if (!adminApp) {
    if (adminModule.apps.length === 0) {
      adminApp = adminModule.initializeApp();
    } else {
      adminApp = adminModule.apps[0];
    }
  }
  return adminModule;
}

// ============================================================================
// Types
// ============================================================================

interface ParsedSet {
  reps: number;
  weight: number;
  equipment?: string;
}

interface ParsedExercise {
  name: string;
  sets: ParsedSet[];
  estimated1RM?: number;
  matchedExerciseId?: string;
}

interface ParsedWorkout {
  workoutNumber: number;
  date: Date;
  exercises: ParsedExercise[];
}

interface ImportedSession {
  id: string;
  sessionNumber: number;
  date: string; // ISO string
  exercises: ImportedSessionExercise[];
}

interface ImportedSessionExercise {
  id: string;
  exerciseName: string;
  matchedExerciseId?: string;
  sets: ParsedSet[];
  estimated1RM?: number;
}

interface ImportedExerciseData {
  id: string;
  exerciseName: string;
  matchedExerciseId?: string;
  matchConfidence?: number;
  oneRepMax?: number;
  recentWeight?: number;
  recentReps?: number;
  datePerformed?: string;
}

interface ExperienceIndicators {
  strengthScore?: number;
  historyScore?: number;
  volumeScore?: number;
  varietyScore?: number;
}

interface ImportIntelligence {
  inferredExperience: string | null;
  trainingStyle: string | null;
  topMuscleGroups: string[];
  avoidedMuscles: string[];
  inferredSplit: string | null;
  estimatedSessionDuration: number;
  confidenceScore: number;
  indicators: ExperienceIndicators;
}

interface ImportSummary {
  sessionsImported: number;
  exercisesMatched: number;
  exercisesUnmatched: string[];
  targetsCreated: number;
  workoutsCreated: number;
}

interface ImportResponse {
  success: boolean;
  summary: ImportSummary;
  intelligence: ImportIntelligence;
  error?: string;
}

// ============================================================================
// CSV Parsing (from CSVImportService.swift)
// ============================================================================

/**
 * Parse a CSV line handling quoted fields with commas
 */
function parseCSVLine(line: string): string[] {
  const result: string[] = [];
  let current = "";
  let inQuotes = false;

  for (const char of line) {
    if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === "," && !inQuotes) {
      result.push(current);
      current = "";
    } else {
      current += char;
    }
  }
  result.push(current);

  return result;
}

/**
 * Parse various date formats
 */
function parseDate(dateStr: string): Date | null {
  // Try "MMM d, yyyy" (e.g., "Dec 2, 2025")
  const monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
  const match1 = dateStr.match(/^([a-zA-Z]+)\s+(\d+),?\s+(\d{4})$/);
  if (match1) {
    const monthIndex = monthNames.indexOf(match1[1].toLowerCase().substring(0, 3));
    if (monthIndex !== -1) {
      return new Date(parseInt(match1[3]), monthIndex, parseInt(match1[2]));
    }
  }

  // Try "MM/dd/yyyy"
  const match2 = dateStr.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (match2) {
    return new Date(parseInt(match2[3]), parseInt(match2[1]) - 1, parseInt(match2[2]));
  }

  // Try "yyyy-MM-dd"
  const match3 = dateStr.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (match3) {
    return new Date(parseInt(match3[1]), parseInt(match3[2]) - 1, parseInt(match3[3]));
  }

  return null;
}

/**
 * Parse weight string like "135 lb barbell" or "45, 50, 55 lb dumbbells"
 */
function parseWeights(weightStr: string): number[] {
  const result: number[] = [];

  // Remove equipment descriptors
  let cleanStr = weightStr.toLowerCase();
  const equipmentWords = ["lb", "lbs", "barbell", "dumbbell", "dumbbells", "kettlebell", "kettlebells", "cable", "machine"];
  for (const word of equipmentWords) {
    cleanStr = cleanStr.replace(new RegExp(word, "g"), "");
  }

  // Handle "2x20" pattern (bilateral kettlebells)
  if (cleanStr.includes("x")) {
    const parts = cleanStr.split("x");
    if (parts.length === 2) {
      const weight = parseFloat(parts[1].trim());
      if (!isNaN(weight)) {
        result.push(weight);
        return result;
      }
    }
  }

  // Parse comma-separated weights
  const weightParts = cleanStr.split(",");
  for (const part of weightParts) {
    const trimmed = part.trim();
    const weight = parseFloat(trimmed);
    if (!isNaN(weight)) {
      result.push(weight);
    }
  }

  return result;
}

/**
 * Parse "3x8-10" or "2x12, 1x10" format
 */
function parseSetsAndWeight(setsRepsStr: string, weightStr: string): ParsedSet[] {
  const result: ParsedSet[] = [];
  const weights = parseWeights(weightStr);

  // Parse sets/reps patterns like "3x8-10" or "2x12, 1x10"
  const setGroups = setsRepsStr.split(",").map((s) => s.trim());

  let weightIndex = 0;

  for (const group of setGroups) {
    // Parse "3x8-10" or "3x8"
    const parts = group.toLowerCase().split("x");
    if (parts.length !== 2) continue;

    const setCount = parseInt(parts[0].trim()) || 1;

    // Parse rep range (e.g., "8-10" → use 10)
    const repPart = parts[1].trim();
    let reps: number;
    if (repPart.includes("-")) {
      const repRange = repPart.split("-");
      reps = parseInt(repRange[repRange.length - 1]) || 0; // Use higher end
    } else {
      reps = parseInt(repPart) || 0;
    }

    // Create sets with corresponding weights
    for (let i = 0; i < setCount; i++) {
      const weight = weightIndex < weights.length ? weights[weightIndex] : (weights[weights.length - 1] || 0);
      result.push({reps, weight});
      weightIndex++;
    }
  }

  return result;
}

/**
 * Calculate 1RM using Epley formula with quality weighting
 */
function calculateBest1RM(sets: ParsedSet[]): number | null {
  if (sets.length === 0) return null;

  const scored: Array<{rm: number; score: number}> = [];
  const totalSets = sets.length;

  for (let i = 0; i < sets.length; i++) {
    const set = sets[i];
    if (set.reps <= 0 || set.reps >= 37 || set.weight <= 0) continue;

    // Epley formula
    const rm = set.weight * (1 + set.reps / 30);

    // Rep score (3-5 reps are most accurate)
    let repScore: number;
    if (set.reps >= 3 && set.reps <= 5) repScore = 1.0;
    else if (set.reps >= 1 && set.reps <= 2) repScore = 0.8;
    else if (set.reps >= 6 && set.reps <= 8) repScore = 0.9;
    else if (set.reps >= 9 && set.reps <= 10) repScore = 0.7;
    else if (set.reps >= 11 && set.reps <= 15) repScore = 0.5;
    else repScore = 0.3;

    // Freshness score (earlier sets = less fatigue)
    const freshnessScore = totalSets <= 1 ? 1.0 : 1.0 - (i / (totalSets - 1)) * 0.4;

    const qualityScore = repScore * freshnessScore;
    scored.push({rm, score: qualityScore});
  }

  if (scored.length === 0) return null;

  // Weighted average
  const totalWeight = scored.reduce((sum, s) => sum + s.score, 0);
  if (totalWeight <= 0) return scored[0].rm;

  return scored.reduce((sum, s) => sum + s.rm * s.score, 0) / totalWeight;
}

/**
 * Parse CSV data into structured workout data
 */
function parseCSV(csvData: string): {
  workouts: ParsedWorkout[];
  uniqueExercises: Map<string, number>;
  totalSets: number;
  unmatchedExercises: string[];
} {
  const lines = csvData.split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  if (lines.length <= 1) {
    throw new Error("CSV file is empty or has only headers");
  }

  // Skip header row
  const dataLines = lines.slice(1);

  const workouts: ParsedWorkout[] = [];
  let currentWorkout: ParsedWorkout | null = null;

  for (const line of dataLines) {
    const columns = parseCSVLine(line);
    if (columns.length < 5) continue;

    const workoutNumStr = columns[0].trim();
    const dateStr = columns[1].trim();
    const exerciseName = columns[2].trim();
    const setsRepsStr = columns[3].trim();
    const weightStr = columns[4].trim();

    // Check if this is a new workout (has workout number)
    if (workoutNumStr && !isNaN(parseInt(workoutNumStr))) {
      // Save previous workout
      if (currentWorkout) {
        workouts.push(currentWorkout);
      }

      // Parse date
      const date = parseDate(dateStr) || new Date();

      currentWorkout = {
        workoutNumber: parseInt(workoutNumStr),
        date,
        exercises: [],
      };
    }

    // Parse exercise
    if (!exerciseName) continue;

    const sets = parseSetsAndWeight(setsRepsStr, weightStr);
    const estimated1RM = calculateBest1RM(sets);

    const exercise: ParsedExercise = {
      name: exerciseName,
      sets,
      estimated1RM: estimated1RM || undefined,
    };

    currentWorkout?.exercises.push(exercise);
  }

  // Don't forget the last workout
  if (currentWorkout) {
    workouts.push(currentWorkout);
  }

  // Aggregate results
  const uniqueExercises = new Map<string, number>();
  let totalSets = 0;
  const unmatchedExercises: string[] = [];

  for (const workout of workouts) {
    for (const exercise of workout.exercises) {
      totalSets += exercise.sets.length;

      // Track best 1RM per exercise
      if (exercise.estimated1RM) {
        const existing = uniqueExercises.get(exercise.name) || 0;
        uniqueExercises.set(exercise.name, Math.max(existing, exercise.estimated1RM));
      }
    }
  }

  return {workouts, uniqueExercises, totalSets, unmatchedExercises};
}

// ============================================================================
// Exercise Matching
// ============================================================================

/**
 * Match exercise name to library
 */
async function matchExerciseToLibrary(
  name: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  exerciseCache: Map<string, any>
): Promise<string | null> {
  const normalizedName = name.toLowerCase()
    .replace(/-/g, " ")
    .trim();

  // Check exact matches first
  for (const [id, exercise] of exerciseCache) {
    const exerciseName = exercise.name?.toLowerCase() || "";
    if (exerciseName === normalizedName) {
      return id;
    }
  }

  // Check partial matches
  for (const [id, exercise] of exerciseCache) {
    const exerciseName = exercise.name?.toLowerCase() || "";

    // "Squats" → "squat", "Deadlifts" → "deadlift"
    const singularName = normalizedName.endsWith("s")
      ? normalizedName.slice(0, -1)
      : normalizedName;

    if (exerciseName.includes(singularName) || singularName.includes(exerciseName)) {
      return id;
    }
  }

  return null;
}

/**
 * Load all exercises from Firestore into cache
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function loadExerciseLibrary(db: any): Promise<Map<string, any>> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const cache = new Map<string, any>();

  const snapshot = await db.collection("exercises").get();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  snapshot.forEach((doc: any) => {
    cache.set(doc.id, doc.data());
  });

  return cache;
}

// ============================================================================
// Intelligence Analysis (from ImportIntelligenceService.swift)
// ============================================================================

/**
 * Find max 1RM for exercises matching keywords
 */
function findExerciseMax(exercises: ImportedExerciseData[], keywords: string[]): number | null {
  const matches = exercises.filter((exercise) => {
    const name = exercise.exerciseName.toLowerCase();
    return keywords.some((keyword) => name.includes(keyword.toLowerCase()));
  });

  const maxes = matches.map((e) => e.oneRepMax).filter((v): v is number => v !== undefined && v !== null);
  return maxes.length > 0 ? Math.max(...maxes) : null;
}

/**
 * Calculate relative strength score (vs bodyweight)
 */
function calculateRelativeStrengthScore(
  squatMax: number | null,
  benchMax: number | null,
  deadliftMax: number | null,
  bodyweight: number
): number | null {
  const scores: number[] = [];

  // Squat standards
  if (squatMax) {
    const ratio = squatMax / bodyweight;
    if (ratio < 1.0) scores.push(0.5);
    else if (ratio < 1.5) scores.push(1.5);
    else if (ratio < 2.0) scores.push(2.5);
    else scores.push(3.0);
  }

  // Bench standards
  if (benchMax) {
    const ratio = benchMax / bodyweight;
    if (ratio < 0.75) scores.push(0.5);
    else if (ratio < 1.25) scores.push(1.5);
    else if (ratio < 1.75) scores.push(2.5);
    else scores.push(3.0);
  }

  // Deadlift standards
  if (deadliftMax) {
    const ratio = deadliftMax / bodyweight;
    if (ratio < 1.25) scores.push(0.5);
    else if (ratio < 2.0) scores.push(1.5);
    else if (ratio < 2.75) scores.push(2.5);
    else scores.push(3.0);
  }

  if (scores.length === 0) return null;
  return scores.reduce((a, b) => a + b, 0) / scores.length;
}

/**
 * Calculate absolute strength score (when bodyweight unavailable)
 */
function calculateAbsoluteStrengthScore(
  squatMax: number | null,
  benchMax: number | null,
  deadliftMax: number | null
): number | null {
  const scores: number[] = [];

  // Squat: <135=beginner, 135-225=intermediate, 225-315=advanced, >315=expert
  if (squatMax) {
    if (squatMax < 135) scores.push(0.5);
    else if (squatMax < 225) scores.push(1.5);
    else if (squatMax < 315) scores.push(2.5);
    else scores.push(3.0);
  }

  // Bench
  if (benchMax) {
    if (benchMax < 135) scores.push(0.5);
    else if (benchMax < 185) scores.push(1.5);
    else if (benchMax < 275) scores.push(2.5);
    else scores.push(3.0);
  }

  // Deadlift
  if (deadliftMax) {
    if (deadliftMax < 185) scores.push(0.5);
    else if (deadliftMax < 315) scores.push(1.5);
    else if (deadliftMax < 405) scores.push(2.5);
    else scores.push(3.0);
  }

  if (scores.length === 0) return null;
  return scores.reduce((a, b) => a + b, 0) / scores.length;
}

/**
 * Calculate history score from date range
 */
function calculateHistoryScore(startDate: Date, endDate: Date): number {
  const months = Math.floor((endDate.getTime() - startDate.getTime()) / (30 * 24 * 60 * 60 * 1000));

  if (months < 6) return 0.5;
  if (months < 18) return 1.5;
  if (months < 36) return 2.5;
  return 3.0;
}

/**
 * Calculate volume score from average sets per session
 */
function calculateVolumeScore(sessions: ImportedSession[]): number {
  if (sessions.length === 0) return 0.5;

  let totalSets = 0;
  for (const session of sessions) {
    for (const exercise of session.exercises) {
      totalSets += exercise.sets.length;
    }
  }
  const avgSetsPerSession = totalSets / sessions.length;

  if (avgSetsPerSession < 12) return 0.5;
  if (avgSetsPerSession < 20) return 1.5;
  if (avgSetsPerSession < 30) return 2.5;
  return 3.0;
}

/**
 * Calculate variety score from unique exercise count
 */
function calculateVarietyScore(exerciseCount: number): number {
  if (exerciseCount < 15) return 0.5;
  if (exerciseCount < 30) return 1.5;
  if (exerciseCount < 50) return 2.5;
  return 3.0;
}

/**
 * Compute experience level from weighted indicators
 */
function computeExperienceLevel(indicators: ExperienceIndicators): string {
  // Weights: strength 40%, history 30%, volume 20%, variety 10%
  let totalWeight = 0;
  let weightedSum = 0;

  if (indicators.strengthScore !== undefined) {
    weightedSum += indicators.strengthScore * 0.4;
    totalWeight += 0.4;
  }
  if (indicators.historyScore !== undefined) {
    weightedSum += indicators.historyScore * 0.3;
    totalWeight += 0.3;
  }
  if (indicators.volumeScore !== undefined) {
    weightedSum += indicators.volumeScore * 0.2;
    totalWeight += 0.2;
  }
  if (indicators.varietyScore !== undefined) {
    weightedSum += indicators.varietyScore * 0.1;
    totalWeight += 0.1;
  }

  if (totalWeight === 0) return "beginner";
  const finalScore = weightedSum / totalWeight;

  if (finalScore < 1.0) return "beginner";
  if (finalScore < 2.0) return "intermediate";
  if (finalScore < 2.75) return "advanced";
  return "expert";
}

/**
 * Infer training style from exercise patterns
 */
function inferTrainingStyle(exercises: ImportedExerciseData[], sessions: ImportedSession[]): string | null {
  if (exercises.length === 0) return null;

  // Count "big 3" exercises
  const big3Keywords = ["squat", "bench", "deadlift"];
  const big3Count = exercises.filter((exercise) => {
    const name = exercise.exerciseName.toLowerCase();
    return big3Keywords.some((k) => name.includes(k));
  }).length;
  const big3Percentage = big3Count / exercises.length;

  // Count isolation exercises
  const isolationKeywords = ["curl", "extension", "raise", "fly", "flye", "kickback", "pushdown", "pulldown", "lateral"];
  const isolationCount = exercises.filter((exercise) => {
    const name = exercise.exerciseName.toLowerCase();
    return isolationKeywords.some((k) => name.includes(k));
  }).length;
  const isolationPercentage = isolationCount / exercises.length;

  // Calculate average reps
  let avgReps = 8.0;
  if (sessions.length > 0) {
    const allSets = sessions.flatMap((s) => s.exercises.flatMap((e) => e.sets));
    if (allSets.length > 0) {
      avgReps = allSets.reduce((sum, s) => sum + s.reps, 0) / allSets.length;
    }
  }

  if (big3Percentage > 0.4 && avgReps < 6) return "powerlifting";
  if (isolationPercentage > 0.4 && avgReps > 8) return "bodybuilding";
  if (exercises.length > 20 && big3Percentage > 0.15) return "hybrid";
  return "generalFitness";
}

/**
 * Infer muscle groups from exercise name
 */
function inferMuscleGroupsFromName(name: string): string[] {
  const lowercased = name.toLowerCase();
  const muscles: string[] = [];

  // Chest
  if (lowercased.includes("bench") || lowercased.includes("chest") || lowercased.includes("fly")) {
    muscles.push("chest");
  }

  // Back
  if (lowercased.includes("row") || lowercased.includes("pull") || lowercased.includes("lat") || lowercased.includes("back")) {
    muscles.push("back");
  }

  // Shoulders
  if (lowercased.includes("shoulder") || lowercased.includes("delt") || lowercased.includes("overhead") || lowercased.includes("lateral raise")) {
    muscles.push("shoulders");
  }

  // Legs
  if (lowercased.includes("squat") || lowercased.includes("leg") || lowercased.includes("lunge") || lowercased.includes("calf")) {
    if (lowercased.includes("quad")) muscles.push("quadriceps");
    else if (lowercased.includes("ham")) muscles.push("hamstrings");
    else if (lowercased.includes("glute")) muscles.push("glutes");
    else if (lowercased.includes("calf") || lowercased.includes("calves")) muscles.push("calves");
    else muscles.push("quadriceps");
  }

  // Arms
  if (lowercased.includes("bicep") || lowercased.includes("curl")) {
    muscles.push("biceps");
  }
  if (lowercased.includes("tricep") || lowercased.includes("pushdown") || (lowercased.includes("extension") && lowercased.includes("tricep"))) {
    muscles.push("triceps");
  }

  // Core
  if (lowercased.includes("core") || lowercased.includes("ab") || lowercased.includes("plank") || lowercased.includes("crunch")) {
    muscles.push("core");
  }

  // Deadlift is posterior chain
  if (lowercased.includes("deadlift")) {
    muscles.push("back", "hamstrings", "glutes");
  }

  return muscles;
}

/**
 * Infer emphasized muscle groups
 */
function inferEmphasizedMuscles(exercises: ImportedExerciseData[]): string[] {
  const muscleFrequency: Map<string, number> = new Map();

  for (const exercise of exercises) {
    const inferredMuscles = inferMuscleGroupsFromName(exercise.exerciseName);
    for (const muscle of inferredMuscles) {
      muscleFrequency.set(muscle, (muscleFrequency.get(muscle) || 0) + 1);
    }
  }

  // Get top 3 most frequent
  const sorted = Array.from(muscleFrequency.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([muscle]) => muscle);

  return sorted;
}

/**
 * Infer split type from session patterns
 */
function inferSplitType(sessions: ImportedSession[]): string | null {
  if (sessions.length < 8) return null;

  // Analyze muscle groups per session
  const sessionMusclePatterns: string[][] = [];

  for (const session of sessions) {
    const muscles: string[] = [];
    for (const exercise of session.exercises) {
      const inferred = inferMuscleGroupsFromName(exercise.exerciseName);
      muscles.push(...inferred);
    }
    sessionMusclePatterns.push(muscles);
  }

  // Check for full body (5+ muscle groups per session)
  const fullBodySessions = sessionMusclePatterns.filter((p) => new Set(p).size >= 5).length;
  if (fullBodySessions > sessions.length / 2) {
    return "fullBody";
  }

  // Check for upper/lower pattern
  const upperMuscles = new Set(["chest", "back", "shoulders", "biceps", "triceps"]);
  const lowerMuscles = new Set(["quadriceps", "hamstrings", "glutes", "calves"]);

  let upperDays = 0;
  let lowerDays = 0;

  for (const pattern of sessionMusclePatterns) {
    const patternSet = new Set(pattern);
    const upperCount = Array.from(patternSet).filter((m) => upperMuscles.has(m)).length;
    const lowerCount = Array.from(patternSet).filter((m) => lowerMuscles.has(m)).length;

    if (upperCount > lowerCount * 2) upperDays++;
    else if (lowerCount > upperCount * 2) lowerDays++;
  }

  if (upperDays > 3 && lowerDays > 3) {
    return "upperLower";
  }

  // Default to PPL if variety is high
  if (sessions.length >= 12) {
    return "pushPullLegs";
  }

  return null;
}

/**
 * Estimate session duration
 */
function estimateSessionDuration(sessions: ImportedSession[]): number {
  if (sessions.length === 0) return 60;

  let totalSets = 0;
  for (const session of sessions) {
    for (const exercise of session.exercises) {
      totalSets += exercise.sets.length;
    }
  }
  const avgSetsPerSession = totalSets / sessions.length;

  // Estimate: 4 min per set + 10 min warmup
  const estimatedMinutes = avgSetsPerSession * 4 + 10;

  // Round to nearest 15 minutes, clamp 45-120
  const rounded = Math.round(estimatedMinutes / 15) * 15;
  return Math.min(Math.max(rounded, 45), 120);
}

/**
 * Calculate confidence score
 */
function calculateConfidence(sessionCount: number, exerciseCount: number, hasWeightData: boolean): number {
  let confidence = 0.5;

  if (sessionCount >= 20) confidence += 0.2;
  else if (sessionCount >= 10) confidence += 0.15;
  else if (sessionCount >= 5) confidence += 0.1;

  if (exerciseCount >= 20) confidence += 0.15;
  else if (exerciseCount >= 10) confidence += 0.1;

  if (hasWeightData) confidence += 0.15;

  return Math.min(confidence, 1.0);
}

/**
 * Full intelligence analysis
 */
function analyzeImport(
  exercises: ImportedExerciseData[],
  sessions: ImportedSession[],
  userWeight?: number
): ImportIntelligence {
  // Build indicators
  const indicators: ExperienceIndicators = {};

  // 1. Strength score
  const squatMax = findExerciseMax(exercises, ["squat", "back squat", "front squat"]);
  const benchMax = findExerciseMax(exercises, ["bench press", "bench", "flat bench"]);
  const deadliftMax = findExerciseMax(exercises, ["deadlift", "conventional deadlift", "sumo deadlift"]);

  if (userWeight && userWeight > 0) {
    indicators.strengthScore = calculateRelativeStrengthScore(squatMax, benchMax, deadliftMax, userWeight) || undefined;
  } else {
    indicators.strengthScore = calculateAbsoluteStrengthScore(squatMax, benchMax, deadliftMax) || undefined;
  }

  // 2. History score
  if (sessions.length > 0) {
    const dates = sessions.map((s) => new Date(s.date)).sort((a, b) => a.getTime() - b.getTime());
    if (dates.length >= 2) {
      indicators.historyScore = calculateHistoryScore(dates[0], dates[dates.length - 1]);
    }
  }

  // 3. Volume score
  indicators.volumeScore = calculateVolumeScore(sessions);

  // 4. Variety score
  indicators.varietyScore = calculateVarietyScore(exercises.length);

  // Compute final experience
  const inferredExperience = computeExperienceLevel(indicators);

  // Training style
  const trainingStyle = inferTrainingStyle(exercises, sessions);

  // Muscle groups
  const topMuscleGroups = inferEmphasizedMuscles(exercises);
  const avoidedMuscles: string[] = []; // Simplified for now

  // Split type
  const inferredSplit = inferSplitType(sessions);

  // Session duration
  const estimatedSessionDuration = estimateSessionDuration(sessions);

  // Confidence
  const confidenceScore = calculateConfidence(sessions.length, exercises.length, userWeight !== undefined);

  return {
    inferredExperience,
    trainingStyle,
    topMuscleGroups,
    avoidedMuscles,
    inferredSplit,
    estimatedSessionDuration,
    confidenceScore,
    indicators,
  };
}

// ============================================================================
// Record Creation
// ============================================================================

/**
 * Create ExerciseTarget records in Firestore
 */
async function createExerciseTargets(
  exercises: ImportedExerciseData[],
  uid: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  db: any
): Promise<number> {
  const batch = db.batch();
  let count = 0;

  for (const exercise of exercises) {
    if (!exercise.matchedExerciseId || !exercise.oneRepMax) continue;

    const targetRef = db.collection("users").doc(uid)
      .collection("targets").doc(exercise.matchedExerciseId);

    const targetData = {
      exerciseId: exercise.matchedExerciseId,
      memberId: uid,
      targetType: "max",
      currentTarget: exercise.oneRepMax,
      lastCalibrated: new Date().toISOString(),
      targetHistory: [{
        date: new Date().toISOString(),
        target: exercise.oneRepMax,
        calibrationSource: "CSV Import",
      }],
    };

    batch.set(targetRef, targetData, {merge: true});
    count++;
  }

  if (count > 0) {
    await batch.commit();
  }

  return count;
}

/**
 * Create historical workout records in Firestore
 */
async function createHistoricalWorkouts(
  sessions: ImportedSession[],
  uid: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  db: any
): Promise<number> {
  const IMPORTED_PLAN_ID = "imported-history";
  const IMPORTED_PROGRAM_ID = "imported-workouts";

  // Ensure plan exists
  const planRef = db.collection("users").doc(uid).collection("plans").doc(IMPORTED_PLAN_ID);
  const planDoc = await planRef.get();

  if (!planDoc.exists) {
    await planRef.set({
      id: IMPORTED_PLAN_ID,
      memberId: uid,
      status: "completed",
      name: "Imported History",
      description: "Historical workout data from imports",
      goal: "generalFitness",
      startDate: new Date(0).toISOString(),
    });
  }

  // Ensure program exists
  const programRef = db.collection("users").doc(uid).collection("programs").doc(IMPORTED_PROGRAM_ID);
  const programDoc = await programRef.get();

  if (!programDoc.exists) {
    await programRef.set({
      id: IMPORTED_PROGRAM_ID,
      planId: IMPORTED_PLAN_ID,
      name: "Imported Workouts",
      status: "completed",
      startDate: new Date(0).toISOString(),
    });
  }

  // Create workouts
  let count = 0;
  for (const session of sessions) {
    const workoutId = `imported-${session.id}`;
    const workoutRef = db.collection("users").doc(uid).collection("workouts").doc(workoutId);

    // Get exercise IDs that are matched
    const exerciseIds = session.exercises
      .filter((e) => e.matchedExerciseId)
      .map((e) => e.matchedExerciseId);

    const workoutData = {
      id: workoutId,
      programId: IMPORTED_PROGRAM_ID,
      name: `Imported: Session ${session.sessionNumber}`,
      scheduledDate: session.date,
      type: "strength",
      status: "completed",
      completedDate: session.date,
      exerciseIds,
    };

    await workoutRef.set(workoutData, {merge: true});
    count++;

    // Create exercise instances and sets
    for (const exercise of session.exercises) {
      if (!exercise.matchedExerciseId) continue;

      const instanceId = `${workoutId}-${exercise.matchedExerciseId}`;
      const instanceRef = db.collection("users").doc(uid)
        .collection("exerciseInstances").doc(instanceId);

      const setIds: string[] = [];
      for (let i = 0; i < exercise.sets.length; i++) {
        const setId = `${instanceId}-set${i + 1}`;
        setIds.push(setId);

        const setRef = db.collection("users").doc(uid)
          .collection("exerciseSets").doc(setId);

        await setRef.set({
          id: setId,
          exerciseInstanceId: instanceId,
          setNumber: i + 1,
          targetWeight: exercise.sets[i].weight,
          targetReps: exercise.sets[i].reps,
          actualWeight: exercise.sets[i].weight,
          actualReps: exercise.sets[i].reps,
          completion: "completed",
          recordedDate: session.date,
        });
      }

      await instanceRef.set({
        id: instanceId,
        exerciseId: exercise.matchedExerciseId,
        workoutId,
        setIds,
        status: "completed",
      });
    }
  }

  return count;
}

// ============================================================================
// Exports for Testing
// ============================================================================

export {
  parseCSVLine,
  parseDate,
  parseWeights,
  parseSetsAndWeight,
  calculateBest1RM,
  parseCSV,
  matchExerciseToLibrary,
  calculateRelativeStrengthScore,
  calculateAbsoluteStrengthScore,
  calculateHistoryScore,
  calculateVolumeScore,
  calculateVarietyScore,
  computeExperienceLevel,
  inferTrainingStyle,
  inferMuscleGroupsFromName,
  inferEmphasizedMuscles,
  inferSplitType,
  estimateSessionDuration,
  calculateConfidence,
  analyzeImport,
};

export type {
  ParsedSet,
  ParsedExercise,
  ParsedWorkout,
  ImportedSession,
  ImportedSessionExercise,
  ImportedExerciseData,
  ExperienceIndicators,
  ImportIntelligence,
  ImportSummary,
  ImportResponse,
};

// ============================================================================
// Main Handler
// ============================================================================

export const importCSV = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 120},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      // Verify auth
      const authHeader = req.headers.authorization;
      if (!authHeader?.startsWith("Bearer ")) {
        res.status(401).json({error: "Unauthorized"});
        return;
      }

      const idToken = authHeader.split("Bearer ")[1];
      const admin = getAdmin();

      let uid: string;
      try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        uid = decoded.uid;
      } catch {
        res.status(401).json({error: "Invalid token"});
        return;
      }

      // Parse request
      const {csvData, createHistoricalWorkouts: shouldCreateWorkouts = true, userWeight} = req.body;

      if (!csvData || typeof csvData !== "string") {
        res.status(400).json({error: "csvData is required (base64 encoded)"});
        return;
      }

      // Decode base64
      const csvString = Buffer.from(csvData, "base64").toString("utf-8");

      // Parse CSV
      const parsed = parseCSV(csvString);
      console.log(`Parsed ${parsed.workouts.length} workouts with ${parsed.totalSets} total sets`);

      // Load exercise library for matching
      const db = admin.firestore();
      const exerciseCache = await loadExerciseLibrary(db);
      console.log(`Loaded ${exerciseCache.size} exercises for matching`);

      // Match exercises
      const unmatchedExercises: string[] = [];
      const matchedCount = {value: 0};

      for (const workout of parsed.workouts) {
        for (const exercise of workout.exercises) {
          const matchedId = await matchExerciseToLibrary(exercise.name, exerciseCache);
          exercise.matchedExerciseId = matchedId || undefined;

          if (matchedId) {
            matchedCount.value++;
          } else if (!unmatchedExercises.includes(exercise.name)) {
            unmatchedExercises.push(exercise.name);
          }
        }
      }

      // Convert to ImportedSession format
      const sessions: ImportedSession[] = parsed.workouts.map((workout) => ({
        id: `session-${workout.workoutNumber}`,
        sessionNumber: workout.workoutNumber,
        date: workout.date.toISOString(),
        exercises: workout.exercises.map((e) => ({
          id: `exercise-${e.name.replace(/\s+/g, "-").toLowerCase()}`,
          exerciseName: e.name,
          matchedExerciseId: e.matchedExerciseId,
          sets: e.sets,
          estimated1RM: e.estimated1RM,
        })),
      }));

      // Convert to ImportedExerciseData format (aggregated)
      const exerciseMap = new Map<string, ImportedExerciseData>();
      for (const workout of parsed.workouts) {
        for (const exercise of workout.exercises) {
          const existing = exerciseMap.get(exercise.name);
          if (existing) {
            if (exercise.estimated1RM && (!existing.oneRepMax || exercise.estimated1RM > existing.oneRepMax)) {
              existing.oneRepMax = exercise.estimated1RM;
              existing.datePerformed = workout.date.toISOString();
            }
          } else {
            exerciseMap.set(exercise.name, {
              id: `agg-${exercise.name.replace(/\s+/g, "-").toLowerCase()}`,
              exerciseName: exercise.name,
              matchedExerciseId: exercise.matchedExerciseId,
              oneRepMax: exercise.estimated1RM,
              recentWeight: exercise.sets[exercise.sets.length - 1]?.weight,
              recentReps: exercise.sets[exercise.sets.length - 1]?.reps,
              datePerformed: workout.date.toISOString(),
            });
          }
        }
      }
      const exercises = Array.from(exerciseMap.values());

      // Run intelligence analysis
      const intelligence = analyzeImport(exercises, sessions, userWeight);

      // Create ExerciseTargets
      const targetsCreated = await createExerciseTargets(exercises, uid, db);

      // Create historical workouts if requested
      let workoutsCreated = 0;
      if (shouldCreateWorkouts) {
        workoutsCreated = await createHistoricalWorkouts(sessions, uid, db);
      }

      // Update user profile with inferred data
      if (intelligence.inferredExperience) {
        const userRef = db.collection("users").doc(uid);
        await userRef.set({
          profile: {
            experienceLevel: intelligence.inferredExperience,
            sessionDuration: intelligence.estimatedSessionDuration,
            emphasizedMuscles: intelligence.topMuscleGroups,
          },
        }, {merge: true});
      }

      // Build response
      const response: ImportResponse = {
        success: true,
        summary: {
          sessionsImported: sessions.length,
          exercisesMatched: matchedCount.value,
          exercisesUnmatched: unmatchedExercises,
          targetsCreated,
          workoutsCreated,
        },
        intelligence,
      };

      console.log(`Import complete for ${uid}: ${sessions.length} sessions, ${targetsCreated} targets, ${workoutsCreated} workouts`);
      res.json(response);
    } catch (error) {
      console.error("Import error:", error);
      const errorMessage = error instanceof Error ? error.message : "Import failed";
      res.status(500).json({error: errorMessage});
    }
  }
);
