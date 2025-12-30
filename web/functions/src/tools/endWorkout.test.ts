/**
 * End Workout Handler Tests
 *
 * Tests for end_workout tool handler
 * Covers: status validation, completion stats, error cases, suggestion chips
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {endWorkoutHandler} from "./endWorkout";
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
  orderBy: (field: string, direction: string) => MockCollection;
  limit: (n: number) => MockCollection;
}

interface MockDocRef {
  get: () => Promise<MockDoc>;
  collection: (name: string) => MockCollection;
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

interface CreateMockDbOptions {
  workoutDoc?: MockDoc;
  inProgressSnapshot?: MockSnapshot;
  nextWorkoutSnapshot?: MockSnapshot;
  instancesSnapshot?: MockSnapshot;
  setsSnapshots?: Map<string, MockSnapshot>;
}

function createMockDb(options: CreateMockDbOptions) {
  const batch: MockBatch = {
    update: vi.fn(),
    commit: vi.fn().mockResolvedValue(undefined),
  };

  const emptySnapshot: MockSnapshot = {empty: true, docs: [], size: 0};

  // Create mock set documents with refs for batch updates
  const createMockSetDocs = (setsSnapshot?: MockSnapshot): MockDoc[] => {
    if (!setsSnapshot) return [];
    return setsSnapshot.docs.map((doc) => ({
      ...doc,
      ref: {
        collection: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue(emptySnapshot),
          doc: vi.fn(),
          where: vi.fn().mockReturnThis(),
          orderBy: vi.fn().mockReturnThis(),
          limit: vi.fn().mockReturnThis(),
        }),
      },
    }));
  };

  // Create mock instance documents with sets subcollection
  const createMockInstanceDocs = (): MockDoc[] => {
    if (!options.instancesSnapshot) return [];
    return options.instancesSnapshot.docs.map((doc) => {
      const instanceId = doc.id;
      const setsSnapshot = options.setsSnapshots?.get(instanceId) || emptySnapshot;
      const setDocs = createMockSetDocs(setsSnapshot);

      return {
        ...doc,
        ref: {
          collection: (name: string) => {
            if (name === "sets") {
              return {
                get: vi.fn().mockResolvedValue({
                  empty: setDocs.length === 0,
                  docs: setDocs,
                  size: setDocs.length,
                }),
                doc: vi.fn(),
                where: vi.fn().mockReturnThis(),
                orderBy: vi.fn().mockReturnThis(),
                limit: vi.fn().mockReturnThis(),
              };
            }
            return {
              get: vi.fn().mockResolvedValue(emptySnapshot),
              doc: vi.fn(),
              where: vi.fn().mockReturnThis(),
              orderBy: vi.fn().mockReturnThis(),
              limit: vi.fn().mockReturnThis(),
            };
          },
        },
      };
    });
  };

  const instanceDocs = createMockInstanceDocs();

  // Mock workout document reference with instances subcollection
  const workoutDocRef = {
    get: vi.fn().mockResolvedValue(options.workoutDoc || {exists: false, id: "", data: () => undefined}),
    collection: (name: string) => {
      if (name === "instances") {
        return {
          get: vi.fn().mockResolvedValue({
            empty: instanceDocs.length === 0,
            docs: instanceDocs,
            size: instanceDocs.length,
          }),
          doc: vi.fn(),
          where: vi.fn().mockReturnThis(),
          orderBy: vi.fn().mockReturnThis(),
          limit: vi.fn().mockReturnThis(),
        };
      }
      return {
        get: vi.fn().mockResolvedValue(emptySnapshot),
        doc: vi.fn(),
        where: vi.fn().mockReturnThis(),
        orderBy: vi.fn().mockReturnThis(),
        limit: vi.fn().mockReturnThis(),
      };
    },
  };

  // Chain tracking for workouts collection
  let currentChain = {
    status: undefined as string | undefined,
    orderByField: undefined as string | undefined,
  };

  // Define workoutsCollection with explicit type to avoid circular reference issues
  const workoutsCollection: MockCollection = {} as MockCollection;

  // Now assign properties after declaration
  workoutsCollection.get = vi.fn().mockImplementation(() => {
    if (currentChain.status === "inProgress") {
      return Promise.resolve(options.inProgressSnapshot || emptySnapshot);
    }
    if (currentChain.status === "scheduled") {
      return Promise.resolve(options.nextWorkoutSnapshot || emptySnapshot);
    }
    return Promise.resolve(emptySnapshot);
  });
  workoutsCollection.doc = vi.fn().mockReturnValue(workoutDocRef);
  workoutsCollection.where = vi.fn().mockImplementation((field: string, _op: string, value: unknown) => {
    if (field === "status") {
      currentChain.status = value as string;
    }
    return workoutsCollection;
  });
  workoutsCollection.orderBy = vi.fn().mockImplementation((field: string) => {
    currentChain.orderByField = field;
    return workoutsCollection;
  });
  workoutsCollection.limit = vi.fn().mockImplementation(() => workoutsCollection);

  return {
    collection: vi.fn().mockImplementation((name: string) => {
      if (name === "users") {
        return {
          doc: vi.fn().mockReturnValue({
            collection: vi.fn().mockImplementation((subName: string) => {
              if (subName === "workouts") {
                // Reset chain state for each new query
                currentChain = {status: undefined, orderByField: undefined};
                return workoutsCollection;
              }
              return {
                get: vi.fn().mockResolvedValue(emptySnapshot),
                doc: vi.fn(),
                where: vi.fn().mockReturnThis(),
                orderBy: vi.fn().mockReturnThis(),
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
        orderBy: vi.fn().mockReturnThis(),
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
// Helper Factories
// ============================================================================

function createWorkoutDoc(overrides: Partial<{
  id: string;
  name: string;
  status: string;
  startedAt: string;
}>): MockDoc {
  const defaults = {
    id: "workout-1",
    name: "Push Day",
    status: "inProgress",
    startedAt: new Date(Date.now() - 45 * 60 * 1000).toISOString(), // 45 mins ago
  };
  const workout = {...defaults, ...overrides};

  return {
    exists: true,
    id: workout.id,
    data: () => workout,
    ref: {
      collection: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue({empty: true, docs: [], size: 0}),
      }),
    },
  };
}

function createInstanceDoc(id: string, data: Record<string, unknown> = {}): MockDoc {
  return {
    exists: true,
    id,
    data: () => ({id, ...data}),
    ref: {
      collection: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue({empty: true, docs: [], size: 0}),
      }),
    },
  };
}

function createSetDoc(id: string, data: Record<string, unknown> = {}): MockDoc {
  return {
    exists: true,
    id,
    data: () => ({id, ...data}),
    ref: {
      collection: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue({empty: true, docs: [], size: 0}),
      }),
    },
  };
}

// ============================================================================
// Tests
// ============================================================================

describe("endWorkoutHandler", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Current Workout Resolution", () => {
    it("finds in-progress workout when no workoutId provided", async () => {
      const workoutDoc = createWorkoutDoc({id: "current-workout"});
      const db = createMockDb({
        inProgressSnapshot: {
          empty: false,
          size: 1,
          docs: [workoutDoc],
        },
        workoutDoc,
        instancesSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({}, context);

      expect(result.output).toContain("completed");
      expect(result.output).not.toContain("ERROR");
    });

    it("finds in-progress workout with 'current' alias", async () => {
      const workoutDoc = createWorkoutDoc({id: "current-workout"});
      const db = createMockDb({
        inProgressSnapshot: {
          empty: false,
          size: 1,
          docs: [workoutDoc],
        },
        workoutDoc,
        instancesSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "current"}, context);

      expect(result.output).toContain("completed");
    });

    it("returns message when no in-progress workout exists", async () => {
      const db = createMockDb({
        inProgressSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({}, context);

      expect(result.output).toContain("don't have a workout in progress");
      expect(result.suggestionChips).toBeDefined();
    });
  });

  describe("Status Validation", () => {
    it("rejects ending already completed workout", async () => {
      const db = createMockDb({
        workoutDoc: createWorkoutDoc({status: "completed"}),
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("already been completed");
    });

    it("rejects ending skipped workout", async () => {
      const db = createMockDb({
        workoutDoc: createWorkoutDoc({status: "skipped"}),
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("was skipped");
    });

    it("suggests skip for scheduled (not started) workout", async () => {
      const db = createMockDb({
        workoutDoc: createWorkoutDoc({status: "scheduled"}),
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("hasn't been started");
      expect(result.output).toContain("skip");
      expect(result.suggestionChips?.some((c) => c.label.includes("Skip"))).toBe(true);
    });

    it("returns error for non-existent workout", async () => {
      const db = createMockDb({
        workoutDoc: {
          exists: false,
          id: "fake-workout",
          data: () => undefined,
          ref: {collection: vi.fn()},
        },
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "fake-workout"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("not found");
    });
  });

  describe("Completion Stats", () => {
    it("reports all sets completed when none skipped", async () => {
      const instanceDoc = createInstanceDoc("instance-1");
      const setDocs = [
        createSetDoc("set-1", {completion: "completed", actualWeight: 135, actualReps: 10}),
        createSetDoc("set-2", {completion: "completed", actualWeight: 135, actualReps: 10}),
        createSetDoc("set-3", {completion: "completed", actualWeight: 135, actualReps: 10}),
      ];

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {
          empty: false,
          docs: [instanceDoc],
          size: 1,
        },
        setsSnapshots: new Map([
          ["instance-1", {empty: false, docs: setDocs, size: 3}],
        ]),
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("All 3 sets completed");
      expect(result.output).toContain("completed!");
    });

    it("reports partial completion with skipped sets", async () => {
      const instanceDoc = createInstanceDoc("instance-1");
      const setDocs = [
        createSetDoc("set-1", {completion: "completed", actualWeight: 135, actualReps: 10}),
        createSetDoc("set-2", {completion: "pending"}), // Not completed
        createSetDoc("set-3", {completion: "pending"}), // Not completed
      ];

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {
          empty: false,
          docs: [instanceDoc],
          size: 1,
        },
        setsSnapshots: new Map([
          ["instance-1", {empty: false, docs: setDocs, size: 3}],
        ]),
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Completed 1 of 3 sets");
      expect(result.output).toContain("Marked 2 remaining sets as skipped");
    });

    it("reports no sets completed when all skipped", async () => {
      const instanceDoc = createInstanceDoc("instance-1");
      const setDocs = [
        createSetDoc("set-1", {completion: "pending"}),
        createSetDoc("set-2", {completion: "pending"}),
      ];

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {
          empty: false,
          docs: [instanceDoc],
          size: 1,
        },
        setsSnapshots: new Map([
          ["instance-1", {empty: false, docs: setDocs, size: 2}],
        ]),
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("No sets were completed");
      expect(result.output).toContain("ended"); // Status is "ended" not "completed" when no sets
    });

    it("counts sets with actual data as completed", async () => {
      const instanceDoc = createInstanceDoc("instance-1");
      // Set has actual data but no explicit completion status
      const setDocs = [
        createSetDoc("set-1", {actualWeight: 100, actualReps: 8}),
      ];

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {
          empty: false,
          docs: [instanceDoc],
          size: 1,
        },
        setsSnapshots: new Map([
          ["instance-1", {empty: false, docs: setDocs, size: 1}],
        ]),
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("All 1 sets completed");
    });
  });

  describe("Next Workout Info", () => {
    it("shows next scheduled workout after completion", async () => {
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);

      const nextWorkoutDoc: MockDoc = {
        exists: true,
        id: "next-workout",
        data: () => ({
          id: "next-workout",
          name: "Pull Day",
          status: "scheduled",
          scheduledDate: tomorrow.toISOString(),
        }),
        ref: {collection: vi.fn()},
      };

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {empty: true, docs: [], size: 0},
        nextWorkoutSnapshot: {
          empty: false,
          docs: [nextWorkoutDoc],
          size: 1,
        },
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("Pull Day");
      expect(result.output).toContain("See you tomorrow");
      expect(result.suggestionChips?.some((c) => c.command.includes("next-workout"))).toBe(true);
    });

    it("offers to create workout when no next scheduled", async () => {
      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {empty: true, docs: [], size: 0},
        nextWorkoutSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("don't have any more scheduled workouts");
      expect(result.output).toContain("create a new workout");
      expect(result.suggestionChips?.some((c) => c.label.includes("Create"))).toBe(true);
    });
  });

  describe("Duration Calculation", () => {
    it("includes duration in summary when startedAt is available", async () => {
      // Started 45 minutes ago
      const startedAt = new Date(Date.now() - 45 * 60 * 1000).toISOString();

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({startedAt}),
        instancesSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      // Should mention duration around 45 minutes
      expect(result.output).toContain("Duration:");
      expect(result.output).toContain("minutes");
    });

    it("formats duration in hours and minutes for long workouts", async () => {
      // Started 90 minutes ago
      const startedAt = new Date(Date.now() - 90 * 60 * 1000).toISOString();

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({startedAt}),
        instancesSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("1h 30m");
    });
  });

  describe("Suggestion Chips", () => {
    it("shows start and skip chips for scheduled workout", async () => {
      const db = createMockDb({
        workoutDoc: createWorkoutDoc({id: "workout-1", status: "scheduled"}),
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.suggestionChips).toHaveLength(2);
      expect(result.suggestionChips?.some((c) => c.label.includes("Skip"))).toBe(true);
      expect(result.suggestionChips?.some((c) => c.label.includes("Start"))).toBe(true);
    });

    it("shows next workout chip when available", async () => {
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);

      const nextWorkoutDoc: MockDoc = {
        exists: true,
        id: "next-workout",
        data: () => ({name: "Leg Day", scheduledDate: tomorrow.toISOString()}),
        ref: {collection: vi.fn()},
      };

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {empty: true, docs: [], size: 0},
        nextWorkoutSnapshot: {
          empty: false,
          docs: [nextWorkoutDoc],
          size: 1,
        },
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.suggestionChips?.some((c) => c.label.includes("Start next"))).toBe(true);
      expect(result.suggestionChips?.some((c) => c.label.includes("schedule"))).toBe(true);
    });

    it("shows create workout chip when no next workout", async () => {
      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {empty: true, docs: [], size: 0},
        nextWorkoutSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.suggestionChips?.some((c) => c.label.includes("Create"))).toBe(true);
    });
  });

  describe("Date Context", () => {
    it("says 'See you tomorrow' for next day workout", async () => {
      const tomorrow = new Date();
      tomorrow.setDate(tomorrow.getDate() + 1);

      const nextWorkoutDoc: MockDoc = {
        exists: true,
        id: "next",
        data: () => ({name: "Next", scheduledDate: tomorrow.toISOString()}),
        ref: {collection: vi.fn()},
      };

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {empty: true, docs: [], size: 0},
        nextWorkoutSnapshot: {empty: false, docs: [nextWorkoutDoc], size: 1},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("See you tomorrow");
    });

    it("says 'See you in a couple days' for 2 days out", async () => {
      const twoDays = new Date();
      twoDays.setDate(twoDays.getDate() + 2);

      const nextWorkoutDoc: MockDoc = {
        exists: true,
        id: "next",
        data: () => ({name: "Next", scheduledDate: twoDays.toISOString()}),
        ref: {collection: vi.fn()},
      };

      const db = createMockDb({
        workoutDoc: createWorkoutDoc({}),
        instancesSnapshot: {empty: true, docs: [], size: 0},
        nextWorkoutSnapshot: {empty: false, docs: [nextWorkoutDoc], size: 1},
      });
      const context = createContext(db);

      const result = await endWorkoutHandler({workoutId: "workout-1"}, context);

      expect(result.output).toContain("See you in a couple days");
    });
  });
});
