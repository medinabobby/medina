/**
 * Create Plan Handler Tests
 *
 * Tests for create_plan tool handler
 * Covers: parameter resolution, periodization, workout scheduling, error cases
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {createPlanHandler} from "./createPlan";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Firestore Factory
// ============================================================================

function createMockDb(options: {
  userProfile?: Record<string, unknown>;
} = {}) {
  const emptySnapshot = {empty: true, docs: [], size: 0};

  const setMock = vi.fn().mockResolvedValue(undefined);
  const batchCommit = vi.fn().mockResolvedValue(undefined);
  const batchSet = vi.fn();
  const batchDelete = vi.fn();

  // Simple recursive mock collection creator (non-recursive implementation)
  const createMockDocRef = () => ({
    get: vi.fn().mockResolvedValue({exists: false, id: "", data: () => undefined}),
    set: setMock,
    collection: vi.fn().mockReturnValue({
      get: vi.fn().mockResolvedValue(emptySnapshot),
      doc: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue({exists: false}),
        set: setMock,
        collection: vi.fn().mockReturnValue({
          get: vi.fn().mockResolvedValue(emptySnapshot),
          doc: vi.fn().mockReturnValue({
            set: setMock,
          }),
        }),
      }),
      where: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue(emptySnapshot),
      }),
    }),
  });

  return {
    collection: vi.fn().mockImplementation((name: string) => {
      if (name === "users") {
        return {
          doc: vi.fn().mockReturnValue({
            get: vi.fn().mockResolvedValue({
              exists: !!options.userProfile,
              id: "test-user-123",
              data: () => options.userProfile,
            }),
            set: setMock,
            collection: vi.fn().mockImplementation((subName: string) => {
              if (subName === "plans") {
                return {
                  get: vi.fn().mockResolvedValue(emptySnapshot),
                  doc: vi.fn().mockReturnValue({
                    get: vi.fn().mockResolvedValue({exists: false}),
                    set: setMock,
                    collection: vi.fn().mockReturnValue({
                      doc: vi.fn().mockReturnValue({
                        set: setMock,
                      }),
                    }),
                  }),
                  where: vi.fn().mockReturnValue({
                    get: vi.fn().mockResolvedValue(emptySnapshot),
                  }),
                };
              }
              if (subName === "workouts") {
                return {
                  get: vi.fn().mockResolvedValue(emptySnapshot),
                  doc: vi.fn().mockReturnValue({
                    get: vi.fn().mockResolvedValue({exists: false}),
                    set: setMock,
                  }),
                  where: vi.fn().mockReturnValue({
                    get: vi.fn().mockResolvedValue(emptySnapshot),
                  }),
                };
              }
              return createMockDocRef().collection("generic");
            }),
          }),
        };
      }
      return {
        doc: createMockDocRef,
        get: vi.fn().mockResolvedValue(emptySnapshot),
      };
    }),
    batch: vi.fn().mockReturnValue({
      set: batchSet,
      delete: batchDelete,
      commit: batchCommit,
    }),
    _setMock: setMock,
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

describe("createPlanHandler", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe("Basic Plan Creation", () => {
    it("creates a plan with minimal required parameters", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Test Plan", goal: "strength"},
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("Test Plan");
      expect(result.output).toContain("Strength");
      expect(result.output).toContain("PLAN_ID:");
    });

    it("creates a plan with all parameters", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "Full Program",
          goal: "muscleGain",
          durationWeeks: 12,
          daysPerWeek: 4,
          sessionDuration: 60,
          startDate: "2025-01-01",
          preferredDays: ["monday", "tuesday", "thursday", "friday"],
          splitType: "upperLower",
          trainingLocation: "gym",
          experienceLevel: "intermediate",
        },
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("Full Program");
      expect(result.output).toContain("Muscle Gain");
      expect(result.output).toContain("12 weeks");
      expect(result.output).toContain("Upper/Lower");
    });

    it("returns suggestion chips for activation", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Test Plan", goal: "strength"},
        context
      );

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.length).toBeGreaterThan(0);
      expect(result.suggestionChips?.[0].label).toContain("Activate");
    });
  });

  describe("Parameter Resolution", () => {
    it("uses profile defaults when args not provided", async () => {
      const db = createMockDb({
        userProfile: {
          preferredWorkoutDays: ["monday", "wednesday", "friday"],
          preferredSessionDuration: 45,
          trainingLocation: "home",
          experienceLevel: "beginner",
        },
      });
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Profile Plan", goal: "generalFitness"},
        context
      );

      expect(result.output).toContain("SUCCESS");
      // Plan should use 3 days from profile
      expect(result.output).toContain("3 days/week");
    });

    it("overrides profile with explicit args", async () => {
      const db = createMockDb({
        userProfile: {
          preferredWorkoutDays: ["monday", "wednesday", "friday"],
          preferredSessionDuration: 45,
        },
      });
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "Override Plan",
          goal: "strength",
          daysPerWeek: 5,
          sessionDuration: 90,
        },
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("90 minutes");
    });

    it("clamps duration to valid range", async () => {
      const db = createMockDb();
      const context = createContext(db);

      // Test upper clamp
      const result = await createPlanHandler(
        {name: "Long Plan", goal: "strength", durationWeeks: 100},
        context
      );
      expect(result.output).toContain("52 weeks");
    });

    it("handles goal aliases correctly", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Test", goal: "muscle_gain"},
        context
      );
      expect(result.output).toContain("Muscle Gain");
    });
  });

  describe("Split Type Recommendation", () => {
    it("recommends Full Body for 2-3 days", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Low Frequency", goal: "strength", daysPerWeek: 3},
        context
      );

      expect(result.output).toContain("Full Body");
    });

    it("recommends Upper/Lower for 4-5 days", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Medium Frequency", goal: "muscleGain", daysPerWeek: 4},
        context
      );

      expect(result.output).toContain("Upper/Lower");
    });

    it("recommends PPL for 6 days", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "High Frequency", goal: "muscleGain", daysPerWeek: 6},
        context
      );

      expect(result.output).toContain("Push/Pull/Legs");
    });

    it("respects explicit split type", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "Custom Split",
          goal: "strength",
          daysPerWeek: 3,
          splitType: "pushPullLegs", // Override recommendation
        },
        context
      );

      expect(result.output).toContain("Push/Pull/Legs");
    });
  });

  describe("Periodization", () => {
    it("creates single phase for short plans", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Short Plan", goal: "strength", durationWeeks: 3},
        context
      );

      expect(result.output).toContain("SUCCESS");
      // Short plans don't show phase structure
      expect(result.output).not.toContain("PHASE STRUCTURE");
    });

    it("creates multi-phase structure for long plans", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Long Plan", goal: "strength", durationWeeks: 12},
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("PHASE STRUCTURE");
      expect(result.output).toContain("Foundation");
      expect(result.output).toContain("Development");
      expect(result.output).toContain("Peak");
    });

    it("applies custom intensity range", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "Custom Intensity",
          goal: "strength",
          durationWeeks: 8,
          intensityStart: 0.50,
          intensityEnd: 0.70,
        },
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("50%");
    });
  });

  describe("Workout Scheduling", () => {
    it("schedules workouts for the plan", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "8 Week Plan",
          goal: "strength",
          durationWeeks: 8,
          daysPerWeek: 4,
        },
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("TOTAL WORKOUTS:");
    });

    it("includes cardio workouts when specified", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "Mixed Plan",
          goal: "fatLoss",
          durationWeeks: 4,
          daysPerWeek: 4,
          cardioDaysPerWeek: 2,
        },
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("cardio");
    });

    it("shows first week preview", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Preview Plan", goal: "strength", durationWeeks: 4, daysPerWeek: 4},
        context
      );

      expect(result.output).toContain("FIRST WEEK PREVIEW");
    });
  });

  describe("Cardio Days", () => {
    it("defaults to 2 cardio days for fat loss goal", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "Fat Loss Plan",
          goal: "fatLoss",
          durationWeeks: 4,
          daysPerWeek: 5,
        },
        context
      );

      expect(result.output).toContain("cardio");
    });

    it("respects explicit cardio days", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "Custom Cardio Plan",
          goal: "strength",
          durationWeeks: 4,
          daysPerWeek: 5,
          cardioDaysPerWeek: 1,
        },
        context
      );

      expect(result.output).toContain("cardio");
    });
  });

  describe("Error Handling", () => {
    it("returns error for database failures", async () => {
      const db = createMockDb();
      // Make the user doc get throw an error
      (db.collection as ReturnType<typeof vi.fn>).mockImplementation(() => {
        throw new Error("Database connection failed");
      });

      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Error Plan", goal: "strength"},
        context
      );

      expect(result.output).toContain("ERROR");
    });

    it("defaults to generalFitness for invalid goal", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {name: "Invalid Goal Plan", goal: "invalid_goal_xyz"},
        context
      );

      expect(result.output).toContain("SUCCESS");
      expect(result.output).toContain("General Fitness");
    });
  });

  describe("Plan Output Format", () => {
    it("includes all required fields in output", async () => {
      const db = createMockDb();
      const context = createContext(db);

      const result = await createPlanHandler(
        {
          name: "Complete Plan",
          goal: "strength",
          durationWeeks: 8,
          daysPerWeek: 4,
          sessionDuration: 60,
        },
        context
      );

      // Check all required output fields
      expect(result.output).toContain("PLAN_ID:");
      expect(result.output).toContain("Name:");
      expect(result.output).toContain("Goal:");
      expect(result.output).toContain("DURATION:");
      expect(result.output).toContain("Start:");
      expect(result.output).toContain("End:");
      expect(result.output).toContain("Split:");
      expect(result.output).toContain("Training Days:");
      expect(result.output).toContain("Session Duration:");
      expect(result.output).toContain("TOTAL WORKOUTS:");
      expect(result.output).toContain("FIRST WEEK PREVIEW:");
      expect(result.output).toContain("RESPONSE RULES:");
    });
  });
});
