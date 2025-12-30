/**
 * Suggest Options Handler
 *
 * Presents quick-action chips to the user at decision points.
 * This is the simplest handler - just formats and returns chip data.
 */

import {HandlerContext, HandlerResult, SuggestionChip} from "./index";

interface OptionArg {
  label: string;
  command: string;
}

/**
 * Handle suggest_options tool call
 *
 * @param args - { options: [{ label: string, command: string }] }
 * @param context - Handler context (unused for this handler)
 * @returns Formatted chips for UI display
 */
export async function suggestOptionsHandler(
  args: Record<string, unknown>,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _context: HandlerContext
): Promise<HandlerResult> {
  const options = args.options as OptionArg[] | undefined;

  if (!options || !Array.isArray(options) || options.length === 0) {
    return {
      output: "No options provided.",
    };
  }

  // Validate and map options to chips
  const chips: SuggestionChip[] = options
    .filter((opt) => opt.label && opt.command)
    .map((opt) => ({
      label: String(opt.label).substring(0, 30), // Truncate long labels
      command: String(opt.command),
    }));

  if (chips.length === 0) {
    return {
      output: "No valid options provided.",
    };
  }

  return {
    output: `Presented ${chips.length} option(s) to user.`,
    suggestionChips: chips,
  };
}
