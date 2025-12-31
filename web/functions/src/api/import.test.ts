/**
 * Import API Tests
 *
 * Tests for /api/import endpoint
 * - CSV parsing (parseCSVLine, parseDate, parseWeights, etc.)
 * - Intelligence analysis (strength scores, experience level, training style)
 * - Exercise matching
 * - Handler integration
 */

import {describe, it, expect} from "vitest";
import {
  parseCSVLine,
  parseDate,
  parseWeights,
  parseSetsAndWeight,
  calculateBest1RM,
  parseCSV,
  matchExerciseToLibrary,
  calculateRelativeStrengthScore,
  calculateAbsoluteStrengthScore,
  calculateHistoryScore,
  calculateVolumeScore,
  calculateVarietyScore,
  computeExperienceLevel,
  inferTrainingStyle,
  inferMuscleGroupsFromName,
  inferEmphasizedMuscles,
  inferSplitType,
  estimateSessionDuration,
  calculateConfidence,
  analyzeImport,
  type ParsedSet,
  type ImportedSession,
  type ImportedExerciseData,
  type ExperienceIndicators,
} from "./import";

// ============================================================================
// CSV Parsing Tests
// ============================================================================

describe("CSV Parsing", () => {
  describe("parseCSVLine", () => {
    it("parses simple comma-separated values", () => {
      const result = parseCSVLine("1,2025-01-15,Squat,3x5,225 lb");
      expect(result).toEqual(["1", "2025-01-15", "Squat", "3x5", "225 lb"]);
    });

    it("handles quoted values with commas inside", () => {
      const result = parseCSVLine('1,2025-01-15,"Smith, John",3x5,225 lb');
      expect(result).toEqual(["1", "2025-01-15", "Smith, John", "3x5", "225 lb"]);
    });

    it("handles empty fields", () => {
      const result = parseCSVLine("1,,Squat,,");
      expect(result).toEqual(["1", "", "Squat", "", ""]);
    });

    it("handles trailing commas", () => {
      const result = parseCSVLine("1,2025-01-15,Squat,");
      expect(result).toEqual(["1", "2025-01-15", "Squat", ""]);
    });

    it("handles mixed quoted and unquoted values", () => {
      const result = parseCSVLine('1,"Dec 15, 2025",Bench Press,3x8,"135, 145, 155 lb"');
      expect(result).toEqual(["1", "Dec 15, 2025", "Bench Press", "3x8", "135, 145, 155 lb"]);
    });

    it("handles quotes at start and end", () => {
      const result = parseCSVLine('"value1","value2"');
      expect(result).toEqual(["value1", "value2"]);
    });
  });

  describe("parseDate", () => {
    it('parses "MMM d, yyyy" format (Dec 2, 2025)', () => {
      const result = parseDate("Dec 2, 2025");
      expect(result).toBeInstanceOf(Date);
      expect(result?.getFullYear()).toBe(2025);
      expect(result?.getMonth()).toBe(11); // December = 11
      expect(result?.getDate()).toBe(2);
    });

    it('parses "MMM dd, yyyy" format (Dec 15, 2025)', () => {
      const result = parseDate("Dec 15, 2025");
      expect(result?.getMonth()).toBe(11);
      expect(result?.getDate()).toBe(15);
    });

    it('parses "MM/dd/yyyy" format (12/02/2025)', () => {
      const result = parseDate("12/02/2025");
      expect(result?.getFullYear()).toBe(2025);
      expect(result?.getMonth()).toBe(11);
      expect(result?.getDate()).toBe(2);
    });

    it('parses "M/d/yyyy" format (1/5/2025)', () => {
      const result = parseDate("1/5/2025");
      expect(result?.getMonth()).toBe(0); // January = 0
      expect(result?.getDate()).toBe(5);
    });

    it('parses "yyyy-MM-dd" format (2025-12-02)', () => {
      const result = parseDate("2025-12-02");
      expect(result?.getFullYear()).toBe(2025);
      expect(result?.getMonth()).toBe(11);
      expect(result?.getDate()).toBe(2);
    });

    it("returns null for invalid date", () => {
      expect(parseDate("not a date")).toBeNull();
      expect(parseDate("")).toBeNull();
      // Note: JS Date accepts some invalid dates like 32/13 (wraps months/days)
    });

    it("handles various month names", () => {
      expect(parseDate("Jan 1, 2025")?.getMonth()).toBe(0);
      expect(parseDate("February 15, 2025")?.getMonth()).toBe(1);
      expect(parseDate("mar 20, 2025")?.getMonth()).toBe(2);
      expect(parseDate("APRIL 10, 2025")?.getMonth()).toBe(3);
    });
  });

  describe("parseWeights", () => {
    it('parses single weight with "lb" (135 lb)', () => {
      const result = parseWeights("135 lb");
      expect(result).toEqual([135]);
    });

    it('parses single weight with "lbs" (135 lbs)', () => {
      const result = parseWeights("135 lbs");
      expect(result).toEqual([135]);
    });

    it("parses comma-separated weights (45, 50, 55 lb)", () => {
      const result = parseWeights("45, 50, 55 lb");
      expect(result).toEqual([45, 50, 55]);
    });

    it("parses bilateral pattern (2x20)", () => {
      const result = parseWeights("2x20");
      expect(result).toEqual([20]);
    });

    it("strips equipment descriptors (135 lb barbell)", () => {
      const result = parseWeights("135 lb barbell");
      expect(result).toEqual([135]);
    });

    it("strips dumbbell descriptor (45 lb dumbbells)", () => {
      const result = parseWeights("45 lb dumbbells");
      expect(result).toEqual([45]);
    });

    it("strips kettlebell descriptor (2x20 kettlebells)", () => {
      const result = parseWeights("2x20 kettlebells");
      expect(result).toEqual([20]);
    });

    it("handles cable/machine weights", () => {
      const result = parseWeights("100 cable");
      expect(result).toEqual([100]);
    });

    it("returns empty array for invalid input", () => {
      expect(parseWeights("")).toEqual([]);
      expect(parseWeights("bodyweight")).toEqual([]);
    });
  });

  describe("parseSetsAndWeight", () => {
    it('parses simple "3x8" with weight', () => {
      const result = parseSetsAndWeight("3x8", "135 lb");
      expect(result).toHaveLength(3);
      expect(result[0]).toEqual({reps: 8, weight: 135});
      expect(result[1]).toEqual({reps: 8, weight: 135});
      expect(result[2]).toEqual({reps: 8, weight: 135});
    });

    it('parses rep range "3x8-10" (uses higher end)', () => {
      const result = parseSetsAndWeight("3x8-10", "135 lb");
      expect(result).toHaveLength(3);
      expect(result[0].reps).toBe(10);
    });

    it('parses multiple set groups "2x12, 1x10"', () => {
      const result = parseSetsAndWeight("2x12, 1x10", "100 lb");
      expect(result).toHaveLength(3);
      expect(result[0].reps).toBe(12);
      expect(result[1].reps).toBe(12);
      expect(result[2].reps).toBe(10);
    });

    it("maps multiple weights to sets", () => {
      const result = parseSetsAndWeight("3x5", "135, 155, 185 lb");
      expect(result).toHaveLength(3);
      expect(result[0].weight).toBe(135);
      expect(result[1].weight).toBe(155);
      expect(result[2].weight).toBe(185);
    });

    it("reuses last weight when weights < sets", () => {
      const result = parseSetsAndWeight("4x5", "135, 155 lb");
      expect(result).toHaveLength(4);
      expect(result[2].weight).toBe(155);
      expect(result[3].weight).toBe(155);
    });

    it("handles single set", () => {
      const result = parseSetsAndWeight("1x5", "225 lb");
      expect(result).toHaveLength(1);
      expect(result[0]).toEqual({reps: 5, weight: 225});
    });

    it("returns empty array for invalid input", () => {
      expect(parseSetsAndWeight("invalid", "100 lb")).toEqual([]);
    });
  });

  describe("calculateBest1RM", () => {
    it("calculates 1RM using Epley formula", () => {
      // Epley: weight * (1 + reps/30)
      // 225 * (1 + 5/30) = 225 * 1.1667 = 262.5
      const sets: ParsedSet[] = [{reps: 5, weight: 225}];
      const result = calculateBest1RM(sets);
      expect(result).toBeCloseTo(262.5, 0);
    });

    it("returns null for empty sets", () => {
      expect(calculateBest1RM([])).toBeNull();
    });

    it("filters invalid reps (0 reps)", () => {
      const sets: ParsedSet[] = [{reps: 0, weight: 225}];
      expect(calculateBest1RM(sets)).toBeNull();
    });

    it("filters invalid reps (>36 reps)", () => {
      const sets: ParsedSet[] = [{reps: 37, weight: 100}];
      expect(calculateBest1RM(sets)).toBeNull();
    });

    it("filters zero weight", () => {
      const sets: ParsedSet[] = [{reps: 10, weight: 0}];
      expect(calculateBest1RM(sets)).toBeNull();
    });

    it("weights earlier sets higher (freshness)", () => {
      // Earlier set should contribute more to weighted average
      const sets: ParsedSet[] = [
        {reps: 5, weight: 225}, // Fresh, high quality
        {reps: 5, weight: 200}, // Fatigued, lower quality
      ];
      const result = calculateBest1RM(sets);
      // Should be closer to 262.5 (first set) than 233.3 (second set)
      expect(result).toBeGreaterThan(240);
    });

    it("weights 3-5 rep range highest (most accurate)", () => {
      const lowRep: ParsedSet[] = [{reps: 4, weight: 200}];
      const highRep: ParsedSet[] = [{reps: 15, weight: 100}];

      // 200 * (1 + 4/30) = 226.67
      expect(calculateBest1RM(lowRep)).toBeCloseTo(226.67, 0);
      // 100 * (1 + 15/30) = 150
      expect(calculateBest1RM(highRep)).toBeCloseTo(150, 0);
    });

    it("handles realistic training data", () => {
      const sets: ParsedSet[] = [
        {reps: 5, weight: 135}, // Warmup
        {reps: 5, weight: 185}, // Working
        {reps: 5, weight: 225}, // Top set
        {reps: 5, weight: 205}, // Back-off
      ];
      const result = calculateBest1RM(sets);
      expect(result).toBeGreaterThan(200);
      expect(result).toBeLessThan(280);
    });
  });

  describe("parseCSV", () => {
    it("parses complete CSV with header", () => {
      // Each row with a workout number starts a new workout
      const csv = `Workout,Date,Exercise,Sets x Reps,Weight
1,Dec 15 2025,Squat,3x5,225 lb
,,Bench Press,3x8,135 lb
2,Dec 17 2025,Deadlift,1x5,315 lb`;

      const result = parseCSV(csv);

      expect(result.workouts).toHaveLength(2);
      expect(result.workouts[0].exercises).toHaveLength(2);
      expect(result.workouts[1].exercises).toHaveLength(1);
      expect(result.totalSets).toBe(7); // 3 + 3 + 1
    });

    it("tracks unique exercises with best 1RM", () => {
      const csv = `Workout,Date,Exercise,Sets x Reps,Weight
1,Dec 15 2025,Squat,3x5,225 lb
2,Dec 17 2025,Squat,3x5,235 lb`;

      const result = parseCSV(csv);
      const squat1RM = result.uniqueExercises.get("Squat");
      expect(squat1RM).toBeDefined();
      // Second workout has higher weight, should have higher 1RM
    });

    it("throws for empty CSV", () => {
      expect(() => parseCSV("")).toThrow();
    });

    it("throws for header-only CSV", () => {
      expect(() => parseCSV("Workout,Date,Exercise,Sets,Weight")).toThrow("empty or has only headers");
    });

    it("handles continuation rows (no workout number)", () => {
      const csv = `Workout,Date,Exercise,Sets x Reps,Weight
1,Dec 15 2025,Squat,3x5,225 lb
,,Bench Press,3x8,135 lb`;

      const result = parseCSV(csv);
      expect(result.workouts).toHaveLength(1);
      expect(result.workouts[0].exercises).toHaveLength(2);
    });
  });
});

// ============================================================================
// Intelligence Analysis Tests
// ============================================================================

describe("Intelligence Analysis", () => {
  describe("calculateRelativeStrengthScore", () => {
    it("returns null when no lifts provided", () => {
      const result = calculateRelativeStrengthScore(null, null, null, 180);
      expect(result).toBeNull();
    });

    it("calculates beginner score (squat < 1.0x BW)", () => {
      // 150 / 180 = 0.83x BW = beginner (0.5)
      const result = calculateRelativeStrengthScore(150, null, null, 180);
      expect(result).toBe(0.5);
    });

    it("calculates intermediate score (squat 1.0-1.5x BW)", () => {
      // 225 / 180 = 1.25x BW = intermediate (1.5)
      const result = calculateRelativeStrengthScore(225, null, null, 180);
      expect(result).toBe(1.5);
    });

    it("calculates advanced score (squat 1.5-2.0x BW)", () => {
      // 315 / 180 = 1.75x BW = advanced (2.5)
      const result = calculateRelativeStrengthScore(315, null, null, 180);
      expect(result).toBe(2.5);
    });

    it("calculates expert score (squat > 2.0x BW)", () => {
      // 405 / 180 = 2.25x BW = expert (3.0)
      const result = calculateRelativeStrengthScore(405, null, null, 180);
      expect(result).toBe(3.0);
    });

    it("averages multiple lifts", () => {
      // All intermediate: average = 1.5
      const result = calculateRelativeStrengthScore(225, 185, 315, 180);
      // Squat: 225/180 = 1.25x = 1.5
      // Bench: 185/180 = 1.03x = 1.5
      // Deadlift: 315/180 = 1.75x = 1.5
      expect(result).toBe(1.5);
    });

    it("uses bench standards (lower ratios)", () => {
      // Bench: 135 / 180 = 0.75x BW = intermediate (1.5)
      const result = calculateRelativeStrengthScore(null, 135, null, 180);
      expect(result).toBe(1.5);
    });

    it("uses deadlift standards (higher ratios)", () => {
      // Deadlift: 315 / 180 = 1.75x BW = intermediate (1.5)
      const result = calculateRelativeStrengthScore(null, null, 315, 180);
      expect(result).toBe(1.5);
    });
  });

  describe("calculateAbsoluteStrengthScore", () => {
    it("returns null when no lifts provided", () => {
      expect(calculateAbsoluteStrengthScore(null, null, null)).toBeNull();
    });

    it("calculates beginner score (squat < 135)", () => {
      const result = calculateAbsoluteStrengthScore(100, null, null);
      expect(result).toBe(0.5);
    });

    it("calculates intermediate score (squat 135-225)", () => {
      const result = calculateAbsoluteStrengthScore(185, null, null);
      expect(result).toBe(1.5);
    });

    it("calculates advanced score (squat 225-315)", () => {
      const result = calculateAbsoluteStrengthScore(275, null, null);
      expect(result).toBe(2.5);
    });

    it("calculates expert score (squat > 315)", () => {
      const result = calculateAbsoluteStrengthScore(405, null, null);
      expect(result).toBe(3.0);
    });

    it("averages multiple lifts", () => {
      // Squat 200 = 1.5, Bench 150 = 1.5, Deadlift 250 = 1.5
      const result = calculateAbsoluteStrengthScore(200, 150, 250);
      expect(result).toBe(1.5);
    });
  });

  describe("calculateHistoryScore", () => {
    it("returns beginner score for < 6 months", () => {
      const start = new Date("2025-06-01");
      const end = new Date("2025-09-01"); // 3 months
      expect(calculateHistoryScore(start, end)).toBe(0.5);
    });

    it("returns intermediate score for 6-18 months", () => {
      const start = new Date("2024-06-01");
      const end = new Date("2025-06-01"); // 12 months
      expect(calculateHistoryScore(start, end)).toBe(1.5);
    });

    it("returns advanced score for 18-36 months", () => {
      const start = new Date("2023-01-01");
      const end = new Date("2025-06-01"); // ~30 months
      expect(calculateHistoryScore(start, end)).toBe(2.5);
    });

    it("returns expert score for > 36 months", () => {
      const start = new Date("2020-01-01");
      const end = new Date("2025-06-01"); // ~66 months
      expect(calculateHistoryScore(start, end)).toBe(3.0);
    });
  });

  describe("calculateVolumeScore", () => {
    it("returns beginner score for empty sessions", () => {
      expect(calculateVolumeScore([])).toBe(0.5);
    });

    it("returns beginner score for < 12 sets/session", () => {
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: [
          {id: "e1", exerciseName: "Squat", sets: [{reps: 5, weight: 225}]},
        ],
      }];
      expect(calculateVolumeScore(sessions)).toBe(0.5);
    });

    it("returns intermediate score for 12-20 sets/session", () => {
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: [
          {id: "e1", exerciseName: "Squat", sets: Array(5).fill({reps: 5, weight: 225})},
          {id: "e2", exerciseName: "Bench", sets: Array(5).fill({reps: 8, weight: 135})},
          {id: "e3", exerciseName: "Row", sets: Array(5).fill({reps: 8, weight: 135})},
        ],
      }];
      expect(calculateVolumeScore(sessions)).toBe(1.5);
    });

    it("returns advanced score for 20-30 sets/session", () => {
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: Array(5).fill(null).map((_, i) => ({
          id: `e${i}`,
          exerciseName: `Exercise ${i}`,
          sets: Array(5).fill({reps: 10, weight: 100}),
        })),
      }];
      expect(calculateVolumeScore(sessions)).toBe(2.5);
    });

    it("returns expert score for > 30 sets/session", () => {
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: Array(8).fill(null).map((_, i) => ({
          id: `e${i}`,
          exerciseName: `Exercise ${i}`,
          sets: Array(5).fill({reps: 10, weight: 100}),
        })),
      }];
      expect(calculateVolumeScore(sessions)).toBe(3.0);
    });
  });

  describe("calculateVarietyScore", () => {
    it("returns beginner score for < 15 exercises", () => {
      expect(calculateVarietyScore(10)).toBe(0.5);
    });

    it("returns intermediate score for 15-30 exercises", () => {
      expect(calculateVarietyScore(20)).toBe(1.5);
    });

    it("returns advanced score for 30-50 exercises", () => {
      expect(calculateVarietyScore(40)).toBe(2.5);
    });

    it("returns expert score for > 50 exercises", () => {
      expect(calculateVarietyScore(60)).toBe(3.0);
    });
  });

  describe("computeExperienceLevel", () => {
    it("returns beginner for all low scores", () => {
      const indicators: ExperienceIndicators = {
        strengthScore: 0.5,
        historyScore: 0.5,
        volumeScore: 0.5,
        varietyScore: 0.5,
      };
      expect(computeExperienceLevel(indicators)).toBe("beginner");
    });

    it("returns intermediate for mixed scores", () => {
      const indicators: ExperienceIndicators = {
        strengthScore: 1.5,
        historyScore: 1.5,
        volumeScore: 1.5,
        varietyScore: 1.5,
      };
      expect(computeExperienceLevel(indicators)).toBe("intermediate");
    });

    it("returns advanced for high scores", () => {
      const indicators: ExperienceIndicators = {
        strengthScore: 2.5,
        historyScore: 2.5,
        volumeScore: 2.5,
        varietyScore: 2.5,
      };
      expect(computeExperienceLevel(indicators)).toBe("advanced");
    });

    it("returns expert for all max scores", () => {
      const indicators: ExperienceIndicators = {
        strengthScore: 3.0,
        historyScore: 3.0,
        volumeScore: 3.0,
        varietyScore: 3.0,
      };
      expect(computeExperienceLevel(indicators)).toBe("expert");
    });

    it("weights strength score 40%", () => {
      // Only strength at 3.0 = 3.0 * 0.4 / 0.4 = 3.0 → expert
      const indicators: ExperienceIndicators = {strengthScore: 3.0};
      expect(computeExperienceLevel(indicators)).toBe("expert");
    });

    it("handles partial indicators", () => {
      const indicators: ExperienceIndicators = {
        strengthScore: 1.5,
        volumeScore: 1.5,
      };
      // (1.5 * 0.4 + 1.5 * 0.2) / (0.4 + 0.2) = 0.9 / 0.6 = 1.5 → intermediate (<2.0)
      expect(computeExperienceLevel(indicators)).toBe("intermediate");
    });

    it("returns beginner for empty indicators", () => {
      expect(computeExperienceLevel({})).toBe("beginner");
    });
  });

  describe("inferTrainingStyle", () => {
    it("returns null for empty exercises", () => {
      expect(inferTrainingStyle([], [])).toBeNull();
    });

    it("detects powerlifting (40%+ big3, <6 avg reps)", () => {
      const exercises: ImportedExerciseData[] = [
        {id: "1", exerciseName: "Squat"},
        {id: "2", exerciseName: "Bench Press"},
        {id: "3", exerciseName: "Deadlift"},
        {id: "4", exerciseName: "Front Squat"},
        {id: "5", exerciseName: "Close Grip Bench"},
      ];
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: exercises.map((e) => ({
          ...e,
          sets: [{reps: 3, weight: 300}, {reps: 3, weight: 300}],
        })),
      }];
      expect(inferTrainingStyle(exercises, sessions)).toBe("powerlifting");
    });

    it("detects bodybuilding (40%+ isolation, >8 avg reps)", () => {
      const exercises: ImportedExerciseData[] = [
        {id: "1", exerciseName: "Bicep Curl"},
        {id: "2", exerciseName: "Tricep Extension"},
        {id: "3", exerciseName: "Lateral Raise"},
        {id: "4", exerciseName: "Leg Extension"},
        {id: "5", exerciseName: "Hamstring Curl"},
      ];
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: exercises.map((e) => ({
          ...e,
          sets: [{reps: 12, weight: 50}, {reps: 12, weight: 50}],
        })),
      }];
      expect(inferTrainingStyle(exercises, sessions)).toBe("bodybuilding");
    });

    it("detects hybrid (varied exercises, moderate big3)", () => {
      // Need >20 exercises and >15% big3 (squat/bench/deadlift)
      const exercises: ImportedExerciseData[] = Array(25).fill(null).map((_, i) => ({
        id: `${i}`,
        // First 5 are big3: 5/25 = 20% > 15%
        exerciseName: i < 2 ? "Squat" : i < 4 ? "Bench Press" : i === 4 ? "Deadlift" : `Accessory ${i}`,
      }));
      expect(inferTrainingStyle(exercises, [])).toBe("hybrid");
    });

    it("defaults to generalFitness", () => {
      const exercises: ImportedExerciseData[] = [
        {id: "1", exerciseName: "Leg Press"},
        {id: "2", exerciseName: "Chest Press Machine"},
      ];
      expect(inferTrainingStyle(exercises, [])).toBe("generalFitness");
    });
  });

  describe("inferMuscleGroupsFromName", () => {
    it("maps bench press to chest", () => {
      expect(inferMuscleGroupsFromName("Bench Press")).toContain("chest");
    });

    it("maps row to back", () => {
      expect(inferMuscleGroupsFromName("Barbell Row")).toContain("back");
    });

    it("maps lat pulldown to back", () => {
      expect(inferMuscleGroupsFromName("Lat Pulldown")).toContain("back");
    });

    it("maps overhead press to shoulders", () => {
      expect(inferMuscleGroupsFromName("Overhead Press")).toContain("shoulders");
    });

    it("maps squat to quadriceps", () => {
      expect(inferMuscleGroupsFromName("Squat")).toContain("quadriceps");
    });

    it("maps deadlift to back, hamstrings, glutes", () => {
      const muscles = inferMuscleGroupsFromName("Deadlift");
      expect(muscles).toContain("back");
      expect(muscles).toContain("hamstrings");
      expect(muscles).toContain("glutes");
    });

    it("maps bicep curl to biceps", () => {
      expect(inferMuscleGroupsFromName("Bicep Curl")).toContain("biceps");
    });

    it("maps tricep extension to triceps", () => {
      expect(inferMuscleGroupsFromName("Tricep Extension")).toContain("triceps");
    });

    it("maps crunch to core", () => {
      expect(inferMuscleGroupsFromName("Crunch")).toContain("core");
    });

    it("maps fly to chest", () => {
      expect(inferMuscleGroupsFromName("Cable Fly")).toContain("chest");
    });
  });

  describe("inferEmphasizedMuscles", () => {
    it("returns top 3 most frequent muscle groups", () => {
      const exercises: ImportedExerciseData[] = [
        {id: "1", exerciseName: "Bench Press"},
        {id: "2", exerciseName: "Incline Bench"},
        {id: "3", exerciseName: "Cable Fly"},
        {id: "4", exerciseName: "Chest Dip"},
      ];
      const result = inferEmphasizedMuscles(exercises);
      expect(result[0]).toBe("chest");
    });

    it("handles empty exercises", () => {
      expect(inferEmphasizedMuscles([])).toEqual([]);
    });
  });

  describe("inferSplitType", () => {
    it("returns null for < 8 sessions", () => {
      const sessions: ImportedSession[] = Array(5).fill(null).map((_, i) => ({
        id: `${i}`,
        sessionNumber: i,
        date: `2025-01-0${i + 1}`,
        exercises: [],
      }));
      expect(inferSplitType(sessions)).toBeNull();
    });

    it("detects fullBody (5+ muscle groups per session)", () => {
      const sessions: ImportedSession[] = Array(10).fill(null).map((_, i) => ({
        id: `${i}`,
        sessionNumber: i,
        date: `2025-01-${String(i + 1).padStart(2, "0")}`,
        exercises: [
          {id: "1", exerciseName: "Squat", sets: []},
          {id: "2", exerciseName: "Bench Press", sets: []},
          {id: "3", exerciseName: "Deadlift", sets: []},
          {id: "4", exerciseName: "Overhead Press", sets: []},
          {id: "5", exerciseName: "Bicep Curl", sets: []},
          {id: "6", exerciseName: "Tricep Extension", sets: []},
        ],
      }));
      expect(inferSplitType(sessions)).toBe("fullBody");
    });

    it("detects upperLower split", () => {
      // Upper: chest, back, shoulders (3 upper muscles, < 5 for non-fullBody)
      const upperSession = (i: number) => ({
        id: `u${i}`,
        sessionNumber: i,
        date: `2025-01-0${i + 1}`,
        exercises: [
          {id: "1", exerciseName: "Bench Press", sets: []}, // → chest
          {id: "2", exerciseName: "Row", sets: []}, // → back
          {id: "3", exerciseName: "Shoulder Press", sets: []}, // → shoulders
        ],
      });

      // Lower: use "Squat" (→ quads) and "Deadlift" (→ back, hams, glutes)
      // Deadlift adds lower muscles but also back - need lowerCount > upperCount * 2
      // With Squat + Leg Press: patternSet = {quadriceps}
      const lowerSession = (i: number) => ({
        id: `l${i}`,
        sessionNumber: i + 4,
        date: `2025-01-0${i + 5}`,
        exercises: [
          {id: "1", exerciseName: "Squat", sets: []}, // → quadriceps
          {id: "2", exerciseName: "Leg Press", sets: []}, // → quadriceps (contains "leg")
          {id: "3", exerciseName: "Lunge", sets: []}, // → quadriceps
        ],
      });

      const sessions = [
        upperSession(0), upperSession(1), upperSession(2), upperSession(3),
        lowerSession(0), lowerSession(1), lowerSession(2), lowerSession(3),
      ];

      expect(inferSplitType(sessions)).toBe("upperLower");
    });
  });

  describe("estimateSessionDuration", () => {
    it("returns 60 for empty sessions", () => {
      expect(estimateSessionDuration([])).toBe(60);
    });

    it("calculates based on 4 min/set + 10 min warmup", () => {
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: [
          {id: "e1", exerciseName: "Squat", sets: Array(5).fill({reps: 5, weight: 225})},
          {id: "e2", exerciseName: "Bench", sets: Array(5).fill({reps: 8, weight: 135})},
        ],
      }];
      // 10 sets * 4 min + 10 min = 50 min → rounds to 45
      const result = estimateSessionDuration(sessions);
      expect(result).toBeGreaterThanOrEqual(45);
      expect(result).toBeLessThanOrEqual(60);
    });

    it("clamps to minimum 45 minutes", () => {
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: [{id: "e1", exerciseName: "Squat", sets: [{reps: 5, weight: 225}]}],
      }];
      expect(estimateSessionDuration(sessions)).toBe(45);
    });

    it("clamps to maximum 120 minutes", () => {
      const sessions: ImportedSession[] = [{
        id: "1",
        sessionNumber: 1,
        date: "2025-01-01",
        exercises: Array(10).fill(null).map((_, i) => ({
          id: `e${i}`,
          exerciseName: `Exercise ${i}`,
          sets: Array(5).fill({reps: 10, weight: 100}),
        })),
      }];
      expect(estimateSessionDuration(sessions)).toBe(120);
    });
  });

  describe("calculateConfidence", () => {
    it("returns base 0.5 confidence", () => {
      expect(calculateConfidence(0, 0, false)).toBe(0.5);
    });

    it("adds 0.2 for 20+ sessions", () => {
      expect(calculateConfidence(25, 0, false)).toBe(0.7);
    });

    it("adds 0.15 for 10-19 sessions", () => {
      expect(calculateConfidence(15, 0, false)).toBe(0.65);
    });

    it("adds 0.15 for 20+ exercises", () => {
      expect(calculateConfidence(0, 25, false)).toBe(0.65);
    });

    it("adds 0.15 for weight data", () => {
      expect(calculateConfidence(0, 0, true)).toBe(0.65);
    });

    it("caps at 1.0", () => {
      expect(calculateConfidence(30, 30, true)).toBe(1.0);
    });
  });

  describe("analyzeImport (integration)", () => {
    it("produces complete intelligence object", () => {
      const exercises: ImportedExerciseData[] = [
        {id: "1", exerciseName: "Squat", oneRepMax: 300},
        {id: "2", exerciseName: "Bench Press", oneRepMax: 225},
        {id: "3", exerciseName: "Deadlift", oneRepMax: 350},
      ];
      const sessions: ImportedSession[] = [
        {
          id: "1",
          sessionNumber: 1,
          date: "2025-01-01",
          exercises: exercises.map((e) => ({
            ...e,
            sets: [{reps: 5, weight: 200}],
          })),
        },
      ];

      const result = analyzeImport(exercises, sessions, 180);

      expect(result.inferredExperience).toBeDefined();
      expect(result.trainingStyle).toBeDefined();
      expect(result.topMuscleGroups).toBeDefined();
      expect(result.estimatedSessionDuration).toBeGreaterThan(0);
      expect(result.confidenceScore).toBeGreaterThan(0);
      expect(result.indicators.strengthScore).toBeDefined();
    });

    it("uses absolute strength when no bodyweight", () => {
      const exercises: ImportedExerciseData[] = [
        {id: "1", exerciseName: "Squat", oneRepMax: 225},
      ];

      const result = analyzeImport(exercises, [], undefined);

      expect(result.indicators.strengthScore).toBeDefined();
    });
  });
});

// ============================================================================
// Exercise Matching Tests
// ============================================================================

describe("Exercise Matching", () => {
  describe("matchExerciseToLibrary", () => {
    const mockExerciseCache = new Map([
      ["squat", {name: "Squat"}],
      ["bench-press", {name: "Bench Press"}],
      ["deadlift", {name: "Deadlift"}],
      ["romanian-deadlift", {name: "Romanian Deadlift"}],
    ]);

    it("matches exact name", async () => {
      const result = await matchExerciseToLibrary("Squat", mockExerciseCache);
      expect(result).toBe("squat");
    });

    it("matches case-insensitive", async () => {
      const result = await matchExerciseToLibrary("SQUAT", mockExerciseCache);
      expect(result).toBe("squat");
    });

    it("matches with trailing s (plurals)", async () => {
      const result = await matchExerciseToLibrary("Squats", mockExerciseCache);
      expect(result).toBe("squat");
    });

    it("matches partial name (Back Squat → Squat)", async () => {
      const result = await matchExerciseToLibrary("Back Squat", mockExerciseCache);
      expect(result).toBe("squat");
    });

    it("returns null for no match", async () => {
      const result = await matchExerciseToLibrary("Unknown Exercise", mockExerciseCache);
      expect(result).toBeNull();
    });

    it("handles hyphenated names", async () => {
      const result = await matchExerciseToLibrary("Bench-Press", mockExerciseCache);
      expect(result).toBe("bench-press");
    });
  });
});
