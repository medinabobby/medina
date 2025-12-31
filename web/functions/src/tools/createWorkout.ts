/**
 * Create Workout Handler
 *
 * v236: Refactored to use StrengthBuilder and CardioBuilder service layers
 *
 * Handles create_workout tool calls - creates workout with exercises and protocols.
 * Routes to StrengthBuilder or CardioBuilder based on sessionType.
 */

import {HandlerContext, HandlerResult, SuggestionChip, WorkoutCardData} from "./index";
import {
  buildStrengthWorkout,
  buildCardioWorkout,
  suggestCardioStyle,
  getActivePlan,
  parseScheduledDate,
  formatDate,
  SplitDay,
  EffortLevel,
  SessionType,
  Equipment,
  TrainingLocation,
  CardioStyle,
} from "../services/workout";

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
  cardioStyle?: string; // For cardio workouts: steady, intervals, hiit, mixed
}

// ============================================================================
// Validation
// ============================================================================

/**
 * Validate required parameters
 * Returns error message or null if valid
 */
function validateArgs(args: CreateWorkoutArgs): string | null {
  if (!args.name) {
    return "ERROR: Missing required parameter 'name'. Please provide a workout name.";
  }

  if (!args.scheduledDate) {
    return "ERROR: Missing required parameter 'scheduledDate'. Please provide a date in YYYY-MM-DD format.";
  }

  if (!args.effortLevel) {
    return "ERROR: Missing required parameter 'effortLevel'. Please specify effort level (recovery, standard, or push).";
  }

  // Cardio workouts have different requirements
  const isCardio = args.sessionType === "cardio";

  if (!isCardio) {
    // Strength workouts require splitDay and exerciseIds
    if (!args.splitDay) {
      return "ERROR: Missing required parameter 'splitDay'. Please specify the workout split (upper, lower, push, pull, legs, fullBody, etc.).";
    }

    if (!args.exerciseIds || args.exerciseIds.length === 0) {
      return "ERROR: Missing required parameter 'exerciseIds'. Please select exercises from your EXERCISE OPTIONS context.";
    }
  }

  return null;
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
 * 3. Route to StrengthBuilder or CardioBuilder based on sessionType
 * 4. Format and return response
 */
export async function createWorkoutHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const typedArgs = args as CreateWorkoutArgs;

  // Validate required parameters
  const validationError = validateArgs(typedArgs);
  if (validationError) {
    return {output: validationError};
  }

  const {
    name,
    splitDay: rawSplitDay,
    scheduledDate: rawScheduledDate,
    duration = 45,
    effortLevel: rawEffortLevel,
    sessionType: rawSessionType,
    exerciseIds: requestedExerciseIds,
    selectionReasoning,
    trainingLocation: rawTrainingLocation,
    availableEquipment: rawEquipment,
    protocolId: overrideProtocolId,
    planId: explicitPlanId,
    cardioStyle: rawCardioStyle,
  } = typedArgs;

  // Parse parameters
  const splitDay = rawSplitDay as SplitDay;
  const effortLevel = rawEffortLevel as EffortLevel;
  const sessionType = (rawSessionType as SessionType) || "strength";
  const scheduledDate = parseScheduledDate(rawScheduledDate);
  const trainingLocation = rawTrainingLocation as TrainingLocation | undefined;
  const availableEquipment = rawEquipment as Equipment[] | undefined;

  console.log(`[create_workout] Creating ${sessionType} workout '${name}' for user ${uid}`);
  console.log(`[create_workout] Duration: ${duration}min, Effort: ${effortLevel}`);

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

    // Route to appropriate builder based on session type
    if (sessionType === "cardio") {
      return await createCardioWorkout(db, uid, {
        name: name!,
        duration,
        effortLevel,
        scheduledDate,
        cardioStyle: (rawCardioStyle as CardioStyle) || suggestCardioStyle(duration, effortLevel),
        trainingLocation,
        availableEquipment,
        planId,
        programId,
        planName,
      });
    }

    // Build strength workout using StrengthBuilder service
    console.log(`[create_workout] Split: ${splitDay}, Requested exercises: ${requestedExerciseIds?.length || 0}`);

    const result = await buildStrengthWorkout(db, {
      userId: uid,
      name: name!,
      targetDuration: duration,
      splitDay,
      effortLevel,
      sessionType,
      scheduledDate,
      exerciseIds: requestedExerciseIds,
      availableEquipment,
      trainingLocation,
      protocolOverride: overrideProtocolId,
      planId,
      programId,
    });

    const {workout, exerciseCount, actualDuration} = result;

    console.log(`[create_workout] Created workout ${workout.id} with ${exerciseCount} exercises`);

    // Format success response
    const dateString = formatDate(scheduledDate);

    // Get exercise names for display (fetch from Firestore)
    const exerciseNames: string[] = [];
    for (const exerciseId of workout.exerciseIds.slice(0, 5)) {
      const exerciseDoc = await db.collection("exercises").doc(exerciseId).get();
      if (exerciseDoc.exists) {
        exerciseNames.push(exerciseDoc.data()?.name || exerciseId);
      } else {
        exerciseNames.push(exerciseId);
      }
    }
    const exerciseList = exerciseNames.join(", ") + (exerciseCount > 5 ? "..." : "");

    // Build response output
    let output = `SUCCESS: Workout created.

WORKOUT_ID: ${workout.id}
Name: ${name}
Date: ${dateString}
Exercises: ${exerciseCount}
Duration: ~${actualDuration} minutes
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

    // Check for 1RM data (check instances for targetWeight)
    const instancesWithTargets = result.instances.filter((i) => i.targetWeight !== undefined);
    if (instancesWithTargets.length > 0) {
      output += `\n\nTARGET WEIGHTS:
${instancesWithTargets.length} of ${exerciseCount} exercises have 1RM data - target weights calculated.`;
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
      {label: "Start workout", command: `Start workout ${workout.id}`},
      {label: "Modify exercises", command: `Modify workout ${workout.id}`},
    ];

    if (!planId) {
      chips.push({label: "Create plan", command: "Create a training plan"});
    }

    // Include workout card data for inline display
    const workoutCard: WorkoutCardData = {
      workoutId: workout.id,
      workoutName: name!,
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
        {label: "Try again", command: `Create a ${splitDay || sessionType} workout for ${rawScheduledDate}`},
        {label: "Get help", command: "What workouts can I create?"},
      ],
    };
  }
}

// ============================================================================
// Cardio Workout Creation
// ============================================================================

interface CardioWorkoutParams {
  name: string;
  duration: number;
  effortLevel: EffortLevel;
  scheduledDate: Date;
  cardioStyle: CardioStyle;
  trainingLocation?: TrainingLocation;
  availableEquipment?: Equipment[];
  planId?: string;
  programId?: string;
  planName?: string;
}

/**
 * Create a cardio workout using CardioBuilder
 */
async function createCardioWorkout(
  db: FirebaseFirestore.Firestore,
  uid: string,
  params: CardioWorkoutParams
): Promise<HandlerResult> {
  const {
    name,
    duration,
    effortLevel,
    scheduledDate,
    cardioStyle,
    trainingLocation,
    availableEquipment,
    planId,
    programId,
    planName,
  } = params;

  console.log(`[create_workout] Cardio style: ${cardioStyle}`);

  const result = await buildCardioWorkout(db, {
    userId: uid,
    name,
    targetDuration: duration,
    effortLevel,
    scheduledDate,
    cardioStyle,
    trainingLocation,
    availableEquipment,
    planId,
    programId,
  });

  const {workout, exerciseCount, actualDuration} = result;

  console.log(`[create_workout] Created cardio workout ${workout.id} with ${exerciseCount} exercises`);

  // Format success response
  const dateString = formatDate(scheduledDate);

  // Get exercise names for display
  const exerciseNames: string[] = [];
  for (const exerciseId of workout.exerciseIds.slice(0, 5)) {
    const exerciseDoc = await db.collection("exercises").doc(exerciseId).get();
    if (exerciseDoc.exists) {
      exerciseNames.push(exerciseDoc.data()?.name || exerciseId);
    } else {
      exerciseNames.push(exerciseId);
    }
  }
  const exerciseList = exerciseNames.length > 0
    ? exerciseNames.join(", ")
    : "Cardio exercises selected automatically";

  // Build response output
  let output = `SUCCESS: Cardio workout created.

WORKOUT_ID: ${workout.id}
Name: ${name}
Date: ${dateString}
Type: ${cardioStyle} cardio
Duration: ~${actualDuration} minutes
Effort: ${effortLevel}
Status: Ready to start

EXERCISES:
${exerciseList}`;

  if (planName) {
    output += `\n\nAdded to plan: ${planName}`;
  }

  output += `

RESPONSE_GUIDANCE:
1. Confirm the cardio workout was created
2. Mention the cardio style (${cardioStyle}) and duration
3. Remind user they can modify if they want different exercises
4. Tell them they can tap the workout card below to review`;

  // Build suggestion chips
  const chips: SuggestionChip[] = [
    {label: "Start workout", command: `Start workout ${workout.id}`},
    {label: "Modify workout", command: `Modify workout ${workout.id}`},
  ];

  if (!planId) {
    chips.push({label: "Create plan", command: "Create a training plan"});
  }

  // Include workout card data for inline display
  const workoutCard: WorkoutCardData = {
    workoutId: workout.id,
    workoutName: name,
  };

  return {
    output,
    suggestionChips: chips,
    workoutCard,
  };
}
