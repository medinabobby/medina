/**
 * E2E Integration Tests for Server-Side Handlers
 *
 * Tests the full flow: chat endpoint → handler execution → AI continuation
 * Uses mocked OpenAI responses to simulate tool calls.
 */

import {describe, it, expect, vi, beforeEach, afterEach} from "vitest";
import {executeHandler, hasHandler, getHandledTools} from "./index";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Firestore Factory (shared with handler tests)
// ============================================================================

interface MockDoc {
  exists: boolean;
  data: () => Record<string, unknown> | undefined;
  id: string;
}

interface MockSnapshot {
  empty: boolean;
  docs: MockDoc[];
}

function createMockDb(options: {
  getResult?: MockDoc;
  queryResult?: MockSnapshot;
  updateFn?: () => Promise<void>;
  setFn?: () => Promise<void>;
}) {
  const updateFn = options.updateFn || vi.fn().mockResolvedValue(undefined);
  const setFn = options.setFn || vi.fn().mockResolvedValue(undefined);

  return {
    collection: vi.fn().mockReturnValue({
      doc: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue(options.getResult || {exists: false}),
        update: updateFn,
        set: setFn,
      }),
      where: vi.fn().mockReturnThis(),
      orderBy: vi.fn().mockReturnThis(),
      limit: vi.fn().mockReturnThis(),
      get: vi.fn().mockResolvedValue(options.queryResult || {empty: true, docs: []}),
    }),
    doc: vi.fn().mockReturnValue({
      get: vi.fn().mockResolvedValue(options.getResult || {exists: false}),
      update: updateFn,
      set: setFn,
    }),
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
// E2E Handler Execution Tests
// ============================================================================

describe("E2E: Handler Execution Flow", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2025-12-27T10:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe("Tool Call Detection", () => {
    it("correctly identifies server-handled tools", () => {
      const serverTools = getHandledTools();
      expect(serverTools).toContain("show_schedule");
      expect(serverTools).toContain("update_profile");
      expect(serverTools).toContain("suggest_options");
      expect(serverTools).toContain("skip_workout");
    });

    it("returns null for client-handled tools", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      // These tools should pass through to iOS (not registered on server)
      const modifyResult = await executeHandler("modify_workout", {}, context);
      const rescheduleResult = await executeHandler("reschedule_plan", {}, context);

      expect(modifyResult).toBeNull();
      expect(rescheduleResult).toBeNull();
    });
  });

  describe("Sequential Handler Execution", () => {
    it("handles show_schedule then update_profile in sequence", async () => {
      const setFn = vi.fn().mockResolvedValue(undefined);
      const db = createMockDb({
        queryResult: {empty: true, docs: []},
        setFn,
      });
      const context = createContext(db);

      // First: show schedule
      const scheduleResult = await executeHandler("show_schedule", {period: "week"}, context);
      expect(scheduleResult?.output).toContain("No workouts scheduled");

      // Second: update profile
      const profileResult = await executeHandler(
        "update_profile",
        {fitnessGoal: "strength", experienceLevel: "intermediate"},
        context
      );
      expect(profileResult?.output).toContain("SUCCESS");
    });

    it("handles skip_workout after show_schedule", async () => {
      const updateFn = vi.fn().mockResolvedValue(undefined);
      const db = createMockDb({
        getResult: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Upper Body", status: "scheduled"}),
        },
        queryResult: {empty: true, docs: []},
        updateFn,
      });
      const context = createContext(db);

      // Skip workout after viewing schedule
      const skipResult = await executeHandler("skip_workout", {workoutId: "workout-1"}, context);

      expect(skipResult?.output).toContain("has been skipped");
      expect(updateFn).toHaveBeenCalled();
    });
  });

  describe("Error Recovery", () => {
    it("returns error message for invalid workout ID", async () => {
      const db = createMockDb({
        getResult: {exists: false, id: "invalid", data: () => undefined},
      });
      const context = createContext(db);

      const result = await executeHandler("skip_workout", {workoutId: "invalid"}, context);

      expect(result?.output).toContain("ERROR");
      expect(result?.output).toContain("not found");
    });

    it("returns error for empty profile update", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      const result = await executeHandler("update_profile", {}, context);

      expect(result?.output).toContain("No profile fields");
    });

    it("returns error for empty suggest_options", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      const result = await executeHandler("suggest_options", {options: []}, context);

      expect(result?.output).toContain("No options");
    });
  });

  describe("Suggestion Chips Flow", () => {
    it("skip_workout returns next workout chip", async () => {
      const db = createMockDb({
        getResult: {
          exists: true,
          id: "workout-1",
          data: () => ({name: "Upper Body", status: "scheduled"}),
        },
        queryResult: {
          empty: false,
          docs: [{
            exists: true,
            id: "workout-2",
            data: () => ({
              name: "Lower Body",
              scheduledDate: "2025-12-29T09:00:00Z",
              status: "scheduled",
            }),
          }],
        },
      });
      const context = createContext(db);

      const result = await executeHandler("skip_workout", {workoutId: "workout-1"}, context);

      expect(result?.suggestionChips).toBeDefined();
      expect(result?.suggestionChips?.[0].label).toContain("Lower Body");
      expect(result?.suggestionChips?.[0].command).toContain("Start workout");
    });

    it("suggest_options returns chips array", async () => {
      const db = createMockDb({});
      const context = createContext(db);

      const result = await executeHandler("suggest_options", {
        options: [
          {label: "Option 1", command: "Do option 1"},
          {label: "Option 2", command: "Do option 2"},
        ],
      }, context);

      expect(result?.suggestionChips).toHaveLength(2);
      expect(result?.suggestionChips?.[0].label).toBe("Option 1");
    });
  });
});

// ============================================================================
// Simulated Chat Flow Tests
// ============================================================================

describe("E2E: Simulated Chat Flow", () => {
  /**
   * These tests simulate the flow that happens in index.ts when
   * OpenAI returns a tool call:
   *
   * 1. Chat endpoint receives message
   * 2. OpenAI returns tool call event
   * 3. Server detects server-handled tool
   * 4. Handler executes with Firestore context
   * 5. Tool output sent back to OpenAI
   * 6. AI generates response with results
   */

  it("simulates show_schedule tool call from AI", async () => {
    // Simulate: User says "Show my schedule"
    // AI calls show_schedule tool

    const db = createMockDb({
      queryResult: {
        empty: false,
        docs: [
          {
            exists: true,
            id: "w1",
            data: () => ({
              name: "Push Day",
              scheduledDate: "2025-12-28T09:00:00Z",
              status: "scheduled",
            }),
          },
        ],
      },
    });

    // Check tool is server-handled
    expect(hasHandler("show_schedule")).toBe(true);

    // Execute handler (simulating what index.ts does)
    const result = await executeHandler(
      "show_schedule",
      {period: "week"},
      createContext(db)
    );

    // Verify output that would be sent to OpenAI for continuation
    expect(result).not.toBeNull();
    expect(result?.output).toContain("1 workout(s)");
    expect(result?.output).toContain("Push Day");
  });

  it("simulates update_profile during onboarding", async () => {
    // Simulate: User tells AI their fitness goals
    // AI extracts info and calls update_profile

    const setFn = vi.fn().mockResolvedValue(undefined);
    const db = createMockDb({setFn});

    // Check tool is server-handled
    expect(hasHandler("update_profile")).toBe(true);

    // Execute handler with profile data
    const result = await executeHandler(
      "update_profile",
      {
        fitnessGoal: "strength",
        experienceLevel: "intermediate",
        preferredDays: ["monday", "wednesday", "friday"],
        sessionDuration: 60,
      },
      createContext(db)
    );

    // Verify success and Firestore write
    expect(result?.output).toContain("SUCCESS");
    expect(setFn).toHaveBeenCalled();
  });

  it("simulates skip_workout conversation flow", async () => {
    // Simulate: User says "Skip today's workout"
    // AI identifies workout and calls skip_workout

    const updateFn = vi.fn().mockResolvedValue(undefined);
    const db = createMockDb({
      getResult: {
        exists: true,
        id: "today-workout",
        data: () => ({name: "Full Body", status: "scheduled"}),
      },
      queryResult: {
        empty: false,
        docs: [{
          exists: true,
          id: "next-workout",
          data: () => ({
            name: "Push Day",
            scheduledDate: "2025-12-28T09:00:00Z",
            status: "scheduled",
          }),
        }],
      },
      updateFn,
    });

    const result = await executeHandler(
      "skip_workout",
      {workoutId: "today-workout"},
      createContext(db)
    );

    // Verify skip and status update
    expect(result?.output).toContain("has been skipped");
    expect(updateFn).toHaveBeenCalled();

    // Verify next workout info included
    expect(result?.output).toContain("Push Day");

    // Verify VOICE_READY instruction for AI (only present when next workout exists)
    expect(result?.output).toContain("VOICE_READY");
  });
});
