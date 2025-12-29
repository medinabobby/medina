/**
 * Abandon Plan Handler
 *
 * Migrated from iOS: AbandonPlanHandler.swift + PlanAbandonmentService.swift
 * Handles abandon_plan tool calls - ends active plan early
 * Marks remaining scheduled workouts as skipped
 */

import {HandlerContext, HandlerResult, SuggestionChip} from "./index";

/**
 * Arguments for abandon_plan tool
 */
interface AbandonPlanArgs {
  planId?: string;
}

/**
 * Plan status enum (matches iOS/Firestore)
 */
type PlanStatus = "draft" | "active" | "completed" | "abandoned";

/**
 * Workout status enum (matches iOS/Firestore)
 */
type WorkoutStatus = "scheduled" | "in_progress" | "completed" | "skipped";

/**
 * Plan document from Firestore
 */
interface PlanDoc {
  id: string;
  name: string;
  status: PlanStatus;
  memberId: string;
}

/**
 * Workout document from Firestore
 */
interface WorkoutDoc {
  id: string;
  planId: string;
  status: WorkoutStatus;
  scheduledDate?: FirebaseFirestore.Timestamp;
}

/**
 * Handle abandon_plan tool call
 *
 * Flow:
 * 1. Resolve planId (supports "current"/"active" aliases)
 * 2. Validate plan exists and is active
 * 3. Update plan status to "completed" (ending early)
 * 4. Mark remaining scheduled workouts as skipped
 */
export async function abandonPlanHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {planId: rawPlanId} = args as AbandonPlanArgs;

  let planId = rawPlanId;

  // Handle "current" or "active" alias - find user's active plan
  if (planId === "current" || planId === "active") {
    const activeSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("plans")
      .where("status", "==", "active")
      .limit(1)
      .get();

    if (activeSnapshot.empty) {
      return {
        output: "ERROR: You don't have an active plan to end. Use 'delete plan' for draft plans.",
      };
    }

    planId = activeSnapshot.docs[0].id;
  }

  // Validate planId provided
  if (!planId) {
    return {
      output: "ERROR: Missing required parameter 'planId'. Please specify which plan to end.",
    };
  }

  // Get the plan
  const planRef = db.collection("users").doc(uid).collection("plans").doc(planId);
  const planDoc = await planRef.get();

  if (!planDoc.exists) {
    return {
      output: `ERROR: Plan not found with ID '${planId}'. Please check the plan ID.`,
    };
  }

  const plan = {id: planDoc.id, ...planDoc.data()} as PlanDoc;

  // Check status - only active plans can be abandoned
  switch (plan.status) {
    case "draft":
      return {
        output: `'${plan.name}' is a draft plan that hasn't been activated yet.\n\nWould you like to delete it instead?`,
        suggestionChips: [
          {label: "Delete draft", command: `Delete plan ${plan.id}`},
          {label: "Keep it", command: "Never mind"},
        ],
      };

    case "completed":
      return {
        output: `'${plan.name}' has already been completed. No action needed.`,
      };

    case "abandoned":
      return {
        output: `'${plan.name}' has already been ended. No action needed.`,
      };

    case "active":
      // This is the valid case - proceed with abandonment
      break;
  }

  // Get all workouts for this plan
  const workoutsSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .where("planId", "==", planId)
    .get();

  const now = new Date();

  // Categorize workouts
  let scheduledCount = 0;
  let completedCount = 0;
  const workoutsToSkip: FirebaseFirestore.DocumentReference[] = [];

  for (const workoutDoc of workoutsSnapshot.docs) {
    const workout = {id: workoutDoc.id, ...workoutDoc.data()} as WorkoutDoc;

    if (workout.status === "completed") {
      completedCount++;
    } else if (workout.status === "scheduled") {
      // Check if workout is in the future (or has no scheduled date)
      const scheduledDate = workout.scheduledDate?.toDate();
      if (!scheduledDate || scheduledDate > now) {
        workoutsToSkip.push(workoutDoc.ref);
        scheduledCount++;
      }
    }
  }

  // Perform abandonment
  try {
    const batch = db.batch();

    // Update plan status to "completed" (v172: ending early = completed)
    batch.update(planRef, {
      status: "completed",
      updatedAt: new Date(),
    });

    // Mark remaining scheduled workouts as skipped
    for (const workoutRef of workoutsToSkip) {
      batch.update(workoutRef, {
        status: "skipped",
        updatedAt: new Date(),
      });
    }

    await batch.commit();

    console.log(`[abandon_plan] Ended plan '${plan.name}' early for user ${uid}, skipped ${scheduledCount} workouts`);

    // Build summary
    let summary = `Plan '${plan.name}' has been ended early.`;

    if (completedCount > 0) {
      summary += ` You completed ${completedCount} workout${completedCount === 1 ? "" : "s"}.`;
    }

    if (scheduledCount > 0) {
      summary += ` ${scheduledCount} remaining workout${scheduledCount === 1 ? " was" : "s were"} marked as skipped.`;
    }

    const chips: SuggestionChip[] = [
      {label: "Create new plan", command: "Create a training plan"},
      {label: "Show schedule", command: "Show my schedule"},
    ];

    return {
      output: summary,
      suggestionChips: chips,
    };
  } catch (error) {
    console.error(`[abandon_plan] Error ending plan:`, error);
    return {
      output: `ERROR: Failed to end plan. Please try again.`,
    };
  }
}
