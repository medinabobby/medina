/**
 * Superset Pairer Service
 *
 * v236: Migrated from iOS SupersetPairingService.swift
 *
 * Creates superset groups for workouts based on:
 * - Auto-pair mode: System pairs exercises based on style (antagonist, agonist, etc.)
 * - Explicit mode: User specifies exact pairings with custom rest times
 * - Circuit mode: All exercises in one circuit
 *
 * Key features:
 * - Pairing algorithms based on muscle groups and movement patterns
 * - Scoring system to find optimal pairs
 * - Reorders exercises to make superset pairs adjacent
 */

import type * as admin from 'firebase-admin';

// ============================================================================
// Types
// ============================================================================

/**
 * Superset style options
 */
export type SupersetStyle =
  | 'none'           // No supersets
  | 'explicit'       // User-specified pairings
  | 'circuit'        // All exercises in one group
  | 'antagonist'     // Push-pull, opposing muscles
  | 'agonist'        // Same muscle group (compound + isolation)
  | 'compoundIsolation';  // Any compound with any isolation

/**
 * Explicit superset group from AI tool call
 */
export interface SupersetGroupIntent {
  positions: number[];    // Exercise positions (0-indexed) to pair
  restBetween: number;    // Rest in seconds between exercises (1a→1b)
  restAfter: number;      // Rest in seconds after completing full rotation
}

/**
 * Superset group in workout
 */
export interface SupersetGroup {
  id: string;
  groupNumber: number;
  exercisePositions: number[];
  restBetweenExercises: number[];  // Rest after each exercise in group
}

/**
 * Exercise info for pairing analysis
 */
export interface ExerciseInfo {
  id: string;
  position: number;
  exerciseType: 'compound' | 'isolation' | 'cardio';
  muscleGroups: string[];
  movementPattern?: string;
  equipment?: string;
  baseExercise?: string;
}

/**
 * Result of superset creation
 */
export interface SupersetResult {
  groups: SupersetGroup[] | null;
  reorderedExerciseIds: string[];
}

// ============================================================================
// Constants
// ============================================================================

/**
 * Default rest times by style (seconds)
 */
const DEFAULT_REST: Record<SupersetStyle, { between: number; after: number }> = {
  none: { between: 0, after: 0 },
  explicit: { between: 15, after: 90 },
  circuit: { between: 15, after: 120 },
  antagonist: { between: 30, after: 90 },
  agonist: { between: 15, after: 120 },
  compoundIsolation: { between: 30, after: 90 },
};

/**
 * Antagonist muscle pairs (push-pull)
 */
const ANTAGONIST_MUSCLES: Array<[string, string]> = [
  ['chest', 'back'],
  ['chest', 'lats'],
  ['biceps', 'triceps'],
  ['quadriceps', 'hamstrings'],
  ['shoulders', 'back'],
  ['shoulders', 'lats'],
  // Lower-upper complementary pairs
  ['quadriceps', 'lats'],
  ['quadriceps', 'back'],
  ['glutes', 'lats'],
  ['glutes', 'back'],
  ['hamstrings', 'lats'],
  ['hamstrings', 'back'],
];

/**
 * Movement pattern antagonist pairs
 */
const MOVEMENT_ANTAGONISTS: Array<[string, string]> = [
  ['horizontalPress', 'horizontalPull'],
  ['verticalPress', 'verticalPull'],
  ['push', 'pull'],
  ['squat', 'hinge'],
  // Complementary (lower + upper)
  ['squat', 'verticalPull'],
  ['squat', 'horizontalPull'],
  ['hinge', 'verticalPull'],
  ['hinge', 'horizontalPull'],
];

// ============================================================================
// Main Entry Point
// ============================================================================

/**
 * Create superset groups from exercise list
 *
 * @param exerciseIds - Array of exercise IDs in workout order
 * @param exercises - Exercise info for pairing analysis
 * @param style - SupersetStyle (antagonist, agonist, circuit, explicit, none)
 * @param explicitGroups - User-specified groupings (only for explicit mode)
 * @returns Superset groups and reordered exercise IDs
 */
export function createSupersets(
  exerciseIds: string[],
  exercises: ExerciseInfo[],
  style: SupersetStyle,
  explicitGroups?: SupersetGroupIntent[]
): SupersetResult {
  // No supersets
  if (style === 'none') {
    return { groups: null, reorderedExerciseIds: exerciseIds };
  }

  let groups: SupersetGroup[] | null = null;

  switch (style) {
    case 'explicit':
      groups = createExplicitGroups(explicitGroups, exerciseIds.length);
      break;

    case 'circuit':
      groups = createCircuitGroup(exerciseIds.length, style);
      break;

    case 'antagonist':
    case 'agonist':
    case 'compoundIsolation':
      // Auto-pair modes need minimum 4 exercises for 2 pairs
      if (exercises.length >= 4) {
        groups = createAutoPairedGroups(exercises, style);
      }
      break;
  }

  if (!groups || groups.length === 0) {
    return { groups: null, reorderedExerciseIds: exerciseIds };
  }

  // Reorder exercises so superset pairs are adjacent
  const { reorderedIds, updatedGroups } = reorderForAdjacentPairs(exerciseIds, groups);

  return {
    groups: updatedGroups,
    reorderedExerciseIds: reorderedIds,
  };
}

// ============================================================================
// Explicit Mode
// ============================================================================

/**
 * Convert user-specified groupings to SupersetGroup objects
 */
function createExplicitGroups(
  intents: SupersetGroupIntent[] | undefined,
  exerciseCount: number
): SupersetGroup[] | null {
  if (!intents || intents.length === 0) {
    return null;
  }

  const groups: SupersetGroup[] = [];
  const usedPositions = new Set<number>();

  for (let index = 0; index < intents.length; index++) {
    const intent = intents[index];

    // Validate positions are within bounds
    const validPositions = intent.positions.filter(
      (pos) => pos >= 0 && pos < exerciseCount
    );
    if (validPositions.length < 2) {
      continue;
    }

    // Filter out positions already used by previous groups
    const availablePositions = validPositions.filter((pos) => !usedPositions.has(pos));
    if (availablePositions.length < 2) {
      continue;
    }

    // Mark positions as used
    availablePositions.forEach((pos) => usedPositions.add(pos));

    // Create rest array - restBetween for all except last, restAfter for last
    const restDurations = availablePositions.map((_, i) =>
      i === availablePositions.length - 1 ? intent.restAfter : intent.restBetween
    );

    groups.push({
      id: `explicit_superset_${index + 1}`,
      groupNumber: index + 1,
      exercisePositions: availablePositions,
      restBetweenExercises: restDurations,
    });
  }

  return groups.length > 0 ? groups : null;
}

// ============================================================================
// Circuit Mode
// ============================================================================

/**
 * Create a single circuit group containing all exercises
 */
function createCircuitGroup(
  exerciseCount: number,
  style: SupersetStyle
): SupersetGroup[] | null {
  if (exerciseCount < 2) {
    return null;
  }

  const positions = Array.from({ length: exerciseCount }, (_, i) => i);
  const restTimes = DEFAULT_REST[style];

  // All exercises get short rest, last one gets longer rest
  const restDurations = positions.map((_, i) =>
    i === exerciseCount - 1 ? restTimes.after : restTimes.between
  );

  return [{
    id: 'circuit_group_1',
    groupNumber: 1,
    exercisePositions: positions,
    restBetweenExercises: restDurations,
  }];
}

// ============================================================================
// Auto-Pair Mode
// ============================================================================

/**
 * Create superset groups using system-determined pairings
 */
function createAutoPairedGroups(
  exercises: ExerciseInfo[],
  style: SupersetStyle
): SupersetGroup[] | null {
  // Find pairs based on style
  let pairs: Array<{ pos1: number; pos2: number; score: number }>;

  switch (style) {
    case 'antagonist':
      pairs = findAntagonistPairs(exercises);
      break;
    case 'agonist':
      pairs = findAgonistPairs(exercises);
      break;
    case 'compoundIsolation':
      pairs = findCompoundIsolationPairs(exercises);
      break;
    default:
      return null;
  }

  if (pairs.length === 0) {
    return null;
  }

  // Convert pairs to SupersetGroups (limit to 2 pairs per workout)
  return createGroupsFromPairs(pairs, style, 2);
}

// ============================================================================
// Pairing Algorithms
// ============================================================================

/**
 * Find antagonist pairs (push-pull, opposing muscles)
 */
function findAntagonistPairs(
  exercises: ExerciseInfo[]
): Array<{ pos1: number; pos2: number; score: number }> {
  const candidates: Array<{ pos1: number; pos2: number; score: number }> = [];

  for (let i = 0; i < exercises.length; i++) {
    for (let j = i + 1; j < exercises.length; j++) {
      const ex1 = exercises[i];
      const ex2 = exercises[j];

      // Skip if same base exercise
      if (ex1.baseExercise && ex1.baseExercise === ex2.baseExercise) {
        continue;
      }

      let score = 0;

      // Movement pattern matching (highest weight: 0.5)
      if (ex1.movementPattern && ex2.movementPattern) {
        if (isMovementAntagonist(ex1.movementPattern, ex2.movementPattern)) {
          score += 0.5;
        }
      }

      // Muscle group opposition (weight: 0.35)
      const primary1 = ex1.muscleGroups[0];
      const primary2 = ex2.muscleGroups[0];
      if (primary1 && primary2) {
        score += antagonistMuscleScore(primary1, primary2) * 0.35;
      }

      // Equipment compatibility bonus (weight: 0.15)
      if (ex1.equipment && ex2.equipment &&
          ex1.equipment === ex2.equipment &&
          ex1.equipment !== 'bodyweight') {
        score += 0.15;
      }

      // Only include if score is meaningful
      if (score >= 0.4) {
        candidates.push({ pos1: ex1.position, pos2: ex2.position, score });
      }
    }
  }

  return candidates.sort((a, b) => b.score - a.score);
}

/**
 * Find agonist pairs (same muscle group - compound + isolation)
 */
function findAgonistPairs(
  exercises: ExerciseInfo[]
): Array<{ pos1: number; pos2: number; score: number }> {
  const candidates: Array<{ pos1: number; pos2: number; score: number }> = [];

  for (let i = 0; i < exercises.length; i++) {
    for (let j = i + 1; j < exercises.length; j++) {
      const ex1 = exercises[i];
      const ex2 = exercises[j];

      // Must have at least one isolation for safety
      if (ex1.exerciseType !== 'isolation' && ex2.exerciseType !== 'isolation') {
        continue;
      }

      // Must target same primary muscle
      const primary1 = ex1.muscleGroups[0];
      const primary2 = ex2.muscleGroups[0];
      if (!primary1 || !primary2 || primary1 !== primary2) {
        continue;
      }

      // Different base exercise
      if (ex1.baseExercise && ex1.baseExercise === ex2.baseExercise) {
        continue;
      }

      let score = 0.6; // Base score for valid agonist pair

      // Compound + isolation is ideal
      if (ex1.exerciseType !== ex2.exerciseType) {
        score += 0.25;
      }

      // Equipment compatibility bonus
      if (ex1.equipment === ex2.equipment) {
        score += 0.1;
      }

      candidates.push({ pos1: ex1.position, pos2: ex2.position, score });
    }
  }

  return candidates.sort((a, b) => b.score - a.score);
}

/**
 * Find compound-isolation pairs (any compound with any isolation)
 */
function findCompoundIsolationPairs(
  exercises: ExerciseInfo[]
): Array<{ pos1: number; pos2: number; score: number }> {
  const candidates: Array<{ pos1: number; pos2: number; score: number }> = [];

  const compounds = exercises.filter((e) => e.exerciseType === 'compound');
  const isolations = exercises.filter((e) => e.exerciseType === 'isolation');

  for (const compound of compounds) {
    for (const isolation of isolations) {
      let score = 0.5; // Base score

      // Same primary muscle is ideal (post-exhaust)
      const primary1 = compound.muscleGroups[0];
      const primary2 = isolation.muscleGroups[0];
      if (primary1 && primary2 && primary1 === primary2) {
        score += 0.3;
      } else {
        score += 0.15; // Different muscles still useful (active recovery)
      }

      // Equipment compatibility
      if (compound.equipment === isolation.equipment) {
        score += 0.1;
      }

      candidates.push({ pos1: compound.position, pos2: isolation.position, score });
    }
  }

  return candidates.sort((a, b) => b.score - a.score);
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Check if two movement patterns are antagonists
 */
function isMovementAntagonist(p1: string, p2: string): boolean {
  return MOVEMENT_ANTAGONISTS.some(
    ([a, b]) => (p1 === a && p2 === b) || (p1 === b && p2 === a)
  );
}

/**
 * Calculate antagonist score between two muscle groups
 */
function antagonistMuscleScore(m1: string, m2: string): number {
  // Perfect pairs (1.0)
  const isPerfect = ANTAGONIST_MUSCLES.slice(0, 5).some(
    ([a, b]) => (m1 === a && m2 === b) || (m1 === b && m2 === a)
  );
  if (isPerfect) return 1.0;

  // Good pairs (0.7)
  const isGood = ANTAGONIST_MUSCLES.slice(5).some(
    ([a, b]) => (m1 === a && m2 === b) || (m1 === b && m2 === a)
  );
  if (isGood) return 0.7;

  // Same muscle = avoid for antagonist
  if (m1 === m2) return 0.0;

  // Neutral
  return 0.3;
}

/**
 * Convert scored pairs into SupersetGroup objects
 */
function createGroupsFromPairs(
  pairs: Array<{ pos1: number; pos2: number; score: number }>,
  style: SupersetStyle,
  maxGroups: number
): SupersetGroup[] | null {
  const usedPositions = new Set<number>();
  const groups: SupersetGroup[] = [];
  const restTimes = DEFAULT_REST[style];

  for (const pair of pairs) {
    if (groups.length >= maxGroups) break;

    // Skip if either position already used
    if (usedPositions.has(pair.pos1) || usedPositions.has(pair.pos2)) {
      continue;
    }

    groups.push({
      id: `superset_${groups.length + 1}`,
      groupNumber: groups.length + 1,
      exercisePositions: [pair.pos1, pair.pos2],
      restBetweenExercises: [restTimes.between, restTimes.after],
    });

    usedPositions.add(pair.pos1);
    usedPositions.add(pair.pos2);
  }

  return groups.length > 0 ? groups : null;
}

// ============================================================================
// Reordering
// ============================================================================

/**
 * Reorder exercises so superset pairs are adjacent, then update group positions
 */
function reorderForAdjacentPairs(
  exerciseIds: string[],
  groups: SupersetGroup[]
): { reorderedIds: string[]; updatedGroups: SupersetGroup[] } {
  if (groups.length === 0) {
    return { reorderedIds: exerciseIds, updatedGroups: groups };
  }

  const reorderedIds: string[] = [];
  const updatedGroups: SupersetGroup[] = [];
  const usedOriginalPositions = new Set<number>();

  // First, add superset pairs in order
  for (const group of groups.sort((a, b) => a.groupNumber - b.groupNumber)) {
    const newPositions: number[] = [];

    for (const originalPos of group.exercisePositions) {
      if (originalPos >= exerciseIds.length) continue;
      if (usedOriginalPositions.has(originalPos)) continue;

      reorderedIds.push(exerciseIds[originalPos]);
      newPositions.push(reorderedIds.length - 1);
      usedOriginalPositions.add(originalPos);
    }

    if (newPositions.length >= 2) {
      updatedGroups.push({
        ...group,
        exercisePositions: newPositions,
      });
    }
  }

  // Then add unpaired exercises at the end
  for (let i = 0; i < exerciseIds.length; i++) {
    if (!usedOriginalPositions.has(i)) {
      reorderedIds.push(exerciseIds[i]);
    }
  }

  return { reorderedIds, updatedGroups };
}

// ============================================================================
// Firestore Integration
// ============================================================================

/**
 * Load exercise info from Firestore for pairing analysis
 */
export async function loadExerciseInfo(
  db: admin.firestore.Firestore,
  exerciseIds: string[]
): Promise<ExerciseInfo[]> {
  const exercises: ExerciseInfo[] = [];

  for (let i = 0; i < exerciseIds.length; i++) {
    const doc = await db.collection('exercises').doc(exerciseIds[i]).get();
    if (doc.exists) {
      const data = doc.data()!;
      exercises.push({
        id: doc.id,
        position: i,
        exerciseType: data.exerciseType || 'compound',
        muscleGroups: data.muscleGroups || [],
        movementPattern: data.movementPattern,
        equipment: data.equipment,
        baseExercise: data.baseExercise,
      });
    }
  }

  return exercises;
}
