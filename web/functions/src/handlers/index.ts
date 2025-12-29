/**
 * Tool Handler Infrastructure
 *
 * Provides types, router, and execution logic for server-side tool handlers.
 * Handlers execute on the server instead of being passed through to iOS.
 *
 * v210: Lazy handler loading to avoid Firebase deployment timeout
 * Handlers are loaded on first use, not at module initialization
 * NOTE: No top-level imports to minimize initialization time
 */

// Import Firestore types only (no runtime import)
import type * as admin from "firebase-admin";

// ============================================================================
// Types
// ============================================================================

/**
 * Suggestion chip for quick-action buttons in the UI
 */
export interface SuggestionChip {
  label: string;
  command: string;
}

/**
 * v210: Workout card data for inline workout display
 * Sent as SSE event to trigger workout card rendering on clients
 */
export interface WorkoutCardData {
  workoutId: string;
  workoutName: string;
}

/**
 * v210: Plan card data for inline plan display
 * Sent as SSE event to trigger plan card rendering on clients
 */
export interface PlanCardData {
  planId: string;
  planName: string;
  workoutCount: number;
  durationWeeks: number;
}

/**
 * Context passed to all handlers
 */
export interface HandlerContext {
  /** Firebase user ID */
  uid: string;
  /** Firestore database instance */
  db: admin.firestore.Firestore;
}

/**
 * Result returned by handlers
 */
export interface HandlerResult {
  /** Text output for OpenAI to continue the conversation */
  output: string;
  /** Optional suggestion chips to show in UI */
  suggestionChips?: SuggestionChip[];
  /** v210: Optional workout card to display inline */
  workoutCard?: WorkoutCardData;
  /** v210: Optional plan card to display inline */
  planCard?: PlanCardData;
}

/**
 * Handler function signature
 */
export type ToolHandler = (
  args: Record<string, unknown>,
  context: HandlerContext
) => Promise<HandlerResult>;

// ============================================================================
// Handler Registry (Lazy Loading)
// ============================================================================

/**
 * List of tool names with server-side handlers.
 * Actual handler modules are loaded lazily on first use.
 */
const HANDLED_TOOLS = new Set([
  // Phase 0: Original handlers
  "show_schedule",
  "update_profile",
  "suggest_options",
  "skip_workout",
  "delete_plan",
  // Phase 1: Core CRUD handlers
  "reset_workout",
  "activate_plan",
  "abandon_plan",
  "start_workout",
  "end_workout",
  "create_workout",
  "create_plan",
  // Phase 2: Library handlers
  "add_to_library",
  "remove_from_library",
  "update_exercise_target",
  "get_substitution_options",
  "get_summary",
  "send_message",
  "reschedule_plan",
]);

/**
 * Cache for loaded handlers (lazy-loaded on first use)
 */
const handlerCache: Record<string, ToolHandler> = {};

/**
 * Load a handler module lazily
 * v210: Prevents deployment timeout by deferring module loading
 */
async function loadHandler(toolName: string): Promise<ToolHandler | null> {
  if (handlerCache[toolName]) {
    return handlerCache[toolName];
  }

  if (!HANDLED_TOOLS.has(toolName)) {
    return null;
  }

  // Map tool names to module paths
  const moduleMap: Record<string, string> = {
    "show_schedule": "./showSchedule",
    "update_profile": "./updateProfile",
    "suggest_options": "./suggestOptions",
    "skip_workout": "./skipWorkout",
    "delete_plan": "./deletePlan",
    "reset_workout": "./resetWorkout",
    "activate_plan": "./activatePlan",
    "abandon_plan": "./abandonPlan",
    "start_workout": "./startWorkout",
    "end_workout": "./endWorkout",
    "create_workout": "./createWorkout",
    "create_plan": "./createPlan",
    "add_to_library": "./addToLibrary",
    "remove_from_library": "./removeFromLibrary",
    "update_exercise_target": "./updateExerciseTarget",
    "get_substitution_options": "./getSubstitutionOptions",
    "get_summary": "./getSummary",
    "send_message": "./sendMessage",
    "reschedule_plan": "./reschedulePlan",
  };

  const modulePath = moduleMap[toolName];
  if (!modulePath) {
    return null;
  }

  try {
    // Dynamic import - deferred until first use
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const module = require(modulePath);
    const handlerName = `${toolName.replace(/_([a-z])/g, (_, c) => c.toUpperCase())}Handler`;
    const handler = module[handlerName];

    if (handler) {
      handlerCache[toolName] = handler;
      return handler;
    }
  } catch (error) {
    console.error(`Failed to load handler for ${toolName}:`, error);
  }

  return null;
}

// ============================================================================
// Execution
// ============================================================================

/**
 * Execute a tool handler if one exists.
 * v210: Uses lazy loading to avoid deployment timeout
 *
 * @param toolName - Name of the tool to execute
 * @param args - Arguments passed to the tool
 * @param context - Handler context with uid and db
 * @returns Handler result, or null if no handler exists (passthrough to iOS)
 */
export async function executeHandler(
  toolName: string,
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult | null> {
  // v210: Lazy load handler on first use
  const handler = await loadHandler(toolName);

  if (!handler) {
    // No server handler - pass through to iOS
    return null;
  }

  try {
    return await handler(args, context);
  } catch (error) {
    console.error(`Handler error for ${toolName}:`, error);
    return {
      output: `ERROR: Failed to execute ${toolName}. ${error instanceof Error ? error.message : "Unknown error"}`,
    };
  }
}

/**
 * Check if a tool has a server-side handler
 * v210: Checks Set instead of loading module
 */
export function hasHandler(toolName: string): boolean {
  return HANDLED_TOOLS.has(toolName);
}

/**
 * Get list of tools with server-side handlers
 */
export function getHandledTools(): string[] {
  return Array.from(HANDLED_TOOLS);
}
