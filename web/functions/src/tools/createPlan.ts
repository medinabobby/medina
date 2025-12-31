/**
 * Create Plan Handler
 *
 * Migrated from iOS: CreatePlanHandler.swift
 * Creates multi-week training plans with professional periodization.
 * Generates plan, program subcollections, and scheduled workouts.
 *
 * Version History:
 * - v1.0: Initial TypeScript port from iOS
 * - v236: Phase 6 - Populate exercises for near-term workouts (within 7 days)
 *         Uses ExerciseSelector and ProtocolAssigner from workout service layer.
 *         Workouts beyond 7 days remain stubs (runtime selection for flexibility).
 */

import {HandlerContext, HandlerResult, SuggestionChip, PlanCardData} from "./index";
import * as admin from "firebase-admin";
import {
  selectExercises,
  calculateExerciseCount,
  determinePrimaryEquipment,
  assignProtocols,
  SplitDay as ServiceSplitDay,
  EffortLevel,
  Equipment,
  TrainingLocation,
} from "../services/workout";

// ============================================================================
// Types
// ============================================================================

/**
 * Arguments for create_plan tool
 */
interface CreatePlanArgs {
  name?: string;
  goal?: string;
  durationWeeks?: number;
  daysPerWeek?: number;
  sessionDuration?: number;
  startDate?: string;
  targetDate?: string;
  preferredDays?: string[];
  splitType?: string;
  trainingLocation?: string;
  experienceLevel?: string;
  emphasizedMuscles?: string[];
  excludedMuscles?: string[];
  cardioDaysPerWeek?: number;
  periodizationStyle?: string;
  includeDeloads?: boolean;
  deloadFrequency?: number;
  workoutDayAssignments?: Record<string, string>;
  intensityStart?: number;
  intensityEnd?: number;
  goalWeightChange?: number;
  forMemberId?: string;
}

/**
 * Plan status enum
 */
type PlanStatus = "draft" | "active" | "completed" | "abandoned";

/**
 * Fitness goal enum (matches iOS/Firestore)
 */
type FitnessGoal =
  | "strength"
  | "muscleGain"
  | "fatLoss"
  | "endurance"
  | "generalFitness"
  | "athleticPerformance";

/**
 * Training focus for phases/programs
 */
type TrainingFocus = "foundation" | "development" | "peak" | "deload" | "maintenance";

/**
 * Progression type
 */
type ProgressionType = "linear" | "undulating" | "staticProgression";

/**
 * Split type
 */
type SplitType = "fullBody" | "upperLower" | "pushPull" | "pushPullLegs" | "bodyPart";

/**
 * Split day
 */
type SplitDay =
  | "upper"
  | "lower"
  | "push"
  | "pull"
  | "legs"
  | "fullBody"
  | "chest"
  | "back"
  | "shoulders"
  | "arms"
  | "notApplicable";

/**
 * Session type
 */
type SessionType = "strength" | "cardio";

/**
 * Day of week
 */
type DayOfWeek = "monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday";

/**
 * Experience level
 */
type ExperienceLevel = "beginner" | "intermediate" | "advanced" | "expert";

/**
 * Phase structure from periodization engine
 */
interface Phase {
  focus: TrainingFocus;
  weeks: number;
  intensityStart: number;
  intensityEnd: number;
  progressionType: ProgressionType;
  rationale: string;
}

/**
 * Program document
 */
interface ProgramDoc {
  id: string;
  planId: string;
  name: string;
  focus: TrainingFocus;
  rationale: string;
  startDate: admin.firestore.Timestamp;
  endDate: admin.firestore.Timestamp;
  startingIntensity: number;
  endingIntensity: number;
  progressionType: ProgressionType;
  status: string;
}

/**
 * Workout document
 */
interface WorkoutDoc {
  id: string;
  programId: string;
  planId: string;
  name: string;
  scheduledDate: admin.firestore.Timestamp;
  type: SessionType;
  splitDay: SplitDay;
  status: string;
  exerciseIds: string[];
}

/**
 * Resolved plan parameters
 */
interface ResolvedPlanParams {
  name: string;
  goal: FitnessGoal;
  durationWeeks: number;
  daysPerWeek: number;
  sessionDuration: number;
  startDate: Date;
  targetDate: Date | null;
  preferredDays: DayOfWeek[];
  splitType: SplitType;
  trainingLocation: string;
  experienceLevel: ExperienceLevel;
  emphasizedMuscles: string[];
  excludedMuscles: string[];
  cardioDays: number;
  periodizationStyle: string;
  includeDeloads: boolean;
  deloadFrequency: number;
  dayAssignments: Record<DayOfWeek, SessionType> | null;
  intensityStart: number | null;
  intensityEnd: number | null;
}

// ============================================================================
// Constants
// ============================================================================

const DAY_ORDER: Record<DayOfWeek, number> = {
  monday: 1,
  tuesday: 2,
  wednesday: 3,
  thursday: 4,
  friday: 5,
  saturday: 6,
  sunday: 7,
};

const GOAL_DISPLAY_NAMES: Record<FitnessGoal, string> = {
  strength: "Strength",
  muscleGain: "Muscle Gain",
  fatLoss: "Fat Loss",
  endurance: "Endurance",
  generalFitness: "General Fitness",
  athleticPerformance: "Athletic Performance",
};

const SPLIT_DISPLAY_NAMES: Record<SplitType, string> = {
  fullBody: "Full Body",
  upperLower: "Upper/Lower",
  pushPull: "Push/Pull",
  pushPullLegs: "Push/Pull/Legs",
  bodyPart: "Body Part Split",
};

const FOCUS_DISPLAY_NAMES: Record<TrainingFocus, string> = {
  foundation: "Foundation",
  development: "Development",
  peak: "Peak",
  deload: "Deload",
  maintenance: "Maintenance",
};

const SPLIT_DAY_DISPLAY_NAMES: Record<SplitDay, string> = {
  upper: "Upper Body",
  lower: "Lower Body",
  push: "Push",
  pull: "Pull",
  legs: "Legs",
  fullBody: "Full Body",
  chest: "Chest",
  back: "Back",
  shoulders: "Shoulders",
  arms: "Arms",
  notApplicable: "Cardio",
};

// ============================================================================
// Main Handler
// ============================================================================

/**
 * Handle create_plan tool call
 *
 * Flow:
 * 1. Resolve all parameters from args and user profile
 * 2. Validate parameters and generate warnings
 * 3. Delete existing draft plans (single draft enforcement)
 * 4. Create plan document with status "draft"
 * 5. Create program subcollection documents
 * 6. Schedule workouts based on plan parameters
 * 7. Return plan summary and suggestion chips
 */
export async function createPlanHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const typedArgs = args as CreatePlanArgs;

  console.log(`[create_plan] Creating plan for user ${uid}`);

  try {
    // Step 1: Get user profile for defaults
    const userDoc = await db.collection("users").doc(uid).get();
    const userProfile = userDoc.exists ? userDoc.data() : {};

    // Step 2: Resolve all parameters
    const params = resolveParameters(typedArgs, userProfile);

    // Step 3: Validate and adjust parameters
    const validation = validateParameters(params);
    const finalDurationWeeks = validation.adjustedDurationWeeks;

    // Step 4: Delete existing draft plans
    await deleteExistingDrafts(db, uid);

    // Step 5: Generate plan ID and create plan document
    const planId = `plan_${uid}_${generateShortId()}`;
    const strengthDays = Math.max(params.daysPerWeek - params.cardioDays, 1);

    // Calculate recommended split type
    const splitType = params.splitType ||
      recommendSplit(strengthDays, params.experienceLevel, params.goal);

    // Calculate plan dates
    const endDate = new Date(params.startDate);
    endDate.setDate(endDate.getDate() + finalDurationWeeks * 7);

    // Create plan document
    const planData = {
      id: planId,
      memberId: uid,
      status: "draft" as PlanStatus,
      name: params.name,
      description: getGoalDescription(params.goal),
      goal: params.goal,
      weightliftingDays: strengthDays,
      cardioDays: params.cardioDays,
      splitType: splitType,
      targetSessionDuration: params.sessionDuration,
      trainingLocation: params.trainingLocation,
      preferredDays: params.preferredDays,
      startDate: admin.firestore.Timestamp.fromDate(params.startDate),
      endDate: admin.firestore.Timestamp.fromDate(endDate),
      emphasizedMuscleGroups: params.emphasizedMuscles,
      excludedMuscleGroups: params.excludedMuscles,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Save plan
    await db.collection("users").doc(uid).collection("plans").doc(planId).set(planData);
    console.log(`[create_plan] Created plan document: ${planId}`);

    // Step 6: Generate phases and programs
    const phases = calculatePhases(
      params.goal,
      finalDurationWeeks,
      params.periodizationStyle,
      params.includeDeloads,
      params.deloadFrequency,
      params.intensityStart,
      params.intensityEnd
    );

    // Create program documents
    const programs = await createPrograms(
      db,
      uid,
      planId,
      phases,
      params.startDate,
      endDate
    );
    console.log(`[create_plan] Created ${programs.length} programs`);

    // Step 7: Generate and save workouts
    const workouts = await generateAndSaveWorkouts(
      db,
      uid,
      planId,
      programs,
      strengthDays,
      params.cardioDays,
      params.preferredDays,
      splitType,
      params.dayAssignments
    );
    console.log(`[create_plan] Created ${workouts.length} workouts`);

    // Step 8: Populate exercises for near-term workouts (within 7 days)
    await populateNearTermExercises(
      db,
      uid,
      workouts,
      params.sessionDuration,
      params.trainingLocation,
      params.startDate
    );

    // Step 9: Format success response
    const output = formatSuccessResponse(
      planId,
      params.name,
      params.goal,
      finalDurationWeeks,
      params.startDate,
      endDate,
      splitType,
      strengthDays,
      params.sessionDuration,
      programs,
      workouts,
      validation.warning
    );

    const chips: SuggestionChip[] = [
      {label: "Activate plan", command: `Activate plan ${planId}`},
      {label: "View schedule", command: "Show my schedule"},
    ];

    // v210: Include plan card data for inline display
    const planCard: PlanCardData = {
      planId,
      planName: params.name,
      workoutCount: workouts.length,
      durationWeeks: finalDurationWeeks,
    };

    return {
      output,
      suggestionChips: chips,
      planCard,
    };
  } catch (error) {
    console.error(`[create_plan] Error creating plan:`, error);
    return {
      output: `ERROR: Failed to create plan. ${error instanceof Error ? error.message : "Unknown error"}`,
    };
  }
}

// ============================================================================
// Parameter Resolution
// ============================================================================

/**
 * Resolve plan parameters from args and user profile
 */
function resolveParameters(
  args: CreatePlanArgs,
  userProfile: Record<string, unknown> | undefined
): ResolvedPlanParams {
  // Name
  const name = args.name || "Training Plan";

  // Goal
  const goal = parseGoal(args.goal || "generalFitness");

  // Duration (clamped 1-52 weeks)
  const rawDuration = args.durationWeeks ?? 8;
  const durationWeeks = Math.min(Math.max(rawDuration, 1), 52);

  // Days per week
  const profileDays = (userProfile?.preferredWorkoutDays as string[] | undefined)?.length || 0;
  const daysPerWeek = args.daysPerWeek ?? (profileDays > 0 ? profileDays : 4);

  // Session duration
  const sessionDuration = args.sessionDuration ??
    (userProfile?.preferredSessionDuration as number | undefined) ?? 60;

  // Start date
  const startDate = args.startDate ? parseDate(args.startDate) : new Date();

  // Target date
  const targetDate = args.targetDate ? parseDate(args.targetDate) : null;

  // Preferred days
  const preferredDays = resolvePreferredDays(
    args.preferredDays,
    userProfile?.preferredWorkoutDays as string[] | undefined,
    daysPerWeek
  );

  // Split type
  const splitType = parseSplitType(args.splitType);

  // Training location
  const trainingLocation = args.trainingLocation ||
    (userProfile?.trainingLocation as string | undefined) || "gym";

  // Experience level
  const experienceLevel = parseExperienceLevel(
    args.experienceLevel || (userProfile?.experienceLevel as string | undefined)
  );

  // Muscle groups
  const emphasizedMuscles = args.emphasizedMuscles || [];
  const excludedMuscles = args.excludedMuscles || [];

  // Cardio days
  const cardioDays = resolveCardioDays(args.cardioDaysPerWeek, goal);

  // Periodization
  const periodizationStyle = args.periodizationStyle || "auto";
  const includeDeloads = args.includeDeloads ?? durationWeeks > 4;
  const deloadFrequency = args.deloadFrequency ?? 5;

  // Day assignments
  const dayAssignments = parseDayAssignments(args.workoutDayAssignments);

  // Intensity range
  const intensityStart = args.intensityStart ?? null;
  const intensityEnd = args.intensityEnd ?? null;

  return {
    name,
    goal,
    durationWeeks,
    daysPerWeek,
    sessionDuration,
    startDate,
    targetDate,
    preferredDays,
    splitType: splitType as SplitType,
    trainingLocation,
    experienceLevel,
    emphasizedMuscles,
    excludedMuscles,
    cardioDays,
    periodizationStyle,
    includeDeloads,
    deloadFrequency,
    dayAssignments,
    intensityStart,
    intensityEnd,
  };
}

/**
 * Parse fitness goal string to enum
 */
function parseGoal(goalStr: string): FitnessGoal {
  const normalized = goalStr.toLowerCase();
  if (normalized === "strength") return "strength";
  if (normalized === "musclegain" || normalized === "muscle_gain" || normalized === "hypertrophy") {
    return "muscleGain";
  }
  if (normalized === "fatloss" || normalized === "fat_loss" || normalized === "weight_loss") {
    return "fatLoss";
  }
  if (normalized === "endurance") return "endurance";
  if (normalized === "athleticperformance" || normalized === "athletic_performance") {
    return "athleticPerformance";
  }
  return "generalFitness";
}

/**
 * Parse split type string
 */
function parseSplitType(splitStr?: string): SplitType | null {
  if (!splitStr) return null;
  const normalized = splitStr.toLowerCase();
  if (normalized === "fullbody" || normalized === "full_body") return "fullBody";
  if (normalized === "upperlower" || normalized === "upper_lower") return "upperLower";
  if (normalized === "pushpull" || normalized === "push_pull") return "pushPull";
  if (normalized === "pushpulllegs" || normalized === "push_pull_legs" || normalized === "ppl") {
    return "pushPullLegs";
  }
  if (normalized === "bodypart" || normalized === "body_part" || normalized === "bro_split") {
    return "bodyPart";
  }
  return null;
}

/**
 * Parse experience level string
 */
function parseExperienceLevel(levelStr?: string): ExperienceLevel {
  if (!levelStr) return "intermediate";
  const normalized = levelStr.toLowerCase();
  if (normalized === "beginner") return "beginner";
  if (normalized === "advanced") return "advanced";
  if (normalized === "expert") return "expert";
  return "intermediate";
}

/**
 * Parse day of week string
 */
function parseDayOfWeek(dayStr: string): DayOfWeek | null {
  const normalized = dayStr.toLowerCase();
  if (normalized === "monday" || normalized === "mon") return "monday";
  if (normalized === "tuesday" || normalized === "tue" || normalized === "tues") return "tuesday";
  if (normalized === "wednesday" || normalized === "wed") return "wednesday";
  if (normalized === "thursday" || normalized === "thu" || normalized === "thur" || normalized === "thurs") return "thursday";
  if (normalized === "friday" || normalized === "fri") return "friday";
  if (normalized === "saturday" || normalized === "sat") return "saturday";
  if (normalized === "sunday" || normalized === "sun") return "sunday";
  return null;
}

/**
 * Parse date string (YYYY-MM-DD) to Date
 */
function parseDate(dateStr: string): Date {
  const parsed = new Date(dateStr);
  if (isNaN(parsed.getTime())) {
    return new Date();
  }
  return parsed;
}

/**
 * Resolve preferred training days
 */
function resolvePreferredDays(
  argDays?: string[],
  profileDays?: string[],
  daysPerWeek?: number
): DayOfWeek[] {
  // Try profile days first
  if (profileDays && profileDays.length > 0) {
    const parsed = profileDays
      .map((d) => parseDayOfWeek(d))
      .filter((d): d is DayOfWeek => d !== null);
    if (parsed.length > 0) {
      return parsed.sort((a, b) => DAY_ORDER[a] - DAY_ORDER[b]);
    }
  }

  // Try arg days
  if (argDays && argDays.length > 0) {
    const parsed = argDays
      .map((d) => parseDayOfWeek(d))
      .filter((d): d is DayOfWeek => d !== null);
    if (parsed.length > 0) {
      return parsed.sort((a, b) => DAY_ORDER[a] - DAY_ORDER[b]);
    }
  }

  // Auto-select days
  return autoSelectDays(daysPerWeek ?? 4);
}

/**
 * Auto-select training days based on count
 */
function autoSelectDays(count: number): DayOfWeek[] {
  const allDays: DayOfWeek[] = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

  // Common patterns based on frequency
  if (count <= 2) {
    return ["monday", "thursday"];
  }
  if (count === 3) {
    return ["monday", "wednesday", "friday"];
  }
  if (count === 4) {
    return ["monday", "tuesday", "thursday", "friday"];
  }
  if (count === 5) {
    return ["monday", "tuesday", "wednesday", "friday", "saturday"];
  }
  if (count === 6) {
    return ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
  }

  return allDays.slice(0, Math.min(count, 7));
}

/**
 * Resolve cardio days from args or goal
 */
function resolveCardioDays(argCardioDays?: number, goal?: FitnessGoal): number {
  if (argCardioDays !== undefined) {
    return argCardioDays;
  }

  // Goal-based defaults
  if (goal === "fatLoss" || goal === "endurance") {
    return 2;
  }
  return 0;
}

/**
 * Parse day assignments from args
 */
function parseDayAssignments(
  assignments?: Record<string, string>
): Record<DayOfWeek, SessionType> | null {
  if (!assignments) return null;

  const result: Record<string, SessionType> = {};
  for (const [dayStr, typeStr] of Object.entries(assignments)) {
    const day = parseDayOfWeek(dayStr);
    if (day) {
      result[day] = typeStr.toLowerCase() === "cardio" ? "cardio" : "strength";
    }
  }

  if (Object.keys(result).length === 0) return null;
  return result as Record<DayOfWeek, SessionType>;
}

// ============================================================================
// Validation
// ============================================================================

interface ValidationResult {
  adjustedDurationWeeks: number;
  warning: string | null;
}

/**
 * Validate parameters and generate warnings
 */
function validateParameters(params: ResolvedPlanParams): ValidationResult {
  let adjustedWeeks = params.durationWeeks;
  const warnings: string[] = [];

  // Target date validation
  if (params.targetDate) {
    const daysBetween = Math.floor(
      (params.targetDate.getTime() - params.startDate.getTime()) / (1000 * 60 * 60 * 24)
    );

    // Ignore past target dates
    if (daysBetween <= 0) {
      console.log(`[create_plan] Target date in past, ignoring`);
    } else {
      const calculatedWeeks = Math.max(1, Math.ceil(daysBetween / 7));

      // Check for mismatch
      if (Math.abs(params.durationWeeks - calculatedWeeks) > 2) {
        adjustedWeeks = Math.min(calculatedWeeks, 52);
      }

      // Short timeline warnings
      if (calculatedWeeks < 4) {
        if (params.goal === "muscleGain") {
          warnings.push(
            `TIMELINE WARNING: ${calculatedWeeks} weeks is very short for muscle gain. Natural muscle gain is 0.5-2lbs per MONTH.`
          );
        } else if (params.goal === "fatLoss") {
          const maxLoss = calculatedWeeks * 2;
          warnings.push(
            `TIMELINE WARNING: Safe fat loss is 1-2lbs per week, max ${maxLoss}lbs in ${calculatedWeeks} weeks.`
          );
        } else if (params.goal === "strength") {
          warnings.push(
            `TIMELINE WARNING: ${calculatedWeeks} weeks is short for significant strength gains. 8-12+ weeks is typical.`
          );
        }
      }
    }
  }

  return {
    adjustedDurationWeeks: adjustedWeeks,
    warning: warnings.length > 0 ? warnings.join("\n") : null,
  };
}

// ============================================================================
// Split Recommendation
// ============================================================================

/**
 * Recommend optimal split type based on frequency, experience, and goal
 */
function recommendSplit(
  liftingDays: number,
  experience: ExperienceLevel,
  goal: FitnessGoal
): SplitType {
  // 2-3 days: Always Full Body
  if (liftingDays <= 3) {
    return "fullBody";
  }

  // 4 days
  if (liftingDays === 4) {
    // Advanced/Expert + Strength goal: Full Body for high frequency
    if ((experience === "advanced" || experience === "expert") && goal === "strength") {
      return "fullBody";
    }
    // Default to Upper/Lower for 4 days
    return "upperLower";
  }

  // 5 days: Upper/Lower with flexible 5th day
  if (liftingDays === 5) {
    return "upperLower";
  }

  // 6 days: Push/Pull/Legs
  return "pushPullLegs";
}

// ============================================================================
// Periodization Engine
// ============================================================================

/**
 * Calculate phase structure based on goal and duration
 */
function calculatePhases(
  goal: FitnessGoal,
  weeks: number,
  style: string,
  includeDeloads: boolean,
  deloadFrequency: number,
  customIntensityStart: number | null,
  customIntensityEnd: number | null
): Phase[] {
  // Short plans or "none" style: single program
  if (weeks <= 3 || style === "none") {
    const defaults = getGoalDefaults(goal);
    return [{
      focus: "development",
      weeks: weeks,
      intensityStart: customIntensityStart ?? defaults.intensityStart,
      intensityEnd: customIntensityEnd ?? defaults.intensityEnd,
      progressionType: "linear",
      rationale: defaults.rationale,
    }];
  }

  // Get base template based on goal
  let phases = getGoalTemplate(goal, weeks);

  // Insert deloads if requested
  if (includeDeloads && weeks > 4) {
    phases = insertDeloads(phases, deloadFrequency);
  }

  // Apply custom intensity range if provided
  if (customIntensityStart !== null && customIntensityEnd !== null) {
    phases = scaleIntensities(phases, customIntensityStart, customIntensityEnd);
  }

  return phases;
}

/**
 * Get default intensity and rationale for a goal
 */
function getGoalDefaults(goal: FitnessGoal): {
  intensityStart: number;
  intensityEnd: number;
  rationale: string;
} {
  switch (goal) {
  case "strength":
    return {
      intensityStart: 0.70,
      intensityEnd: 0.85,
      rationale: "Progressive strength building with compound movements",
    };
  case "muscleGain":
    return {
      intensityStart: 0.65,
      intensityEnd: 0.78,
      rationale: "Volume-focused training for muscle growth",
    };
  case "fatLoss":
    return {
      intensityStart: 0.60,
      intensityEnd: 0.72,
      rationale: "Metabolic conditioning with strength preservation",
    };
  case "endurance":
    return {
      intensityStart: 0.55,
      intensityEnd: 0.70,
      rationale: "Build aerobic capacity and work tolerance",
    };
  case "athleticPerformance":
    return {
      intensityStart: 0.68,
      intensityEnd: 0.82,
      rationale: "Sport-specific power and conditioning",
    };
  default:
    return {
      intensityStart: 0.62,
      intensityEnd: 0.75,
      rationale: "Balanced training for overall fitness",
    };
  }
}

/**
 * Get goal description for plan
 */
function getGoalDescription(goal: FitnessGoal): string {
  switch (goal) {
  case "strength":
    return "Build maximal strength through progressive overload with compound movements";
  case "muscleGain":
    return "Maximize muscle growth through volume and metabolic stress";
  case "fatLoss":
    return "Burn calories and maintain muscle through circuit training and conditioning";
  case "endurance":
    return "Build muscular endurance and work capacity";
  case "athleticPerformance":
    return "Sport-specific power, explosiveness, and conditioning";
  default:
    return "Balanced training for overall health and fitness";
  }
}

/**
 * Get phase template for a goal
 */
function getGoalTemplate(goal: FitnessGoal, weeks: number): Phase[] {
  if (weeks <= 4) {
    const defaults = getGoalDefaults(goal);
    return [{
      focus: "development",
      weeks: weeks,
      intensityStart: defaults.intensityStart,
      intensityEnd: defaults.intensityEnd,
      progressionType: "linear",
      rationale: defaults.rationale,
    }];
  }

  if (weeks <= 8) {
    // Medium: Development -> Peak (or Foundation -> Development for hypertrophy)
    if (goal === "muscleGain") {
      const foundWeeks = Math.max(2, Math.floor(weeks * 0.35));
      const devWeeks = weeks - foundWeeks;
      return [
        {
          focus: "foundation",
          weeks: foundWeeks,
          intensityStart: 0.60,
          intensityEnd: 0.68,
          progressionType: "linear",
          rationale: "Build work capacity and establish training habits",
        },
        {
          focus: "development",
          weeks: devWeeks,
          intensityStart: 0.68,
          intensityEnd: 0.78,
          progressionType: "linear",
          rationale: "Progressive overload with hypertrophy-focused volume",
        },
      ];
    }

    const devWeeks = Math.floor(weeks * 0.6);
    const peakWeeks = weeks - devWeeks;
    return [
      {
        focus: "development",
        weeks: devWeeks,
        intensityStart: 0.70,
        intensityEnd: 0.80,
        progressionType: "linear",
        rationale: "Build strength base with progressive overload",
      },
      {
        focus: "peak",
        weeks: peakWeeks,
        intensityStart: 0.80,
        intensityEnd: 0.90,
        progressionType: "linear",
        rationale: "Maximize performance with higher intensity, lower volume",
      },
    ];
  }

  // Long plans (9-16 weeks): Foundation -> Development -> Peak
  const foundWeeks = Math.max(2, Math.floor(weeks * 0.25));
  const peakWeeks = Math.max(2, Math.floor(weeks * 0.25));
  const devWeeks = weeks - foundWeeks - peakWeeks;

  return [
    {
      focus: "foundation",
      weeks: foundWeeks,
      intensityStart: 0.60,
      intensityEnd: 0.70,
      progressionType: "linear",
      rationale: "Build work capacity and perfect movement patterns",
    },
    {
      focus: "development",
      weeks: devWeeks,
      intensityStart: 0.70,
      intensityEnd: 0.82,
      progressionType: "linear",
      rationale: "Progressive overload drives adaptation",
    },
    {
      focus: "peak",
      weeks: peakWeeks,
      intensityStart: 0.82,
      intensityEnd: 0.92,
      progressionType: "linear",
      rationale: "Peak intensity for maximum performance",
    },
  ];
}

/**
 * Insert deload weeks into phase structure
 */
function insertDeloads(phases: Phase[], frequency: number): Phase[] {
  // If phases already have deloads, skip
  if (phases.some((p) => p.focus === "deload")) {
    return phases;
  }

  const result: Phase[] = [];
  let weekCount = 0;

  for (const phase of phases) {
    // Check if we need a deload before this phase
    if (weekCount > 0 && weekCount % frequency === 0) {
      result.push({
        focus: "deload",
        weeks: 1,
        intensityStart: 0.50,
        intensityEnd: 0.60,
        progressionType: "staticProgression",
        rationale: "Scheduled recovery week to prevent overtraining",
      });
    }

    result.push(phase);
    weekCount += phase.weeks;
  }

  return result;
}

/**
 * Scale intensities to custom range
 */
function scaleIntensities(
  phases: Phase[],
  targetStart: number,
  targetEnd: number
): Phase[] {
  const trainingPhases = phases.filter((p) => p.focus !== "deload");
  if (trainingPhases.length === 0) return phases;

  const minIntensity = Math.min(...trainingPhases.map((p) => p.intensityStart));
  const maxIntensity = Math.max(...trainingPhases.map((p) => p.intensityEnd));
  const originalRange = maxIntensity - minIntensity;

  if (originalRange <= 0) return phases;

  const targetRange = targetEnd - targetStart;

  return phases.map((phase) => {
    if (phase.focus === "deload") {
      const deloadIntensity = Math.max(0.40, targetStart - 0.15);
      return {
        ...phase,
        intensityStart: deloadIntensity,
        intensityEnd: deloadIntensity + 0.10,
      };
    }

    const scaledStart = targetStart + ((phase.intensityStart - minIntensity) / originalRange) * targetRange;
    const scaledEnd = targetStart + ((phase.intensityEnd - minIntensity) / originalRange) * targetRange;

    return {
      ...phase,
      intensityStart: Math.min(Math.max(scaledStart, 0.40), 0.95),
      intensityEnd: Math.min(Math.max(scaledEnd, 0.40), 0.95),
    };
  });
}

// ============================================================================
// Database Operations
// ============================================================================

/**
 * Delete existing draft plans (single draft enforcement)
 */
async function deleteExistingDrafts(
  db: admin.firestore.Firestore,
  uid: string
): Promise<void> {
  const draftsSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("plans")
    .where("status", "==", "draft")
    .get();

  for (const doc of draftsSnapshot.docs) {
    // Count workouts for this plan
    const workoutsSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("workouts")
      .where("planId", "==", doc.id)
      .get();

    // Only delete multi-week plans (more than 1 workout)
    if (workoutsSnapshot.size > 1) {
      // Delete workouts first
      const batch = db.batch();
      for (const workoutDoc of workoutsSnapshot.docs) {
        batch.delete(workoutDoc.ref);
      }

      // Delete programs
      const programsSnapshot = await doc.ref.collection("programs").get();
      for (const progDoc of programsSnapshot.docs) {
        batch.delete(progDoc.ref);
      }

      // Delete plan
      batch.delete(doc.ref);
      await batch.commit();

      console.log(`[create_plan] Deleted existing draft: ${doc.id}`);
    }
  }
}

/**
 * Create program subcollection documents
 */
async function createPrograms(
  db: admin.firestore.Firestore,
  uid: string,
  planId: string,
  phases: Phase[],
  planStartDate: Date,
  planEndDate: Date
): Promise<ProgramDoc[]> {
  const programs: ProgramDoc[] = [];
  let currentDate = new Date(planStartDate);
  let deloadCount = 0;
  let phaseCount = 0;

  for (let i = 0; i < phases.length; i++) {
    const phase = phases[i];
    const programId = `prog_${planId}_${i + 1}`;

    // Calculate phase end date
    const phaseEndDate = new Date(currentDate);
    phaseEndDate.setDate(phaseEndDate.getDate() + phase.weeks * 7);

    // Clamp to plan end date
    const clampedEndDate = phaseEndDate > planEndDate ? planEndDate : phaseEndDate;

    // Generate program name
    let programName: string;
    if (phase.focus === "deload") {
      deloadCount++;
      programName = `Deload Week ${deloadCount}`;
    } else {
      phaseCount++;
      programName = `Phase ${phaseCount}: ${FOCUS_DISPLAY_NAMES[phase.focus]}`;
    }

    const program: ProgramDoc = {
      id: programId,
      planId: planId,
      name: programName,
      focus: phase.focus,
      rationale: phase.rationale,
      startDate: admin.firestore.Timestamp.fromDate(currentDate),
      endDate: admin.firestore.Timestamp.fromDate(clampedEndDate),
      startingIntensity: phase.intensityStart,
      endingIntensity: phase.intensityEnd,
      progressionType: phase.progressionType,
      status: "draft",
    };

    // Save to Firestore
    await db
      .collection("users")
      .doc(uid)
      .collection("plans")
      .doc(planId)
      .collection("programs")
      .doc(programId)
      .set(program);

    programs.push(program);
    currentDate = clampedEndDate;
  }

  return programs;
}

/**
 * Generate and save workouts for all programs
 */
async function generateAndSaveWorkouts(
  db: admin.firestore.Firestore,
  uid: string,
  planId: string,
  programs: ProgramDoc[],
  strengthDaysPerWeek: number,
  cardioDaysPerWeek: number,
  preferredDays: DayOfWeek[],
  splitType: SplitType,
  dayAssignments: Record<DayOfWeek, SessionType> | null
): Promise<WorkoutDoc[]> {
  const allWorkouts: WorkoutDoc[] = [];

  for (const program of programs) {
    const startDate = program.startDate.toDate();
    const endDate = program.endDate.toDate();

    // Calculate training dates for this program
    const trainingDates = calculateTrainingDates(
      startDate,
      endDate,
      strengthDaysPerWeek,
      cardioDaysPerWeek,
      preferredDays,
      dayAssignments
    );

    // Build workouts
    const workouts = buildWorkouts(
      planId,
      program.id,
      trainingDates.strength,
      trainingDates.cardio,
      splitType,
      allWorkouts.length
    );

    // Save to Firestore
    const batch = db.batch();
    for (const workout of workouts) {
      const workoutRef = db
        .collection("users")
        .doc(uid)
        .collection("workouts")
        .doc(workout.id);
      batch.set(workoutRef, workout);
    }
    await batch.commit();

    allWorkouts.push(...workouts);
  }

  return allWorkouts;
}

/**
 * Calculate training dates for a program period
 */
function calculateTrainingDates(
  startDate: Date,
  endDate: Date,
  strengthDays: number,
  cardioDays: number,
  preferredDays: DayOfWeek[],
  dayAssignments: Record<DayOfWeek, SessionType> | null
): { strength: Date[]; cardio: Date[] } {
  const strengthDates: Date[] = [];
  const cardioDates: Date[] = [];

  // Sort preferred days
  const orderedDays = [...preferredDays].sort((a, b) => DAY_ORDER[a] - DAY_ORDER[b]);

  // Determine which days are strength vs cardio
  let strengthDayTypes: DayOfWeek[];
  let cardioDayTypes: DayOfWeek[];

  if (dayAssignments) {
    strengthDayTypes = orderedDays.filter((d) => dayAssignments[d] === "strength");
    cardioDayTypes = orderedDays.filter((d) => dayAssignments[d] === "cardio");
  } else {
    // Interleave cardio among strength days
    const result = interleaveDays(orderedDays, strengthDays, cardioDays);
    strengthDayTypes = result.strength;
    cardioDayTypes = result.cardio;
  }

  // Iterate through weeks
  let currentWeekStart = getStartOfWeek(startDate);

  while (currentWeekStart <= endDate) {
    // Add strength workouts
    for (const day of strengthDayTypes) {
      const trainingDate = getDateForDay(day, currentWeekStart);
      if (trainingDate >= startDate && trainingDate <= endDate) {
        strengthDates.push(trainingDate);
      }
    }

    // Add cardio workouts
    for (const day of cardioDayTypes) {
      const trainingDate = getDateForDay(day, currentWeekStart);
      if (trainingDate >= startDate && trainingDate <= endDate) {
        cardioDates.push(trainingDate);
      }
    }

    // Move to next week
    currentWeekStart = new Date(currentWeekStart);
    currentWeekStart.setDate(currentWeekStart.getDate() + 7);
  }

  return {
    strength: strengthDates.sort((a, b) => a.getTime() - b.getTime()),
    cardio: cardioDates.sort((a, b) => a.getTime() - b.getTime()),
  };
}

/**
 * Interleave cardio days evenly among training days
 */
function interleaveDays(
  orderedDays: DayOfWeek[],
  strengthCount: number,
  cardioCount: number
): { strength: DayOfWeek[]; cardio: DayOfWeek[] } {
  if (cardioCount === 0) {
    return {strength: orderedDays.slice(0, strengthCount), cardio: []};
  }
  if (strengthCount === 0) {
    return {strength: [], cardio: orderedDays.slice(0, cardioCount)};
  }

  const totalDays = orderedDays.length;
  const cardioIndices = new Set<number>();

  // Spread cardio evenly
  for (let i = 0; i < cardioCount; i++) {
    const position = Math.floor(((i + 1) * totalDays) / (cardioCount + 1));
    cardioIndices.add(Math.min(position, totalDays - 1));
  }

  const strengthDays: DayOfWeek[] = [];
  const cardioDays: DayOfWeek[] = [];

  for (let i = 0; i < orderedDays.length; i++) {
    if (cardioIndices.has(i) && cardioDays.length < cardioCount) {
      cardioDays.push(orderedDays[i]);
    } else if (strengthDays.length < strengthCount) {
      strengthDays.push(orderedDays[i]);
    }
  }

  return {strength: strengthDays, cardio: cardioDays};
}

/**
 * Get start of week (Monday) for a date
 */
function getStartOfWeek(date: Date): Date {
  const d = new Date(date);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1); // Adjust for Sunday
  d.setDate(diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

/**
 * Get date for a specific day of week in a given week
 */
function getDateForDay(day: DayOfWeek, weekStart: Date): Date {
  const offset = DAY_ORDER[day] - 1; // Monday = 0 offset
  const result = new Date(weekStart);
  result.setDate(result.getDate() + offset);
  return result;
}

/**
 * Build workout documents for strength and cardio dates
 */
function buildWorkouts(
  planId: string,
  programId: string,
  strengthDates: Date[],
  cardioDates: Date[],
  splitType: SplitType,
  startIndex: number
): WorkoutDoc[] {
  const workouts: WorkoutDoc[] = [];
  const splitRotation = getSplitDayRotation(splitType);
  let index = startIndex;

  // Build strength workouts
  for (let i = 0; i < strengthDates.length; i++) {
    const date = strengthDates[i];
    const splitDay = splitRotation[i % splitRotation.length];

    workouts.push({
      id: `${programId}_w${index + 1}`,
      programId: programId,
      planId: planId,
      name: `${SPLIT_DAY_DISPLAY_NAMES[splitDay]} - ${formatDateShort(date)}`,
      scheduledDate: admin.firestore.Timestamp.fromDate(date),
      type: "strength",
      splitDay: splitDay,
      status: "scheduled",
      exerciseIds: [],
    });
    index++;
  }

  // Build cardio workouts
  for (let i = 0; i < cardioDates.length; i++) {
    const date = cardioDates[i];

    workouts.push({
      id: `${programId}_w${index + 1}`,
      programId: programId,
      planId: planId,
      name: `Cardio Session - ${formatDateShort(date)}`,
      scheduledDate: admin.firestore.Timestamp.fromDate(date),
      type: "cardio",
      splitDay: "notApplicable",
      status: "scheduled",
      exerciseIds: [],
    });
    index++;
  }

  // Sort by date
  return workouts.sort((a, b) =>
    a.scheduledDate.toDate().getTime() - b.scheduledDate.toDate().getTime()
  );
}

/**
 * Get split day rotation for a split type
 */
function getSplitDayRotation(splitType: SplitType): SplitDay[] {
  switch (splitType) {
  case "fullBody":
    return ["fullBody"];
  case "upperLower":
    return ["upper", "lower"];
  case "pushPull":
    return ["push", "pull"];
  case "pushPullLegs":
    return ["push", "pull", "legs"];
  case "bodyPart":
    return ["chest", "back", "shoulders", "legs", "arms"];
  }
}

/**
 * Format date as "MMM d" (e.g., "Dec 28")
 */
function formatDateShort(date: Date): string {
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${months[date.getMonth()]} ${date.getDate()}`;
}

/**
 * Format date as "EEEE, MMMM d" (e.g., "Saturday, December 28")
 */
function formatDateLong(date: Date): string {
  const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const months = ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"];
  return `${days[date.getDay()]}, ${months[date.getMonth()]} ${date.getDate()}`;
}

/**
 * Generate a short random ID
 */
function generateShortId(): string {
  return Math.random().toString(36).substring(2, 10);
}

// ============================================================================
// Exercise Selection for Near-Term Workouts
// ============================================================================

/**
 * Populate exercises for workouts within 7 days of plan start
 *
 * Phase 6 integration: Near-term workouts get exercises selected immediately
 * so users can see their upcoming exercises. Workouts beyond 7 days remain
 * as stubs - exercises will be selected at runtime.
 */
async function populateNearTermExercises(
  db: admin.firestore.Firestore,
  uid: string,
  workouts: WorkoutDoc[],
  sessionDuration: number,
  trainingLocation: string,
  planStartDate: Date
): Promise<void> {
  // Calculate 7-day cutoff from plan start
  const cutoffDate = new Date(planStartDate);
  cutoffDate.setDate(cutoffDate.getDate() + 7);

  // Filter to near-term strength workouts (cardio exercises selected at runtime for more variety)
  const nearTermWorkouts = workouts.filter((w) => {
    const workoutDate = w.scheduledDate.toDate();
    return workoutDate < cutoffDate && w.type === "strength" && w.splitDay !== "notApplicable";
  });

  if (nearTermWorkouts.length === 0) {
    console.log(`[create_plan] No near-term strength workouts to populate`);
    return;
  }

  console.log(`[create_plan] Populating exercises for ${nearTermWorkouts.length} near-term workouts`);

  // Convert training location to Equipment array and TrainingLocation type
  const location = trainingLocation as TrainingLocation;
  const equipment = determineEquipmentFromLocation(location);

  for (const workout of nearTermWorkouts) {
    try {
      // Calculate exercise count based on duration and equipment
      const primaryEquipment = determinePrimaryEquipment(equipment);
      const exerciseCount = calculateExerciseCount(sessionDuration, primaryEquipment);

      // Map local SplitDay to service SplitDay
      const serviceSplitDay = workout.splitDay as ServiceSplitDay;

      // Select exercises using ExerciseSelector
      const selectionResult = await selectExercises(db, {
        splitDay: serviceSplitDay,
        targetCount: exerciseCount,
        availableEquipment: equipment,
        trainingLocation: location,
      });

      const exercises = selectionResult.exercises;
      if (!exercises || exercises.length === 0) {
        console.log(`[create_plan] No exercises found for ${workout.splitDay}, skipping`);
        continue;
      }

      // Update workout with selected exercises
      const exerciseIds = exercises.map((e) => e.id);

      // Assign protocols to get protocol variant IDs
      const protocols = assignProtocols(exercises, "standard");
      const protocolVariantIds: Record<string, string> = {};
      exercises.forEach((exercise, index) => {
        const protocol = protocols.find((p) => p.exerciseId === exercise.id);
        if (protocol) {
          protocolVariantIds[index.toString()] = protocol.protocolId;
        }
      });

      // Update Firestore
      await db
        .collection("users")
        .doc(uid)
        .collection("workouts")
        .doc(workout.id)
        .update({
          exerciseIds,
          protocolVariantIds,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      console.log(`[create_plan] Populated ${exerciseIds.length} exercises for workout ${workout.id}`);
    } catch (error) {
      // Log error but don't fail the entire plan creation
      console.error(`[create_plan] Failed to populate exercises for ${workout.id}:`, error);
    }
  }
}

/**
 * Determine available equipment based on training location
 */
function determineEquipmentFromLocation(location: TrainingLocation): Equipment[] {
  switch (location) {
  case "gym":
    return ["barbell", "dumbbell", "cable", "machine", "bodyweight"];
  case "home":
    return ["dumbbell", "bodyweight", "bands"];
  case "outdoor":
    return ["bodyweight"];
  default:
    return ["barbell", "dumbbell", "cable", "machine", "bodyweight"];
  }
}

// ============================================================================
// Response Formatting
// ============================================================================

/**
 * Format success response for AI
 */
function formatSuccessResponse(
  planId: string,
  name: string,
  goal: FitnessGoal,
  durationWeeks: number,
  startDate: Date,
  endDate: Date,
  splitType: SplitType,
  strengthDays: number,
  sessionDuration: number,
  programs: ProgramDoc[],
  workouts: WorkoutDoc[],
  warning: string | null
): string {
  const startDateStr = formatDateLong(startDate);
  const endDateStr = formatDateLong(endDate);
  const splitName = SPLIT_DISPLAY_NAMES[splitType];
  const goalName = GOAL_DISPLAY_NAMES[goal];

  const strengthWorkouts = workouts.filter((w) => w.type === "strength").length;
  const cardioWorkouts = workouts.filter((w) => w.type === "cardio").length;

  // Build phase structure
  let phaseStructure = "";
  if (programs.length > 1) {
    phaseStructure = `\nPHASE STRUCTURE (${programs.length} phases):\n`;
    let weekStart = 1;

    for (const program of programs) {
      const startD = program.startDate.toDate();
      const endD = program.endDate.toDate();
      const weekCount = Math.ceil((endD.getTime() - startD.getTime()) / (7 * 24 * 60 * 60 * 1000));
      const weekEnd = weekStart + weekCount - 1;
      const weekRange = weekEnd > weekStart ? `Weeks ${weekStart}-${weekEnd}` : `Week ${weekStart}`;
      const intensityRange = `${Math.round(program.startingIntensity * 100)}%-${Math.round(program.endingIntensity * 100)}%`;

      phaseStructure += `- ${FOCUS_DISPLAY_NAMES[program.focus]} Phase (${weekRange}): ${intensityRange} intensity\n`;
      weekStart = weekEnd + 1;
    }
  }

  // Build first week preview
  let firstWeekPreview = "";
  const firstWeekEnd = new Date(startDate);
  firstWeekEnd.setDate(firstWeekEnd.getDate() + 7);

  const firstWeekWorkouts = workouts
    .filter((w) => {
      const date = w.scheduledDate.toDate();
      return date >= startDate && date < firstWeekEnd;
    })
    .slice(0, 5);

  for (const workout of firstWeekWorkouts) {
    const date = workout.scheduledDate.toDate();
    const dayName = formatDateLong(date).split(",")[0];
    firstWeekPreview += `- ${dayName}: ${workout.name}\n`;
  }

  const warningSection = warning ? `\n${warning}\nIMPORTANT: You MUST communicate this timeline concern to the user.\n` : "";

  return `SUCCESS: Training plan created with professional periodization.${warningSection}

CRITICAL: Use ONLY these exact values in your response. Do NOT use your own calculations.

PLAN_ID: ${planId}
Name: ${name}
Goal: ${goalName}
DURATION: ${durationWeeks} weeks
Start: ${startDateStr}
End: ${endDateStr}
Split: ${splitName}
Training Days: ${strengthDays} days/week
Session Duration: ${sessionDuration} minutes
${phaseStructure}
TOTAL WORKOUTS: ${workouts.length} (${strengthWorkouts} strength${cardioWorkouts > 0 ? `, ${cardioWorkouts} cardio` : ""})

FIRST WEEK PREVIEW:
${firstWeekPreview}
RESPONSE RULES:
1. State the EXACT duration above (${durationWeeks} weeks) - do NOT say any other number
2. Mention the plan name and goal
3. Tell them ${workouts.length} workouts were scheduled
4. Keep response concise and conversational
5. If there are multiple phases, briefly explain the structure
6. Ask if they want to activate the plan to start tracking`;
}
