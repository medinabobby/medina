/**
 * Activate Plan Handler Tests
 *
 * Tests for activate_plan tool handler
 * Covers: draft alias, status validation, overlap handling, error cases
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {activatePlanHandler} from "./activatePlan";
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
    update?: ReturnType<typeof vi.fn>;
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
  update: ReturnType<typeof vi.fn>;
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

// Helper to create a Firestore Timestamp-like object
function createTimestamp(date: Date) {
  return {
    toDate: () => date,
  };
}

function createMockDb(options: {
  planDoc?: MockDoc;
  draftPlanSnapshot?: MockSnapshot;
  programsSnapshot?: MockSnapshot;
  workoutsSnapshot?: MockSnapshot;
  activePlansSnapshot?: MockSnapshot;
  scheduledWorkoutsSnapshot?: MockSnapshot;
  updateShouldFail?: boolean;
}) {
  const batch: MockBatch = {
    update: vi.fn(),
    commit: vi.fn().mockResolvedValue(undefined),
  };

  const emptySnapshot: MockSnapshot = {empty: true, docs: [], size: 0};

  const updateMock = options.updateShouldFail
    ? vi.fn().mockRejectedValue(new Error("Update failed"))
    : vi.fn().mockResolvedValue(undefined);

  // Mocked doc with subcollection support
  const planDocRef: MockDocRef = {
    get: vi.fn().mockResolvedValue(options.planDoc || {exists: false, id: "", data: () => undefined}),
    collection: (name: string) => {
      if (name === "programs") {
        return {
          get: vi.fn().mockResolvedValue(options.programsSnapshot || emptySnapshot),
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
    update: updateMock,
  };

  // Track where clauses for workouts
  let workoutWhereField = "";
  let workoutWhereValue: unknown = null;

  const workoutsCollection: MockCollection = {
    get: vi.fn().mockImplementation(() => {
      // Return scheduled workouts snapshot when filtering by status
      if (workoutWhereField === "status" && workoutWhereValue === "scheduled") {
        return Promise.resolve(options.scheduledWorkoutsSnapshot || emptySnapshot);
      }
      return Promise.resolve(options.workoutsSnapshot || emptySnapshot);
    }),
    doc: vi.fn(),
    where: vi.fn().mockImplementation((field: string, _op: string, value: unknown) => {
      workoutWhereField = field;
      workoutWhereValue = value;
      return workoutsCollection;
    }),
    limit: vi.fn().mockReturnThis(),
  };

  // Track where clauses for plans
  let planWhereField = "";
  let planWhereValue: unknown = null;

  const plansCollection: MockCollection = {
    get: vi.fn().mockImplementation(() => {
      if (planWhereField === "status" && planWhereValue === "draft") {
        return Promise.resolve(options.draftPlanSnapshot || emptySnapshot);
      }
      if (planWhereField === "status" && planWhereValue === "active") {
        return Promise.resolve(options.activePlansSnapshot || emptySnapshot);
      }
      return Promise.resolve(emptySnapshot);
    }),
    doc: vi.fn().mockReturnValue(planDocRef),
    where: vi.fn().mockImplementation((field: string, _op: string, value: unknown) => {
      planWhereField = field;
      planWhereValue = value;
      return {
        ...plansCollection,
        limit: vi.fn().mockReturnValue({
          get: vi.fn().mockImplementation(() => {
            if (field === "status" && value === "draft") {
              return Promise.resolve(options.draftPlanSnapshot || emptySnapshot);
            }
            return Promise.resolve(emptySnapshot);
          }),
        }),
      };
    }),
    limit: vi.fn().mockReturnThis(),
  };

  return {
    collection: vi.fn().mockImplementation((name: string) => {
      if (name === "users") {
        return {
          doc: vi.fn().mockReturnValue({
            collection: vi.fn().mockImplementation((subName: string) => {
              if (subName === "plans") {
                return plansCollection;
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

// ============================================================================
// Tests
// ============================================================================

describe("activatePlanHandler", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Draft Alias", () => {
    it("finds draft plan using 'draft' alias", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        draftPlanSnapshot: {
          empty: false,
          size: 1,
          docs: [{
            exists: true,
            id: "draft-plan-1",
            data: () => ({
              name: "My Draft Plan",
              status: "draft",
              memberId: "test-user-123",
              startDate: createTimestamp(startDate),
              endDate: createTimestamp(endDate),
            }),
            ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
          }],
        },
        planDoc: {
          exists: true,
          id: "draft-plan-1",
          data: () => ({
            name: "My Draft Plan",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: false, docs: [{exists: true, id: "p1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        workoutsSnapshot: {empty: false, docs: [{exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        activePlansSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "draft"}, context);

      expect(result.output).toContain("activated");
      expect(result.output).toContain("My Draft Plan");
    });

    it("returns error when no draft plan exists", async () => {
      const db = createMockDb({
        draftPlanSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "draft"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("don't have a draft plan");
    });
  });

  describe("Status Validation", () => {
    it("rejects activation of already active plan", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "Active Plan",
            status: "active",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("already active");
      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("View"))).toBe(true);
    });

    it("rejects activation of completed plan", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "Completed Plan",
            status: "completed",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("completed");
      expect(result.output).toContain("cannot be reactivated");
    });

    it("rejects activation of plan without programs", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "Empty Plan",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("no programs");
    });

    it("rejects activation of plan without workouts", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "Plan Without Workouts",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: false, docs: [{exists: true, id: "p1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        workoutsSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("no workouts");
    });
  });

  describe("Successful Activation", () => {
    it("activates a draft plan successfully", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 14 * 24 * 60 * 60 * 1000); // 2 weeks

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "My Training Plan",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: false, docs: [{exists: true, id: "p1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        workoutsSnapshot: {
          empty: false,
          docs: [
            {exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}},
            {exists: true, id: "w2", data: () => ({}), ref: {collection: vi.fn()}},
            {exists: true, id: "w3", data: () => ({}), ref: {collection: vi.fn()}},
          ],
          size: 3,
        },
        activePlansSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("activated");
      expect(result.output).toContain("My Training Plan");
      expect(result.output).toContain("3 workouts");
      expect(result.output).toContain("2 weeks");
      expect(result.output).toContain("VOICE_READY");
      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("schedule"))).toBe(true);
    });

    it("shows singular workout text for single workout", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 1 * 24 * 60 * 60 * 1000); // 1 day

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "Single Workout Plan",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
            isSingleWorkout: true,
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: false, docs: [{exists: true, id: "p1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        workoutsSnapshot: {
          empty: false,
          docs: [{exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}}],
          size: 1,
        },
        activePlansSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("1 workout scheduled");
      expect(result.output).not.toContain("1 workouts");
    });
  });

  describe("Overlap Handling", () => {
    it("asks for confirmation when overlap detected", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 14 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "new-plan",
          data: () => ({
            name: "New Plan",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: false, docs: [{exists: true, id: "p1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        workoutsSnapshot: {empty: false, docs: [{exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        activePlansSnapshot: {
          empty: false,
          docs: [{
            exists: true,
            id: "existing-plan",
            data: () => ({
              name: "Current Active Plan",
              status: "active",
              memberId: "test-user-123",
              startDate: createTimestamp(startDate),
              endDate: createTimestamp(endDate),
            }),
            ref: {collection: vi.fn()},
          }],
          size: 1,
        },
        scheduledWorkoutsSnapshot: {
          empty: false,
          docs: [
            {exists: true, id: "sw1", data: () => ({status: "scheduled", scheduledDate: createTimestamp(new Date(Date.now() + 86400000))}), ref: {collection: vi.fn()}},
            {exists: true, id: "sw2", data: () => ({status: "scheduled", scheduledDate: createTimestamp(new Date(Date.now() + 172800000))}), ref: {collection: vi.fn()}},
          ],
          size: 2,
        },
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "new-plan"}, context);

      expect(result.output).toContain("end your current plan");
      expect(result.output).toContain("Current Active Plan");
      expect(result.output).toContain("remaining");
      expect(result.output).toContain("INSTRUCTION");
      expect(result.output).toContain("confirmOverlap=true");
      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("Yes"))).toBe(true);
      expect(result.suggestionChips?.some((c) => c.label.includes("No"))).toBe(true);
    });

    it("skips overlap check for single workout plans", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 1 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "single-workout-plan",
          data: () => ({
            name: "Quick Workout",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
            isSingleWorkout: true,
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: false, docs: [{exists: true, id: "p1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        workoutsSnapshot: {empty: false, docs: [{exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        // Even with active plans, single workouts should activate without overlap check
        activePlansSnapshot: {
          empty: false,
          docs: [{
            exists: true,
            id: "existing-plan",
            data: () => ({
              name: "Current Active Plan",
              status: "active",
              memberId: "test-user-123",
              startDate: createTimestamp(startDate),
              endDate: createTimestamp(endDate),
            }),
            ref: {collection: vi.fn()},
          }],
          size: 1,
        },
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "single-workout-plan"}, context);

      // Should activate without asking for overlap confirmation
      expect(result.output).toContain("activated");
      expect(result.output).toContain("Quick Workout");
      expect(result.output).not.toContain("end your current plan");
    });
  });

  describe("Error Cases", () => {
    it("returns error for missing planId", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      const result = await activatePlanHandler({}, context);

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

      const result = await activatePlanHandler({planId: "fake-plan"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("not found");
    });

    it("handles update failure gracefully", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "Test Plan",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: false, docs: [{exists: true, id: "p1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        workoutsSnapshot: {empty: false, docs: [{exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        activePlansSnapshot: {empty: true, docs: [], size: 0},
        updateShouldFail: true,
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("Failed to activate");
    });
  });

  describe("Suggestion Chips", () => {
    it("returns appropriate chips after successful activation", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "Test Plan",
            status: "draft",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
        programsSnapshot: {empty: false, docs: [{exists: true, id: "p1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        workoutsSnapshot: {empty: false, docs: [{exists: true, id: "w1", data: () => ({}), ref: {collection: vi.fn()}}], size: 1},
        activePlansSnapshot: {empty: true, docs: [], size: 0},
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.suggestionChips).toHaveLength(2);
      expect(result.suggestionChips?.some((c) => c.label.includes("schedule"))).toBe(true);
      expect(result.suggestionChips?.some((c) => c.label.includes("Start"))).toBe(true);
    });

    it("returns new plan chip after completed plan rejection", async () => {
      const startDate = new Date();
      const endDate = new Date(startDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      const db = createMockDb({
        planDoc: {
          exists: true,
          id: "plan-1",
          data: () => ({
            name: "Completed Plan",
            status: "completed",
            memberId: "test-user-123",
            startDate: createTimestamp(startDate),
            endDate: createTimestamp(endDate),
          }),
          ref: {collection: vi.fn().mockReturnValue({get: vi.fn().mockResolvedValue({empty: true, docs: []})})},
        },
      });
      const context = createContext(db);

      const result = await activatePlanHandler({planId: "plan-1"}, context);

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("new plan"))).toBe(true);
    });
  });
});
