/**
 * Activate Plan Handler
 *
 * Migrated from iOS: ActivatePlanHandler.swift, PlanActivationService.swift
 * Handles activate_plan tool calls - activates a draft plan with overlap handling
 */

import {HandlerContext, HandlerResult, SuggestionChip} from "./index";

/**
 * Arguments for activate_plan tool
 */
interface ActivatePlanArgs {
  planId?: string;
  confirmOverlap?: boolean;
}

/**
 * Plan status enum (matches iOS/Firestore)
 */
type PlanStatus = "draft" | "active" | "completed";

/**
 * Plan document from Firestore
 */
interface PlanDoc {
  id: string;
  name: string;
  status: PlanStatus;
  memberId: string;
  startDate: FirebaseFirestore.Timestamp;
  endDate: FirebaseFirestore.Timestamp;
  isSingleWorkout?: boolean;
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
  status: WorkoutStatus;
  scheduledDate?: FirebaseFirestore.Timestamp;
  planId: string;
}

/**
 * Handle activate_plan tool call
 *
 * Flow:
 * 1. Resolve planId (supports "draft" alias)
 * 2. Validate plan exists and is in draft status
 * 3. Check for overlapping active plans
 * 4. If overlap and not confirmed, ask for confirmation
 * 5. If confirmed, auto-complete overlapping plan and activate new plan
 * 6. Return success message with suggestion chips
 */
export async function activatePlanHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;
  const {planId: rawPlanId, confirmOverlap = false} = args as ActivatePlanArgs;

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
        output: "ERROR: You don't have a draft plan to activate.",
      };
    }

    planId = draftSnapshot.docs[0].id;
  }

  // Validate planId provided
  if (!planId) {
    return {
      output: "ERROR: Missing required parameter 'planId'. Please specify which plan to activate.",
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

  // Check status - only draft plans can be activated
  if (plan.status === "active") {
    return {
      output: `Plan '${plan.name}' is already active.`,
      suggestionChips: [
        {label: "View schedule", command: "Show my workout schedule"},
        {label: "Start workout", command: "Start today's workout"},
      ],
    };
  }

  if (plan.status === "completed") {
    return {
      output: `ERROR: Plan '${plan.name}' is completed and cannot be reactivated. You can create a new plan instead.`,
      suggestionChips: [
        {label: "Create new plan", command: "Create a training plan"},
      ],
    };
  }

  // Validate plan has programs
  const programsSnapshot = await planRef.collection("programs").get();
  if (programsSnapshot.empty) {
    return {
      output: `ERROR: Cannot activate plan '${plan.name}' because it has no programs. Plans must have at least one program.`,
    };
  }

  // Validate programs have workouts
  const workoutsSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .where("planId", "==", planId)
    .get();

  if (workoutsSnapshot.empty) {
    return {
      output: `ERROR: Cannot activate plan '${plan.name}' because it has no workouts. Create workouts first.`,
    };
  }

  // Check for overlapping active plans (skip for single workout plans)
  if (!plan.isSingleWorkout) {
    const overlappingPlan = await findOverlappingActivePlan(db, uid, plan);

    if (overlappingPlan && !confirmOverlap) {
      // Count remaining scheduled workouts for the overlapping plan
      const remainingCount = await countRemainingWorkouts(db, uid, overlappingPlan.id);

      const chips: SuggestionChip[] = [
        {label: "Yes, proceed", command: `Activate plan ${planId} and end current plan`},
        {label: "No, keep current", command: "Cancel"},
      ];

      return {
        output: `To activate '${plan.name}', I'll need to end your current plan '${overlappingPlan.name}' early.\nThis will mark ${remainingCount} remaining ${remainingCount === 1 ? "workout" : "workouts"} as skipped.\n\nShould I proceed? (Respond 'yes' to confirm)\n\n[INSTRUCTION: If user confirms, call activate_plan again with planId='${planId}' and confirmOverlap=true]`,
        suggestionChips: chips,
      };
    }

    // If overlap exists and confirmed, complete the overlapping plan first
    if (overlappingPlan && confirmOverlap) {
      await completePlanEarly(db, uid, overlappingPlan.id);
      console.log(`[activate_plan] Auto-completed overlapping plan '${overlappingPlan.name}' for user ${uid}`);
    }
  }

  // Activate the plan
  try {
    await planRef.update({
      status: "active",
    });

    console.log(`[activate_plan] Activated plan '${plan.name}' for user ${uid}`);

    // Count workouts and calculate duration for success message
    const workoutCount = workoutsSnapshot.size;
    const startDate = plan.startDate.toDate();
    const endDate = plan.endDate.toDate();
    const durationDays = Math.ceil((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24));
    const durationWeeks = Math.max(1, Math.ceil(durationDays / 7));

    const durationText = durationWeeks === 1 ? "1 week" : `${durationWeeks} weeks`;

    return {
      output: `I've activated '${plan.name}'. You're all set to start your workouts!\n\nPlan details:\n- ${workoutCount} workout${workoutCount === 1 ? "" : "s"} scheduled\n- Duration: ${durationText}\n\n[VOICE_READY: Confirm the plan is active and ready to use.]`,
      suggestionChips: [
        {label: "View schedule", command: "Show my workout schedule"},
        {label: "Start workout", command: "Start today's workout"},
      ],
    };
  } catch (error) {
    console.error(`[activate_plan] Error activating plan:`, error);
    return {
      output: `ERROR: Failed to activate plan. Please try again.`,
    };
  }
}

/**
 * Find an overlapping active plan (same user, intersecting date range)
 * Returns null if no overlap found
 */
async function findOverlappingActivePlan(
  db: FirebaseFirestore.Firestore,
  uid: string,
  plan: PlanDoc
): Promise<PlanDoc | null> {
  // Get all active plans for this user
  const activePlansSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("plans")
    .where("status", "==", "active")
    .get();

  if (activePlansSnapshot.empty) {
    return null;
  }

  const planStartDate = plan.startDate.toDate();
  const planEndDate = plan.endDate.toDate();

  for (const doc of activePlansSnapshot.docs) {
    const existingPlan = {id: doc.id, ...doc.data()} as PlanDoc;

    // Skip the same plan and single workout plans
    if (existingPlan.id === plan.id || existingPlan.isSingleWorkout) {
      continue;
    }

    const existingStart = existingPlan.startDate.toDate();
    const existingEnd = existingPlan.endDate.toDate();

    // Check for date overlap (inclusive of start and end dates)
    const hasOverlap = !(planEndDate < existingStart || planStartDate > existingEnd);

    if (hasOverlap) {
      return existingPlan;
    }
  }

  return null;
}

/**
 * Count remaining scheduled workouts for a plan
 */
async function countRemainingWorkouts(
  db: FirebaseFirestore.Firestore,
  uid: string,
  planId: string
): Promise<number> {
  const now = new Date();

  const workoutsSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .where("planId", "==", planId)
    .where("status", "==", "scheduled")
    .get();

  let count = 0;
  for (const doc of workoutsSnapshot.docs) {
    const workout = doc.data() as WorkoutDoc;
    if (workout.scheduledDate && workout.scheduledDate.toDate() > now) {
      count++;
    }
  }

  return count;
}

/**
 * Complete a plan early by marking it as completed and skipping remaining workouts
 */
async function completePlanEarly(
  db: FirebaseFirestore.Firestore,
  uid: string,
  planId: string
): Promise<void> {
  const now = new Date();
  const batch = db.batch();

  // Update plan status to completed
  const planRef = db.collection("users").doc(uid).collection("plans").doc(planId);
  batch.update(planRef, {status: "completed"});

  // Get all scheduled workouts for this plan
  const workoutsSnapshot = await db
    .collection("users")
    .doc(uid)
    .collection("workouts")
    .where("planId", "==", planId)
    .where("status", "==", "scheduled")
    .get();

  // Mark future scheduled workouts as skipped
  for (const doc of workoutsSnapshot.docs) {
    const workout = doc.data() as WorkoutDoc;
    if (workout.scheduledDate && workout.scheduledDate.toDate() > now) {
      batch.update(doc.ref, {status: "skipped"});
    }
  }

  await batch.commit();
}
