/**
 * Show Schedule Handler
 *
 * Queries and displays a user's workout schedule for a given time period.
 * Read-only handler - no data modifications.
 */

import {HandlerContext, HandlerResult} from "./index";

/**
 * Get the start and end of the current ISO week (Monday-Sunday)
 */
function getWeekRange(): { start: Date; end: Date } {
  const now = new Date();
  const dayOfWeek = now.getDay();
  // Adjust for Monday start (getDay returns 0 for Sunday)
  const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;

  const start = new Date(now);
  start.setDate(now.getDate() - daysToMonday);
  start.setHours(0, 0, 0, 0);

  const end = new Date(start);
  end.setDate(start.getDate() + 6);
  end.setHours(23, 59, 59, 999);

  return {start, end};
}

/**
 * Get the start and end of the current calendar month
 */
function getMonthRange(): { start: Date; end: Date } {
  const now = new Date();

  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  start.setHours(0, 0, 0, 0);

  const end = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  end.setHours(23, 59, 59, 999);

  return {start, end};
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
 * Format workout status for display
 */
function formatStatus(status: string): string {
  switch (status) {
  case "completed":
    return "completed";
  case "skipped":
    return "skipped";
  case "inProgress":
    return "in progress";
  default:
    return "scheduled";
  }
}

interface WorkoutDoc {
  name?: string;
  scheduledDate?: string;
  status?: string;
}

/**
 * Handle show_schedule tool call
 *
 * @param args - { period: "week" | "month" }
 * @param context - Handler context with uid and db
 * @returns Formatted workout schedule
 */
export async function showScheduleHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const period = (args.period as string) || "week";
  const {uid, db} = context;

  // Calculate date range
  const range = period === "month" ? getMonthRange() : getWeekRange();
  const startISO = range.start.toISOString();
  const endISO = range.end.toISOString();

  // Query workouts in date range
  const workoutsRef = db.collection(`users/${uid}/workouts`);
  const snapshot = await workoutsRef
    .where("scheduledDate", ">=", startISO)
    .where("scheduledDate", "<=", endISO)
    .orderBy("scheduledDate", "asc")
    .get();

  if (snapshot.empty) {
    const periodLabel = period === "month" ? "this month" : "this week";
    return {
      output: `No workouts scheduled ${periodLabel}. Would you like to create one?`,
      suggestionChips: [
        {label: "Create workout", command: "Create a workout for today"},
        {label: "Create plan", command: "Create a training plan"},
      ],
    };
  }

  // Format workout list
  const workoutLines: string[] = [];
  snapshot.docs.forEach((doc) => {
    const data = doc.data() as WorkoutDoc;
    const name = data.name || "Workout";
    const date = data.scheduledDate ? new Date(data.scheduledDate) : new Date();
    const status = formatStatus(data.status || "scheduled");

    workoutLines.push(`${formatDate(date)}: ${name} (${status})`);
  });

  const periodLabel = period === "month" ? "this month" : "this week";
  const output = `Found ${workoutLines.length} workout(s) ${periodLabel}:

${workoutLines.join("\n")}

Generate a conversational summary of this schedule. Be concise and highlight any completed or upcoming workouts.`;

  return {
    output,
  };
}
