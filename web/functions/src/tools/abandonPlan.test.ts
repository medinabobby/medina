/**
 * Abandon Plan Handler Tests
 *
 * Tests for abandon_plan tool handler
 * Covers: alias resolution, status validation, workout skipping, error cases
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {abandonPlanHandler} from "./abandonPlan";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Firestore Factory
// ============================================================================

interface MockDoc {
  exists: boolean;
  data: () => Record<string, unknown> | undefined;
  id: string;
  ref: FirebaseFirestore.DocumentReference;
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
  update: ReturnType<typeof vi.fn>;
  commit: ReturnType<typeof vi.fn>;
}

function createMockDb(options: {
  planDoc?: MockDoc;
  activePlanSnapshot?: MockSnapshot;
  workoutsSnapshot?: MockSnapshot;
  batchCommitError?: boolean;
}) {
  const batch: MockBatch = {
    update: vi.fn(),
    commit: options.batchCommitError
      ? vi.fn().mockRejectedValue(new Error("Batch commit failed"))
      : vi.fn().mockResolvedValue(undefined),
  };

  const emptySnapshot: MockSnapshot = {empty: true, docs: [], size: 0};

  // Mocked doc reference
  const planDocRef = {
    get: vi.fn().mockResolvedValue(options.planDoc || {exists: false, id: "", data: () => undefined}),
    collection: vi.fn().mockReturnValue({
      get: vi.fn().mockResolvedValue(emptySnapshot),
      doc: vi.fn(),
      where: vi.fn().mockReturnThis(),
      limit: vi.fn().mockReturnThis(),
    }),
  };

  // Workout docs with refs for batch updates
  const workoutDocs = (options.workoutsSnapshot?.docs || []).map((doc) => ({
    ...doc,
    ref: doc.ref || {id: doc.id},
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
                      get: vi.fn().mockResolvedValue(options.activePlanSnapshot || emptySnapshot),
                    }),
                  }),
                  get: vi.fn().mockResolvedValue(emptySnapshot),
                };
              }
              if (subName === "workouts") {
                return workoutsCollection;
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

// Helper to create a mock Firestore timestamp
function createMockTimestamp(date: Date) {
  return {
    toDate: () => date,
  };
}

// ============================================================================
// Tests
// ============================================================================

describe("abandonPlanHandler", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Alias Resolution", () => {
    it("finds active plan using 'current' alias", async () => {
      const db = createMockDb({
        activePlanSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "active-plan-1",
            data: () => ({name: "My Active Plan", status: "active", memberId: "test-user-123"}),
            ref: {id: "active-plan-1"} as FirebaseFirestore.DocumentReference,
          }],
        },
        planDoc: {
          exists: true,
          id: "active-plan-1",
          data: () => ({name: "My Active Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "active-plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "current"}, context);

      expect(result.output).toContain("has been ended early");
    });

    it("finds active plan using 'active' alias", async () => {
      const db = createMockDb({
        activePlanSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "active-plan-1",
            data: () => ({name: "Training Plan", status: "active", memberId: "test-user-123"}),
            ref: {id: "active-plan-1"} as FirebaseFirestore.DocumentReference,
          }],
        },
        planDoc: {
          exists: true,
          id: "active-plan-1",
          data: () => ({name: "Training Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "active-plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "active"}, context);

      expect(result.output).toContain("has been ended early");
      expect(result.output).toContain("Training Plan");
    });

    it("returns error when no active plan exists for alias", async () => {
      const db = createMockDb({
        activePlanSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "current"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("don't have an active plan");
    });
  });

  describe("Status Validation", () => {
    it("successfully abandons active plan", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Active Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("has been ended early");
      expect(result.suggestionChips).toBeDefined();
    });

    it("rejects abandonment of draft plan with suggestion to delete", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Draft Plan", status: "draft", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("draft plan");
      expect(result.output).toContain("hasn't been activated");
      expect(result.output).toContain("delete it instead");
      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.[0].label).toContain("Delete");
    });

    it("rejects abandonment of already completed plan", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Completed Plan", status: "completed", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("already been completed");
      expect(result.output).toContain("No action needed");
    });

    it("rejects abandonment of already abandoned plan", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Abandoned Plan", status: "abandoned", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("already been ended");
      expect(result.output).toContain("No action needed");
    });
  });

  describe("Error Cases", () => {
    it("returns error for missing planId", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      const result = await abandonPlanHandler({}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("Missing required parameter");
    });

    it("returns error for non-existent plan", async () => {
      const db = createMockDb({
        planDoc: {
          exists: false,
          id: "fake-plan",
          data: () => undefined,
          ref: {id: "fake-plan"} as FirebaseFirestore.DocumentReference,
        },
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "fake-plan"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("not found");
    });

    it("handles batch commit error gracefully", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Active Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
        batchCommitError: true,
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("Failed to end plan");
    });
  });

  describe("Workout Handling", () => {
    it("marks scheduled future workouts as skipped", async () => {
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 7);

      const workoutDocs = [
        {
          exists: true,
          id: "w1",
          data: () => ({planId: "plan-1", status: "scheduled", scheduledDate: createMockTimestamp(futureDate)}),
          ref: {id: "w1"} as FirebaseFirestore.DocumentReference,
        },
        {
          exists: true,
          id: "w2",
          data: () => ({planId: "plan-1", status: "scheduled", scheduledDate: createMockTimestamp(futureDate)}),
          ref: {id: "w2"} as FirebaseFirestore.DocumentReference,
        },
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Active Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: false, docs: workoutDocs, size: 2},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("2 remaining workouts were marked as skipped");
    });

    it("reports completed workout count", async () => {
      const workoutDocs = [
        {
          exists: true,
          id: "w1",
          data: () => ({planId: "plan-1", status: "completed"}),
          ref: {id: "w1"} as FirebaseFirestore.DocumentReference,
        },
        {
          exists: true,
          id: "w2",
          data: () => ({planId: "plan-1", status: "completed"}),
          ref: {id: "w2"} as FirebaseFirestore.DocumentReference,
        },
        {
          exists: true,
          id: "w3",
          data: () => ({planId: "plan-1", status: "completed"}),
          ref: {id: "w3"} as FirebaseFirestore.DocumentReference,
        },
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "My Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: false, docs: workoutDocs, size: 3},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("completed 3 workouts");
    });

    it("reports both completed and skipped counts", async () => {
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 7);

      const workoutDocs = [
        {
          exists: true,
          id: "w1",
          data: () => ({planId: "plan-1", status: "completed"}),
          ref: {id: "w1"} as FirebaseFirestore.DocumentReference,
        },
        {
          exists: true,
          id: "w2",
          data: () => ({planId: "plan-1", status: "scheduled", scheduledDate: createMockTimestamp(futureDate)}),
          ref: {id: "w2"} as FirebaseFirestore.DocumentReference,
        },
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Mixed Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: false, docs: workoutDocs, size: 2},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("completed 1 workout");
      expect(result.output).toContain("1 remaining workout was marked as skipped");
    });

    it("uses singular grammar for single workout", async () => {
      const workoutDocs = [
        {
          exists: true,
          id: "w1",
          data: () => ({planId: "plan-1", status: "completed"}),
          ref: {id: "w1"} as FirebaseFirestore.DocumentReference,
        },
      ];

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Single Workout Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: false, docs: workoutDocs, size: 1},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("1 workout");
      expect(result.output).not.toContain("1 workouts");
    });
  });

  describe("Suggestion Chips", () => {
    it("returns next action chips after abandonment", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Test Plan", status: "active", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
        workoutsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips).toHaveLength(2);
      expect(result.suggestionChips?.[0].label).toContain("Create new plan");
      expect(result.suggestionChips?.[1].label).toContain("Show schedule");
    });

    it("returns delete suggestion for draft plans", async () => {
      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({name: "Draft Plan", status: "draft", memberId: "test-user-123"}),
          ref: {id: "plan-1"} as FirebaseFirestore.DocumentReference,
        },
      });
      const context = createContext(db);

      const result = await abandonPlanHandler({planId: "plan-1"}, context);

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.[0].command).toContain("Delete plan");
    });
  });
});
