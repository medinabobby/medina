/**
 * Start Workout Handler
 *
 * Migrated from iOS: StartWorkoutHandler.swift
 * Starts a workout session by updating status to inProgress and setting startedAt.
 * Validates workout exists and is in a valid state (scheduled, not already started/completed).
 */

import {HandlerContext, HandlerResult, SuggestionChip} from "./index";
import * as admin from "firebase-admin";

/**
 * Arguments for start_workout tool
 */
interface StartWorkoutArgs {
  workoutId?: string;
}

/**
 * Workout status enum (matches iOS/Firestore)
 */
type WorkoutStatus = "scheduled" | "inProgress" | "completed" | "skipped";

/**
 * Workout document from Firestore
 */
interface WorkoutDoc {
  id: string;
  name?: string;
  scheduledDate?: string;
  status?: WorkoutStatus;
  planId?: string;
  programId?: string;
  exerciseIds?: string[];
  startedAt?: string;
}

/**
 * Plan document from Firestore
 */
interface PlanDoc {
  id: string;
  name: string;
  status: "draft" | "active" | "completed" | "abandoned";
}

/**
 * Format a date as "Monday, December 15"
 */
function formatDate(date: Date): string {
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

/**
 * Get start of day for a date (for date comparisons)
 */
function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setHours(0, 0, 0, 0);
  return result;
}

/**
 * Resolve workoutId aliases like "today" or "next" to actual workout IDs
 */
async function resolveWorkoutId(
  workoutId: string,
  uid: string,
  db: admin.firestore.Firestore
): Promise<string | null> {
  // If it's a regular ID, return as-is
  if (workoutId !== "today" && workoutId !== "next") {
    return workoutId;
  }

  const now = new Date();
  const todayStart = startOfDay(now).toISOString();
  const todayEnd = new Date(startOfDay(now).getTime() + 24 * 60 * 60 * 1000 - 1).toISOString();

  if (workoutId === "today") {
    // Find workout scheduled for today
    const snapshot = await db
      .collection(`users/${uid}/workouts`)
      .where("scheduledDate", ">=", todayStart)
      .where("scheduledDate", "<=", todayEnd)
      .where("status", "==", "scheduled")
      .limit(1)
      .get();

    return snapshot.empty ? null : snapshot.docs[0].id;
  }

  if (workoutId === "next") {
    // Find next scheduled workout (today or future)
    const snapshot = await db
      .collection(`users/${uid}/workouts`)
      .where("status", "==", "scheduled")
      .where("scheduledDate", ">=", todayStart)
      .orderBy("scheduledDate", "asc")
      .limit(1)
      .get();

    return snapshot.empty ? null : snapshot.docs[0].id;
  }

  return null;
}

/**
 * Check if there's an active workout session for this user
 */
async function findActiveWorkout(
  uid: string,
  db: admin.firestore.Firestore
): Promise<{id: string; name: string} | null> {
  const snapshot = await db
    .collection(`users/${uid}/workouts`)
    .where("status", "==", "inProgress")
    .limit(1)
    .get();

  if (snapshot.empty) {
    return null;
  }

  const doc = snapshot.docs[0];
  const data = doc.data() as WorkoutDoc;
  return {
    id: doc.id,
    name: data.name || "Workout",
  };
}

/**
 * Handle start_workout tool call
 *
 * Flow:
 * 1. Resolve workoutId (supports "today" and "next" aliases)
 * 2. Check for active workout session (user can only have one active workout)
 * 3. Validate workout exists and is scheduled
 * 4. Check if workout belongs to an active plan (not draft)
 * 5. Update workout status to "inProgress" and set startedAt
 * 6. Return success with exercise suggestions
 */
export async function startWorkoutHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {workoutId: rawWorkoutId} = args as StartWorkoutArgs;

  // Validate workoutId provided
  if (!rawWorkoutId) {
    return {
      output: "ERROR: Missing required parameter 'workoutId'. Please specify which workout to start.",
    };
  }

  // Check for active workout first (before resolving ID)
  const activeWorkout = await findActiveWorkout(uid, db);

  // Resolve workout ID aliases
  const workoutId = await resolveWorkoutId(rawWorkoutId, uid, db);

  // If trying to start the same workout that's already active
  if (activeWorkout && workoutId === activeWorkout.id) {
    return {
      output: `Your "${activeWorkout.name}" workout is already in progress. Would you like to continue?`,
      suggestionChips: [
        {label: "Continue workout", command: `Continue workout ${activeWorkout.id}`},
        {label: "End workout", command: `End workout ${activeWorkout.id}`},
      ],
    };
  }

  // If there's a different active workout
  if (activeWorkout) {
    return {
      output: `You already have "${activeWorkout.name}" in progress. You need to finish or end that workout before starting a new one.`,
      suggestionChips: [
        {label: `Continue ${activeWorkout.name}`, command: `Continue workout ${activeWorkout.id}`},
        {label: "End current workout", command: `End workout ${activeWorkout.id}`},
      ],
    };
  }

  // Handle case where alias didn't resolve to a workout
  if (!workoutId) {
    if (rawWorkoutId === "today") {
      return {
        output: "No workout scheduled for today. Would you like to create one?",
        suggestionChips: [
          {label: "Create workout", command: "Create a workout for today"},
          {label: "Show schedule", command: "Show my schedule"},
        ],
      };
    }
    if (rawWorkoutId === "next") {
      return {
        output: "No upcoming workouts scheduled. Would you like to create one?",
        suggestionChips: [
          {label: "Create workout", command: "Create a workout for today"},
          {label: "Create plan", command: "Create a training plan"},
        ],
      };
    }
    return {
      output: `ERROR: Workout not found with ID '${rawWorkoutId}'.`,
    };
  }

  // Get the workout document
  const workoutRef = db.doc(`users/${uid}/workouts/${workoutId}`);
  const workoutDoc = await workoutRef.get();

  if (!workoutDoc.exists) {
    return {
      output: `ERROR: Workout not found with ID '${workoutId}'.`,
    };
  }

  const workout = {id: workoutDoc.id, ...workoutDoc.data()} as WorkoutDoc;
  const workoutName = workout.name || "Workout";

  // Check if workout belongs to a draft plan
  if (workout.planId) {
    const planRef = db.doc(`users/${uid}/plans/${workout.planId}`);
    const planDoc = await planRef.get();

    if (planDoc.exists) {
      const plan = planDoc.data() as PlanDoc;
      if (plan.status === "draft") {
        return {
          output: `Cannot start "${workoutName}" because the plan "${plan.name}" hasn't been activated yet. Would you like to activate it first?`,
          suggestionChips: [
            {label: "Activate plan", command: `Activate plan ${workout.planId}`},
            {label: "Keep as draft", command: "Never mind"},
          ],
        };
      }
    }
  }

  // Check workout status
  if (workout.status === "completed") {
    return {
      output: `"${workoutName}" has already been completed. Would you like to review your results or start a different workout?`,
      suggestionChips: [
        {label: "Show results", command: `Show results for workout ${workoutId}`},
        {label: "Show schedule", command: "Show my schedule"},
      ],
    };
  }

  if (workout.status === "skipped") {
    return {
      output: `"${workoutName}" was marked as skipped. Would you like to reschedule it or create a new workout?`,
      suggestionChips: [
        {label: "Reschedule", command: `Reschedule workout ${workoutId}`},
        {label: "Create new", command: "Create a workout for today"},
      ],
    };
  }

  if (workout.status === "inProgress") {
    return {
      output: `"${workoutName}" is already in progress. Would you like to continue?`,
      suggestionChips: [
        {label: "Continue workout", command: `Continue workout ${workoutId}`},
        {label: "End workout", command: `End workout ${workoutId}`},
      ],
    };
  }

  // Update workout status to inProgress and set startedAt
  const now = new Date().toISOString();
  try {
    await workoutRef.update({
      status: "inProgress",
      startedAt: now,
      updatedAt: now,
    });

    console.log(`[start_workout] Started workout '${workoutName}' for user ${uid}`);
  } catch (error) {
    console.error(`[start_workout] Error starting workout:`, error);
    return {
      output: `ERROR: Failed to start workout. Please try again.`,
    };
  }

  // Build success response
  const exerciseCount = workout.exerciseIds?.length || 0;
  const scheduledDate = workout.scheduledDate ? new Date(workout.scheduledDate) : null;
  const dateStr = scheduledDate ? formatDate(scheduledDate) : "today";

  // Build suggestion chips for exercises
  const chips: SuggestionChip[] = [
    {label: "Show exercises", command: `Show exercises for workout ${workoutId}`},
    {label: "End workout", command: `End workout ${workoutId}`},
  ];

  const output = `Started "${workoutName}" (${dateStr}).

${exerciseCount > 0 ? `This workout has ${exerciseCount} exercise${exerciseCount === 1 ? "" : "s"}.` : ""}

Tap the workout card below to begin, or ask me about specific exercises.

[VOICE_READY]
Confirm the workout has started and mention they can tap the card to begin.`;

  return {
    output,
    suggestionChips: chips,
  };
}
