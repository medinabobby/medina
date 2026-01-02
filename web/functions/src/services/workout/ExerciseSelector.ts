/**
 * Exercise Selector Service
 *
 * Selects exercises for workouts based on split day, equipment, and user constraints.
 * Validates AI-provided exercises and supplements from library if needed.
 *
 * Key features:
 * - Validates AI exercise IDs against global catalog
 * - Filters by split day muscle groups
 * - Filters by available equipment
 * - Prioritizes compound exercises
 * - Prevents duplicate base exercises (e.g., barbell + dumbbell bench press)
 */

import type * as admin from 'firebase-admin';
import {
  ExerciseDoc,
  ExerciseSelectionRequest,
  ExerciseSelectionResult,
  NameMatch,
  SplitDay,
  SessionType,
  Equipment,
  SPLIT_DAY_MUSCLES,
} from './types';

// ============================================================================
// Exercise Name Mappings (v255: Vision import support)
// ============================================================================

/**
 * Common exercise name → ID mappings for vision import
 * When AI passes exercise names instead of IDs, we use this to find matches
 * v257: Updated to match comprehensive exercise database
 */
const EXERCISE_NAME_MAPPINGS: Record<string, string> = {
  // Press variations
  'bench press': 'barbell_bench_press',
  'flat bench': 'barbell_bench_press',
  'flat bench press': 'barbell_bench_press',
  'barbell bench': 'barbell_bench_press',
  'incline press': 'incline_barbell_bench_press',
  'incline bench': 'incline_barbell_bench_press',
  'incline bench press': 'incline_barbell_bench_press',
  'incline barbell bench press': 'incline_barbell_bench_press',
  'decline press': 'decline_barbell_bench_press',
  'decline bench press': 'decline_barbell_bench_press',
  'decline barbell bench press': 'decline_barbell_bench_press',
  'shoulder press': 'overhead_press',
  'overhead press': 'overhead_press',
  'military press': 'overhead_press',
  'ohp': 'overhead_press',
  'barbell shoulder press': 'overhead_press',
  'standing shoulder press': 'overhead_press',

  // Dumbbell variants
  'dumbbell press': 'dumbbell_bench_press',
  'db bench': 'dumbbell_bench_press',
  'db bench press': 'dumbbell_bench_press',
  'dumbbell bench press': 'dumbbell_bench_press',
  'dumbbell incline press': 'incline_dumbbell_bench_press',
  'incline dumbbell press': 'incline_dumbbell_bench_press',
  'incline db press': 'incline_dumbbell_bench_press',
  'dumbbell fly': 'dumbbell_fly',
  'db fly': 'dumbbell_fly',
  'chest fly': 'dumbbell_fly',
  'flat fly': 'dumbbell_fly',
  'lateral raise': 'dumbbell_lateral_raise',
  'lat raise': 'dumbbell_lateral_raise',
  'side raise': 'dumbbell_lateral_raise',
  'lateral raises': 'dumbbell_lateral_raise',
  'side lateral raise': 'dumbbell_lateral_raise',
  'front raise': 'dumbbell_front_raise',
  'front raises': 'dumbbell_front_raise',
  'dumbbell front raise': 'dumbbell_front_raise',

  // Triceps
  'tricep dips': 'dip',
  'triceps dips': 'dip',
  'dips': 'dip',
  'chest dips': 'dip',
  'parallel bar dips': 'dip',
  'triceps pushdowns': 'cable_tricep_pushdown',
  'tricep pushdowns': 'cable_tricep_pushdown',
  'tricep pushdown': 'cable_tricep_pushdown',
  'pushdown': 'cable_tricep_pushdown',
  'pushdowns': 'cable_tricep_pushdown',
  'rope pushdown': 'cable_tricep_pushdown',
  'cable pushdown': 'cable_tricep_pushdown',
  'tricep rope pushdown': 'cable_tricep_pushdown',
  'skull crushers': 'skull_crusher',
  'skull crusher': 'skull_crusher',
  'lying tricep extension': 'skull_crusher',
  'ez bar skull crusher': 'skull_crusher',
  'tricep extension': 'tricep_extension',
  'rope tricep extension': 'tricep_extension',
  'overhead tricep extension': 'overhead_tricep_extension',
  'tricep kickback': 'tricep_kickback',
  'tricep kickbacks': 'tricep_kickback',
  'close grip bench': 'close_grip_bench_press',
  'close grip bench press': 'close_grip_bench_press',

  // Back
  'lat pulldown': 'lat_pulldown',
  'lat pull down': 'lat_pulldown',
  'pulldown': 'lat_pulldown',
  'pull down': 'lat_pulldown',
  'wide grip lat pulldown': 'lat_pulldown',
  'close grip pulldown': 'close_grip_lat_pulldown',
  'seated row': 'seated_row',
  'cable row': 'seated_row',
  'low row': 'seated_row',
  'seated cable row': 'seated_row',
  'bent over row': 'barbell_row',
  'barbell row': 'barbell_row',
  'bb row': 'barbell_row',
  'bent over barbell row': 'barbell_row',
  'dumbbell row': 'dumbbell_row',
  'db row': 'dumbbell_row',
  'single arm row': 'dumbbell_row',
  'one arm dumbbell row': 'dumbbell_row',
  'pull ups': 'pull_up',
  'pullups': 'pull_up',
  'pull up': 'pull_up',
  'wide grip pull up': 'pull_up',
  'chin ups': 'chin_up',
  'chinups': 'chin_up',
  'chin up': 'chin_up',
  'face pulls': 'face_pull',
  'face pull': 'face_pull',
  'cable face pull': 'face_pull',
  't bar row': 't_bar_row',
  't-bar row': 't_bar_row',
  'pendlay row': 'pendlay_row',
  'straight arm pulldown': 'straight_arm_pulldown',

  // Legs
  'squat': 'barbell_back_squat',
  'squats': 'barbell_back_squat',
  'back squat': 'barbell_back_squat',
  'back squats': 'barbell_back_squat',
  'barbell squat': 'barbell_back_squat',
  'barbell back squat': 'barbell_back_squat',
  'front squat': 'front_squat',
  'front squats': 'front_squat',
  'barbell front squat': 'front_squat',
  'goblet squat': 'goblet_squat',
  'goblet squats': 'goblet_squat',
  'hack squat': 'hack_squat',
  'hack squats': 'hack_squat',
  'leg press': 'leg_press',
  'leg extension': 'leg_extension',
  'leg extensions': 'leg_extension',
  'quad extension': 'leg_extension',
  'leg curl': 'leg_curl',
  'leg curls': 'leg_curl',
  'hamstring curl': 'leg_curl',
  'hamstring curls': 'leg_curl',
  'lying leg curl': 'leg_curl',
  'seated leg curl': 'seated_leg_curl',
  'deadlift': 'conventional_deadlift',
  'deadlifts': 'conventional_deadlift',
  'conventional deadlift': 'conventional_deadlift',
  'sumo deadlift': 'sumo_deadlift',
  'trap bar deadlift': 'trap_bar_deadlift',
  'hex bar deadlift': 'trap_bar_deadlift',
  'rdl': 'romanian_deadlift',
  'romanian deadlift': 'romanian_deadlift',
  'stiff leg deadlift': 'romanian_deadlift',
  'dumbbell rdl': 'dumbbell_romanian_deadlift',
  'lunges': 'walking_lunge',
  'lunge': 'walking_lunge',
  'walking lunges': 'walking_lunge',
  'walking lunge': 'walking_lunge',
  'reverse lunge': 'reverse_lunge',
  'reverse lunges': 'reverse_lunge',
  'bulgarian split squat': 'bulgarian_split_squat',
  'split squat': 'bulgarian_split_squat',
  'step up': 'step_up',
  'step ups': 'step_up',
  'calf raise': 'calf_raise',
  'calf raises': 'calf_raise',
  'standing calf raise': 'calf_raise',
  'seated calf raise': 'seated_calf_raise',
  'hip thrust': 'hip_thrust',
  'hip thrusts': 'hip_thrust',
  'barbell hip thrust': 'hip_thrust',
  'glute bridge': 'glute_bridge',
  'glute bridges': 'glute_bridge',
  'glute ham raise': 'glute_ham_raise',
  'ghr': 'glute_ham_raise',
  'good morning': 'good_morning',
  'good mornings': 'good_morning',

  // Biceps
  'bicep curl': 'dumbbell_bicep_curl',
  'bicep curls': 'dumbbell_bicep_curl',
  'biceps curl': 'dumbbell_bicep_curl',
  'curls': 'dumbbell_bicep_curl',
  'curl': 'dumbbell_bicep_curl',
  'dumbbell curl': 'dumbbell_bicep_curl',
  'dumbbell curls': 'dumbbell_bicep_curl',
  'hammer curl': 'hammer_curl',
  'hammer curls': 'hammer_curl',
  'preacher curl': 'preacher_curl',
  'preacher curls': 'preacher_curl',
  'ez bar preacher curl': 'preacher_curl',
  'dumbbell preacher curl': 'dumbbell_preacher_curl',
  'barbell curl': 'barbell_curl',
  'barbell curls': 'barbell_curl',
  'ez bar curl': 'ez_bar_curl',
  'ez curl': 'ez_bar_curl',
  'incline curl': 'incline_dumbbell_curl',
  'incline dumbbell curl': 'incline_dumbbell_curl',
  'cable curl': 'cable_curl',
  'cable curls': 'cable_curl',
  'concentration curl': 'concentration_curl',
  'concentration curls': 'concentration_curl',

  // Core
  'plank': 'plank',
  'planks': 'plank',
  'front plank': 'plank',
  'side plank': 'side_plank',
  'crunches': 'crunch',
  'crunch': 'crunch',
  'ab crunch': 'crunch',
  'cable crunch': 'cable_crunch',
  'cable crunches': 'cable_crunch',
  'sit ups': 'sit_up',
  'sit up': 'sit_up',
  'situps': 'sit_up',
  'situp': 'sit_up',
  'leg raise': 'hanging_leg_raise',
  'leg raises': 'hanging_leg_raise',
  'hanging leg raise': 'hanging_leg_raise',
  'hanging leg raises': 'hanging_leg_raise',
  'lying leg raise': 'lying_leg_raise',
  'russian twist': 'russian_twist',
  'russian twists': 'russian_twist',
  'ab wheel': 'ab_wheel_rollout',
  'ab rollout': 'ab_wheel_rollout',
  'ab wheel rollout': 'ab_wheel_rollout',
  'cable woodchop': 'cable_woodchop',
  'woodchop': 'cable_woodchop',
  'dead bug': 'dead_bug',
  'bird dog': 'bird_dog',

  // Shoulders
  'shrugs': 'dumbbell_shrug',
  'shrug': 'dumbbell_shrug',
  'dumbbell shrug': 'dumbbell_shrug',
  'dumbbell shrugs': 'dumbbell_shrug',
  'barbell shrug': 'barbell_shrug',
  'barbell shrugs': 'barbell_shrug',
  'upright row': 'upright_row',
  'upright rows': 'upright_row',
  'barbell upright row': 'upright_row',
  'rear delt fly': 'rear_delt_fly',
  'rear delt flys': 'rear_delt_fly',
  'reverse fly': 'rear_delt_fly',
  'reverse flys': 'rear_delt_fly',
  'bent over reverse fly': 'rear_delt_fly',
  'arnold press': 'arnold_press',
  'arnold presses': 'arnold_press',
  'dumbbell arnold press': 'arnold_press',
  'seated dumbbell press': 'dual_dumbbell_seated_press',
  'seated shoulder press': 'dual_dumbbell_seated_press',

  // Cardio
  'treadmill': 'treadmill_run',
  'treadmill run': 'treadmill_run',
  'run': 'outdoor_run',
  'running': 'outdoor_run',
  'stationary bike': 'stationary_bike',
  'bike': 'stationary_bike',
  'assault bike': 'assault_bike',
  'air bike': 'assault_bike',
  'rowing': 'rower',
  'rowing machine': 'rower',
  'row machine': 'rower',
  'elliptical': 'elliptical',
  'stair climber': 'stair_climber',
  'stairmaster': 'stair_climber',
  'jump rope': 'jump_rope',
  'skipping': 'jump_rope',

  // Misc compound
  'push up': 'push_up',
  'push ups': 'push_up',
  'pushup': 'push_up',
  'pushups': 'push_up',
  'kettlebell swing': 'kettlebell_swing',
  'kb swing': 'kettlebell_swing',
  'farmers carry': 'farmers_carry',
  'farmers walk': 'farmers_carry',
  'box jump': 'box_jump',
  'box jumps': 'box_jump',
  'burpee': 'burpee',
  'burpees': 'burpee',
  'mountain climber': 'mountain_climber',
  'mountain climbers': 'mountain_climber',
};

// ============================================================================
// Name Matching (v255: Vision import support)
// ============================================================================

/**
 * Try to match an exercise name to an ID
 * Returns matched exercise or null if no match found
 */
async function matchExerciseByName(
  db: admin.firestore.Firestore,
  inputName: string,
  availableEquipment: Equipment[] | undefined,
  isBodyweightOnly: boolean
): Promise<ExerciseDoc | null> {
  // Normalize input: lowercase, convert underscores to spaces, remove extra spaces
  // v256: Convert underscores BEFORE removing special chars so "incline_press" → "incline press"
  const normalized = inputName
    .toLowerCase()
    .replace(/_/g, ' ')
    .replace(/[^a-z0-9\s]/g, '')
    .replace(/\s+/g, ' ')
    .trim();

  console.log(`[ExerciseSelector] Matching name: "${inputName}" → normalized: "${normalized}"`);

  // 1. Try common mappings first (fastest)
  const mappedId = EXERCISE_NAME_MAPPINGS[normalized];
  if (mappedId) {
    const doc = await db.collection('exercises').doc(mappedId).get();
    if (doc.exists) {
      const data = doc.data()!;
      const exercise: ExerciseDoc = {
        id: doc.id,
        name: data.name || doc.id,
        muscleGroups: data.muscleGroups || [],
        exerciseType: data.exerciseType || 'compound',
        equipment: data.equipment || 'barbell',
        baseExercise: data.baseExercise,
      };

      // Check equipment compatibility
      if (passesEquipmentFilter(exercise, availableEquipment, isBodyweightOnly)) {
        console.log(`[ExerciseSelector] Mapped "${inputName}" → "${doc.id}"`);
        return exercise;
      } else {
        console.log(`[ExerciseSelector] Mapped "${inputName}" → "${doc.id}" but equipment mismatch`);
      }
    }
  }

  // 2. Try partial word matching in the mapping keys
  const normalizedWords = normalized.split(' ').filter(w => w.length > 2);
  for (const [key, id] of Object.entries(EXERCISE_NAME_MAPPINGS)) {
    const keyWords = key.split(' ').filter(w => w.length > 2);
    const matchedWords = normalizedWords.filter(word =>
      keyWords.some(kw => kw.includes(word) || word.includes(kw))
    );

    // If 60%+ of words match, try this ID
    if (matchedWords.length >= Math.ceil(normalizedWords.length * 0.6)) {
      const doc = await db.collection('exercises').doc(id).get();
      if (doc.exists) {
        const data = doc.data()!;
        const exercise: ExerciseDoc = {
          id: doc.id,
          name: data.name || doc.id,
          muscleGroups: data.muscleGroups || [],
          exerciseType: data.exerciseType || 'compound',
          equipment: data.equipment || 'barbell',
          baseExercise: data.baseExercise,
        };

        if (passesEquipmentFilter(exercise, availableEquipment, isBodyweightOnly)) {
          console.log(`[ExerciseSelector] Partial match "${inputName}" → "${doc.id}"`);
          return exercise;
        }
      }
    }
  }

  // 3. Search by name field in collection (last resort)
  if (normalized.length > 3) {
    const capitalizedFirst = normalized.charAt(0).toUpperCase() + normalized.slice(1);
    try {
      const snapshot = await db.collection('exercises')
        .orderBy('name')
        .startAt(capitalizedFirst)
        .endAt(capitalizedFirst + '\uf8ff')
        .limit(10)
        .get();

      for (const doc of snapshot.docs) {
        const data = doc.data();
        const exerciseName = (data.name || '').toLowerCase();

        // Check if exercise name contains the key words
        const matchedWords = normalizedWords.filter(word => exerciseName.includes(word));
        if (matchedWords.length >= Math.ceil(normalizedWords.length * 0.6)) {
          const exercise: ExerciseDoc = {
            id: doc.id,
            name: data.name || doc.id,
            muscleGroups: data.muscleGroups || [],
            exerciseType: data.exerciseType || 'compound',
            equipment: data.equipment || 'barbell',
            baseExercise: data.baseExercise,
          };

          if (passesEquipmentFilter(exercise, availableEquipment, isBodyweightOnly)) {
            console.log(`[ExerciseSelector] Name search matched "${inputName}" → "${doc.id}"`);
            return exercise;
          }
        }
      }
    } catch (error) {
      // Index may not exist, that's ok - we tried
      console.log(`[ExerciseSelector] Name search failed for "${inputName}":`, error);
    }
  }

  console.log(`[ExerciseSelector] No match found for "${inputName}"`);
  return null;
}

// ============================================================================
// Main Function
// ============================================================================

/**
 * Select exercises for a workout
 *
 * @param db - Firestore database instance
 * @param request - Selection request with constraints
 * @returns Selected exercises with metadata about supplementation
 */
export async function selectExercises(
  db: admin.firestore.Firestore,
  request: ExerciseSelectionRequest
): Promise<ExerciseSelectionResult> {
  const {
    splitDay,
    sessionType,
    targetCount,
    requestedExerciseIds,
    availableEquipment,
    trainingLocation,
  } = request;

  // Track base exercises to prevent duplicates (e.g., barbell + dumbbell bench press)
  const usedBaseExercises = new Set<string>();
  const selectedExercises: ExerciseDoc[] = [];

  // Determine if home workout with bodyweight only
  const isBodyweightOnly = trainingLocation === 'home' && (
    !availableEquipment ||
    availableEquipment.length === 0 ||
    (availableEquipment.length === 1 && availableEquipment[0] === 'bodyweight')
  );

  // v258: Track name matches for substitution reporting
  let nameMatches: NameMatch[] = [];

  // 1. Validate AI-provided exercises first (highest priority)
  if (requestedExerciseIds && requestedExerciseIds.length > 0) {
    const validationResult = await validateExerciseIds(
      db,
      requestedExerciseIds,
      splitDay,
      sessionType,
      availableEquipment,
      isBodyweightOnly,
      usedBaseExercises
    );
    selectedExercises.push(...validationResult.exercises);
    nameMatches = validationResult.nameMatches;
  }

  const aiExerciseCount = selectedExercises.length;

  // 2. Supplement from global catalog if needed
  if (selectedExercises.length < targetCount) {
    const supplementCount = targetCount - selectedExercises.length;
    const supplemented = await selectFromCatalog(
      db,
      splitDay,
      sessionType,
      supplementCount,
      availableEquipment,
      isBodyweightOnly,
      usedBaseExercises
    );
    selectedExercises.push(...supplemented);
  }

  const supplementedCount = selectedExercises.length - aiExerciseCount;

  console.log(
    `[ExerciseSelector] Selected ${selectedExercises.length} exercises ` +
    `(${aiExerciseCount} from AI, ${supplementedCount} supplemented)` +
    (nameMatches.length > 0 ? `, ${nameMatches.length} name-matched` : '')
  );

  return {
    exercises: selectedExercises.slice(0, targetCount),
    wasSupplemented: supplementedCount > 0,
    aiExerciseCount,
    supplementedCount,
    nameMatches: nameMatches.length > 0 ? nameMatches : undefined,
  };
}

// ============================================================================
// Validation
// ============================================================================

/**
 * Result from validateExerciseIds with name match tracking
 * v258: Track name matches for substitution reporting
 */
interface ValidationResult {
  exercises: ExerciseDoc[];
  nameMatches: NameMatch[];
}

/**
 * Validate AI-provided exercise IDs
 * Returns only exercises that exist and pass all filters
 *
 * v255: Now supports name matching as fallback for vision import
 * When exact ID lookup fails, treats input as exercise name and tries to match
 * v258: Returns name matches for substitution reporting
 */
async function validateExerciseIds(
  db: admin.firestore.Firestore,
  exerciseIds: string[],
  splitDay: SplitDay,
  sessionType: SessionType,
  availableEquipment: Equipment[] | undefined,
  isBodyweightOnly: boolean,
  usedBaseExercises: Set<string>
): Promise<ValidationResult> {
  const validExercises: ExerciseDoc[] = [];
  const nameMatches: NameMatch[] = [];
  const targetMuscles = new Set(SPLIT_DAY_MUSCLES[splitDay]);

  for (const exerciseId of exerciseIds) {
    let exercise: ExerciseDoc | null = null;
    let wasNameMatched = false;

    // 1. Try exact ID lookup first (standard path)
    const exerciseDoc = await db.collection('exercises').doc(exerciseId).get();

    if (exerciseDoc.exists) {
      const data = exerciseDoc.data()!;
      exercise = {
        id: exerciseDoc.id,
        name: data.name || exerciseId,
        muscleGroups: data.muscleGroups || [],
        exerciseType: data.exerciseType || 'compound',
        equipment: data.equipment || 'barbell',
        baseExercise: data.baseExercise || data.name || exerciseId,
      };
    } else {
      // 2. ID not found - try matching by name (v255: vision import support)
      console.log(`[ExerciseSelector] ID '${exerciseId}' not found, trying name match`);
      exercise = await matchExerciseByName(
        db,
        exerciseId, // Treat the "ID" as a name
        availableEquipment,
        isBodyweightOnly
      );
      wasNameMatched = true;
    }

    if (!exercise) {
      console.log(`[ExerciseSelector] Rejecting '${exerciseId}' - not found and no name match`);
      continue;
    }

    // Check equipment filter
    if (!passesEquipmentFilter(exercise, availableEquipment, isBodyweightOnly)) {
      console.log(`[ExerciseSelector] Rejecting ${exercise.id} - equipment mismatch`);
      continue;
    }

    // Check muscle group filter (skip for cardio)
    if (sessionType !== 'cardio') {
      if (!passesMuscleFilter(exercise, targetMuscles)) {
        console.log(`[ExerciseSelector] Rejecting ${exercise.id} - muscle mismatch for ${splitDay}`);
        continue;
      }
    }

    // Check for duplicate base exercise
    const baseExercise = exercise.baseExercise || exercise.id;
    if (usedBaseExercises.has(baseExercise)) {
      console.log(`[ExerciseSelector] Rejecting ${exercise.id} - duplicate base exercise ${baseExercise}`);
      continue;
    }

    usedBaseExercises.add(baseExercise);
    validExercises.push(exercise);

    // v258: Track name match for substitution reporting
    if (wasNameMatched) {
      nameMatches.push({
        requestedName: exerciseId,
        matchedId: exercise.id,
        matchedName: exercise.name,
      });
    }
  }

  return { exercises: validExercises, nameMatches };
}

// ============================================================================
// Catalog Selection
// ============================================================================

/**
 * Select exercises from global catalog
 * Used to supplement AI-provided exercises
 */
async function selectFromCatalog(
  db: admin.firestore.Firestore,
  splitDay: SplitDay,
  sessionType: SessionType,
  targetCount: number,
  availableEquipment: Equipment[] | undefined,
  isBodyweightOnly: boolean,
  usedBaseExercises: Set<string>
): Promise<ExerciseDoc[]> {
  const targetMuscles = new Set(SPLIT_DAY_MUSCLES[splitDay]);
  const exercisesRef = db.collection('exercises');

  // Query based on session type
  let query: admin.firestore.Query = exercisesRef;
  if (sessionType === 'cardio') {
    query = query.where('exerciseType', '==', 'cardio');
  }

  const snapshot = await query.limit(100).get();
  const candidates: ExerciseDoc[] = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();

    const exercise: ExerciseDoc = {
      id: doc.id,
      name: data.name || doc.id,
      muscleGroups: data.muscleGroups || [],
      exerciseType: data.exerciseType || 'compound',
      equipment: data.equipment || 'barbell',
      baseExercise: data.baseExercise || data.name || doc.id,
    };

    // Skip cardio for strength workouts
    if (sessionType !== 'cardio' && exercise.exerciseType === 'cardio') {
      continue;
    }

    // Check equipment filter
    if (!passesEquipmentFilter(exercise, availableEquipment, isBodyweightOnly)) {
      continue;
    }

    // Check muscle group filter (skip for cardio)
    if (sessionType !== 'cardio') {
      if (!passesMuscleFilter(exercise, targetMuscles)) {
        continue;
      }
    }

    // Check for duplicate base exercise
    const baseExercise = exercise.baseExercise || exercise.id;
    if (usedBaseExercises.has(baseExercise)) {
      continue;
    }

    candidates.push(exercise);
  }

  // Sort: compounds first, then by name for consistency
  candidates.sort((a, b) => {
    if (a.exerciseType === 'compound' && b.exerciseType !== 'compound') return -1;
    if (a.exerciseType !== 'compound' && b.exerciseType === 'compound') return 1;
    return a.name.localeCompare(b.name);
  });

  // Select and mark as used
  const selected: ExerciseDoc[] = [];
  for (const exercise of candidates) {
    if (selected.length >= targetCount) break;
    const base = exercise.baseExercise || exercise.id;
    usedBaseExercises.add(base);
    selected.push(exercise);
  }

  return selected;
}

// ============================================================================
// Filters
// ============================================================================

/**
 * Check if exercise passes equipment filter
 */
function passesEquipmentFilter(
  exercise: ExerciseDoc,
  availableEquipment: Equipment[] | undefined,
  isBodyweightOnly: boolean
): boolean {
  // Bodyweight-only mode (home with no equipment)
  if (isBodyweightOnly) {
    return exercise.equipment === 'bodyweight' || exercise.equipment === 'none';
  }

  // No filter specified - allow all
  if (!availableEquipment || availableEquipment.length === 0) {
    return true;
  }

  // Bodyweight always allowed
  if (exercise.equipment === 'bodyweight' || exercise.equipment === 'none') {
    return true;
  }

  // Check if equipment is in available list
  return availableEquipment.includes(exercise.equipment);
}

/**
 * Check if exercise targets any of the split day muscles
 */
function passesMuscleFilter(
  exercise: ExerciseDoc,
  targetMuscles: Set<string>
): boolean {
  // If no target muscles defined (notApplicable), allow all
  if (targetMuscles.size === 0) {
    return true;
  }

  // Check for any muscle overlap
  return exercise.muscleGroups.some((muscle) => targetMuscles.has(muscle));
}

// ============================================================================
// Utility
// ============================================================================

/**
 * Calculate exercise count from target duration
 * Uses formula-based approach (no iteration)
 */
export function calculateExerciseCount(
  targetDuration: number,
  primaryEquipment: Equipment = 'barbell'
): number {
  // Average time per exercise based on equipment
  const avgTimes: Record<Equipment, number> = {
    bodyweight: 8.0,
    resistanceBand: 8.0,
    cable: 8.5,
    machine: 8.0,
    dumbbells: 9.0,
    barbell: 9.5,
    kettlebell: 8.5,
    none: 8.0,
  };

  const avgTime = avgTimes[primaryEquipment] || 9.0;
  const rawCount = Math.floor(targetDuration / avgTime);

  // Clamp to reasonable range (3-8 exercises)
  return Math.max(3, Math.min(8, rawCount));
}

/**
 * Determine primary equipment from training location and available equipment
 */
export function determinePrimaryEquipment(
  trainingLocation?: TrainingLocation,
  availableEquipment?: Equipment[]
): Equipment {
  // If only bodyweight available
  if (availableEquipment) {
    const nonBodyweight = availableEquipment.filter((e) => e !== 'bodyweight' && e !== 'none');
    if (nonBodyweight.length === 0) {
      return 'bodyweight';
    }
    // Return first available non-bodyweight equipment
    if (nonBodyweight.length > 0) {
      return nonBodyweight[0];
    }
  }

  // Infer from location
  if (trainingLocation === 'home') {
    return 'bodyweight';
  }

  // Default to barbell (gym assumption)
  return 'barbell';
}

type TrainingLocation = 'home' | 'gym' | 'outdoor' | 'hybrid';
