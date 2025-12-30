/**
 * Exercise Selection Endpoint
 *
 * Phase 3: Minimal migration of LibraryExerciseSelector (~300 lines vs ~2,000 LOC iOS)
 *
 * Core algorithm:
 * 1. Build exercise pool (library-first, expand to experience level if insufficient)
 * 2. Filter by equipment and muscle targets
 * 3. Score and rank exercises (library preference, emphasis, bodyweight boost)
 * 4. Select compounds with movement pattern diversity
 * 5. Select isolations with muscle balance boost
 *
 * Skipped from iOS:
 * - SupersetPairingService (no callsites found - dead code)
 * - RuntimeExerciseSelector (wrapper only)
 * - ExerciseSelectionService (orchestration layer)
 */

import {onRequest} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

// =============================================================================
// TYPES
// =============================================================================

// Exercise type enum values (matching iOS ExerciseType)
type ExerciseType = "compound" | "isolation" | "warmup" | "cooldown" | "cardio";

// Equipment enum values (matching iOS Equipment)
type Equipment =
  | "barbell" | "dumbbells" | "cable_machine" | "bodyweight" | "kettlebell"
  | "resistance_band" | "machine" | "smith" | "trx" | "bench" | "squat_rack"
  | "pullup_bar" | "dip_station" | "treadmill" | "bike" | "rower"
  | "elliptical" | "ski_erg" | "none";

// Muscle group enum values (matching iOS MuscleGroup)
type MuscleGroup =
  | "chest" | "back" | "shoulders" | "biceps" | "triceps" | "quadriceps"
  | "hamstrings" | "glutes" | "calves" | "core" | "forearms" | "lats"
  | "traps" | "abs" | "full_body";

// Experience level enum values (matching iOS ExperienceLevel)
type ExperienceLevel = "beginner" | "intermediate" | "advanced" | "expert";

// Movement pattern enum values (matching iOS MovementPattern)
type MovementPattern =
  | "squat" | "hinge" | "horizontal_press" | "vertical_press"
  | "horizontal_pull" | "vertical_pull" | "lunge" | "carry" | "core"
  | "accessory" | "push" | "pull" | "rotation" | "dynamic" | "static_stretch";

// Split day enum values (matching iOS SplitDay)
type SplitDay =
  | "upper" | "lower" | "push" | "pull" | "legs" | "full_body"
  | "chest" | "back" | "shoulders" | "arms" | "not_applicable";

// Exercise model (subset of fields needed for selection)
interface Exercise {
  id: string;
  name: string;
  baseExercise: string;
  equipment: Equipment;
  type: ExerciseType;
  muscleGroups: MuscleGroup[];
  movementPattern?: MovementPattern;
  experienceLevel: ExperienceLevel;
}

// Request body
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

// Response body
interface SelectionResult {
  exerciseIds: string[];
  fromLibrary: string[];
  introduced: string[];
  usedFallback: boolean;
}

interface SelectionResponse {
  result?: SelectionResult;
  error?: string;
}

// =============================================================================
// EXPERIENCE LEVEL ORDERING
// =============================================================================

const experienceLevelOrder: Record<ExperienceLevel, number> = {
  beginner: 0,
  intermediate: 1,
  advanced: 2,
  expert: 3,
};

// =============================================================================
// SELECTION ALGORITHM
// =============================================================================

/**
 * Build exercise pool: library first, expand to experience level if insufficient
 */
function buildExercisePool(
  allExercises: Map<string, Exercise>,
  criteria: SelectionRequest
): { exercises: Exercise[]; usedFallback: boolean } {
  const excludedSet = new Set(criteria.excludedExerciseIds || []);
  const equipmentSet = new Set(criteria.availableEquipment);
  const muscleTargetSet = new Set(criteria.muscleTargets);

  // Get library exercises
  const libraryExercises = criteria.libraryExerciseIds
    .filter((id) => !excludedSet.has(id))
    .map((id) => allExercises.get(id))
    .filter((e): e is Exercise => e !== undefined);

  // Filter library by equipment and muscle targets
  const libraryFiltered = libraryExercises.filter((e) =>
    equipmentSet.has(e.equipment) &&
    e.muscleGroups.some((m) => muscleTargetSet.has(m))
  );

  const libraryCompounds = libraryFiltered.filter((e) => e.type === "compound").length;
  const libraryIsolations = libraryFiltered.filter((e) => e.type === "isolation").length;

  // Check if library has enough exercises
  const libraryHasEnough =
    libraryCompounds >= criteria.compoundCount &&
    libraryIsolations >= criteria.isolationCount;

  if (libraryHasEnough) {
    console.log(`Library sufficient: ${libraryCompounds} compounds, ${libraryIsolations} isolations`);
    return {exercises: libraryExercises, usedFallback: false};
  }

  // Library insufficient - expand to all exercises at user's experience level
  console.log(`Library insufficient (${libraryCompounds}/${criteria.compoundCount} compounds, ${libraryIsolations}/${criteria.isolationCount} isolations) - using fallback`);

  const userLevel = experienceLevelOrder[criteria.userExperienceLevel];
  const expandedExercises = Array.from(allExercises.values()).filter((e) =>
    experienceLevelOrder[e.experienceLevel] <= userLevel &&
    !excludedSet.has(e.id)
  );

  console.log(`Expanded to ${expandedExercises.length} exercises at ${criteria.userExperienceLevel} level or below`);
  return {exercises: expandedExercises, usedFallback: true};
}

/**
 * Select compound exercises with scoring and diversity
 */
function selectCompounds(
  pool: Exercise[],
  count: number,
  emphasizedMuscles: MuscleGroup[] | undefined,
  libraryIds: Set<string>,
  preferBodyweight: boolean
): string[] {
  const emphasizedSet = emphasizedMuscles ? new Set(emphasizedMuscles) : null;

  // Score each exercise
  const ranked = pool.map((exercise) => {
    let score = 1.0;

    // Bodyweight preference boost for home/light equipment (2.0x)
    if (preferBodyweight && exercise.equipment === "bodyweight") {
      score *= 2.0;
    }

    // Library preference boost (1.2x)
    if (libraryIds.has(exercise.id)) {
      score *= 1.2;
    }

    // Emphasis boost (1.5x)
    if (emphasizedSet && exercise.muscleGroups.some((m) => emphasizedSet.has(m))) {
      score *= 1.5;
    }

    return {exercise, score};
  }).sort((a, b) => b.score - a.score);

  // Select with movement pattern diversity and no duplicate base exercises
  const selected: string[] = [];
  const usedPatterns = new Set<MovementPattern>();
  const usedBaseExercises = new Set<string>();

  for (const {exercise} of ranked) {
    // Skip if we already selected an exercise with same baseExercise
    if (usedBaseExercises.has(exercise.baseExercise)) {
      continue;
    }

    // Enforce pattern diversity (skip if pattern already used, unless needed)
    if (exercise.movementPattern) {
      if (usedPatterns.has(exercise.movementPattern) && selected.length < count) {
        continue;
      }
      usedPatterns.add(exercise.movementPattern);
    }

    selected.push(exercise.id);
    usedBaseExercises.add(exercise.baseExercise);

    if (selected.length === count) {
      break;
    }
  }

  // Fill remaining if diversity blocked slots
  if (selected.length < count) {
    const remaining = ranked
      .filter((r) => !selected.includes(r.exercise.id))
      .filter((r) => !usedBaseExercises.has(r.exercise.baseExercise));

    for (const {exercise} of remaining) {
      if (selected.length >= count) break;
      selected.push(exercise.id);
      usedBaseExercises.add(exercise.baseExercise);
    }
  }

  return selected;
}

/**
 * Select isolation exercises with scoring and muscle balance
 */
function selectIsolations(
  pool: Exercise[],
  count: number,
  emphasizedMuscles: MuscleGroup[] | undefined,
  alreadySelectedMuscles: Set<MuscleGroup>,
  libraryIds: Set<string>
): string[] {
  const emphasizedSet = emphasizedMuscles ? new Set(emphasizedMuscles) : null;

  // Score each exercise
  const ranked = pool.map((exercise) => {
    let score = 1.0;

    // Library preference boost (1.2x)
    if (libraryIds.has(exercise.id)) {
      score *= 1.2;
    }

    // Emphasis boost (1.5x)
    if (emphasizedSet && exercise.muscleGroups.some((m) => emphasizedSet.has(m))) {
      score *= 1.5;
    }

    // Muscle balance boost (1.3x) - prefer under-represented muscles
    const underRepresented = exercise.muscleGroups.filter((m) => !alreadySelectedMuscles.has(m));
    if (underRepresented.length > 0) {
      score *= 1.3;
    }

    return {exercise, score};
  }).sort((a, b) => b.score - a.score);

  // Select with no duplicate base exercises
  const selected: string[] = [];
  const usedBaseExercises = new Set<string>();

  for (const {exercise} of ranked) {
    if (usedBaseExercises.has(exercise.baseExercise)) {
      continue;
    }

    selected.push(exercise.id);
    usedBaseExercises.add(exercise.baseExercise);

    if (selected.length === count) {
      break;
    }
  }

  return selected;
}

/**
 * Extract muscle groups from selected exercises
 */
function extractMuscles(exerciseIds: string[], pool: Exercise[]): Set<MuscleGroup> {
  const muscles = new Set<MuscleGroup>();
  for (const id of exerciseIds) {
    const exercise = pool.find((e) => e.id === id);
    if (exercise) {
      exercise.muscleGroups.forEach((m) => muscles.add(m));
    }
  }
  return muscles;
}

// =============================================================================
// MAIN ENDPOINT
// =============================================================================

export const selectExercises = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 30},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      // 1. Verify auth
      const authHeader = req.headers.authorization;
      if (!authHeader?.startsWith("Bearer ")) {
        res.status(401).json({error: "Unauthorized"});
        return;
      }

      const idToken = authHeader.split("Bearer ")[1];
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      const uid = decodedToken.uid;

      // 2. Parse request
      const body = req.body as SelectionRequest;

      if (!body.muscleTargets || body.muscleTargets.length === 0) {
        res.status(400).json({error: "muscleTargets array is required"});
        return;
      }

      if (!body.availableEquipment || body.availableEquipment.length === 0) {
        res.status(400).json({error: "availableEquipment array is required"});
        return;
      }

      if (body.compoundCount === undefined || body.isolationCount === undefined) {
        res.status(400).json({error: "compoundCount and isolationCount are required"});
        return;
      }

      if (!body.userExperienceLevel) {
        res.status(400).json({error: "userExperienceLevel is required"});
        return;
      }

      console.log(`Exercise selection for ${uid}: ${body.compoundCount} compounds + ${body.isolationCount} isolations, muscles: ${body.muscleTargets.join(", ")}`);

      // 3. Load all exercises from Firestore
      const db = admin.firestore();
      const exercisesSnapshot = await db.collection("exercises").get();

      const allExercises = new Map<string, Exercise>();
      exercisesSnapshot.forEach((doc) => {
        const data = doc.data() as Exercise;
        allExercises.set(doc.id, {...data, id: doc.id});
      });

      console.log(`Loaded ${allExercises.size} exercises from Firestore`);

      // 4. Build exercise pool
      const {exercises: exercisePool, usedFallback} = buildExercisePool(allExercises, body);

      // 5. Filter by equipment
      const equipmentSet = new Set(body.availableEquipment);
      const equipmentFiltered = exercisePool.filter((e) => equipmentSet.has(e.equipment));
      console.log(`Equipment filter: ${equipmentFiltered.length} exercises`);

      // 6. Filter by muscle targets
      const muscleTargetSet = new Set(body.muscleTargets);
      const muscleFiltered = equipmentFiltered.filter((e) =>
        e.muscleGroups.some((m) => muscleTargetSet.has(m))
      );
      console.log(`Muscle filter: ${muscleFiltered.length} exercises`);

      // 7. Split into compound and isolation pools
      const compoundPool = muscleFiltered.filter((e) => e.type === "compound");
      const isolationPool = muscleFiltered.filter((e) => e.type === "isolation");
      console.log(`Split: ${compoundPool.length} compounds, ${isolationPool.length} isolations`);

      // 8. Validate sufficient exercises
      if (compoundPool.length < body.compoundCount) {
        res.json({
          error: `Insufficient compound exercises: need ${body.compoundCount}, available ${compoundPool.length}`,
        } as SelectionResponse);
        return;
      }

      if (isolationPool.length < body.isolationCount) {
        res.json({
          error: `Insufficient isolation exercises: need ${body.isolationCount}, available ${isolationPool.length}`,
        } as SelectionResponse);
        return;
      }

      // 9. Select compound exercises
      const librarySet = new Set(body.libraryExerciseIds || []);
      const selectedCompounds = selectCompounds(
        compoundPool,
        body.compoundCount,
        body.emphasizedMuscles,
        librarySet,
        body.preferBodyweightCompounds || false
      );

      // 10. Select isolation exercises
      const selectedCompoundMuscles = extractMuscles(selectedCompounds, muscleFiltered);
      const selectedIsolations = selectIsolations(
        isolationPool,
        body.isolationCount,
        body.emphasizedMuscles,
        selectedCompoundMuscles,
        librarySet
      );

      // 11. Combine results
      const exerciseIds = [...selectedCompounds, ...selectedIsolations];
      const fromLibrary = exerciseIds.filter((id) => librarySet.has(id));
      const introduced = exerciseIds.filter((id) => !librarySet.has(id));

      console.log(`Selected ${exerciseIds.length} exercises (${fromLibrary.length} from library, ${introduced.length} introduced) for ${body.splitDay || "unspecified"}`);

      const result: SelectionResult = {
        exerciseIds,
        fromLibrary,
        introduced,
        usedFallback,
      };

      res.json({result} as SelectionResponse);
    } catch (error) {
      console.error("Exercise selection error:", error);
      const errorMessage = error instanceof Error ? error.message : "Selection failed";
      res.status(500).json({error: errorMessage});
    }
  }
);
