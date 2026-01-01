/**
 * Show Schedule Handler
 * v248: Smart responses based on query type
 *
 * Query types:
 * - 'full': Complete schedule with calendar card
 * - 'next_workout': Just the next upcoming workout
 * - 'specific_day': Find a specific split day (e.g., "when is leg day?")
 */

import {HandlerContext, HandlerResult} from "./index";

// ============================================================================
// Types
// ============================================================================

interface WorkoutDoc {
  id?: string;
  name?: string;
  scheduledDate?: string;
  status?: string;
  splitDay?: string;
}

interface ScheduleWorkout {
  id: string;
  name: string;
  date: string;
  dayOfWeek: string;
  status: 'scheduled' | 'completed' | 'skipped' | 'inProgress';
  splitDay: string;
}

interface ScheduleCard {
  weekStart: string;
  weekEnd: string;
  workouts: ScheduleWorkout[];
}

type QueryType = 'full' | 'next_workout' | 'specific_day';

// ============================================================================
// Date Utilities
// ============================================================================

/**
 * Get the start of today (midnight local time)
 */
function getStartOfToday(): Date {
  const now = new Date();
  now.setHours(0, 0, 0, 0);
  return now;
}

/**
 * Get the end of the current ISO week (Sunday 23:59:59)
 */
function getEndOfWeek(): Date {
  const now = new Date();
  const dayOfWeek = now.getDay();
  const daysToSunday = dayOfWeek === 0 ? 0 : 7 - dayOfWeek;

  const end = new Date(now);
  end.setDate(now.getDate() + daysToSunday);
  end.setHours(23, 59, 59, 999);

  return end;
}

/**
 * Get the start of current week (Monday)
 */
function getStartOfWeek(): Date {
  const now = new Date();
  const dayOfWeek = now.getDay();
  const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;

  const start = new Date(now);
  start.setDate(now.getDate() - daysToMonday);
  start.setHours(0, 0, 0, 0);

  return start;
}

/**
 * Get the end of the current month
 */
function getEndOfMonth(): Date {
  const now = new Date();
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  end.setHours(23, 59, 59, 999);
  return end;
}

/**
 * Format date as "Dec 15"
 */
function formatDateShort(date: Date): string {
  return date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

/**
 * Get day of week name
 */
function getDayOfWeek(date: Date): string {
  return date.toLocaleDateString("en-US", {weekday: "long"});
}

/**
 * Format date as ISO string (YYYY-MM-DD)
 */
function toISODateString(date: Date): string {
  return date.toISOString().split("T")[0];
}

// ============================================================================
// Query Handlers
// ============================================================================

/**
 * Handle "when is leg day?" type queries
 */
function handleSpecificDayQuery(
  workouts: ScheduleWorkout[],
  dayQuery: string
): HandlerResult {
  const query = dayQuery.toLowerCase().trim();

  // Try to match split day first (legs, push, pull, upper, lower, etc.)
  const splitMatches = workouts.filter((w) => {
    const split = (w.splitDay || "").toLowerCase();
    const name = (w.name || "").toLowerCase();
    return split.includes(query) || name.includes(query);
  });

  if (splitMatches.length > 0) {
    const match = splitMatches[0];
    const dayName = match.dayOfWeek;

    return {
      output: `Your ${query} day is ${dayName} (${formatDateShort(new Date(match.date))}).`,
      suggestionChips: [
        {label: "Show full schedule", command: "Show my schedule"},
        {label: "Start workout", command: `Start my ${query} workout`},
      ],
    };
  }

  // Try to match day of week (Monday, Tuesday, etc.)
  const dayOfWeekMatches = workouts.filter((w) => {
    return w.dayOfWeek.toLowerCase().includes(query);
  });

  if (dayOfWeekMatches.length > 0) {
    const match = dayOfWeekMatches[0];
    return {
      output: `On ${match.dayOfWeek} you have: ${match.name}`,
      suggestionChips: [
        {label: "Show full schedule", command: "Show my schedule"},
      ],
    };
  }

  // No match found
  return {
    output: `No ${query} day found in your schedule this week. Would you like to create one?`,
    suggestionChips: [
      {label: "Create workout", command: `Create a ${query} workout`},
      {label: "Show schedule", command: "Show my schedule"},
    ],
  };
}

/**
 * Handle "what's my next workout?" queries
 */
function handleNextWorkoutQuery(workouts: ScheduleWorkout[]): HandlerResult {
  // Filter to scheduled workouts only (not completed/skipped)
  const upcoming = workouts.filter((w) => w.status === "scheduled");

  if (upcoming.length === 0) {
    return {
      output: "No upcoming workouts scheduled. Would you like to create one?",
      suggestionChips: [
        {label: "Create workout", command: "Create a workout for today"},
        {label: "Create plan", command: "Create a training plan"},
      ],
    };
  }

  const next = upcoming[0];
  const isToday = toISODateString(new Date()) === next.date;
  const dayContext = isToday ? "today" : `on ${next.dayOfWeek}`;

  return {
    output: `Your next workout is ${next.name} ${dayContext} (${formatDateShort(new Date(next.date))}).`,
    suggestionChips: [
      {label: "Start workout", command: "Start my workout"},
      {label: "Show schedule", command: "Show my schedule"},
    ],
  };
}

/**
 * Handle full schedule query with calendar card
 */
function handleFullScheduleQuery(
  workouts: ScheduleWorkout[],
  weekStart: Date,
  weekEnd: Date
): HandlerResult {
  if (workouts.length === 0) {
    return {
      output: "No workouts scheduled this week. Would you like to create one?",
      suggestionChips: [
        {label: "Create workout", command: "Create a workout for today"},
        {label: "Create plan", command: "Create a training plan"},
      ],
    };
  }

  // Build schedule card data
  const scheduleCard: ScheduleCard = {
    weekStart: toISODateString(weekStart),
    weekEnd: toISODateString(weekEnd),
    workouts: workouts,
  };

  // Build text summary
  const upcomingCount = workouts.filter((w) => w.status === "scheduled").length;
  const completedCount = workouts.filter((w) => w.status === "completed").length;

  const lines: string[] = [];

  // Group by date
  const byDate = new Map<string, ScheduleWorkout[]>();
  for (const w of workouts) {
    const existing = byDate.get(w.date) || [];
    existing.push(w);
    byDate.set(w.date, existing);
  }

  for (const [date, dayWorkouts] of byDate) {
    const dateObj = new Date(date);
    const dayName = getDayOfWeek(dateObj);
    const dateStr = formatDateShort(dateObj);

    for (const w of dayWorkouts) {
      const statusIcon = w.status === "completed" ? "✓" :
        w.status === "skipped" ? "✗" :
          w.status === "inProgress" ? "▶" : "○";
      lines.push(`${statusIcon} ${dayName} (${dateStr}): ${w.name}`);
    }
  }

  let summary = `This week: ${upcomingCount} upcoming`;
  if (completedCount > 0) {
    summary += `, ${completedCount} completed`;
  }

  const output = `${summary}\n\n${lines.join("\n")}`;

  return {
    output,
    scheduleCard,
    suggestionChips: [
      {label: "Start workout", command: "Start my workout"},
      {label: "Create workout", command: "Create a workout"},
    ],
  };
}

// ============================================================================
// Main Handler
// ============================================================================

/**
 * Handle show_schedule tool call
 *
 * @param args - { period?, query_type?, day_query? }
 * @param context - Handler context with uid and db
 * @returns Formatted schedule response with optional card data
 */
export async function showScheduleHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const period = (args.period as string) || "week";
  const queryType = (args.query_type as QueryType) || "full";
  const dayQuery = args.day_query as string | undefined;
  const {uid, db} = context;

  // Calculate date range (today forward)
  const startDate = getStartOfToday();
  const endDate = period === "month" ? getEndOfMonth() : getEndOfWeek();
  const weekStart = getStartOfWeek();

  // Query workouts from today forward
  const workoutsRef = db.collection(`users/${uid}/workouts`);
  const snapshot = await workoutsRef
    .where("scheduledDate", ">=", startDate.toISOString())
    .where("scheduledDate", "<=", endDate.toISOString())
    .orderBy("scheduledDate", "asc")
    .get();

  // Transform to ScheduleWorkout format
  const workouts: ScheduleWorkout[] = snapshot.docs.map((doc) => {
    const data = doc.data() as WorkoutDoc;
    const date = data.scheduledDate ? new Date(data.scheduledDate) : new Date();

    return {
      id: doc.id,
      name: data.name || "Workout",
      date: toISODateString(date),
      dayOfWeek: getDayOfWeek(date),
      status: (data.status as ScheduleWorkout["status"]) || "scheduled",
      splitDay: data.splitDay || "",
    };
  });

  // Route to appropriate handler based on query type
  switch (queryType) {
  case "specific_day":
    if (!dayQuery) {
      return {
        output: "What day are you looking for? (e.g., 'legs', 'push', 'Monday')",
      };
    }
    return handleSpecificDayQuery(workouts, dayQuery);

  case "next_workout":
    return handleNextWorkoutQuery(workouts);

  case "full":
  default:
    return handleFullScheduleQuery(workouts, weekStart, endDate);
  }
}
