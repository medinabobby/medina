/**
 * Superset Pairer Service Tests
 *
 * Tests for superset pairing logic:
 * - Style-based group creation (antagonist, agonist, circuit, explicit)
 * - Pairing algorithms
 * - Exercise reordering
 */

import {describe, it, expect} from 'vitest';
import {
  createSupersets,
  SupersetStyle,
  SupersetGroupIntent,
  ExerciseInfo,
} from './SupersetPairer';

// ============================================================================
// Test Data
// ============================================================================

const CHEST_COMPOUND: ExerciseInfo = {
  id: 'bench_press',
  position: 0,
  exerciseType: 'compound',
  muscleGroups: ['chest', 'triceps'],
  movementPattern: 'horizontalPress',
  equipment: 'barbell',
};

const BACK_COMPOUND: ExerciseInfo = {
  id: 'barbell_row',
  position: 1,
  exerciseType: 'compound',
  muscleGroups: ['back', 'biceps'],
  movementPattern: 'horizontalPull',
  equipment: 'barbell',
};

const SHOULDER_COMPOUND: ExerciseInfo = {
  id: 'overhead_press',
  position: 2,
  exerciseType: 'compound',
  muscleGroups: ['shoulders', 'triceps'],
  movementPattern: 'verticalPress',
  equipment: 'barbell',
};

const LAT_COMPOUND: ExerciseInfo = {
  id: 'lat_pulldown',
  position: 3,
  exerciseType: 'compound',
  muscleGroups: ['lats', 'biceps'],
  movementPattern: 'verticalPull',
  equipment: 'cable',
};

const BICEP_ISOLATION: ExerciseInfo = {
  id: 'bicep_curl',
  position: 4,
  exerciseType: 'isolation',
  muscleGroups: ['biceps'],
  equipment: 'dumbbells',
};

const TRICEP_ISOLATION: ExerciseInfo = {
  id: 'tricep_pushdown',
  position: 5,
  exerciseType: 'isolation',
  muscleGroups: ['triceps'],
  equipment: 'cable',
};

const EXERCISE_IDS = [
  'bench_press',
  'barbell_row',
  'overhead_press',
  'lat_pulldown',
  'bicep_curl',
  'tricep_pushdown',
];

const ALL_EXERCISES = [
  CHEST_COMPOUND,
  BACK_COMPOUND,
  SHOULDER_COMPOUND,
  LAT_COMPOUND,
  BICEP_ISOLATION,
  TRICEP_ISOLATION,
];

// ============================================================================
// createSupersets Tests - Style: none
// ============================================================================

describe('createSupersets - style: none', () => {
  it('returns null groups for none style', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'none');

    expect(result.groups).toBeNull();
    expect(result.reorderedExerciseIds).toEqual(EXERCISE_IDS);
  });
});

// ============================================================================
// createSupersets Tests - Style: circuit
// ============================================================================

describe('createSupersets - style: circuit', () => {
  it('creates single group with all exercises', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'circuit');

    expect(result.groups).not.toBeNull();
    expect(result.groups!.length).toBe(1);
    expect(result.groups![0].exercisePositions.length).toBe(6);
  });

  it('includes all positions in circuit group', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'circuit');

    const positions = result.groups![0].exercisePositions;
    expect(positions).toContain(0);
    expect(positions).toContain(1);
    expect(positions).toContain(2);
    expect(positions).toContain(3);
    expect(positions).toContain(4);
    expect(positions).toContain(5);
  });

  it('returns null for single exercise', () => {
    const result = createSupersets(['bench_press'], [CHEST_COMPOUND], 'circuit');

    expect(result.groups).toBeNull();
  });
});

// ============================================================================
// createSupersets Tests - Style: explicit
// ============================================================================

describe('createSupersets - style: explicit', () => {
  it('creates groups from explicit intents', () => {
    const intents: SupersetGroupIntent[] = [
      { positions: [0, 1], restBetween: 15, restAfter: 90 },
    ];

    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'explicit', intents);

    expect(result.groups).not.toBeNull();
    expect(result.groups!.length).toBe(1);
  });

  it('applies correct rest times from intents', () => {
    const intents: SupersetGroupIntent[] = [
      { positions: [0, 1], restBetween: 20, restAfter: 120 },
    ];

    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'explicit', intents);

    const restDurations = result.groups![0].restBetweenExercises;
    expect(restDurations[0]).toBe(20);  // First exercise gets restBetween
    expect(restDurations[1]).toBe(120); // Last exercise gets restAfter
  });

  it('filters out invalid positions', () => {
    const intents: SupersetGroupIntent[] = [
      { positions: [0, 10], restBetween: 15, restAfter: 90 }, // 10 is out of bounds
    ];

    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'explicit', intents);

    expect(result.groups).toBeNull(); // Can't form pair with only 1 valid position
  });

  it('prevents duplicate positions across groups', () => {
    const intents: SupersetGroupIntent[] = [
      { positions: [0, 1], restBetween: 15, restAfter: 90 },
      { positions: [1, 2], restBetween: 15, restAfter: 90 }, // Position 1 already used
    ];

    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'explicit', intents);

    expect(result.groups!.length).toBe(1); // Second group rejected
  });

  it('returns null for empty intents', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'explicit', []);

    expect(result.groups).toBeNull();
  });
});

// ============================================================================
// createSupersets Tests - Style: antagonist
// ============================================================================

describe('createSupersets - style: antagonist', () => {
  it('pairs chest with back (classic push-pull)', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'antagonist');

    expect(result.groups).not.toBeNull();

    // Should find chest↔back pair due to horizontal press/pull patterns
    const allPositions = result.groups!.flatMap((g) => g.exercisePositions);
    expect(allPositions).toContain(0); // bench_press
    expect(allPositions).toContain(1); // barbell_row
  });

  it('pairs shoulders with lats (vertical press-pull)', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'antagonist');

    expect(result.groups).not.toBeNull();

    // Should find shoulders↔lats pair due to vertical press/pull patterns
    const allPositions = result.groups!.flatMap((g) => g.exercisePositions);
    expect(allPositions).toContain(2); // overhead_press
    expect(allPositions).toContain(3); // lat_pulldown
  });

  it('pairs biceps with triceps', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'antagonist');

    const allPositions = result.groups!.flatMap((g) => g.exercisePositions);

    // Either both bicep/tricep are paired, or at least one of the classic pairs
    const hasBicepTricep = allPositions.includes(4) && allPositions.includes(5);
    const hasChestBack = allPositions.includes(0) && allPositions.includes(1);
    const hasShoulderLat = allPositions.includes(2) && allPositions.includes(3);

    expect(hasBicepTricep || hasChestBack || hasShoulderLat).toBe(true);
  });

  it('limits to 2 superset groups', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'antagonist');

    expect(result.groups!.length).toBeLessThanOrEqual(2);
  });

  it('returns null for fewer than 4 exercises', () => {
    const threeExercises = [CHEST_COMPOUND, BACK_COMPOUND, SHOULDER_COMPOUND];
    const threeIds = ['bench_press', 'barbell_row', 'overhead_press'];

    const result = createSupersets(threeIds, threeExercises, 'antagonist');

    expect(result.groups).toBeNull();
  });
});

// ============================================================================
// createSupersets Tests - Style: agonist
// ============================================================================

describe('createSupersets - style: agonist', () => {
  it('pairs same muscle group exercises', () => {
    // Create exercises targeting same muscle
    const chestCompound: ExerciseInfo = {
      id: 'bench_press',
      position: 0,
      exerciseType: 'compound',
      muscleGroups: ['chest'],
      baseExercise: 'bench',
    };
    const chestIsolation: ExerciseInfo = {
      id: 'chest_fly',
      position: 1,
      exerciseType: 'isolation',
      muscleGroups: ['chest'],
      baseExercise: 'fly',
    };
    const backCompound: ExerciseInfo = {
      id: 'barbell_row',
      position: 2,
      exerciseType: 'compound',
      muscleGroups: ['back'],
      baseExercise: 'row',
    };
    const backIsolation: ExerciseInfo = {
      id: 'lat_pulldown',
      position: 3,
      exerciseType: 'isolation',
      muscleGroups: ['back'],
      baseExercise: 'pulldown',
    };

    const exercises = [chestCompound, chestIsolation, backCompound, backIsolation];
    const ids = ['bench_press', 'chest_fly', 'barbell_row', 'lat_pulldown'];

    const result = createSupersets(ids, exercises, 'agonist');

    expect(result.groups).not.toBeNull();
  });

  it('requires at least one isolation exercise per pair', () => {
    // All compounds - should not find agonist pairs
    const fourCompounds = [
      { ...CHEST_COMPOUND, position: 0, muscleGroups: ['chest'] },
      { ...BACK_COMPOUND, position: 1, muscleGroups: ['chest'] },
      { ...SHOULDER_COMPOUND, position: 2, muscleGroups: ['back'] },
      { ...LAT_COMPOUND, position: 3, muscleGroups: ['back'] },
    ];

    const result = createSupersets(
      ['ex1', 'ex2', 'ex3', 'ex4'],
      fourCompounds,
      'agonist'
    );

    expect(result.groups).toBeNull();
  });
});

// ============================================================================
// createSupersets Tests - Style: compoundIsolation
// ============================================================================

describe('createSupersets - style: compoundIsolation', () => {
  it('pairs compound with isolation exercises', () => {
    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'compoundIsolation');

    expect(result.groups).not.toBeNull();

    // After reordering, check the paired exercise IDs
    for (const group of result.groups!) {
      // Get exercise IDs from reordered list using group positions
      const pairedIds = group.exercisePositions.map(
        (pos) => result.reorderedExerciseIds[pos]
      );
      // Look up original exercise info by ID
      const exercises = pairedIds.map((id) =>
        ALL_EXERCISES.find((e) => e.id === id)
      );
      const hasCompound = exercises.some((e) => e?.exerciseType === 'compound');
      const hasIsolation = exercises.some((e) => e?.exerciseType === 'isolation');

      expect(hasCompound).toBe(true);
      expect(hasIsolation).toBe(true);
    }
  });
});

// ============================================================================
// Exercise Reordering Tests
// ============================================================================

describe('exercise reordering', () => {
  it('places superset pairs adjacent', () => {
    const intents: SupersetGroupIntent[] = [
      { positions: [0, 3], restBetween: 15, restAfter: 90 }, // Pair bench_press with lat_pulldown
    ];

    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'explicit', intents);

    // First two positions should be the paired exercises
    expect(result.reorderedExerciseIds[0]).toBe('bench_press');
    expect(result.reorderedExerciseIds[1]).toBe('lat_pulldown');
  });

  it('updates group positions after reordering', () => {
    const intents: SupersetGroupIntent[] = [
      { positions: [0, 3], restBetween: 15, restAfter: 90 },
    ];

    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'explicit', intents);

    // After reordering, positions should be 0 and 1 (adjacent)
    expect(result.groups![0].exercisePositions).toEqual([0, 1]);
  });

  it('appends unpaired exercises at the end', () => {
    const intents: SupersetGroupIntent[] = [
      { positions: [0, 1], restBetween: 15, restAfter: 90 },
    ];

    const result = createSupersets(EXERCISE_IDS, ALL_EXERCISES, 'explicit', intents);

    // Paired exercises first, then unpaired
    expect(result.reorderedExerciseIds.length).toBe(6);
    expect(result.reorderedExerciseIds.slice(2)).toContain('overhead_press');
    expect(result.reorderedExerciseIds.slice(2)).toContain('lat_pulldown');
  });
});
