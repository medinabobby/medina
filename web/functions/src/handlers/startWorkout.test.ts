/**
 * Start Workout Handler Tests
 *
 * Tests for start_workout tool handler
 * Covers: workout validation, status transitions, aliases, error cases
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {startWorkoutHandler} from "./startWorkout";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Firestore Factory
// ============================================================================

interface MockDoc {
  exists: boolean;
  data: () => Record<string, unknown> | undefined;
  id: string;
}

interface MockDocRef {
  get: () => Promise<MockDoc>;
  update: ReturnType<typeof vi.fn>;
}

interface MockCollection {
  get: () => Promise<MockSnapshot>;
  doc: (id: string) => MockDocRef;
  where: (field: string, op: string, value: unknown) => MockCollection;
  orderBy: (field: string, direction: string) => MockCollection;
  limit: (n: number) => MockCollection;
}

interface MockSnapshot {
  empty: boolean;
  docs: MockDoc[];
  size: number;
}

interface MockDbOptions {
  workoutDoc?: MockDoc;
  planDoc?: MockDoc;
  activeWorkoutSnapshot?: MockSnapshot;
  todayWorkoutSnapshot?: MockSnapshot;
  nextWorkoutSnapshot?: MockSnapshot;
}

function createMockDb(options: MockDbOptions) {
  const emptySnapshot: MockSnapshot = {empty: true, docs: [], size: 0};

  const updateFn = vi.fn().mockResolvedValue(undefined);

  // Create workout document reference
  const workoutDocRef: MockDocRef = {
    get: vi.fn().mockResolvedValue(options.workoutDoc || {exists: false, id: "", data: () => undefined}),
    update: updateFn,
  };

  // Create plan document reference
  const planDocRef: MockDocRef = {
    get: vi.fn().mockResolvedValue(options.planDoc || {exists: false, id: "", data: () => undefined}),
    update: vi.fn(),
  };

  // Track query state for chained calls
  let isActiveQuery = false;
  let isTodayQuery = false;
  let isNextQuery = false;
  let hasOrderBy = false;

  // Create collection object first, then populate methods
  const workoutsCollection: MockCollection = {} as MockCollection;

  workoutsCollection.get = vi.fn().mockImplementation(() => {
    // Determine which snapshot to return based on query state
    if (isActiveQuery) {
      return Promise.resolve(options.activeWorkoutSnapshot || emptySnapshot);
    }
    if (isTodayQuery && !hasOrderBy) {
      return Promise.resolve(options.todayWorkoutSnapshot || emptySnapshot);
    }
    if (isNextQuery || hasOrderBy) {
      return Promise.resolve(options.nextWorkoutSnapshot || emptySnapshot);
    }
    return Promise.resolve(emptySnapshot);
  });

  workoutsCollection.doc = vi.fn().mockReturnValue(workoutDocRef);

  workoutsCollection.where = vi.fn().mockImplementation((field: string, _op: string, value: unknown) => {
    if (field === "status" && value === "inProgress") {
      isActiveQuery = true;
    }
    if (field === "status" && value === "scheduled") {
      isActiveQuery = false;
    }
    if (field === "scheduledDate") {
      isTodayQuery = true;
      isNextQuery = true;
    }
    return workoutsCollection;
  });

  workoutsCollection.orderBy = vi.fn().mockImplementation(() => {
    hasOrderBy = true;
    return workoutsCollection;
  });

  workoutsCollection.limit = vi.fn().mockImplementation(() => workoutsCollection);

  const plansCollection: MockCollection = {
    get: vi.fn().mockResolvedValue(emptySnapshot),
    doc: vi.fn().mockReturnValue(planDocRef),
    where: vi.fn().mockReturnThis(),
    orderBy: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
  };

  return {
    doc: vi.fn().mockImplementation((path: string) => {
      if (path.includes("/workouts/")) {
        return workoutDocRef;
      }
      if (path.includes("/plans/")) {
        return planDocRef;
      }
      return workoutDocRef;
    }),
    collection: vi.fn().mockImplementation((path: string) => {
      // Reset query state for each new collection call
      isActiveQuery = false;
      isTodayQuery = false;
      isNextQuery = false;
      hasOrderBy = false;

      if (path.includes("/workouts")) {
        return workoutsCollection;
      }
      if (path.includes("/plans")) {
        return plansCollection;
      }
      return workoutsCollection;
    }),
    _updateFn: updateFn,
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

describe("startWorkoutHandler", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Parameter Validation", () => {
    it("returns error when workoutId is missing", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      const result = await startWorkoutHandler({}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("Missing required parameter");
      expect(result.output).toContain("workoutId");
    });

    it("returns error when workout not found", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: false,
          id: "fake-workout",
          data: () => undefined,
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "fake-workout"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("not found");
    });
  });

  describe("Workout Aliases", () => {
    it("resolves 'today' alias to today's scheduled workout", async () => {
      const db = createMockDb({
        todayWorkoutSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "today-workout-1",
            data: () => ({name: "Today's Workout", status: "scheduled"}),
          }],
        },
        workoutDoc: {
          exists: true,
          id: "today-workout-1",
          data: () => ({name: "Today's Workout", status: "scheduled", exerciseIds: ["ex1", "ex2"]}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "today"}, context);

      expect(result.output).toContain("Started");
      expect(result.output).toContain("Today's Workout");
    });

    it("returns helpful message when no workout scheduled for today", async () => {
      const db = createMockDb({
        todayWorkoutSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "today"}, context);

      expect(result.output).toContain("No workout scheduled for today");
      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("Create"))).toBe(true);
    });

    it("resolves 'next' alias to next scheduled workout", async () => {
      const db = createMockDb({
        nextWorkoutSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "next-workout-1",
            data: () => ({name: "Next Workout", status: "scheduled"}),
          }],
        },
        workoutDoc: {
          exists: true,
          id: "next-workout-1",
          data: () => ({name: "Next Workout", status: "scheduled", exerciseIds: ["ex1"]}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "next"}, context);

      expect(result.output).toContain("Started");
      expect(result.output).toContain("Next Workout");
    });

    it("returns helpful message when no upcoming workouts", async () => {
      const db = createMockDb({
        nextWorkoutSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "next"}, context);

      expect(result.output).toContain("No upcoming workouts");
      expect(result.suggestionChips).toBeDefined();
    });
  });

  describe("Active Workout Detection", () => {
    it("detects when trying to start same workout that is already active", async () => {
      const db = createMockDb({
        activeWorkoutSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "workout-1",
            data: () => ({name: "Active Workout", status: "inProgress"}),
          }],
        },
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Active Workout", status: "inProgress"}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("already in progress");
      expect(result.suggestionChips?.some((c) => c.label.includes("Continue"))).toBe(true);
    });

    it("blocks starting new workout when another is active", async () => {
      const db = createMockDb({
        activeWorkoutSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "active-workout",
            data: () => ({name: "Active Workout", status: "inProgress"}),
          }],
        },
        workoutDoc: {
          exists: true,
          id: "new-workout",
          data: () => ({name: "New Workout", status: "scheduled"}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "new-workout"}, context);

      expect(result.output).toContain("already have");
      expect(result.output).toContain("Active Workout");
      expect(result.output).toContain("in progress");
      expect(result.suggestionChips?.some((c) => c.label.includes("End"))).toBe(true);
    });
  });

  describe("Workout Status Validation", () => {
    it("rejects starting a completed workout", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Completed Workout", status: "completed"}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("already been completed");
      expect(result.suggestionChips?.some((c) => c.label.includes("results"))).toBe(true);
    });

    it("rejects starting a skipped workout", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Skipped Workout", status: "skipped"}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("marked as skipped");
      expect(result.suggestionChips?.some((c) => c.label.includes("Reschedule"))).toBe(true);
    });

    it("handles workout already in progress", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "In Progress Workout", status: "inProgress"}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("already in progress");
      expect(result.suggestionChips?.some((c) => c.label.includes("Continue"))).toBe(true);
    });
  });

  describe("Plan Status Validation", () => {
    it("blocks starting workout from draft plan", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({
            name: "Draft Plan Workout",
            status: "scheduled",
            planId: "plan-1",
          }),
        },
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "My Draft Plan", status: "draft"}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Cannot start");
      expect(result.output).toContain("hasn't been activated");
      expect(result.suggestionChips?.some((c) => c.label.includes("Activate"))).toBe(true);
    });

    it("allows starting workout from active plan", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({
            name: "Active Plan Workout",
            status: "scheduled",
            planId: "plan-1",
            exerciseIds: ["ex1", "ex2", "ex3"],
          }),
        },
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "My Active Plan", status: "active"}),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Started");
      expect(result.output).toContain("Active Plan Workout");
    });
  });

  describe("Successful Start", () => {
    it("starts a scheduled workout and updates status", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({
            name: "Leg Day",
            status: "scheduled",
            exerciseIds: ["squat", "lunges", "leg-press"],
            scheduledDate: new Date().toISOString(),
          }),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Started");
      expect(result.output).toContain("Leg Day");
      expect(result.output).toContain("3 exercises");
      expect(db._updateFn).toHaveBeenCalledWith(
        expect.objectContaining({
          status: "inProgress",
          startedAt: expect.any(String),
          updatedAt: expect.any(String),
        })
      );
    });

    it("returns suggestion chips for exercises", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({
            name: "Push Day",
            status: "scheduled",
            exerciseIds: ["bench", "shoulder-press"],
          }),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.length).toBeGreaterThan(0);
      expect(result.suggestionChips?.some((c) => c.label.includes("exercises"))).toBe(true);
    });

    it("handles workout with no exercises gracefully", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({
            name: "Empty Workout",
            status: "scheduled",
            exerciseIds: [],
          }),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Started");
      expect(result.output).toContain("Empty Workout");
      // Should not include exercise count text for empty workouts
      expect(result.output).not.toContain("0 exercises");
    });
  });

  describe("Error Handling", () => {
    it("handles Firestore update error gracefully", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Test Workout", status: "scheduled"}),
        },
      });

      // Make update throw an error
      db._updateFn.mockRejectedValue(new Error("Firestore error"));

      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("Failed to start workout");
    });
  });

  describe("Response Format", () => {
    it("includes VOICE_READY instruction for AI", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({
            name: "Voice Test Workout",
            status: "scheduled",
            exerciseIds: ["ex1"],
          }),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("[VOICE_READY]");
    });

    it("formats scheduled date correctly", async () => {
      const scheduledDate = new Date("2024-12-15T10:00:00Z");
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({
            name: "Dated Workout",
            status: "scheduled",
            exerciseIds: ["ex1"],
            scheduledDate: scheduledDate.toISOString(),
          }),
        },
      });
      const context = createContext(db);

      const result = await startWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Started");
      expect(result.output).toContain("December");
    });
  });
});
