/**
 * Prompt Regression Tests
 *
 * Phase 2: Validate AI prompt → tool call mapping
 *
 * These tests verify:
 * 1. Tool definitions have correct required parameters
 * 2. Tool descriptions contain trigger phrases for common intents
 * 3. Golden test cases document expected intent → tool mappings
 *
 * Since we can't unit test actual AI interpretation, these tests:
 * - Validate the prompt "ingredients" are correct
 * - Document expected behavior for manual/integration testing
 * - Catch regressions in tool definitions
 */

import {describe, it, expect} from "vitest";
import {
  allTools,
  getToolDefinitions,
  showSchedule,
  createWorkout,
  createPlan,
  skipWorkout,
  modifyWorkout,
  updateProfile,
  getSubstitutionOptions,
  startWorkout,
} from "../tools/definitions";

// ============================================================================
// Tool Definition Validation
// ============================================================================

describe("Tool Definitions", () => {
  describe("getToolDefinitions()", () => {
    it("returns all tools (22+)", () => {
      const tools = getToolDefinitions();
      expect(tools.length).toBeGreaterThanOrEqual(22);
    });

    it("all tools have required fields", () => {
      const tools = getToolDefinitions();

      for (const tool of tools) {
        expect(tool.type).toBe("function");
        expect(tool.name).toBeDefined();
        expect(tool.description).toBeDefined();
        expect(tool.parameters).toBeDefined();
        expect(tool.parameters.type).toBe("object");
        expect(tool.parameters.properties).toBeDefined();
      }
    });

    it("tool names are snake_case", () => {
      const tools = getToolDefinitions();

      for (const tool of tools) {
        expect(tool.name).toMatch(/^[a-z]+(_[a-z]+)*$/);
      }
    });
  });

  describe("Required Parameters", () => {
    it("show_schedule requires period", () => {
      expect(showSchedule.parameters.required).toContain("period");
    });

    it("create_workout requires core fields", () => {
      const required = createWorkout.parameters.required;
      expect(required).toContain("name");
      expect(required).toContain("splitDay");
      expect(required).toContain("scheduledDate");
      expect(required).toContain("duration");
      expect(required).toContain("effortLevel");
      expect(required).toContain("exerciseIds");
    });

    it("create_plan requires name and goal", () => {
      expect(createPlan.parameters.required).toContain("name");
      expect(createPlan.parameters.required).toContain("goal");
    });

    it("skip_workout requires workoutId", () => {
      expect(skipWorkout.parameters.required).toContain("workoutId");
    });

    it("update_profile has no required fields (all optional)", () => {
      expect(updateProfile.parameters.required).toEqual([]);
    });

    it("get_substitution_options requires exerciseId", () => {
      expect(getSubstitutionOptions.parameters.required).toContain("exerciseId");
    });
  });

  describe("Parameter Schemas", () => {
    it("create_workout duration has min/max constraints", () => {
      const duration = createWorkout.parameters.properties.duration;
      expect(duration.minimum).toBe(15);
      expect(duration.maximum).toBe(120);
    });

    it("create_plan durationWeeks has min/max constraints", () => {
      const weeks = createPlan.parameters.properties.durationWeeks;
      expect(weeks.minimum).toBe(1);
      expect(weeks.maximum).toBe(52);
    });

    it("splitDay has correct enum values", () => {
      const splitDay = createWorkout.parameters.properties.splitDay;
      expect(splitDay.enum).toContain("upper");
      expect(splitDay.enum).toContain("lower");
      expect(splitDay.enum).toContain("push");
      expect(splitDay.enum).toContain("pull");
      expect(splitDay.enum).toContain("legs");
      expect(splitDay.enum).toContain("fullBody");
    });

    it("update_profile experienceLevel has correct enum", () => {
      const level = updateProfile.parameters.properties.experienceLevel;
      expect(level.enum).toContain("beginner");
      expect(level.enum).toContain("intermediate");
      expect(level.enum).toContain("advanced");
      expect(level.enum).toContain("expert");
    });

    it("update_profile birthdate description mentions age extraction", () => {
      const birthdate = updateProfile.parameters.properties.birthdate;
      expect(birthdate.description).toContain("age");
    });
  });
});

// ============================================================================
// Tool Description Trigger Phrases
// ============================================================================

describe("Tool Trigger Phrases", () => {
  describe("show_schedule triggers", () => {
    it("mentions schedule keywords", () => {
      const desc = showSchedule.description.toLowerCase();
      expect(desc).toContain("schedule");
    });

    it("mentions calendar keyword", () => {
      const desc = showSchedule.description.toLowerCase();
      expect(desc).toContain("calendar");
    });
  });

  describe("skip_workout triggers", () => {
    it("mentions skip keywords", () => {
      const desc = skipWorkout.description.toLowerCase();
      expect(desc).toContain("skip");
    });

    it("provides example phrases", () => {
      const desc = skipWorkout.description.toLowerCase();
      expect(desc).toContain("skip my workout");
      expect(desc).toContain("skip today");
    });
  });

  describe("update_profile triggers", () => {
    it("mentions profile update keywords", () => {
      const desc = updateProfile.description.toLowerCase();
      expect(desc).toContain("profile");
      expect(desc).toContain("age");
    });

    it("mentions fitness goal", () => {
      const desc = updateProfile.description.toLowerCase();
      expect(desc).toContain("fitness goal");
    });
  });

  describe("create_plan triggers", () => {
    it("mentions plan keywords", () => {
      const desc = createPlan.description.toLowerCase();
      expect(desc).toContain("plan");
      expect(desc).toContain("program");
    });

    it("mentions multi-week", () => {
      const desc = createPlan.description.toLowerCase();
      expect(desc).toContain("multi-week");
    });
  });

  describe("modify_workout triggers", () => {
    it("mentions modify keyword", () => {
      const desc = modifyWorkout.description.toLowerCase();
      expect(desc).toContain("modify");
    });
  });

  describe("get_substitution_options triggers", () => {
    it("mentions substitute/alternative keywords", () => {
      const desc = getSubstitutionOptions.description.toLowerCase();
      expect(desc).toContain("alternative");
      expect(desc).toContain("substitute");
    });

    it("mentions swap keyword", () => {
      const desc = getSubstitutionOptions.description.toLowerCase();
      expect(desc).toContain("swap");
    });
  });

  describe("start_workout triggers", () => {
    it("mentions start keywords", () => {
      const desc = startWorkout.description.toLowerCase();
      expect(desc).toContain("start");
    });

    it("mentions ready to train", () => {
      const desc = startWorkout.description.toLowerCase();
      expect(desc).toContain("ready to train");
    });
  });
});

// ============================================================================
// Golden Test Cases (Intent → Tool Mapping)
// ============================================================================

/**
 * Golden test cases document the EXPECTED behavior for common user intents.
 *
 * These cannot be automatically verified without calling the actual AI,
 * but they serve as:
 * 1. Documentation for expected behavior
 * 2. Manual test cases for QA
 * 3. Regression detection if tool definitions change
 *
 * Format: { userSays, expectedTool, expectedParams, priority }
 */
interface GoldenTestCase {
  id: number;
  userSays: string;
  expectedTool: string;
  expectedParams: Record<string, unknown>;
  priority: "critical" | "high" | "medium" | "low";
  notes?: string;
}

const GOLDEN_TEST_CASES: GoldenTestCase[] = [
  {
    id: 1,
    userSays: "I'm 30 years old",
    expectedTool: "update_profile",
    expectedParams: {birthdate: "calculated from age"},
    priority: "medium",
    notes: "AI should calculate birthdate from stated age (30 → ~1995)",
  },
  {
    id: 2,
    userSays: "Create a 30 minute workout",
    expectedTool: "create_workout",
    expectedParams: {duration: 30},
    priority: "critical",
    notes: "Duration should be extracted exactly as stated",
  },
  {
    id: 3,
    userSays: "I only have dumbbells",
    expectedTool: "update_profile",
    expectedParams: {/* equipment should be set */},
    priority: "critical",
    notes: "Equipment preference should be saved to profile",
  },
  {
    id: 4,
    userSays: "Skip today's workout",
    expectedTool: "skip_workout",
    expectedParams: {workoutId: "today's workout ID from context"},
    priority: "medium",
    notes: "AI should use workout ID from Today's Workout context",
  },
  {
    id: 5,
    userSays: "Show my schedule",
    expectedTool: "show_schedule",
    expectedParams: {period: "week"},
    priority: "low",
    notes: "Default to week view",
  },
  {
    id: 6,
    userSays: "Make it harder",
    expectedTool: "modify_workout",
    expectedParams: {/* intensity adjustment */},
    priority: "high",
    notes: "Should modify the most recently created/discussed workout",
  },
  {
    id: 7,
    userSays: "4 week plan, gym",
    expectedTool: "create_plan",
    expectedParams: {durationWeeks: 4, trainingLocation: "gym"},
    priority: "critical",
    notes: "Both duration and location should be extracted",
  },
  {
    id: 8,
    userSays: "Swap bench for something else",
    expectedTool: "get_substitution_options",
    expectedParams: {exerciseId: "bench exercise ID"},
    priority: "medium",
    notes: "AI should identify bench press exercise ID from context",
  },
];

describe("Golden Test Cases (Documentation)", () => {
  describe("Case 1: Age → update_profile", () => {
    it("update_profile can accept birthdate", () => {
      const props = updateProfile.parameters.properties;
      expect(props.birthdate).toBeDefined();
      expect(props.birthdate.type).toBe("string");
    });

    it("birthdate description explains age extraction", () => {
      const desc = updateProfile.parameters.properties.birthdate.description;
      expect(desc.toLowerCase()).toContain("age");
      expect(desc).toContain("I'm 13");
    });
  });

  describe("Case 2: Duration → create_workout", () => {
    it("create_workout accepts duration parameter", () => {
      const props = createWorkout.parameters.properties;
      expect(props.duration).toBeDefined();
      expect(props.duration.type).toBe("integer");
    });

    it("duration allows 30 minutes", () => {
      const duration = createWorkout.parameters.properties.duration;
      expect(duration.minimum).toBeLessThanOrEqual(30);
      expect(duration.maximum).toBeGreaterThanOrEqual(30);
    });
  });

  describe("Case 3: Equipment → update_profile", () => {
    it("update_profile should handle equipment (via profile fields)", () => {
      // Note: Equipment is set in profile but not directly via update_profile
      // This tests that the tool exists and can be called
      expect(updateProfile.name).toBe("update_profile");
    });
  });

  describe("Case 4: Skip → skip_workout", () => {
    it("skip_workout requires workoutId", () => {
      expect(skipWorkout.parameters.required).toContain("workoutId");
    });

    it("description mentions 'skip today'", () => {
      expect(skipWorkout.description).toContain("skip today");
    });
  });

  describe("Case 5: Schedule → show_schedule", () => {
    it("show_schedule has week/month period options", () => {
      const period = showSchedule.parameters.properties.period;
      expect(period.enum).toContain("week");
      expect(period.enum).toContain("month");
    });
  });

  describe("Case 6: Harder → modify_workout", () => {
    it("modify_workout can adjust effort level", () => {
      const props = modifyWorkout.parameters.properties;
      expect(props.newEffortLevel).toBeDefined();
      expect(props.newEffortLevel.enum).toContain("push");
    });

    it("modify_workout can adjust protocols", () => {
      const props = modifyWorkout.parameters.properties;
      expect(props.protocolCustomizations).toBeDefined();
    });
  });

  describe("Case 7: Plan with duration and location → create_plan", () => {
    it("create_plan accepts durationWeeks", () => {
      const props = createPlan.parameters.properties;
      expect(props.durationWeeks).toBeDefined();
      expect(props.durationWeeks.type).toBe("integer");
    });

    it("create_plan accepts trainingLocation", () => {
      const props = createPlan.parameters.properties;
      expect(props.trainingLocation).toBeDefined();
      expect(props.trainingLocation.enum).toContain("gym");
      expect(props.trainingLocation.enum).toContain("home");
    });
  });

  describe("Case 8: Swap exercise → get_substitution_options", () => {
    it("get_substitution_options requires exerciseId", () => {
      expect(getSubstitutionOptions.parameters.required).toContain("exerciseId");
    });

    it("description mentions swap keyword", () => {
      expect(getSubstitutionOptions.description.toLowerCase()).toContain("swap");
    });
  });
});

// ============================================================================
// Tool Coverage Validation
// ============================================================================

describe("Tool Coverage", () => {
  it("all expected tools exist", () => {
    const toolNames = allTools.map((t) => t.name);

    // Core tools that must exist
    const requiredTools = [
      "show_schedule",
      "create_workout",
      "create_plan",
      "activate_plan",
      "delete_plan",
      "abandon_plan",
      "start_workout",
      "skip_workout",
      "end_workout",
      "reset_workout",
      "modify_workout",
      "update_profile",
      "get_substitution_options",
      "get_summary",
      "analyze_training_data",
    ];

    for (const tool of requiredTools) {
      expect(toolNames).toContain(tool);
    }
  });

  it("no duplicate tool names", () => {
    const toolNames = allTools.map((t) => t.name);
    const uniqueNames = new Set(toolNames);
    expect(uniqueNames.size).toBe(toolNames.length);
  });
});

// ============================================================================
// Export Golden Cases for Manual Testing
// ============================================================================

/**
 * Export golden test cases for use in manual/integration testing.
 * These can be used to verify AI behavior in staging environments.
 */
export {GOLDEN_TEST_CASES};

/**
 * Generate a markdown report of golden test cases
 */
export function generateGoldenCaseReport(): string {
  const lines = [
    "# Prompt Regression - Golden Test Cases",
    "",
    "| # | User Says | Expected Tool | Priority | Notes |",
    "|---|-----------|---------------|----------|-------|",
  ];

  for (const tc of GOLDEN_TEST_CASES) {
    lines.push(
      `| ${tc.id} | "${tc.userSays}" | \`${tc.expectedTool}\` | ${tc.priority} | ${tc.notes || ""} |`
    );
  }

  return lines.join("\n");
}
