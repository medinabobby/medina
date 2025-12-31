/**
 * Create Workout Handler Tests
 *
 * Tests for create_workout tool handler
 * Covers: parameter validation, exercise selection, protocol assignment, error cases
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {createWorkoutHandler} from "./createWorkout";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Firestore Factory
// ============================================================================

interface MockDoc {
  exists: boolean;
  data: () => Record<string, unknown> | undefined;
  id: string;
  ref: {
    collection: (name: string) => MockCollection;
  };
}

interface MockCollection {
  get: () => Promise<MockSnapshot>;
  doc: (id: string) => MockDocRef;
  where: (field: string, op: string, value: unknown) => MockCollection;
  limit: (n: number) => MockCollection;
  orderBy?: (field: string, direction: string) => MockCollection;
}

interface MockDocRef {
  get: () => Promise<MockDoc>;
  set: (data: Record<string, unknown>) => Promise<void>;
  collection: (name: string) => MockCollection;
}

interface MockSnapshot {
  empty: boolean;
  docs: MockDoc[];
  size: number;
}

interface MockBatch {
  set: ReturnType<typeof vi.fn>;
  delete: ReturnType<typeof vi.fn>;
  commit: ReturnType<typeof vi.fn>;
}

// Sample exercise documents
const SAMPLE_EXERCISES: Record<string, Record<string, unknown>> = {
  barbell_bench_press: {
    id: "barbell_bench_press",
    name: "Barbell Bench Press",
    muscleGroups: ["chest", "triceps"],
    exerciseType: "compound",
    equipment: "barbell",
  },
  barbell_back_squat: {
    id: "barbell_back_squat",
    name: "Barbell Back Squat",
    muscleGroups: ["quadriceps", "glutes", "hamstrings"],
    exerciseType: "compound",
    equipment: "barbell",
  },
  dumbbell_bicep_curl: {
    id: "dumbbell_bicep_curl",
    name: "Dumbbell Bicep Curl",
    muscleGroups: ["biceps"],
    exerciseType: "isolation",
    equipment: "dumbbell",
  },
  pull_up: {
    id: "pull_up",
    name: "Pull Up",
    muscleGroups: ["back", "biceps"],
    exerciseType: "compound",
    equipment: "bodyweight",
  },
  treadmill_run: {
    id: "treadmill_run",
    name: "Treadmill Run",
    muscleGroups: ["cardio"],
    exerciseType: "cardio",
    equipment: "cardio_machine",
  },
};

function createMockDb(options: {
  exercises?: Record<string, Record<string, unknown>>;
  exerciseTargets?: Record<string, Record<string, unknown>>;
  activePlan?: {id: string; name: string; programId: string} | null;
  protocols?: Record<string, Record<string, unknown>>;
} = {}) {
  const batch: MockBatch = {
    set: vi.fn(),
    delete: vi.fn(),
    commit: vi.fn().mockResolvedValue(undefined),
  };

  const emptySnapshot: MockSnapshot = {empty: true, docs: [], size: 0};
  const exercises = options.exercises || SAMPLE_EXERCISES;
  const exerciseTargets = options.exerciseTargets || {};
  const protocols = options.protocols || {};

  // Create exercise docs for snapshot
  const exerciseDocs: MockDoc[] = Object.entries(exercises).map(([id, data]) => ({
    exists: true,
    id,
    data: () => data,
    ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue(emptySnapshot)})},
  }));

  // Active plan snapshot
  const activePlanSnapshot: MockSnapshot = options.activePlan
    ? {
      empty: false,
      docs: [{
        exists: true,
        id: options.activePlan.id,
        data: () => ({name: options.activePlan!.name, status: "active", isSingleWorkout: false}),
        ref: {
          collection: (name: string) => {
            if (name === "programs") {
              return {
                get: vi.fn().mockResolvedValue({
                  empty: false,
                  docs: [{
                    exists: true,
                    id: options.activePlan!.programId,
                    data: () => ({}),
                    ref: {collection: vi.fn()},
                  }],
                  size: 1,
                }),
                doc: vi.fn(),
                where: vi.fn().mockReturnThis(),
                limit: vi.fn().mockReturnThis(),
              };
            }
            return {
              get: vi.fn().mockResolvedValue(emptySnapshot),
              doc: vi.fn(),
              where: vi.fn().mockReturnThis(),
              limit: vi.fn().mockReturnThis(),
            };
          },
        },
      }],
      size: 1,
    }
    : emptySnapshot;

  return {
    collection: vi.fn().mockImplementation((path: string) => {
      // Global exercises collection
      if (path === "exercises") {
        return {
          get: vi.fn().mockResolvedValue({
            empty: exerciseDocs.length === 0,
            docs: exerciseDocs,
            size: exerciseDocs.length,
          }),
          doc: vi.fn().mockImplementation((id: string) => ({
            get: vi.fn().mockResolvedValue({
              exists: id in exercises,
              id,
              data: () => exercises[id],
              ref: {collection: vi.fn()},
            }),
            set: vi.fn().mockResolvedValue(undefined),
            collection: vi.fn().mockReturnValue({
              get: vi.fn().mockResolvedValue(emptySnapshot),
              doc: vi.fn(),
              where: vi.fn().mockReturnThis(),
              limit: vi.fn().mockReturnThis(),
            }),
          })),
          where: vi.fn().mockReturnThis(),
          limit: vi.fn().mockReturnValue({
            get: vi.fn().mockResolvedValue({
              empty: exerciseDocs.length === 0,
              docs: exerciseDocs,
              size: exerciseDocs.length,
            }),
          }),
        };
      }

      // Global protocols collection
      if (path === "protocols") {
        return {
          doc: vi.fn().mockImplementation((id: string) => ({
            get: vi.fn().mockResolvedValue({
              exists: id in protocols,
              id,
              data: () => protocols[id] || {id, name: id, sets: 3, reps: [8, 8, 8]},
              ref: {collection: vi.fn()},
            }),
          })),
          get: vi.fn().mockResolvedValue(emptySnapshot),
          where: vi.fn().mockReturnThis(),
          limit: vi.fn().mockReturnThis(),
        };
      }

      // User-scoped collections
      if (path.startsWith("users/")) {
        const pathParts = path.split("/");

        // users/{uid}/workouts
        if (pathParts[2] === "workouts") {
          return {
            doc: vi.fn().mockImplementation((workoutId: string) => ({
              get: vi.fn().mockResolvedValue({exists: false, id: workoutId, data: () => undefined}),
              set: vi.fn().mockResolvedValue(undefined),
              collection: vi.fn().mockImplementation((subName: string) => {
                if (subName === "instances") {
                  return {
                    doc: vi.fn().mockReturnValue({
                      set: vi.fn().mockResolvedValue(undefined),
                    }),
                    get: vi.fn().mockResolvedValue(emptySnapshot),
                    where: vi.fn().mockReturnThis(),
                    limit: vi.fn().mockReturnThis(),
                  };
                }
                return {
                  get: vi.fn().mockResolvedValue(emptySnapshot),
                  doc: vi.fn(),
                  where: vi.fn().mockReturnThis(),
                  limit: vi.fn().mockReturnThis(),
                };
              }),
            })),
            get: vi.fn().mockResolvedValue(emptySnapshot),
            where: vi.fn().mockReturnThis(),
            limit: vi.fn().mockReturnThis(),
            orderBy: vi.fn().mockReturnThis(),
          };
        }

        // users/{uid}/plans
        if (pathParts[2] === "plans") {
          return {
            doc: vi.fn().mockReturnValue({
              get: vi.fn().mockResolvedValue({exists: false, id: "", data: () => undefined}),
              collection: vi.fn().mockReturnValue({
                get: vi.fn().mockResolvedValue(emptySnapshot),
                doc: vi.fn(),
                where: vi.fn().mockReturnThis(),
                limit: vi.fn().mockReturnThis(),
              }),
            }),
            get: vi.fn().mockResolvedValue(emptySnapshot),
            where: vi.fn().mockImplementation(() => ({
              where: vi.fn().mockReturnValue({
                limit: vi.fn().mockReturnValue({
                  get: vi.fn().mockResolvedValue(activePlanSnapshot),
                }),
              }),
              limit: vi.fn().mockReturnValue({
                get: vi.fn().mockResolvedValue(activePlanSnapshot),
              }),
            })),
            limit: vi.fn().mockReturnThis(),
          };
        }

        // users/{uid}/exerciseTargets
        if (pathParts[2] === "exerciseTargets") {
          return {
            doc: vi.fn().mockImplementation((exerciseId: string) => ({
              get: vi.fn().mockResolvedValue({
                exists: exerciseId in exerciseTargets,
                id: exerciseId,
                data: () => exerciseTargets[exerciseId],
              }),
            })),
            get: vi.fn().mockResolvedValue(emptySnapshot),
            where: vi.fn().mockReturnThis(),
            limit: vi.fn().mockReturnThis(),
          };
        }
      }

      // Default fallback
      return {
        doc: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue({exists: false, id: "", data: () => undefined}),
          set: vi.fn().mockResolvedValue(undefined),
          collection: vi.fn().mockReturnValue({
            get: vi.fn().mockResolvedValue(emptySnapshot),
            doc: vi.fn(),
            where: vi.fn().mockReturnThis(),
            limit: vi.fn().mockReturnThis(),
          }),
        }),
        get: vi.fn().mockResolvedValue(emptySnapshot),
        where: vi.fn().mockReturnThis(),
        limit: vi.fn().mockReturnThis(),
      };
    }),
    batch: vi.fn().mockReturnValue(batch),
  };
}

function createContext(db: ReturnType<typeof createMockDb>): HandlerContext {
  return {
    uid: "test-user-123",
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    db: db as any,
  };
}

// ============================================================================
// Tests
// ============================================================================

describe("createWorkoutHandler", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Parameter Validation", () => {
    it("returns error for missing name", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("name");
    });

    it("returns error for missing splitDay", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Test Workout",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("splitDay");
    });

    it("returns error for missing scheduledDate", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Test Workout",
        splitDay: "upper",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("scheduledDate");
    });

    it("returns error for missing effortLevel", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Test Workout",
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("effortLevel");
    });

    it("returns error for missing exerciseIds", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Test Workout",
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
      }, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("exerciseIds");
    });
  });

  describe("Workout Creation", () => {
    it("creates workout successfully with valid parameters", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Upper Body Strength",
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        duration: 45,
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press", "pull_up"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("WORKOUT_ID");
      expect(result.output).toContain("Upper Body Strength");
    });

    it("includes exercise names in output", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Chest Day",
        splitDay: "chest",
        scheduledDate: "2025-01-15",
        duration: 45,
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("EXERCISES");
      expect(result.output).toContain("Barbell Bench Press");
    });

    it("includes exercise selection reasoning when provided", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Upper Body",
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press", "pull_up"],
        selectionReasoning: "Included 2 compound exercises for balanced upper body",
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("EXERCISE SELECTION");
      expect(result.output).toContain("compound exercises");
    });
  });

  describe("Effort Level Handling", () => {
    it("handles recovery effort level", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Recovery Day",
        splitDay: "fullBody",
        scheduledDate: "2025-01-15",
        effortLevel: "recovery",
        exerciseIds: ["barbell_back_squat"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("recovery");
    });

    it("handles push effort level", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Intense Session",
        splitDay: "legs",
        scheduledDate: "2025-01-15",
        effortLevel: "push",
        exerciseIds: ["barbell_back_squat"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("push");
    });
  });

  describe("Session Type Handling", () => {
    it("creates strength workout by default", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Leg Day",
        splitDay: "legs",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_back_squat"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      // No explicit cardio mention, implies strength
    });

    it("creates cardio workout when sessionType is cardio", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "30 Min Cardio",
        splitDay: "notApplicable",
        scheduledDate: "2025-01-15",
        duration: 30,
        effortLevel: "standard",
        sessionType: "cardio",
        exerciseIds: ["treadmill_run"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("30 Min Cardio");
    });
  });

  describe("Exercise Targets Integration", () => {
    it("notes when exercises have 1RM data", async () => {
      const db = createMockDb({
        exerciseTargets: {
          barbell_bench_press: {
            exerciseId: "barbell_bench_press",
            oneRepMax: 225,
            lastUpdated: "2025-01-01",
          },
        },
      });
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Bench Focus",
        splitDay: "chest",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("1RM data");
      expect(result.output).toContain("target weights");
    });

    it("notes when exercises lack 1RM data", async () => {
      const db = createMockDb({
        exerciseTargets: {},
      });
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "New Workout",
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("No 1RM data");
    });
  });

  describe("Plan Integration", () => {
    it("inserts workout into active plan when one exists", async () => {
      const db = createMockDb({
        activePlan: {
          id: "plan-123",
          name: "8 Week Strength",
          programId: "program-456",
        },
      });
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Extra Push Day",
        splitDay: "push",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("Added to plan");
      expect(result.output).toContain("8 Week Strength");
    });

    it("creates standalone workout when no active plan", async () => {
      const db = createMockDb({
        activePlan: null,
      });
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Quick Workout",
        splitDay: "fullBody",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_back_squat"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      expect(result.output).not.toContain("Added to plan");
    });
  });

  describe("Suggestion Chips", () => {
    it("returns start and modify chips after creation", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Test Workout",
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("Start"))).toBe(true);
      expect(result.suggestionChips?.some((c) => c.label.includes("Modify"))).toBe(true);
    });

    it("includes create plan chip when no active plan", async () => {
      const db = createMockDb({
        activePlan: null,
      });
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Standalone Workout",
        splitDay: "legs",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_back_squat"],
      }, context);

      expect(result.suggestionChips?.some((c) => c.label.includes("plan"))).toBe(true);
    });

    it("omits create plan chip when active plan exists", async () => {
      const db = createMockDb({
        activePlan: {
          id: "plan-123",
          name: "My Plan",
          programId: "program-456",
        },
      });
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Plan Workout",
        splitDay: "push",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      // Should have start and modify, but not "Create plan"
      expect(result.suggestionChips?.some((c) =>
        c.label.toLowerCase().includes("create") && c.label.toLowerCase().includes("plan")
      )).toBe(false);
    });
  });

  describe("Error Handling", () => {
    it("returns error when no exercises found for configuration", async () => {
      const db = createMockDb({
        exercises: {}, // No exercises available
      });
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Empty Workout",
        splitDay: "arms",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["nonexistent_exercise"],
      }, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("No exercises available");
    });
  });

  describe("Duration Handling", () => {
    it("shows estimated duration based on protocols", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Default Duration",
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      // v236: Now shows estimated duration from protocols, not requested duration
      expect(result.output).toContain("Duration:");
      expect(result.output).toMatch(/Duration: ~\d+ minutes/);
    });

    it("shows estimated duration for multiple exercises", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "Long Workout",
        splitDay: "fullBody",
        scheduledDate: "2025-01-15",
        duration: 90,
        effortLevel: "standard",
        exerciseIds: ["barbell_back_squat", "barbell_bench_press", "pull_up", "dumbbell_bicep_curl"],
      }, context);

      expect(result.output).toContain("SUCCESS");
      // v236: Duration is now calculated from protocols (more accurate)
      expect(result.output).toContain("Duration:");
      expect(result.output).toMatch(/Duration: ~\d+ minutes/);
    });
  });

  describe("Protocol Assignment", () => {
    it("uses override protocol when provided", async () => {
      const db = createMockDb({
        protocols: {
          gbc_relative_compound: {
            id: "gbc_relative_compound",
            name: "GBC Protocol",
            sets: 4,
            reps: [12, 12, 12, 12],
            restSeconds: 30,
          },
        },
      });
      const context = createContext(db);

      const result = await createWorkoutHandler({
        name: "GBC Workout",
        splitDay: "upper",
        scheduledDate: "2025-01-15",
        effortLevel: "standard",
        exerciseIds: ["barbell_bench_press"],
        protocolId: "gbc_relative_compound",
      }, context);

      expect(result.output).toContain("SUCCESS");
    });
  });
});
