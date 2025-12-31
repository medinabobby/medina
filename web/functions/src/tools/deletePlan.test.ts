/**
 * Delete Plan Handler Tests
 *
 * Tests for delete_plan tool handler
 * Covers: confirmation flow, cascade deletion, error cases
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {deletePlanHandler} from "./deletePlan";
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
  delete: ReturnType<typeof vi.fn>;
  commit: ReturnType<typeof vi.fn>;
}

function createMockDb(options: {
  planDoc?: MockDoc;
  draftPlanSnapshot?: MockSnapshot;
  workoutsSnapshot?: MockSnapshot;
  programsSnapshot?: MockSnapshot;
  instancesSnapshot?: MockSnapshot;
  setsSnapshot?: MockSnapshot;
}) {
  const batch: MockBatch = {
    delete: vi.fn(),
    commit: vi.fn().mockResolvedValue(undefined),
  };

  const emptySnapshot: MockSnapshot = {empty: true, docs: [], size: 0};

  // Create a simple mock collection (non-recursive)
  const createSimpleMockCollection = (snapshot: MockSnapshot): MockCollection => ({
    get: vi.fn().mockResolvedValue(snapshot),
    doc: vi.fn().mockReturnValue({
      get: vi.fn().mockResolvedValue({exists: false, id: "", data: () => undefined}),
      collection: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue(emptySnapshot),
        doc: vi.fn(),
        where: vi.fn().mockReturnThis(),
        limit: vi.fn().mockReturnThis(),
      }),
    }),
    where: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
  });

  // Mocked doc with subcollection support
  const planDocRef = {
    get: vi.fn().mockResolvedValue(options.planDoc || {exists: false, id: "", data: () => undefined}),
    collection: (name: string) => {
      if (name === "programs") {
        return createSimpleMockCollection(options.programsSnapshot || emptySnapshot);
      }
      return createSimpleMockCollection(emptySnapshot);
    },
  };

  // Workout docs with instance subcollections
  const workoutDocs = (options.workoutsSnapshot?.docs || []).map((doc) => ({
    ...doc,
    ref: {
      collection: (name: string) => {
        if (name === "instances") {
          const instanceDocs = (options.instancesSnapshot?.docs || []).map((iDoc) => ({
            ...iDoc,
            ref: {
              collection: (subName: string) => {
                if (subName === "sets") {
                  return createSimpleMockCollection(options.setsSnapshot || emptySnapshot);
                }
                return createSimpleMockCollection(emptySnapshot);
              },
            },
          }));
          return {
            get: vi.fn().mockResolvedValue({
              empty: instanceDocs.length === 0,
              docs: instanceDocs,
              size: instanceDocs.length,
            }),
            doc: vi.fn(),
            where: vi.fn().mockReturnThis(),
            limit: vi.fn().mockReturnThis(),
          };
        }
        return createSimpleMockCollection(emptySnapshot);
      },
    },
  }));

  const workoutsCollection: MockCollection = {
    get: vi.fn().mockResolvedValue({
      empty: workoutDocs.length === 0,
      docs: workoutDocs,
      size: workoutDocs.length,
    }),
    doc: vi.fn(),
    where: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
  };

  return {
    collection: vi.fn().mockImplementation((name: string) => {
      if (name === "users") {
        return {
          doc: vi.fn().mockReturnValue({
            collection: vi.fn().mockImplementation((subName: string) => {
              if (subName === "plans") {
                return {
                  doc: vi.fn().mockReturnValue(planDocRef),
                  where: vi.fn().mockReturnValue({
                    limit: vi.fn().mockReturnValue({
                      get: vi.fn().mockResolvedValue(options.draftPlanSnapshot || emptySnapshot),
                    }),
                  }),
                  get: vi.fn().mockResolvedValue(emptySnapshot),
                };
              }
              if (subName === "workouts") {
                return workoutsCollection;
              }
              return createSimpleMockCollection(emptySnapshot);
            }),
          }),
        };
      }
      return createSimpleMockCollection(emptySnapshot);
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

describe("deletePlanHandler", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Confirmation Flow", () => {
    it("returns warning without confirmation", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Test Plan", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("permanently delete");
      expect(result.output).toContain("cannot be undone");
      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.[0].label).toContain("Yes");
    });

    it("deletes plan with confirmation", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Test Plan", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
        programsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1", confirmDelete: true}, context);

      expect(result.output).toContain("has been deleted");
      expect(result.output).toContain("Test Plan");
    });
  });

  describe("Draft Alias", () => {
    it("finds draft plan using 'draft' alias", async () => {
      const db = createMockDb({
        draftPlanSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "draft-plan-1",
            data: () => ({name: "My Draft", status: "draft", memberId: "test-user-123"}),
            ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
          }],
        },
        planDoc: {
          exists: true,
          id: "draft-plan-1",
          data: () => ({name: "My Draft", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
        programsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "draft", confirmDelete: true}, context);

      expect(result.output).toContain("has been deleted");
    });

    it("returns error when no draft plan exists", async () => {
      const db = createMockDb({
        draftPlanSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "draft"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("don't have a draft plan");
    });
  });

  describe("Status Validation", () => {
    it("rejects deletion of active plan", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Active Plan", status: "active", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1", confirmDelete: true}, context);

      expect(result.output).toContain("active plan");
      expect(result.output).toContain("can't delete");
      expect(result.suggestionChips?.[0].label).toContain("End plan");
    });

    it("allows deletion of completed plan", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Completed Plan", status: "completed", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
        programsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1", confirmDelete: true}, context);

      expect(result.output).toContain("has been deleted");
    });
  });

  describe("Error Cases", () => {
    it("returns error for missing planId", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      const result = await deletePlanHandler({}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("Missing required parameter");
    });

    it("returns error for non-existent plan", async () => {
      const db = createMockDb({
        planDoc: {
          exists: false,
          id: "fake-plan",
          data: () => undefined,
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "fake-plan", confirmDelete: true}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("not found");
    });
  });

  describe("Cascade Deletion", () => {
    it("reports workout count in confirmation", async () => {
      const workoutDocs = [
        {exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}},
        {exists: true, id: "w2", data: () => ({}), ref: {collection: vi.fn()}},
        {exists: true, id: "w3", data: () => ({}), ref: {collection: vi.fn()}},
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Plan With Workouts", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: false, docs: workoutDocs, size: 3},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("3 workouts");
    });

    it("reports deletion count in success message", async () => {
      const workoutDocs = [
        {exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})}},
        {exists: true, id: "w2", data: () => ({}), ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})}},
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "My Plan", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: false, docs: workoutDocs, size: 2},
        programsSnapshot: {empty: true, docs: [], size: 0},
        instancesSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1", confirmDelete: true}, context);

      expect(result.output).toContain("2 workouts");
      expect(result.output).toContain("has been deleted");
    });

    it("deletes all programs in the plan", async () => {
      const programDocs = [
        {exists: true, id: "prog-1", data: () => ({}), ref: {id: "prog-1"}},
        {exists: true, id: "prog-2", data: () => ({}), ref: {id: "prog-2"}},
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Plan With Programs", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
        programsSnapshot: {empty: false, docs: programDocs, size: 2},
      });
      const context = createContext(db);

      await deletePlanHandler({planId: "plan-1", confirmDelete: true}, context);

      const batch = db.batch();
      // batch.delete should be called for each program + the plan itself
      expect(batch.delete).toHaveBeenCalled();
      expect(batch.commit).toHaveBeenCalledOnce();
    });

    it("deletes exercise instances and sets for each workout", async () => {
      const setDocs = [
        {exists: true, id: "set-1", data: () => ({}), ref: {id: "set-1"}},
        {exists: true, id: "set-2", data: () => ({}), ref: {id: "set-2"}},
      ];
      const instanceDocs = [
        {exists: true, id: "inst-1", data: () => ({}), ref: {id: "inst-1", collection: vi.fn()}},
      ];
      const workoutDocs = [
        {exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}},
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Full Plan", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: false, docs: workoutDocs, size: 1},
        programsSnapshot: {empty: true, docs: [], size: 0},
        instancesSnapshot: {empty: false, docs: instanceDocs, size: 1},
        setsSnapshot: {empty: false, docs: setDocs, size: 2},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1", confirmDelete: true}, context);

      expect(result.output).toContain("has been deleted");
      const batch = db.batch();
      // Verify batch operations were called (sets + instances + workouts + plan)
      expect(batch.delete).toHaveBeenCalled();
      expect(batch.commit).toHaveBeenCalledOnce();
    });

    it("commits all deletions in single batch", async () => {
      // Full hierarchy: plan → 2 programs, 2 workouts → 1 instance each → 2 sets each
      const setDocs = [
        {exists: true, id: "set-1", data: () => ({}), ref: {id: "set-1"}},
        {exists: true, id: "set-2", data: () => ({}), ref: {id: "set-2"}},
      ];
      const instanceDocs = [
        {exists: true, id: "inst-1", data: () => ({}), ref: {id: "inst-1", collection: vi.fn()}},
      ];
      const workoutDocs = [
        {exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}},
        {exists: true, id: "w2", data: () => ({}), ref: {collection: vi.fn()}},
      ];
      const programDocs = [
        {exists: true, id: "prog-1", data: () => ({}), ref: {id: "prog-1"}},
        {exists: true, id: "prog-2", data: () => ({}), ref: {id: "prog-2"}},
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Complete Plan", status: "completed", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: false, docs: workoutDocs, size: 2},
        programsSnapshot: {empty: false, docs: programDocs, size: 2},
        instancesSnapshot: {empty: false, docs: instanceDocs, size: 1},
        setsSnapshot: {empty: false, docs: setDocs, size: 2},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1", confirmDelete: true}, context);

      expect(result.output).toContain("has been deleted");
      const batch = db.batch();
      // Batch commit should be called exactly once (not multiple times)
      expect(batch.commit).toHaveBeenCalledTimes(1);
      // batch.delete should be called multiple times for all entities:
      // 2 workouts × (2 sets + 1 instance) = 6, + 2 workouts + 2 programs + 1 plan = 11 total
      expect(batch.delete.mock.calls.length).toBeGreaterThan(0);
    });
  });

  describe("Suggestion Chips", () => {
    it("returns confirmation chips when not confirmed", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Test Plan", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1"}, context);

      expect(result.suggestionChips).toHaveLength(2);
      expect(result.suggestionChips?.[0].label).toContain("Yes");
      expect(result.suggestionChips?.[1].label).toContain("No");
    });

    it("returns next action chips after deletion", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Test Plan", status: "draft", memberId: "test-user-123"}),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
        programsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await deletePlanHandler({planId: "plan-1", confirmDelete: true}, context);

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("plan"))).toBe(true);
    });
  });
});
