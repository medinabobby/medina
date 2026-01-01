/**
 * AI Model Evaluation Test Suite
 *
 * v247: Test cases for comparing AI models on fitness coaching tasks.
 *
 * Categories:
 * - tool_calling: Verify correct tool invocations
 * - fitness_accuracy: Verify fitness knowledge
 * - tone: Verify coaching style and off-topic handling
 * - speed: Verify response time for simple queries
 *
 * Intent Classification (v247):
 * - Explicit commands → immediate tool execution
 * - Preference statements → confirmation first (expectedTool: null)
 * - Multi-param requests → clarifying questions (expectedTool: null)
 * - Data provision → immediate tool execution
 * - Destructive actions → confirmation first (expectedTool: null)
 */

export interface TestCase {
  id: string;
  category: 'tool_calling' | 'fitness_accuracy' | 'tone' | 'speed';
  prompt: string;
  expectedTool?: string | null;  // Which tool should be called (null = no tool)
  expectedTopics?: string[];     // Keywords that should appear in response
  maxResponseTime?: number;      // ms - for speed tests
  description?: string;          // Human-readable description
}

export const TEST_CASES: TestCase[] = [
  // =========================================================================
  // TOOL CALLING TESTS (10)
  // Verify AI correctly invokes the right tools
  // =========================================================================
  {
    id: 'TC01',
    category: 'tool_calling',
    prompt: 'Create a 45-minute push workout for tomorrow',
    expectedTool: 'create_workout',
    description: 'Should call create_workout with duration and splitDay',
  },
  {
    id: 'TC02',
    category: 'tool_calling',
    prompt: 'Show my schedule for this week',
    expectedTool: 'show_schedule',
    description: 'Should call show_schedule with week period',
  },
  {
    id: 'TC03',
    category: 'tool_calling',
    prompt: 'My bench press 1RM is 225 lbs',
    expectedTool: 'update_exercise_target',
    description: 'Should call update_exercise_target, NOT update_profile',
  },
  {
    id: 'TC04',
    category: 'tool_calling',
    prompt: "Skip today's workout",
    expectedTool: 'skip_workout',
    description: 'Should call skip_workout for the current day',
  },
  {
    id: 'TC05',
    category: 'tool_calling',
    prompt: 'Create a 12-week strength program',
    expectedTool: null,
    description: 'Multi-param request - AI should ask clarifying questions (goal, days/week) before creating plan',
  },
  {
    id: 'TC06',
    category: 'tool_calling',
    prompt: 'Add bench press to my library',
    expectedTool: 'add_to_library',
    description: 'Should call add_to_library with exercise ID',
  },
  {
    id: 'TC07',
    category: 'tool_calling',
    prompt: "I'm 30 years old and weigh 180 lbs",
    expectedTool: null,
    description: 'Should NOT auto-update - user stating info is not requesting update. AI should confirm first.',
  },
  {
    id: 'TC08',
    category: 'tool_calling',
    prompt: 'Swap the barbell row for something else',
    expectedTool: 'get_substitution_options',
    description: 'Should call get_substitution_options for alternatives',
  },
  {
    id: 'TC09',
    category: 'tool_calling',
    prompt: "What's the difference between strength and hypertrophy training?",
    expectedTool: null,
    description: 'Should NOT call any tool - just answer the question',
  },
  {
    id: 'TC10',
    category: 'tool_calling',
    prompt: 'I want to train 4 days per week',
    expectedTool: null,
    description: 'Preference statement - AI should ask confirmation before updating profile ("Want me to save this?")',
  },

  // =========================================================================
  // FITNESS ACCURACY TESTS (10)
  // Verify AI has correct fitness knowledge - NO TOOLS expected
  // =========================================================================
  {
    id: 'FA01',
    category: 'fitness_accuracy',
    prompt: 'What muscles does the Romanian deadlift target?',
    expectedTool: null,  // Knowledge question, no tool
    expectedTopics: ['hamstrings', 'glutes', 'lower back', 'posterior'],
    description: 'Should mention key posterior chain muscles',
  },
  {
    id: 'FA02',
    category: 'fitness_accuracy',
    prompt: 'How should I breathe during a bench press?',
    expectedTool: null,
    expectedTopics: ['inhale', 'exhale', 'brace', 'lower', 'press'],
    description: 'Should explain breathing pattern for bench press',
  },
  {
    id: 'FA03',
    category: 'fitness_accuracy',
    prompt: 'What rep range builds the most muscle?',
    expectedTool: null,
    expectedTopics: ['8', '12', 'hypertrophy', 'volume'],
    description: 'Should mention 8-12 rep range for hypertrophy',
  },
  {
    id: 'FA04',
    category: 'fitness_accuracy',
    prompt: 'How long should I rest between heavy compound sets?',
    expectedTool: null,
    expectedTopics: ['2', '3', '5', 'minute', 'recovery', 'strength'],
    description: 'Should recommend 2-5 minutes for heavy compounds',
  },
  {
    id: 'FA05',
    category: 'fitness_accuracy',
    prompt: 'Should I lift through lower back pain?',
    expectedTool: null,
    expectedTopics: ['stop', 'doctor', 'pain', 'injury', 'rest'],
    description: 'Should advise stopping and seeing a doctor',
  },
  {
    id: 'FA06',
    category: 'fitness_accuracy',
    prompt: "What's progressive overload?",
    expectedTool: null,
    expectedTopics: ['increase', 'weight', 'reps', 'volume', 'progress'],
    description: 'Should explain progressive overload principle',
  },
  {
    id: 'FA07',
    category: 'fitness_accuracy',
    prompt: 'Push pull legs vs upper lower split - which is better?',
    expectedTool: null,
    expectedTopics: ['frequency', 'recovery', 'depends', 'goals', 'schedule'],
    description: 'Should explain both have trade-offs, depends on goals',
  },
  {
    id: 'FA08',
    category: 'fitness_accuracy',
    prompt: 'How much protein do I need per day?',
    expectedTool: null,
    expectedTopics: ['0.7', '0.8', '1', 'gram', 'pound', 'bodyweight', 'protein'],
    description: 'Should mention 0.7-1g per pound of bodyweight',
  },
  {
    id: 'FA09',
    category: 'fitness_accuracy',
    prompt: 'Is it bad to train the same muscle two days in a row?',
    expectedTool: null,
    expectedTopics: ['recovery', '48', 'hours', 'rest', 'repair'],
    description: 'Should explain muscles need 48-72 hours to recover',
  },
  {
    id: 'FA10',
    category: 'fitness_accuracy',
    prompt: 'Can I build muscle in a calorie deficit?',
    expectedTool: null,
    expectedTopics: ['beginner', 'recomp', 'harder', 'protein', 'deficit'],
    description: 'Should explain it is possible but harder, easier for beginners',
  },

  // =========================================================================
  // TONE/STYLE TESTS (5)
  // Verify coaching style and off-topic handling - NO TOOLS expected
  // =========================================================================
  {
    id: 'TN01',
    category: 'tone',
    prompt: "I'm struggling to stay motivated",
    expectedTool: null,  // Motivational response, no tool
    expectedTopics: ['normal', 'goals', 'small', 'habit', 'consistency'],
    description: 'Should be encouraging and offer practical advice',
  },
  {
    id: 'TN02',
    category: 'tone',
    prompt: 'I missed 3 workouts this week',
    expectedTool: null,
    expectedTopics: ['okay', 'back', 'track', 'happens', 'start'],
    description: 'Should be supportive, not judgmental',
  },
  {
    id: 'TN03',
    category: 'tone',
    prompt: 'What stocks should I buy?',
    expectedTool: null,  // Should politely decline
    expectedTopics: ['fitness', 'coach', 'expertise', 'workout', 'help'],
    description: 'Should politely decline and redirect to fitness',
  },
  {
    id: 'TN04',
    category: 'tone',
    prompt: 'Explain deload weeks',
    expectedTool: null,
    expectedTopics: ['recovery', 'reduce', 'intensity', 'fatigue', 'week'],
    description: 'Should explain deload concept clearly',
  },
  {
    id: 'TN05',
    category: 'tone',
    prompt: 'I want to gain 50 lbs of muscle in 3 months',
    expectedTool: null,  // Should correct expectations, not create a plan
    expectedTopics: ['unrealistic', 'natural', 'rate', 'month', 'realistic'],
    description: 'Should gently correct unrealistic expectations',
  },

  // =========================================================================
  // SPEED TESTS (5)
  // Verify response time for simple queries
  // =========================================================================
  {
    id: 'SP01',
    category: 'speed',
    prompt: 'Hi',
    expectedTool: null,  // Should NOT call any tool
    maxResponseTime: 2000,
    description: 'Simple greeting should be fast',
  },
  {
    id: 'SP02',
    category: 'speed',
    prompt: 'Show my schedule',
    expectedTool: 'show_schedule',
    maxResponseTime: 3000,
    description: 'Schedule query with tool call',
  },
  {
    id: 'SP03',
    category: 'speed',
    prompt: 'What day is leg day?',
    expectedTool: null,  // General question, no tool needed
    maxResponseTime: 2500,
    description: 'Simple question about schedule',
  },
  {
    id: 'SP04',
    category: 'speed',
    prompt: 'Create a quick 30 min workout',
    expectedTool: 'create_workout',
    maxResponseTime: 5000,
    description: 'Workout creation with tool call',
  },
  {
    id: 'SP05',
    category: 'speed',
    prompt: 'Thanks!',
    expectedTool: null,  // Should NOT call any tool
    maxResponseTime: 2000,
    description: 'Simple acknowledgment should be fast',
  },

  // =========================================================================
  // EXPLICIT COMMAND TESTS (v247)
  // Verify explicit commands trigger immediate tool execution
  // =========================================================================
  {
    id: 'TC11',
    category: 'tool_calling',
    prompt: 'Update my profile to train 4 days per week',
    expectedTool: 'update_profile',
    description: 'Explicit command - should update immediately (compare to TC10 preference statement)',
  },
  {
    id: 'TC12',
    category: 'tool_calling',
    prompt: 'Save my schedule preference as Monday, Wednesday, Friday',
    expectedTool: 'update_profile',
    description: 'Explicit save command - should update profile immediately',
  },

  // =========================================================================
  // PLAN MANAGEMENT TESTS (v247)
  // Verify destructive/commitment actions require confirmation
  // =========================================================================
  {
    id: 'PL01',
    category: 'tool_calling',
    prompt: 'Delete my current plan',
    expectedTool: null,
    description: 'Destructive action - AI should ask confirmation before deleting',
  },
  {
    id: 'PL02',
    category: 'tool_calling',
    prompt: 'Activate the strength plan',
    expectedTool: null,
    description: 'Multi-week commitment - AI should confirm before activating',
  },

  // =========================================================================
  // SYNONYM TESTS (v247)
  // Verify user terms are silently mapped to Medina concepts
  // =========================================================================
  {
    id: 'SY01',
    category: 'tool_calling',
    prompt: 'Create a 12-week program for muscle gain',
    expectedTool: null,
    description: 'Synonym "program" → plan; multi-param request should ask questions first',
  },
  {
    id: 'SY02',
    category: 'tool_calling',
    prompt: 'Show my routine for this week',
    expectedTool: 'show_schedule',
    description: 'Synonym "routine" → schedule; should show schedule immediately',
  },

  // =========================================================================
  // EDGE CASE TESTS (v247)
  // Verify handling of ambiguous or extreme requests
  // =========================================================================
  {
    id: 'ED01',
    category: 'tool_calling',
    prompt: 'Update my profile',
    expectedTool: null,
    description: 'Incomplete command - AI should ask what to update',
  },
  {
    id: 'ED02',
    category: 'tool_calling',
    prompt: 'Create a workout',
    expectedTool: 'create_workout',
    description: 'Minimal command - should create workout using profile defaults',
  },
  {
    id: 'ED03',
    category: 'tool_calling',
    prompt: 'I want to go from 2 to 7 days per week',
    expectedTool: null,
    description: 'Major change - AI should advise about overtraining risks before updating',
  },
  {
    id: 'ED04',
    category: 'tool_calling',
    prompt: 'Remove bench press from my library',
    expectedTool: 'remove_from_library',
    description: 'Explicit removal command - reversible, should execute immediately',
  },
];

// Pricing per 1M tokens (as of Dec 2024)
export const TOKEN_PRICING = {
  'gpt-4o-mini': { input: 0.15, output: 0.60 },
  'gpt-4o': { input: 2.50, output: 10.00 },
  'claude-3.5-sonnet': { input: 3.00, output: 15.00 },
  'claude-3.5-haiku': { input: 0.80, output: 4.00 },
  'grok-2': { input: 2.00, output: 10.00 },
};

/**
 * Calculate cost for a request
 */
export function calculateCost(
  model: keyof typeof TOKEN_PRICING,
  inputTokens: number,
  outputTokens: number
): number {
  const pricing = TOKEN_PRICING[model];
  if (!pricing) return 0;

  const inputCost = (inputTokens / 1_000_000) * pricing.input;
  const outputCost = (outputTokens / 1_000_000) * pricing.output;

  return inputCost + outputCost;
}

/**
 * Get test cases by category
 */
export function getTestsByCategory(category: TestCase['category']): TestCase[] {
  return TEST_CASES.filter(t => t.category === category);
}

/**
 * Summary of test suite
 */
export function getTestSuiteSummary(): {
  total: number;
  byCategory: Record<string, number>;
} {
  const byCategory: Record<string, number> = {};

  for (const test of TEST_CASES) {
    byCategory[test.category] = (byCategory[test.category] || 0) + 1;
  }

  return {
    total: TEST_CASES.length,
    byCategory,
  };
}
