/**
 * Modify Workout Handler Tests
 *
 * Tests for modify_workout tool
 */

import {describe, it, expect, vi} from "vitest";
import {modifyWorkoutHandler} from "./modifyWorkout";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Setup
// ============================================================================

function createMockDb(options: {
  workoutData?: Record<string, unknown>;
  workoutExists?: boolean;
  exerciseData?: Record<string, Record<string, unknown>>;
} = {}) {
  const {
    workoutExists = true,
    workoutData = {
      id: "workout-123",
      name: "Test Workout",
      scheduledDate: "2025-01-15",
      status: "scheduled",
      exerciseIds: ["bench_press", "squat"],
    },
    exerciseData = {
      bench_press: {name: "Bench Press"},
      squat: {name: "Squat"},
    },
  } = options;

  return {
    collection: vi.fn().mockReturnValue({
      doc: vi.fn().mockImplementation((id: string) => {
        if (id === "workout-123" || id === workoutData?.id) {
          return {
            get: vi.fn().mockResolvedValue({
              exists: workoutExists,
              data: () => workoutData,
              id: workoutData?.id || "workout-123",
            }),
            update: vi.fn().mockResolvedValue(undefined),
            set: vi.fn().mockResolvedValue(undefined),
          };
        }
        // Exercise lookup
        if (exerciseData[id]) {
          return {
            get: vi.fn().mockResolvedValue({
              exists: true,
              data: () => exerciseData[id],
            }),
          };
        }
        return {
          get: vi.fn().mockResolvedValue({exists: false}),
        };
      }),
      where: vi.fn().mockReturnThis(),
      get: vi.fn().mockResolvedValue({empty: true, docs: []}),
    }),
  };
}

function createContext(db: ReturnType<typeof createMockDb>): HandlerContext {
  return {
    uid: "test-user-123",
    db: db as any,
  };
}

// ============================================================================
// Validation Tests
// ============================================================================

describe("modifyWorkoutHandler", () => {
  describe("Validation", () => {
    it("returns error when workoutId is missing", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler({}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("workoutId");
    });

    it("returns error when no modifications provided", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123"},
        context
      );

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("No modifications");
    });

    it("accepts workoutId with at least one modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      // This should pass validation (even if service call fails)
      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123", newName: "Updated Workout"},
        context
      );

      // Should not have validation error
      expect(result.output).not.toContain("Missing required parameter");
      expect(result.output).not.toContain("No modifications");
    });
  });

  describe("Modification Types", () => {
    it("recognizes name as valid modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123", newName: "New Name"},
        context
      );

      expect(result.output).not.toContain("No modifications specified");
    });

    it("recognizes scheduledDate as valid modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123", newScheduledDate: "2025-02-01"},
        context
      );

      expect(result.output).not.toContain("No modifications specified");
    });

    it("recognizes effortLevel as valid modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123", newEffortLevel: "push"},
        context
      );

      expect(result.output).not.toContain("No modifications specified");
    });

    it("recognizes splitDay as valid modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123", newSplitDay: "upper"},
        context
      );

      expect(result.output).not.toContain("No modifications specified");
    });

    it("recognizes duration as valid modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123", newDuration: 60},
        context
      );

      expect(result.output).not.toContain("No modifications specified");
    });

    it("recognizes sessionType as valid modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123", newSessionType: "cardio"},
        context
      );

      expect(result.output).not.toContain("No modifications specified");
    });

    it("recognizes trainingLocation as valid modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {workoutId: "workout-123", newTrainingLocation: "home"},
        context
      );

      expect(result.output).not.toContain("No modifications specified");
    });

    it("recognizes exerciseSubstitutions as valid modification", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await modifyWorkoutHandler(
        {
          workoutId: "workout-123",
          exerciseSubstitutions: [{position: 0, newExerciseId: "dumbbell_press"}],
        },
        context
      );

      expect(result.output).not.toContain("No modifications specified");
    });
  });
});
