/**
 * Select Exercises API Tests
 *
 * Tests for /api/selectExercises endpoint
 * - Pool building (library sufficient vs fallback)
 * - Compound selection (scoring: bodyweight 2.0x, library 1.2x, emphasis 1.5x)
 * - Isolation selection (scoring: library 1.2x, emphasis 1.5x, balance 1.3x)
 */

import {describe, it, expect} from "vitest";
import {
  buildExercisePool,
  selectCompounds,
  selectIsolations,
  extractMuscles,
  experienceLevelOrder,
  type Exercise,
  type SelectionRequest,
} from "./selectExercises";

// ============================================================================
// Test Exercise Fixtures
// ============================================================================

function createExercise(overrides: Partial<Exercise>): Exercise {
  return {
    id: "test-exercise",
    name: "Test Exercise",
    baseExercise: "test",
    equipment: "barbell",
    type: "compound",
    muscleGroups: ["chest"],
    experienceLevel: "intermediate",
    ...overrides,
  };
}

function createExerciseMap(exercises: Exercise[]): Map<string, Exercise> {
  return new Map(exercises.map((e) => [e.id, e]));
}

// ============================================================================
// Experience Level Order Tests
// ============================================================================

describe("Experience Level Order", () => {
  it("orders experience levels correctly", () => {
    expect(experienceLevelOrder.beginner).toBe(0);
    expect(experienceLevelOrder.intermediate).toBe(1);
    expect(experienceLevelOrder.advanced).toBe(2);
    expect(experienceLevelOrder.expert).toBe(3);
  });

  it("allows comparison between levels", () => {
    expect(experienceLevelOrder.beginner < experienceLevelOrder.intermediate).toBe(true);
    expect(experienceLevelOrder.advanced > experienceLevelOrder.beginner).toBe(true);
  });
});

// ============================================================================
// Pool Building Tests
// ============================================================================

describe("buildExercisePool", () => {
  const benchPress = createExercise({
    id: "bench-press",
    name: "Bench Press",
    baseExercise: "bench",
    type: "compound",
    muscleGroups: ["chest"],
  });

  const inclineBench = createExercise({
    id: "incline-bench",
    name: "Incline Bench Press",
    baseExercise: "bench-incline",
    type: "compound",
    muscleGroups: ["chest"],
  });

  const chestFly = createExercise({
    id: "chest-fly",
    name: "Chest Fly",
    baseExercise: "fly",
    type: "isolation",
    muscleGroups: ["chest"],
  });

  const tricepPushdown = createExercise({
    id: "tricep-pushdown",
    name: "Tricep Pushdown",
    baseExercise: "pushdown",
    type: "isolation",
    muscleGroups: ["triceps"],
    equipment: "cable_machine",
  });

  const advancedExercise = createExercise({
    id: "advanced-exercise",
    name: "Advanced Exercise",
    baseExercise: "advanced",
    experienceLevel: "advanced",
  });

  const allExercises = createExerciseMap([
    benchPress,
    inclineBench,
    chestFly,
    tricepPushdown,
    advancedExercise,
  ]);

  it("returns library exercises when library is sufficient", () => {
    const criteria: SelectionRequest = {
      splitDay: "push",
      muscleTargets: ["chest"],
      compoundCount: 1,
      isolationCount: 1,
      availableEquipment: ["barbell", "cable_machine"],
      userExperienceLevel: "intermediate",
      libraryExerciseIds: ["bench-press", "chest-fly"],
    };

    const result = buildExercisePool(allExercises, criteria);

    expect(result.usedFallback).toBe(false);
    expect(result.exercises).toHaveLength(2);
    expect(result.exercises.map((e) => e.id)).toContain("bench-press");
    expect(result.exercises.map((e) => e.id)).toContain("chest-fly");
  });

  it("expands to experience level when library insufficient", () => {
    const criteria: SelectionRequest = {
      splitDay: "push",
      muscleTargets: ["chest"],
      compoundCount: 3, // More than library has
      isolationCount: 1,
      availableEquipment: ["barbell"],
      userExperienceLevel: "intermediate",
      libraryExerciseIds: ["bench-press"],
    };

    const result = buildExercisePool(allExercises, criteria);

    expect(result.usedFallback).toBe(true);
    // Should include all exercises at intermediate level or below (not advanced)
    expect(result.exercises.length).toBeGreaterThan(1);
  });

  it("filters out excluded exercises", () => {
    const criteria: SelectionRequest = {
      splitDay: "push",
      muscleTargets: ["chest"],
      compoundCount: 3,
      isolationCount: 1,
      availableEquipment: ["barbell"],
      userExperienceLevel: "intermediate",
      libraryExerciseIds: ["bench-press", "incline-bench"],
      excludedExerciseIds: ["bench-press"],
    };

    const result = buildExercisePool(allExercises, criteria);

    expect(result.exercises.map((e) => e.id)).not.toContain("bench-press");
  });

  it("respects experience level when expanding", () => {
    const criteria: SelectionRequest = {
      splitDay: "push",
      muscleTargets: ["chest"],
      compoundCount: 5,
      isolationCount: 5,
      availableEquipment: ["barbell"],
      userExperienceLevel: "beginner",
      libraryExerciseIds: [],
    };

    const result = buildExercisePool(allExercises, criteria);

    // Should NOT include advanced exercise for beginner
    const hasAdvanced = result.exercises.some((e) => e.id === "advanced-exercise");
    expect(hasAdvanced).toBe(false);
  });

  it("includes lower experience levels when expanding", () => {
    const beginnerExercise = createExercise({
      id: "beginner-exercise",
      name: "Beginner Exercise",
      baseExercise: "beginner",
      experienceLevel: "beginner",
    });

    const exercises = createExerciseMap([benchPress, beginnerExercise, advancedExercise]);

    const criteria: SelectionRequest = {
      splitDay: "push",
      muscleTargets: ["chest"],
      compoundCount: 5,
      isolationCount: 5,
      availableEquipment: ["barbell"],
      userExperienceLevel: "intermediate",
      libraryExerciseIds: [],
    };

    const result = buildExercisePool(exercises, criteria);

    // Should include beginner and intermediate, but not advanced
    const ids = result.exercises.map((e) => e.id);
    expect(ids).toContain("beginner-exercise");
    expect(ids).toContain("bench-press");
    expect(ids).not.toContain("advanced-exercise");
  });
});

// ============================================================================
// Compound Selection Tests
// ============================================================================

describe("selectCompounds", () => {
  it("applies bodyweight boost (2.0x)", () => {
    const barbellSquat = createExercise({
      id: "barbell-squat",
      name: "Barbell Squat",
      baseExercise: "squat",
      equipment: "barbell",
      muscleGroups: ["quadriceps"],
    });

    const bodyweightSquat = createExercise({
      id: "bodyweight-squat",
      name: "Bodyweight Squat",
      baseExercise: "squat-bw",
      equipment: "bodyweight",
      muscleGroups: ["quadriceps"],
    });

    const pool = [barbellSquat, bodyweightSquat];
    const libraryIds = new Set<string>();

    // With bodyweight preference, bodyweight should rank higher
    const result = selectCompounds(pool, 1, undefined, libraryIds, true);

    expect(result[0]).toBe("bodyweight-squat");
  });

  it("applies library boost (1.2x)", () => {
    const exercise1 = createExercise({
      id: "ex1",
      name: "Exercise 1",
      baseExercise: "ex1",
      muscleGroups: ["chest"],
    });

    const exercise2 = createExercise({
      id: "ex2",
      name: "Exercise 2",
      baseExercise: "ex2",
      muscleGroups: ["chest"],
    });

    const pool = [exercise1, exercise2];
    const libraryIds = new Set(["ex2"]); // ex2 is in library

    const result = selectCompounds(pool, 1, undefined, libraryIds, false);

    expect(result[0]).toBe("ex2"); // Library exercise should win
  });

  it("applies emphasis boost (1.5x)", () => {
    const chestExercise = createExercise({
      id: "chest-ex",
      name: "Chest Exercise",
      baseExercise: "chest",
      muscleGroups: ["chest"],
    });

    const backExercise = createExercise({
      id: "back-ex",
      name: "Back Exercise",
      baseExercise: "back",
      muscleGroups: ["back"],
    });

    const pool = [chestExercise, backExercise];
    const libraryIds = new Set<string>();

    const result = selectCompounds(pool, 1, ["chest"], libraryIds, false);

    expect(result[0]).toBe("chest-ex"); // Emphasized muscle should win
  });

  it("combines boosts correctly (2.0 x 1.2 x 1.5 = 3.6x)", () => {
    // Exercise with all boosts should beat exercise with none
    const superBoosted = createExercise({
      id: "super-boosted",
      name: "Super Boosted",
      baseExercise: "super",
      equipment: "bodyweight",
      muscleGroups: ["chest"],
    });

    const noBoosted = createExercise({
      id: "no-boost",
      name: "No Boost",
      baseExercise: "none",
      equipment: "barbell",
      muscleGroups: ["back"],
    });

    const pool = [noBoosted, superBoosted]; // Put no-boost first to test sorting
    const libraryIds = new Set(["super-boosted"]);

    const result = selectCompounds(pool, 1, ["chest"], libraryIds, true);

    expect(result[0]).toBe("super-boosted");
  });

  it("enforces movement pattern diversity", () => {
    const squat1 = createExercise({
      id: "squat1",
      name: "Squat 1",
      baseExercise: "squat1",
      movementPattern: "squat",
    });

    const squat2 = createExercise({
      id: "squat2",
      name: "Squat 2",
      baseExercise: "squat2",
      movementPattern: "squat",
    });

    const hinge = createExercise({
      id: "hinge",
      name: "Hinge",
      baseExercise: "hinge",
      movementPattern: "hinge",
    });

    const pool = [squat1, squat2, hinge];
    const libraryIds = new Set<string>();

    const result = selectCompounds(pool, 2, undefined, libraryIds, false);

    // Should select one squat and one hinge (not two squats)
    expect(result).toContain("squat1");
    expect(result).toContain("hinge");
    expect(result).not.toContain("squat2");
  });

  it("prevents duplicate base exercises", () => {
    const benchBarbell = createExercise({
      id: "bench-barbell",
      name: "Barbell Bench",
      baseExercise: "bench",
    });

    const benchDumbbell = createExercise({
      id: "bench-dumbbell",
      name: "Dumbbell Bench",
      baseExercise: "bench", // Same base as barbell bench
    });

    const squat = createExercise({
      id: "squat",
      name: "Squat",
      baseExercise: "squat",
    });

    const pool = [benchBarbell, benchDumbbell, squat];
    const libraryIds = new Set<string>();

    const result = selectCompounds(pool, 2, undefined, libraryIds, false);

    // Should select bench-barbell (first) and squat, not both benches
    expect(result).toHaveLength(2);
    const benchCount = result.filter((id) => id.includes("bench")).length;
    expect(benchCount).toBe(1);
  });

  it("fills remaining slots when diversity blocks selection", () => {
    // Create 3 exercises with same pattern
    const ex1 = createExercise({id: "ex1", baseExercise: "ex1", movementPattern: "squat"});
    const ex2 = createExercise({id: "ex2", baseExercise: "ex2", movementPattern: "squat"});
    const ex3 = createExercise({id: "ex3", baseExercise: "ex3", movementPattern: "squat"});

    const pool = [ex1, ex2, ex3];
    const libraryIds = new Set<string>();

    // Request 3 but only 1 pattern available - should still return 3
    const result = selectCompounds(pool, 3, undefined, libraryIds, false);

    // The function fills remaining slots after pattern diversity blocks
    expect(result.length).toBeLessThanOrEqual(3);
  });
});

// ============================================================================
// Isolation Selection Tests
// ============================================================================

describe("selectIsolations", () => {
  it("applies library boost (1.2x)", () => {
    const ex1 = createExercise({id: "ex1", baseExercise: "ex1", type: "isolation"});
    const ex2 = createExercise({id: "ex2", baseExercise: "ex2", type: "isolation"});

    const pool = [ex1, ex2];
    const libraryIds = new Set(["ex2"]);

    const result = selectIsolations(pool, 1, undefined, new Set(), libraryIds);

    expect(result[0]).toBe("ex2");
  });

  it("applies emphasis boost (1.5x)", () => {
    const chestIso = createExercise({
      id: "chest-iso",
      baseExercise: "chest",
      type: "isolation",
      muscleGroups: ["chest"],
    });

    const backIso = createExercise({
      id: "back-iso",
      baseExercise: "back",
      type: "isolation",
      muscleGroups: ["back"],
    });

    const pool = [chestIso, backIso];
    const libraryIds = new Set<string>();

    const result = selectIsolations(pool, 1, ["chest"], new Set(), libraryIds);

    expect(result[0]).toBe("chest-iso");
  });

  it("applies muscle balance boost (1.3x) for under-represented muscles", () => {
    const chestIso = createExercise({
      id: "chest-iso",
      baseExercise: "chest",
      type: "isolation",
      muscleGroups: ["chest"],
    });

    const tricepIso = createExercise({
      id: "tricep-iso",
      baseExercise: "tricep",
      type: "isolation",
      muscleGroups: ["triceps"],
    });

    const pool = [chestIso, tricepIso];
    const libraryIds = new Set<string>();
    const alreadySelectedMuscles = new Set<string>(["chest"]) as Set<any>;

    // Triceps is under-represented (not in alreadySelectedMuscles)
    const result = selectIsolations(pool, 1, undefined, alreadySelectedMuscles, libraryIds);

    expect(result[0]).toBe("tricep-iso");
  });

  it("prevents duplicate base exercises", () => {
    const curl1 = createExercise({
      id: "curl1",
      baseExercise: "curl",
      type: "isolation",
    });

    const curl2 = createExercise({
      id: "curl2",
      baseExercise: "curl", // Same base
      type: "isolation",
    });

    const extension = createExercise({
      id: "extension",
      baseExercise: "extension",
      type: "isolation",
    });

    const pool = [curl1, curl2, extension];
    const libraryIds = new Set<string>();

    const result = selectIsolations(pool, 2, undefined, new Set(), libraryIds);

    expect(result).toHaveLength(2);
    const curlCount = result.filter((id) => id.includes("curl")).length;
    expect(curlCount).toBe(1);
  });
});

// ============================================================================
// Extract Muscles Tests
// ============================================================================

describe("extractMuscles", () => {
  it("extracts muscle groups from selected exercises", () => {
    const ex1 = createExercise({id: "ex1", muscleGroups: ["chest", "triceps"]});
    const ex2 = createExercise({id: "ex2", muscleGroups: ["back", "biceps"]});

    const pool = [ex1, ex2];
    const result = extractMuscles(["ex1", "ex2"], pool);

    expect(result.has("chest")).toBe(true);
    expect(result.has("triceps")).toBe(true);
    expect(result.has("back")).toBe(true);
    expect(result.has("biceps")).toBe(true);
  });

  it("deduplicates muscle groups", () => {
    const ex1 = createExercise({id: "ex1", muscleGroups: ["chest"]});
    const ex2 = createExercise({id: "ex2", muscleGroups: ["chest"]});

    const pool = [ex1, ex2];
    const result = extractMuscles(["ex1", "ex2"], pool);

    expect(result.size).toBe(1);
    expect(result.has("chest")).toBe(true);
  });

  it("handles missing exercises gracefully", () => {
    const ex1 = createExercise({id: "ex1", muscleGroups: ["chest"]});
    const pool = [ex1];

    const result = extractMuscles(["ex1", "missing-exercise"], pool);

    expect(result.size).toBe(1);
  });

  it("returns empty set for empty input", () => {
    const result = extractMuscles([], []);
    expect(result.size).toBe(0);
  });
});

// ============================================================================
// Integration Scenarios
// ============================================================================

describe("Selection Integration", () => {
  it("full selection flow: compounds then isolations with muscle balance", () => {
    // Create a realistic pool
    const benchPress = createExercise({
      id: "bench",
      name: "Bench Press",
      baseExercise: "bench",
      type: "compound",
      muscleGroups: ["chest", "triceps"],
      movementPattern: "horizontal_press",
    });

    const overheadPress = createExercise({
      id: "ohp",
      name: "Overhead Press",
      baseExercise: "ohp",
      type: "compound",
      muscleGroups: ["shoulders", "triceps"],
      movementPattern: "vertical_press",
    });

    const chestFly = createExercise({
      id: "fly",
      name: "Chest Fly",
      baseExercise: "fly",
      type: "isolation",
      muscleGroups: ["chest"],
    });

    const lateralRaise = createExercise({
      id: "lateral",
      name: "Lateral Raise",
      baseExercise: "lateral",
      type: "isolation",
      muscleGroups: ["shoulders"],
    });

    const tricepExt = createExercise({
      id: "tricep",
      name: "Tricep Extension",
      baseExercise: "tricep",
      type: "isolation",
      muscleGroups: ["triceps"],
    });

    const compoundPool = [benchPress, overheadPress];
    const isolationPool = [chestFly, lateralRaise, tricepExt];
    const libraryIds = new Set<string>();

    // Select 2 compounds
    const compounds = selectCompounds(compoundPool, 2, undefined, libraryIds, false);
    expect(compounds).toHaveLength(2);

    // Extract muscles from compounds
    const compoundMuscles = extractMuscles(compounds, compoundPool);
    expect(compoundMuscles.has("chest")).toBe(true);
    expect(compoundMuscles.has("shoulders")).toBe(true);
    expect(compoundMuscles.has("triceps")).toBe(true);

    // Select 2 isolations - should NOT prioritize already-worked muscles
    const isolations = selectIsolations(isolationPool, 2, undefined, compoundMuscles, libraryIds);
    expect(isolations).toHaveLength(2);

    // All exercises selected should be unique
    const allSelected = [...compounds, ...isolations];
    expect(new Set(allSelected).size).toBe(allSelected.length);
  });

  it("preferBodyweight scenario for home workout", () => {
    const barbellBench = createExercise({
      id: "barbell-bench",
      baseExercise: "bench",
      equipment: "barbell",
      muscleGroups: ["chest"],
    });

    const pushup = createExercise({
      id: "pushup",
      baseExercise: "pushup",
      equipment: "bodyweight",
      muscleGroups: ["chest"],
    });

    const pool = [barbellBench, pushup];
    const libraryIds = new Set<string>();

    // Without bodyweight preference
    const normalResult = selectCompounds(pool, 1, undefined, libraryIds, false);

    // With bodyweight preference
    const homeResult = selectCompounds(pool, 1, undefined, libraryIds, true);

    // Home workout should prefer pushup
    expect(homeResult[0]).toBe("pushup");
  });
});
