/**
 * Shared Formatters for AI Prompts
 *
 * v236: Extracted from systemPrompt.ts, userContext.ts, trainerContext.ts
 * to eliminate ~200 tokens of duplicate code.
 */

/**
 * Capitalize first letter of a string
 */
export function capitalize(str: string): string {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

/**
 * Format fitness goal for display
 */
export function formatGoal(goal: string): string {
  const goalMap: Record<string, string> = {
    strength: 'Build Strength',
    muscleGain: 'Build Muscle',
    fatLoss: 'Lose Fat',
    endurance: 'Improve Endurance',
    generalFitness: 'General Fitness',
    athleticPerformance: 'Athletic Performance',
  };
  return goalMap[goal] || goal;
}

/**
 * Format date for prompt display
 */
export function formatPromptDate(date: Date): string {
  return date.toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });
}
