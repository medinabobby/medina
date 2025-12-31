/**
 * Get Substitution Options Handler Tests
 *
 * Tests for get_substitution_options tool
 */

import {describe, it, expect, vi} from "vitest";
import {getSubstitutionOptionsHandler} from "./getSubstitutionOptions";
import type {HandlerContext} from "./index";

// ============================================================================
// Mock Setup
// ============================================================================

function createMockDb() {
  return {
    collection: vi.fn().mockReturnValue({
      doc: vi.fn().mockReturnValue({
        get: vi.fn().mockResolvedValue({exists: false}),
      }),
    }),
  };
}

function createContext(): HandlerContext {
  return {
    uid: "test-user-123",
    db: createMockDb() as any,
  };
}

// ============================================================================
// Tests
// ============================================================================

describe("getSubstitutionOptionsHandler", () => {
  describe("Validation", () => {
    it("returns error when exerciseId is missing", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler({}, context);

      expect(result.output).toContain("ERROR");
      expect(result.output).toContain("exerciseId");
    });
  });

  describe("Known Exercises", () => {
    it("returns alternatives for bench_press", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "bench_press"},
        context
      );

      expect(result.output).toContain("alternatives");
      expect(result.output).toContain("Dumbbell Bench Press");
    });

    it("returns alternatives for squat", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "squat"},
        context
      );

      expect(result.output).toContain("alternatives");
      expect(result.output).toContain("Leg Press");
    });

    it("returns alternatives for pull_up", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "pull_up"},
        context
      );

      expect(result.output).toContain("alternatives");
      expect(result.output).toContain("Lat Pulldown");
    });

    it("returns alternatives for deadlift", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "deadlift"},
        context
      );

      expect(result.output).toContain("alternatives");
      expect(result.output).toContain("Romanian Deadlift");
    });

    it("returns alternatives for bicep_curl", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "bicep_curl"},
        context
      );

      expect(result.output).toContain("alternatives");
      expect(result.output).toContain("Hammer Curl");
    });
  });

  describe("Unknown Exercises", () => {
    it("returns guidance for unknown exercise", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "unknown_exercise"},
        context
      );

      expect(result.output).toContain("No pre-defined alternatives");
      expect(result.output).toContain("Suggestions");
    });

    it("provides suggestion chips for unknown exercise", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "mystery_move"},
        context
      );

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.length).toBeGreaterThan(0);
    });
  });

  describe("Input Normalization", () => {
    it("handles spaces in exercise name", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "bench press"},
        context
      );

      expect(result.output).toContain("alternatives");
    });

    it("handles mixed case", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "Bench_Press"},
        context
      );

      expect(result.output).toContain("alternatives");
    });

    it("handles hyphens", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "bench-press"},
        context
      );

      expect(result.output).toContain("alternatives");
    });
  });

  describe("Output Format", () => {
    it("includes numbered list of alternatives", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "squat"},
        context
      );

      expect(result.output).toMatch(/1\./);
      expect(result.output).toMatch(/2\./);
    });

    it("includes suggestion chips", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "squat"},
        context
      );

      expect(result.suggestionChips).toBeDefined();
      expect(result.suggestionChips?.[0].label).toContain("Substitute");
    });

    it("limits alternatives to 5", async () => {
      const context = createContext();

      const result = await getSubstitutionOptionsHandler(
        {exerciseId: "squat"},
        context
      );

      // Count numbered items in output
      const matches = result.output.match(/\d+\./g);
      expect(matches?.length).toBeLessThanOrEqual(5);
    });
  });
});
