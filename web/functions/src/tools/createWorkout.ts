/**
 * Create Workout Handler
 *
 * Migrated from iOS: CreateWorkoutHandler.swift
 * Handles create_workout tool calls - creates workout with exercises and protocols
 * Most complex handler due to exercise selection and protocol assignment logic
 */

import * as admin from "firebase-admin";
import {HandlerContext, HandlerResult, SuggestionChip, WorkoutCardData} from "./index";

// ============================================================================
// Types
// ============================================================================

/**
 * Arguments for create_workout tool
 */
interface CreateWorkoutArgs {
  name?: string;
  splitDay?: string;
  scheduledDate?: string;
  duration?: number;
  effortLevel?: string;
  sessionType?: string;
  exerciseIds?: string[];
  selectionReasoning?: string;
  trainingLocation?: string;
  availableEquipment?: string[];
  protocolId?: string;
  planId?: string;
}

/**
 * Split day types (matches iOS SplitDay enum)
 */
type SplitDay = "upper" | "lower" | "push" | "pull" | "legs" | "fullBody" |
  "chest" | "back" | "shoulders" | "arms" | "notApplicable";

/**
 * Effort level types (matches iOS EffortLevel enum)
 */
type EffortLevel = "recovery" | "standard" | "push";

/**
 * Session type (strength or cardio)
 */
type SessionType = "strength" | "cardio";

/**
 * Workout status types
 */
type WorkoutStatus = "scheduled" | "inProgress" | "completed" | "skipped";

/**
 * Exercise document from Firestore
 */
interface ExerciseDoc {
  id: string;
  name: string;
  muscleGroups?: string[];
  exerciseType?: string;
  equipment?: string;
}

/**
 * Exercise target (user's 1RM data)
 */
interface ExerciseTargetDoc {
  exerciseId: string;
  oneRepMax?: number;
  lastUpdated?: string;
}

/**
 * Workout document structure for Firestore
 */
interface WorkoutDocument {
  id: string;
  name: string;
  scheduledDate: string;
  type: SessionType;
  splitDay: SplitDay;
  status: WorkoutStatus;
  exerciseIds: string[];
  protocolVariantIds: Record<string, string>;
  planId?: string;
  programId?: string;
  createdAt: string;
  updatedAt: string;
}

/**
 * Exercise instance document for Firestore
 */
interface ExerciseInstanceDocument {
  id: string;
  workoutId: string;
  exerciseId: string;
  protocolVariantId: string;
  position: number;
  targetWeight?: number;
  createdAt: string;
}

// ============================================================================
// Constants
// ============================================================================

/**
 * Muscle groups for each split day
 */
const SPLIT_DAY_MUSCLES: Record<SplitDay, string[]> = {
  upper: ["chest", "back", "shoulders", "biceps", "triceps"],
  lower: ["quadriceps", "hamstrings", "glutes", "calves"],
  push: ["chest", "shoulders", "triceps"],
  pull: ["back", "biceps", "traps", "lats"],
  legs: ["quadriceps", "hamstrings", "glutes", "calves"],
  fullBody: ["chest", "back", "quadriceps", "hamstrings", "shoulders"],
  chest: ["chest", "triceps"],
  back: ["back", "biceps", "traps"],
  shoulders: ["shoulders", "traps"],
  arms: ["biceps", "triceps", "forearms"],
  notApplicable: [],
};

/**
 * Exercise count based on duration
 * 30min -> 3, 45min -> 4, 60min -> 5, 75min -> 6, 90min -> 7
 */
function getExerciseCount(duration: number): number {
  if (duration <= 30) return 3;
  if (duration <= 45) return 4;
  if (duration <= 60) return 5;
  if (duration <= 75) return 6;
  return 7;
}

/**
 * Effort level to intensity mapping
 */
const EFFORT_INTENSITY: Record<EffortLevel, number> = {
  recovery: 0.60,
  standard: 0.75,
  push: 0.85,
};

/**
 * Default protocols for exercise types and intensities
 */
function getDefaultProtocol(exerciseType: string, intensity: number): string {
  if (exerciseType === "cardio") {
    return "cardio_30min_steady";
  }

  if (exerciseType === "compound") {
    if (intensity < 0.65) return "strength_3x5_moderate";
    if (intensity < 0.80) return "strength_3x5_heavy";
    return "strength_3x3_heavy";
  }

  // Isolation
  if (intensity < 0.65) return "accessory_3x12_light";
  if (intensity < 0.80) return "accessory_3x10_rpe8";
  return "accessory_3x8_rpe8";
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Validate and parse the scheduled date
 */
function parseScheduledDate(dateStr: string | undefined): Date {
  if (!dateStr) {
    return new Date();
  }

  const parsed = new Date(dateStr);
  if (isNaN(parsed.getTime())) {
    return new Date();
  }

  return parsed;
}

/**
 * Format date for display
 */
function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

/**
 * Get exercises from Firestore global collection that match the split day
 */
async function getExercisesForSplitDay(
  db: admin.firestore.Firestore,
  splitDay: SplitDay,
  sessionType: SessionType,
  exerciseCount: number,
  requestedExerciseIds?: string[],
  availableEquipment?: string[]
): Promise<ExerciseDoc[]> {
  // If specific exercise IDs were requested, fetch and validate them
  if (requestedExerciseIds && requestedExerciseIds.length > 0) {
    const validExercises: ExerciseDoc[] = [];

    for (const exerciseId of requestedExerciseIds) {
      const exerciseDoc = await db.collection("exercises").doc(exerciseId).get();
      if (exerciseDoc.exists) {
        const data = exerciseDoc.data();
        validExercises.push({
          id: exerciseDoc.id,
          name: data?.name || exerciseId,
          muscleGroups: data?.muscleGroups || [],
          exerciseType: data?.exerciseType || "compound",
          equipment: data?.equipment || "barbell",
        });
      }
    }

    return validExercises.slice(0, exerciseCount);
  }

  // Query exercises based on split day and session type
  const targetMuscles = SPLIT_DAY_MUSCLES[splitDay];
  const exercisesRef = db.collection("exercises");

  let query: admin.firestore.Query = exercisesRef;

  // For cardio, filter by exercise type
  if (sessionType === "cardio") {
    query = query.where("exerciseType", "==", "cardio");
  }

  const snapshot = await query.limit(50).get();
  const exercises: ExerciseDoc[] = [];

  snapshot.docs.forEach((doc) => {
    const data = doc.data();
    const muscleGroups: string[] = data.muscleGroups || [];
    const exerciseType: string = data.exerciseType || "compound";
    const equipment: string = data.equipment || "barbell";

    // Filter by session type
    if (sessionType === "cardio") {
      if (exerciseType === "cardio") {
        exercises.push({
          id: doc.id,
          name: data.name || doc.id,
          muscleGroups,
          exerciseType,
          equipment,
        });
      }
      return;
    }

    // For strength, check muscle group match
    const matchesMuscle = targetMuscles.length === 0 ||
      muscleGroups.some((mg) => targetMuscles.includes(mg));

    // Filter by equipment if specified
    const matchesEquipment = !availableEquipment || availableEquipment.length === 0 ||
      availableEquipment.includes(equipment) ||
      equipment === "bodyweight";

    if (matchesMuscle && matchesEquipment && exerciseType !== "cardio") {
      exercises.push({
        id: doc.id,
        name: data.name || doc.id,
        muscleGroups,
        exerciseType,
        equipment,
      });
    }
  });

  // Prioritize compound exercises first
  exercises.sort((a, b) => {
    if (a.exerciseType === "compound" && b.exerciseType !== "compound") return -1;
    if (a.exerciseType !== "compound" && b.exerciseType === "compound") return 1;
    return 0;
  });

  return exercises.slice(0, exerciseCount);
}

/**
 * Get user's exercise targets (1RM data)
 */
async function getExerciseTargets(
  db: admin.firestore.Firestore,
  uid: string,
  exerciseIds: string[]
): Promise<Map<string, ExerciseTargetDoc>> {
  const targets = new Map<string, ExerciseTargetDoc>();

  for (const exerciseId of exerciseIds) {
    const targetDoc = await db
      .collection(`users/${uid}/exerciseTargets`)
      .doc(exerciseId)
      .get();

    if (targetDoc.exists) {
      const data = targetDoc.data();
      targets.set(exerciseId, {
        exerciseId,
        oneRepMax: data?.oneRepMax,
        lastUpdated: data?.lastUpdated,
      });
    }
  }

  return targets;
}

/**
 * Calculate target weight based on 1RM and intensity
 */
function calculateTargetWeight(oneRepMax: number | undefined, intensity: number): number | undefined {
  if (!oneRepMax) return undefined;
  // Round to nearest 5
  const raw = oneRepMax * intensity;
  return Math.round(raw / 5) * 5;
}

/**
 * Create exercise instances for the workout
 */
async function createExerciseInstances(
  db: admin.firestore.Firestore,
  uid: string,
  workoutId: string,
  exercises: ExerciseDoc[],
  intensity: number,
  exerciseTargets: Map<string, ExerciseTargetDoc>,
  overrideProtocolId?: string
): Promise<Record<string, string>> {
  const batch = db.batch();
  const protocolVariantIds: Record<string, string> = {};

  for (let i = 0; i < exercises.length; i++) {
    const exercise = exercises[i];
    const instanceId = `instance_${workoutId}_${i}`;

    // Determine protocol
    const protocolId = overrideProtocolId ||
      getDefaultProtocol(exercise.exerciseType || "compound", intensity);

    protocolVariantIds[i.toString()] = protocolId;

    // Get target weight from user's 1RM data
    const target = exerciseTargets.get(exercise.id);
    const targetWeight = calculateTargetWeight(target?.oneRepMax, intensity);

    const instanceDoc: ExerciseInstanceDocument = {
      id: instanceId,
      workoutId,
      exerciseId: exercise.id,
      protocolVariantId: protocolId,
      position: i,
      createdAt: new Date().toISOString(),
      // Only include targetWeight if defined (Firestore rejects undefined)
      ...(targetWeight !== undefined && {targetWeight}),
    };

    const instanceRef = db
      .collection(`users/${uid}/workouts/${workoutId}/instances`)
      .doc(instanceId);

    batch.set(instanceRef, instanceDoc);
  }

  await batch.commit();

  return protocolVariantIds;
}

/**
 * Check if user has an active plan and get it
 */
async function getActivePlan(
  db: admin.firestore.Firestore,
  uid: string
): Promise<{planId: string; programId: string; planName: string} | null> {
  const plansSnapshot = await db
    .collection(`users/${uid}/plans`)
    .where("status", "==", "active")
    .where("isSingleWorkout", "==", false)
    .limit(1)
    .get();

  if (plansSnapshot.empty) {
    return null;
  }

  const planDoc = plansSnapshot.docs[0];
  const planData = planDoc.data();

  // Get the program for this plan
  const programsSnapshot = await planDoc.ref.collection("programs").limit(1).get();
  const programId = programsSnapshot.empty ? `program_${planDoc.id}` : programsSnapshot.docs[0].id;

  return {
    planId: planDoc.id,
    programId,
    planName: planData.name || "Training Plan",
  };
}

// ============================================================================
// Main Handler
// ============================================================================

/**
 * Handle create_workout tool call
 *
 * Flow:
 * 1. Validate required parameters
 * 2. Check for active plan (insert into it, or create standalone)
 * 3. Select exercises (from AI request or auto-select)
 * 4. Assign protocols based on effort level
 * 5. Create workout document with instances
 * 6. Return workout details
 */
export async function createWorkoutHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {
    name,
    splitDay: rawSplitDay,
    scheduledDate: rawScheduledDate,
    duration = 45,
    effortLevel: rawEffortLevel,
    sessionType: rawSessionType,
    exerciseIds: requestedExerciseIds,
    selectionReasoning,
    trainingLocation: _trainingLocation,
    availableEquipment,
    protocolId: overrideProtocolId,
    planId: explicitPlanId,
  } = args as CreateWorkoutArgs;

  // Validate required parameters
  if (!name) {
    return {
      output: "ERROR: Missing required parameter 'name'. Please provide a workout name.",
    };
  }

  if (!rawSplitDay) {
    return {
      output: "ERROR: Missing required parameter 'splitDay'. Please specify the workout split (upper, lower, push, pull, legs, fullBody, etc.).",
    };
  }

  if (!rawScheduledDate) {
    return {
      output: "ERROR: Missing required parameter 'scheduledDate'. Please provide a date in YYYY-MM-DD format.",
    };
  }

  if (!rawEffortLevel) {
    return {
      output: "ERROR: Missing required parameter 'effortLevel'. Please specify effort level (recovery, standard, or push).",
    };
  }

  if (!requestedExerciseIds || requestedExerciseIds.length === 0) {
    return {
      output: "ERROR: Missing required parameter 'exerciseIds'. Please select exercises from your EXERCISE OPTIONS context.",
    };
  }

  // Parse and validate parameters
  const splitDay = rawSplitDay as SplitDay;
  const effortLevel = rawEffortLevel as EffortLevel;
  const sessionType = (rawSessionType as SessionType) || "strength";
  const scheduledDate = parseScheduledDate(rawScheduledDate);
  const intensity = EFFORT_INTENSITY[effortLevel] || 0.75;
  const exerciseCount = getExerciseCount(duration);

  console.log(`[create_workout] Creating workout '${name}' for user ${uid}`);
  console.log(`[create_workout] Split: ${splitDay}, Duration: ${duration}min, Effort: ${effortLevel}`);
  console.log(`[create_workout] Requested exercises: ${requestedExerciseIds?.length || 0}`);

  try {
    // Check for active plan to insert into
    let planId = explicitPlanId;
    let programId: string | undefined;
    let planName: string | undefined;

    if (!planId) {
      const activePlan = await getActivePlan(db, uid);
      if (activePlan) {
        planId = activePlan.planId;
        programId = activePlan.programId;
        planName = activePlan.planName;
        console.log(`[create_workout] Inserting into active plan: ${planName} (${planId})`);
      }
    }

    // Get exercises - validate requested ones or select appropriate exercises
    const exercises = await getExercisesForSplitDay(
      db,
      splitDay,
      sessionType,
      exerciseCount,
      requestedExerciseIds,
      availableEquipment
    );

    if (exercises.length === 0) {
      return {
        output: `ERROR: No exercises available for ${splitDay} ${sessionType} workout. Please check your exercise library or try a different configuration.`,
        suggestionChips: [
          {label: "Try different split", command: "Create a full body workout"},
          {label: "Add exercises", command: "Add exercises to my library"},
        ],
      };
    }

    // Get user's exercise targets (1RM data)
    const exerciseIds = exercises.map((e) => e.id);
    const exerciseTargets = await getExerciseTargets(db, uid, exerciseIds);

    // Generate workout ID
    const workoutId = `${uid}_workout_${Date.now()}`;

    // Create exercise instances and get protocol mapping
    const protocolVariantIds = await createExerciseInstances(
      db,
      uid,
      workoutId,
      exercises,
      intensity,
      exerciseTargets,
      overrideProtocolId
    );

    // Create workout document (only include planId/programId if defined)
    const workoutDoc: WorkoutDocument = {
      id: workoutId,
      name,
      scheduledDate: scheduledDate.toISOString(),
      type: sessionType,
      splitDay,
      status: "scheduled",
      exerciseIds,
      protocolVariantIds,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      // Only include planId/programId if defined (Firestore rejects undefined)
      ...(planId !== undefined && {planId}),
      ...(programId !== undefined && {programId}),
    };

    // Save workout to Firestore
    await db.collection(`users/${uid}/workouts`).doc(workoutId).set(workoutDoc);

    console.log(`[create_workout] Created workout ${workoutId} with ${exercises.length} exercises`);

    // Format success response
    const dateString = formatDate(scheduledDate);
    const exerciseNames = exercises.slice(0, 5).map((e) => e.name);
    const exerciseList = exerciseNames.join(", ") + (exercises.length > 5 ? "..." : "");

    // Build response output
    let output = `SUCCESS: Workout created.

WORKOUT_ID: ${workoutId}
Name: ${name}
Date: ${dateString}
Exercises: ${exercises.length}
Duration: ~${duration} minutes
Effort: ${effortLevel}
Status: Ready to start

EXERCISES:
${exerciseList}`;

    if (planName) {
      output += `\n\nAdded to plan: ${planName}`;
    }

    if (selectionReasoning) {
      output += `\n\nEXERCISE SELECTION:\n${selectionReasoning}`;
    }

    // Check which exercises have target weights
    const exercisesWithTargets = exercises.filter((e) => exerciseTargets.has(e.id));
    if (exercisesWithTargets.length > 0) {
      output += `\n\nTARGET WEIGHTS:
${exercisesWithTargets.length} of ${exercises.length} exercises have 1RM data - target weights calculated.`;
    } else {
      output += `\n\nNOTE: No 1RM data found for these exercises. You can add your maxes to get personalized target weights.`;
    }

    output += `

RESPONSE_GUIDANCE:
1. Confirm the workout was created with the exercise selection
2. Mention the date and exercise count
3. Remind user they can modify if they want different exercises
4. Tell them they can tap the workout card below to review`;

    // Build suggestion chips
    const chips: SuggestionChip[] = [
      {label: "Start workout", command: `Start workout ${workoutId}`},
      {label: "Modify exercises", command: `Modify workout ${workoutId}`},
    ];

    if (!planId) {
      chips.push({label: "Create plan", command: "Create a training plan"});
    }

    // v210: Include workout card data for inline display
    const workoutCard: WorkoutCardData = {
      workoutId,
      workoutName: name,
    };

    return {
      output,
      suggestionChips: chips,
      workoutCard,
    };
  } catch (error) {
    console.error(`[create_workout] Error creating workout:`, error);
    return {
      output: `ERROR: Failed to create workout. ${error instanceof Error ? error.message : "Unknown error"}`,
      suggestionChips: [
        {label: "Try again", command: `Create a ${splitDay} workout for ${rawScheduledDate}`},
        {label: "Get help", command: "What workouts can I create?"},
      ],
    };
  }
}
