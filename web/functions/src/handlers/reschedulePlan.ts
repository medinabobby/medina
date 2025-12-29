/**
 * Reschedule Plan Handler
 *
 * Changes the schedule of an existing plan without losing completed progress.
 * Port of iOS ReschedulePlanHandler.swift
 *
 * Parameters:
 *   planId: "current", "draft", or specific plan ID
 *   newPreferredDays: Array of day names (e.g., ["monday", "wednesday", "friday"])
 *   newDaysPerWeek: (optional) Number of workout days per week
 *   newCardioDays: (optional) Number of cardio days per week
 *
 * Firestore structure:
 *   users/{uid}/plans/{planId} → Plan
 *   users/{uid}/workouts/{workoutId} → Workout (with scheduledDate)
 */

import type {HandlerContext, HandlerResult} from "./index";

interface Plan {
  id: string;
  name: string;
  status: string;
  preferredDays?: string[];
  daysPerWeek?: number;
  startDate?: string;
  endDate?: string;
}

interface Workout {
  id: string;
  planId?: string;
  status: string;
  scheduledDate?: string;
}

const DAYS_OF_WEEK = [
  "sunday", "monday", "tuesday", "wednesday",
  "thursday", "friday", "saturday",
];

/**
 * Parse day of week string to index (0 = Sunday, 6 = Saturday)
 */
function parseDayOfWeek(dayStr: string): number {
  const normalized = dayStr.toLowerCase().trim();
  const index = DAYS_OF_WEEK.indexOf(normalized);
  return index >= 0 ? index : -1;
}

/**
 * Format day of week index to display name
 */
function formatDayName(dayIndex: number): string {
  const day = DAYS_OF_WEEK[dayIndex];
  return day.charAt(0).toUpperCase() + day.slice(1);
}

/**
 * Reschedule a training plan
 */
export async function reschedulePlanHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;

  // Parse planId
  const planIdArg = args.planId as string | undefined;
  if (!planIdArg) {
    return {
      output: "ERROR: Missing required parameter 'planId'. " +
        "Use 'current' for active plan, 'draft' for draft, or specific plan ID.",
    };
  }

  // Parse new preferred days
  const newDaysArray = args.newPreferredDays as string[] | undefined;
  if (!newDaysArray || newDaysArray.length === 0) {
    return {
      output: "ERROR: Missing required parameter 'newPreferredDays'. " +
        "Provide array like ['monday', 'wednesday', 'friday'].",
    };
  }

  const newPreferredDays = newDaysArray
    .map((d) => parseDayOfWeek(d))
    .filter((i) => i >= 0);

  if (newPreferredDays.length === 0) {
    return {
      output: "ERROR: Could not parse any valid days. " +
        "Use lowercase day names like 'monday', 'wednesday', 'friday'.",
    };
  }

  try {
    // Resolve the plan
    let plan: Plan | null = null;
    let planId: string;

    const plansRef = db.collection("users").doc(uid).collection("plans");

    if (planIdArg.toLowerCase() === "current") {
      // Find active plan
      const activeSnap = await plansRef.where("status", "==", "active").limit(1).get();
      if (activeSnap.empty) {
        return {
          output: "ERROR: No active plan found. Create a new plan with create_plan instead.",
        };
      }
      plan = activeSnap.docs[0].data() as Plan;
      planId = activeSnap.docs[0].id;
    } else if (planIdArg.toLowerCase() === "draft") {
      // Find draft plan
      const draftSnap = await plansRef.where("status", "==", "draft").limit(1).get();
      if (draftSnap.empty) {
        return {
          output: "ERROR: No draft plan found. Create a new plan with create_plan instead.",
        };
      }
      plan = draftSnap.docs[0].data() as Plan;
      planId = draftSnap.docs[0].id;
    } else {
      // Specific plan ID
      const planDoc = await plansRef.doc(planIdArg).get();
      if (!planDoc.exists) {
        return {
          output: `ERROR: Plan not found with ID '${planIdArg}'.`,
        };
      }
      plan = planDoc.data() as Plan;
      planId = planIdArg;
    }

    if (!plan) {
      return {
        output: "ERROR: Could not resolve plan.",
      };
    }

    // Parse optional parameters
    const newDaysPerWeek = (args.newDaysPerWeek as number) || newPreferredDays.length;

    // Update plan with new schedule
    const sortedDays = newPreferredDays.sort((a, b) => a - b);
    const preferredDayNames = sortedDays.map((i) => DAYS_OF_WEEK[i]);

    await plansRef.doc(planId).update({
      preferredDays: preferredDayNames,
      daysPerWeek: newDaysPerWeek,
      lastModified: new Date(),
    });

    // Get workouts for this plan that need rescheduling
    const workoutsSnap = await db
      .collection("users")
      .doc(uid)
      .collection("workouts")
      .where("planId", "==", planId)
      .get();

    const workouts = workoutsSnap.docs.map((doc) => {
      const data = doc.data() as Workout;
      return {...data, id: doc.id};
    });

    // Count completed vs pending
    const completedWorkouts = workouts.filter((w) => w.status === "completed").length;

    // Reschedule pending workouts to new days
    // This is a simplified implementation - full version would recalculate dates
    const batch = db.batch();
    let rescheduledCount = 0;

    workouts.forEach((workout, index) => {
      if (workout.status !== "completed") {
        // Calculate new scheduled date based on preferred days
        // For now, just mark as needing reschedule
        const workoutRef = db
          .collection("users")
          .doc(uid)
          .collection("workouts")
          .doc(workout.id);

        batch.update(workoutRef, {
          needsReschedule: true,
          preferredDays: preferredDayNames,
        });
        rescheduledCount++;
      }
    });

    await batch.commit();

    // Format response
    const dayDisplay = sortedDays.map((i) => formatDayName(i)).join(", ");

    let output = `SUCCESS: Plan rescheduled.\n\n`;
    output += `PLAN: ${plan.name}\n`;
    output += `NEW_SCHEDULE: ${dayDisplay}\n`;
    output += `WORKOUTS_UPDATED: ${rescheduledCount}`;

    if (completedWorkouts > 0) {
      output += `\nCOMPLETED_PRESERVED: ${completedWorkouts}`;
    }

    return {
      output,
      suggestionChips: [
        {label: "Show schedule", command: "show my schedule"},
        {label: "Today's workout", command: "what's my workout today"},
      ],
      planCard: {
        planId,
        planName: plan.name,
        workoutCount: workouts.length,
        durationWeeks: 4, // Default, could be calculated from dates
      },
    };
  } catch (error) {
    console.error("[reschedulePlan] Error:", error);
    return {
      output: `ERROR: Failed to reschedule plan. ${
        error instanceof Error ? error.message : "Unknown error"
      }`,
    };
  }
}
