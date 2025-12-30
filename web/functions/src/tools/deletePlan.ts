/**
 * Delete Plan Handler
 *
 * Migrated from iOS: DeletePlanHandler.swift
 * Handles delete_plan tool calls - cascade deletes plan, programs, workouts
 * Requires confirmation for destructive action
 */

import {HandlerContext, HandlerResult, SuggestionChip} from "./index";

/**
 * Arguments for delete_plan tool
 */
interface DeletePlanArgs {
  planId?: string;
  confirmDelete?: boolean;
}

/**
 * Plan status enum (matches iOS/Firestore)
 */
type PlanStatus = "draft" | "active" | "completed" | "abandoned";

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
 * Handle delete_plan tool call
 *
 * Flow:
 * 1. Resolve planId (supports "draft" alias)
 * 2. Validate plan exists and is deletable (not active)
 * 3. If not confirmed, return warning
 * 4. If confirmed, cascade delete plan → programs → workouts
 */
export async function deletePlanHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {planId: rawPlanId, confirmDelete = false} = args as DeletePlanArgs;

  let planId = rawPlanId;

  // Handle "draft" alias - find user's draft plan
  if (planId === "draft") {
    const draftSnapshot = await db
      .collection("users")
      .doc(uid)
      .collection("plans")
      .where("status", "==", "draft")
      .limit(1)
      .get();

    if (draftSnapshot.empty) {
      return {
        output: "ERROR: You don't have a draft plan to delete.",
      };
    }

    planId = draftSnapshot.docs[0].id;
  }

  // Validate planId provided
  if (!planId) {
    return {
      output: "ERROR: Missing required parameter 'planId'. Please specify which plan to delete.",
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

  // Check status - only draft or completed plans can be deleted
  if (plan.status === "active") {
    return {
      output: `'${plan.name}' is an active plan. You can't delete active plans.\n\nWould you like to end it early instead? I'll mark remaining workouts as skipped.`,
      suggestionChips: [
        {label: "End plan early", command: `Abandon plan ${plan.id}`},
        {label: "Keep it", command: "Never mind"},
      ],
    };
  }

  // Count workouts for deletion summary
  const workoutsSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .where("planId", "==", planId)
    .get();

  const workoutCount = workoutsSnapshot.size;

  // If not confirmed, ask for confirmation
  if (!confirmDelete) {
    const chips: SuggestionChip[] = [
      {label: "Yes, delete it", command: `Delete plan ${planId} confirmed`},
      {label: "No, keep it", command: "Cancel"},
    ];

    return {
      output: `This will permanently delete:\n• Plan: ${plan.name}\n• ${workoutCount} workout${workoutCount === 1 ? "" : "s"}\n• All logged exercise data\n\nThis cannot be undone. Are you sure?`,
      suggestionChips: chips,
    };
  }

  // Perform cascade deletion
  try {
    const batch = db.batch();

    // Delete all workouts for this plan
    for (const workoutDoc of workoutsSnapshot.docs) {
      // Delete exercise instances subcollection
      const instancesSnapshot = await workoutDoc.ref.collection("instances").get();
      for (const instanceDoc of instancesSnapshot.docs) {
        // Delete sets subcollection
        const setsSnapshot = await instanceDoc.ref.collection("sets").get();
        for (const setDoc of setsSnapshot.docs) {
          batch.delete(setDoc.ref);
        }
        batch.delete(instanceDoc.ref);
      }
      batch.delete(workoutDoc.ref);
    }

    // Delete programs subcollection
    const programsSnapshot = await planRef.collection("programs").get();
    for (const programDoc of programsSnapshot.docs) {
      batch.delete(programDoc.ref);
    }

    // Delete the plan
    batch.delete(planRef);

    // Commit all deletions
    await batch.commit();

    console.log(`[delete_plan] Deleted plan '${plan.name}' with ${workoutCount} workouts for user ${uid}`);

    return {
      output: `Plan '${plan.name}' has been deleted along with ${workoutCount} workout${workoutCount === 1 ? "" : "s"}.`,
      suggestionChips: [
        {label: "Create new plan", command: "Create a training plan"},
        {label: "Create workout", command: "Create a workout for today"},
      ],
    };
  } catch (error) {
    console.error(`[delete_plan] Error deleting plan:`, error);
    return {
      output: `ERROR: Failed to delete plan. Please try again.`,
    };
  }
}
