/**
 * Reset Workout Handler Tests
 *
 * Tests for reset_workout tool handler
 * Covers: confirmation flow, today/current aliases, set clearing, error cases
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {resetWorkoutHandler} from "./resetWorkout";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Firestore Factory
// ============================================================================

interface MockDoc {
  exists: boolean;
  data: () => Record<string, unknown> | undefined;
  id: string;
  ref: MockDocRef;
}

interface MockCollection {
  get: () => Promise<MockSnapshot>;
  doc: (id: string) => MockDocRef;
  where: (field: string, op: string, value: unknown) => MockCollection;
  limit: (n: number) => MockCollection;
}

interface MockDocRef {
  get: () => Promise<MockDoc>;
  collection: (name: string) => MockCollection;
  update?: ReturnType<typeof vi.fn>;
}

interface MockSnapshot {
  empty: boolean;
  docs: MockDoc[];
  size: number;
}

interface MockBatch {
  update: ReturnType<typeof vi.fn>;
  commit: ReturnType<typeof vi.fn>;
}

interface SetDocData {
  id: string;
  actualWeight?: number | null;
  actualReps?: number | null;
  completion?: string | null;
}

interface InstanceDocData {
  id: string;
  status?: string;
}

function createMockDb(options: {
  workoutDoc?: MockDoc;
  todayWorkoutSnapshot?: MockSnapshot;
  instancesSnapshot?: {docs: InstanceDocData[]};
  setsSnapshot?: {docs: SetDocData[]};
}) {
  const batch: MockBatch = {
    update: vi.fn(),
    commit: vi.fn().mockResolvedValue(undefined),
  };

  const emptySnapshot: MockSnapshot = {empty: true, docs: [], size: 0};

  // Create set docs with refs
  const setDocs = (options.setsSnapshot?.docs || []).map((setData) => ({
    exists: true,
    id: setData.id,
    data: () => setData,
    ref: {
      get: vi.fn().mockResolvedValue({exists: true, id: setData.id, data: () => setData}),
      collection: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue(emptySnapshot),
        doc: vi.fn(),
        where: vi.fn().mockReturnThis(),
        limit: vi.fn().mockReturnThis(),
      }),
      update: vi.fn(),
    },
  }));

  const setsCollection: MockCollection = {
    get: vi.fn().mockResolvedValue({
      empty: setDocs.length === 0,
      docs: setDocs,
      size: setDocs.length,
    }),
    doc: vi.fn(),
    where: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
  };

  // Create instance docs with sets subcollection
  const instanceDocs = (options.instancesSnapshot?.docs || []).map((instData) => ({
    exists: true,
    id: instData.id,
    data: () => instData,
    ref: {
      get: vi.fn().mockResolvedValue({exists: true, id: instData.id, data: () => instData}),
      collection: (name: string) => {
        if (name === "sets") {
          return setsCollection;
        }
        return {
          get: vi.fn().mockResolvedValue(emptySnapshot),
          doc: vi.fn(),
          where: vi.fn().mockReturnThis(),
          limit: vi.fn().mockReturnThis(),
        };
      },
      update: vi.fn(),
    },
  }));

  const instancesCollection: MockCollection = {
    get: vi.fn().mockResolvedValue({
      empty: instanceDocs.length === 0,
      docs: instanceDocs,
      size: instanceDocs.length,
    }),
    doc: vi.fn(),
    where: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
  };

  // Workout doc ref with instances subcollection
  const workoutDocRef: MockDocRef = {
    get: vi.fn().mockResolvedValue(options.workoutDoc || {exists: false, id: "", data: () => undefined, ref: {} as MockDocRef}),
    collection: (name: string) => {
      if (name === "instances") {
        return instancesCollection;
      }
      return {
        get: vi.fn().mockResolvedValue(emptySnapshot),
        doc: vi.fn(),
        where: vi.fn().mockReturnThis(),
        limit: vi.fn().mockReturnThis(),
      };
    },
    update: vi.fn(),
  };

  // Today workout snapshot for alias resolution
  const todayDocs = (options.todayWorkoutSnapshot?.docs || []).map((doc) => ({
    ...doc,
    ref: workoutDocRef,
  }));

  const todayWorkoutsCollection: MockCollection = {
    get: vi.fn().mockResolvedValue({
      empty: todayDocs.length === 0,
      docs: todayDocs,
      size: todayDocs.length,
    }),
    doc: vi.fn().mockReturnValue(workoutDocRef),
    where: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
  };

  return {
    collection: vi.fn().mockImplementation((name: string) => {
      if (name === "users") {
        return {
          doc: vi.fn().mockReturnValue({
            collection: vi.fn().mockImplementation((subName: string) => {
              if (subName === "workouts") {
                return todayWorkoutsCollection;
              }
              return {
                get: vi.fn().mockResolvedValue(emptySnapshot),
                doc: vi.fn(),
                where: vi.fn().mockReturnThis(),
                limit: vi.fn().mockReturnThis(),
              };
            }),
          }),
        };
      }
      return {
        get: vi.fn().mockResolvedValue(emptySnapshot),
        doc: vi.fn(),
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

describe("resetWorkoutHandler", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Parameter Validation", () => {
    it("returns error for missing workoutId", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      const result = await resetWorkoutHandler({}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("Missing required parameter");
      expect(result.output).toContain("workoutId");
    });

    it("returns error for non-existent workout", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: false,
          id: "fake-workout",
          data: () => undefined,
          ref: {} as MockDocRef,
        },
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "fake-workout"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("not found");
    });
  });

  describe("Today/Current Alias", () => {
    it("resolves 'today' alias to today's workout", async () => {
      const db = createMockDb({
        todayWorkoutSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "today-workout-1",
            data: () => ({name: "Push Day", status: "inProgress", memberId: "test-user-123"}),
            ref: {} as MockDocRef,
          }],
        },
        workoutDoc: {
          exists: true,
          id: "today-workout-1",
          data: () => ({name: "Push Day", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: []},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "today"}, context);

      // Should not error - either asks for confirmation or says nothing to reset
      expect(result.output).not.toContain("ERROR");
    });

    it("resolves 'current' alias to today's workout", async () => {
      const db = createMockDb({
        todayWorkoutSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "current-workout-1",
            data: () => ({name: "Leg Day", status: "inProgress", memberId: "test-user-123"}),
            ref: {} as MockDocRef,
          }],
        },
        workoutDoc: {
          exists: true,
          id: "current-workout-1",
          data: () => ({name: "Leg Day", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: []},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "current"}, context);

      expect(result.output).not.toContain("ERROR");
    });

    it("returns error when no workout scheduled for today", async () => {
      const db = createMockDb({
        todayWorkoutSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "today"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("don't have a workout scheduled for today");
      expect(result.suggestionChips).toBeDefined();
    });
  });

  describe("Already Reset State", () => {
    it("returns message when workout is already in initial state", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Push Day", status: "scheduled", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "scheduled"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: null, actualReps: null, completion: null},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("already in its initial state");
      expect(result.output).toContain("Nothing to reset");
      expect(result.suggestionChips?.[0].label).toContain("Start");
    });
  });

  describe("Confirmation Flow", () => {
    it("returns warning without confirmation when there is logged data", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Push Day", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 135, actualReps: 10, completion: "completed"},
          {id: "set-2", actualWeight: 145, actualReps: 8, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("clear all logged data");
      expect(result.output).toContain("2 logged sets");
      expect(result.output).toContain("cannot be undone");
      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.[0].label).toContain("Yes");
      expect(result.suggestionChips?.[1].label).toContain("No");
    });

    it("reports single set correctly in confirmation", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Push Day", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 135, actualReps: 10, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("1 logged set");
      expect(result.output).not.toContain("1 logged sets");
    });

    it("resets workout with confirmation", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Push Day", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 135, actualReps: 10, completion: "completed"},
          {id: "set-2", actualWeight: 145, actualReps: 8, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1", confirmReset: true}, context);

      expect(result.output).toContain("has been reset");
      expect(result.output).toContain("Cleared 2 logged sets");
      expect(result.output).toContain("Ready to start fresh");
      expect(result.suggestionChips?.[0].label).toContain("Start");
    });
  });

  describe("DisplayName Handling", () => {
    it("uses displayName when available", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({displayName: "Upper Body A", name: "Workout 1", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 135, actualReps: 10, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Upper Body A");
    });

    it("falls back to name when displayName not available", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Leg Day", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 135, actualReps: 10, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Leg Day");
    });

    it("falls back to 'Workout' when neither name is available", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 135, actualReps: 10, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("'Workout'");
    });
  });

  describe("Logged Set Detection", () => {
    it("counts sets with actualWeight as logged", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Test", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 100, actualReps: null, completion: null},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("1 logged set");
    });

    it("counts sets with actualReps as logged", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Test", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: null, actualReps: 10, completion: null},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("1 logged set");
    });

    it("counts sets with completion=completed as logged", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Test", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: null, actualReps: null, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("1 logged set");
    });

    it("does not count empty sets as logged", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Test", status: "scheduled", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "scheduled"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: null, actualReps: null, completion: null},
          {id: "set-2", actualWeight: null, actualReps: null, completion: null},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("already in its initial state");
    });
  });

  describe("Suggestion Chips", () => {
    it("returns confirmation chips when not confirmed", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Push Day", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 135, actualReps: 10, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.suggestionChips).toHaveLength(2);
      expect(result.suggestionChips?.[0].label).toContain("Yes");
      expect(result.suggestionChips?.[0].command).toContain("confirmed");
      expect(result.suggestionChips?.[1].label).toContain("No");
    });

    it("returns next action chips after reset", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Push Day", status: "inProgress", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "inProgress"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: 135, actualReps: 10, completion: "completed"},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1", confirmReset: true}, context);

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("Start"))).toBe(true);
      expect(result.suggestionChips?.some((c) => c.label.includes("schedule"))).toBe(true);
    });

    it("returns helpful chips when no workout for today", async () => {
      const db = createMockDb({
        todayWorkoutSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "today"}, context);

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("schedule"))).toBe(true);
      expect(result.suggestionChips?.some((c) => c.label.includes("Create"))).toBe(true);
    });

    it("returns start chip when workout already in initial state", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Push Day", status: "scheduled", memberId: "test-user-123"}),
          ref: {} as MockDocRef,
        },
        instancesSnapshot: {docs: [{id: "inst-1", status: "scheduled"}]},
        setsSnapshot: {docs: [
          {id: "set-1", actualWeight: null, actualReps: null, completion: null},
        ]},
      });
      const context = createContext(db);

      const result = await resetWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.suggestionChips?.[0].label).toContain("Start");
      expect(result.suggestionChips?.[0].command).toContain("workout-1");
    });
  });
});
