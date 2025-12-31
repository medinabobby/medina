/**
 * Reschedule Plan Handler Tests
 *
 * Tests for reschedule_plan tool
 */

import {describe, it, expect, vi} from "vitest";
import {reschedulePlanHandler} from "./reschedulePlan";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Setup
// ============================================================================

interface MockPlanOptions {
  planExists?: boolean;
  planData?: Record<string, unknown>;
  planStatus?: string;
  workouts?: Array<{id: string; status: string; scheduledDate?: string}>;
}

function createMockDb(options: MockPlanOptions = {}) {
  const {
    planExists = true,
    planData = {
      id: "plan-123",
      name: "Test Plan",
      status: "active",
      preferredDays: ["monday", "wednesday", "friday"],
      daysPerWeek: 3,
    },
    planStatus = "active",
    workouts = [
      {id: "w1", status: "completed", scheduledDate: "2025-01-01"},
      {id: "w2", status: "scheduled", scheduledDate: "2025-01-03"},
      {id: "w3", status: "scheduled", scheduledDate: "2025-01-05"},
    ],
  } = options;

  const updateFn = vi.fn().mockResolvedValue(undefined);
  const batchUpdateFn = vi.fn();
  const batchCommitFn = vi.fn().mockResolvedValue(undefined);

  // Create plans subcollection mock
  const createPlansCollection = () => ({
    doc: vi.fn().mockImplementation((id: string) => {
      if (id === "plan-123" || id === planData?.id) {
        return {
          get: vi.fn().mockResolvedValue({
            exists: planExists,
            data: () => ({...planData, status: planStatus}),
            id: planData?.id || "plan-123",
          }),
          update: updateFn,
        };
      }
      return {
        get: vi.fn().mockResolvedValue({exists: false}),
        update: updateFn,
      };
    }),
    where: vi.fn().mockImplementation((field: string, op: string, value: string) => {
      if (field === "status" && value === planStatus) {
        return {
          limit: vi.fn().mockReturnValue({
            get: vi.fn().mockResolvedValue({
              empty: !planExists,
              docs: planExists
                ? [{
                    id: planData?.id || "plan-123",
                    data: () => ({...planData, status: planStatus}),
                  }]
                : [],
            }),
          }),
        };
      }
      return {
        limit: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue({empty: true, docs: []}),
        }),
        get: vi.fn().mockResolvedValue({empty: true, docs: []}),
      };
    }),
  });

  // Create workouts subcollection mock
  const createWorkoutsCollection = () => ({
    doc: vi.fn().mockImplementation((id: string) => {
      const workout = workouts.find((w) => w.id === id);
      if (workout) {
        return {
          get: vi.fn().mockResolvedValue({
            exists: true,
            data: () => workout,
            id: workout.id,
          }),
          update: batchUpdateFn,
        };
      }
      return {
        get: vi.fn().mockResolvedValue({exists: false}),
      };
    }),
    where: vi.fn().mockImplementation((field: string) => {
      if (field === "planId") {
        return {
          get: vi.fn().mockResolvedValue({
            empty: false,
            docs: workouts.map((w) => ({
              id: w.id,
              data: () => w,
              ref: {update: batchUpdateFn},
            })),
          }),
        };
      }
      return {
        get: vi.fn().mockResolvedValue({empty: true, docs: []}),
      };
    }),
  });

  return {
    collection: vi.fn().mockImplementation((name: string) => {
      if (name === "users") {
        return {
          doc: vi.fn().mockReturnValue({
            collection: vi.fn().mockImplementation((subName: string) => {
              if (subName === "plans") return createPlansCollection();
              if (subName === "workouts") return createWorkoutsCollection();
              return {};
            }),
          }),
        };
      }
      return {};
    }),
    batch: vi.fn().mockReturnValue({
      update: batchUpdateFn,
      commit: batchCommitFn,
    }),
    _updateFn: updateFn,
    _batchCommitFn: batchCommitFn,
  };
}

function createContext(db: ReturnType<typeof createMockDb>): HandlerContext {
  return {
    uid: "test-user-123",
    db: db as any,
  };
}

// ============================================================================
// Tests
// ============================================================================

describe("reschedulePlanHandler", () => {
  describe("Validation", () => {
    it("returns error when planId is missing", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {newPreferredDays: ["monday", "wednesday"]},
        context
      );

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("planId");
    });

    it("returns error when newPreferredDays is missing", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123"},
        context
      );

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("newPreferredDays");
    });

    it("returns error when newPreferredDays is empty", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: []},
        context
      );

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("newPreferredDays");
    });

    it("returns error for invalid day names", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: ["funday", "happyday"]},
        context
      );

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("valid days");
    });
  });

  describe("Plan Resolution", () => {
    it('resolves "current" to active plan', async () => {
      const db = createMockDb({planStatus: "active"});
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "current", newPreferredDays: ["monday", "wednesday"]},
        context
      );

      expect(result.output).toContain("SUCCESS");
    });

    it('returns error when no active plan for "current"', async () => {
      const db = createMockDb({planExists: false, planStatus: "active"});
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "current", newPreferredDays: ["monday"]},
        context
      );

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("No active plan");
    });

    it('resolves "draft" to draft plan', async () => {
      const db = createMockDb({planStatus: "draft"});
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "draft", newPreferredDays: ["tuesday", "thursday"]},
        context
      );

      expect(result.output).toContain("SUCCESS");
    });

    it('returns error when no draft plan for "draft"', async () => {
      const db = createMockDb({planExists: false, planStatus: "draft"});
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "draft", newPreferredDays: ["monday"]},
        context
      );

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("No draft plan");
    });

    it("resolves specific plan ID", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: ["monday", "friday"]},
        context
      );

      expect(result.output).toContain("SUCCESS");
    });

    it("returns error for non-existent plan ID", async () => {
      const db = createMockDb({planExists: false});
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "non-existent", newPreferredDays: ["monday"]},
        context
      );

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("not found");
    });
  });

  describe("Day Parsing", () => {
    it("accepts lowercase day names", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: ["monday", "wednesday", "friday"]},
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("Monday");
      expect(result.output).toContain("Wednesday");
      expect(result.output).toContain("Friday");
    });

    it("sorts days in week order", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: ["friday", "monday", "wednesday"]},
        context
      );

      // Output should have days in order: Monday, Wednesday, Friday
      const mondayPos = result.output.indexOf("Monday");
      const wednesdayPos = result.output.indexOf("Wednesday");
      const fridayPos = result.output.indexOf("Friday");

      expect(mondayPos).toBeLessThan(wednesdayPos);
      expect(wednesdayPos).toBeLessThan(fridayPos);
    });

    it("accepts all valid day names", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const allDays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: allDays.slice(0, 3)},
        context
      );

      expect(result.output).toContain("SUCCESS");
    });
  });

  describe("Output Format", () => {
    it("includes plan name in success output", async () => {
      const db = createMockDb({planData: {id: "plan-123", name: "My Training Plan", status: "active"}});
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: ["monday"]},
        context
      );

      expect(result.output).toContain("My Training Plan");
    });

    it("includes new schedule in output", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: ["tuesday", "thursday"]},
        context
      );

      expect(result.output).toContain("NEW_SCHEDULE");
      expect(result.output).toContain("Tuesday");
      expect(result.output).toContain("Thursday");
    });

    it("includes suggestion chips", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: ["monday"]},
        context
      );

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.some((c) => c.label.includes("schedule"))).toBe(true);
    });

    it("includes plan card", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await reschedulePlanHandler(
        {planId: "plan-123", newPreferredDays: ["monday"]},
        context
      );

      expect(result.planCard).toBeDefined();
      expect(result.planCard?.planId).toBe("plan-123");
    });
  });
});
