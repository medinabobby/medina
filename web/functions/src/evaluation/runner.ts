/**
 * AI Model Evaluation Runner
 *
 * v266: Temperature=0 for reproducible eval, multi-turn credit, output quality scoring
 * v259b: Fixed vision tests - now calls chat after vision (like production web flow)
 * v259: Multi-dimensional scoring for vision (extraction + intent + action)
 * v253: Multimodal support (vision + URL import tests)
 * v252: Multi-turn testing + intent detection scoring
 * v251: Added latency category metrics (basic vs tool_call vs vision)
 * v246: Proper SSE parsing + LLM-as-judge evaluation.
 *
 * Key improvements:
 * - Parse SSE events to detect actual function_call, not text patterns
 * - Use GPT-4 as evaluator to score responses with explanations
 * - Track accuracy, tone, completeness, and safety
 * - v253: Vision API integration for image-based tests
 * - v253: URL import tests for article/link extraction
 * - v259b: Vision tests now replicate production flow (vision → chat → tool_executed)
 *
 * Usage:
 *   npx ts-node src/evaluation/runner.ts --model gpt-4o-mini
 *   npx ts-node src/evaluation/runner.ts --model gpt-4o
 */

import OpenAI from 'openai';
import * as fs from 'fs';
import * as path from 'path';
import { TEST_CASES, TestCase, calculateCost, TOKEN_PRICING, assignTier } from './testSuite';

// v253: Fixtures directory for test images
const FIXTURES_DIR = path.join(__dirname, 'fixtures');

// ============================================================================
// Types
// ============================================================================

/**
 * LLM evaluation scores from GPT-4 judge
 */
export interface LLMEvaluation {
  toolScore: number;          // 1-5: Did it call the right tool?
  toolFeedback: string;
  accuracyScore: number;      // 1-5: Is fitness info correct?
  accuracyFeedback: string;
  toneScore: number;          // 1-5: Friendly, encouraging?
  toneFeedback: string;
  completenessScore: number;  // 1-5: Fully answered?
  completenessFeedback: string;
  safetyScore: number;        // 1-5: Any dangerous advice?
  safetyFeedback: string;
  overallScore: number;       // 1-5: Overall satisfaction
  summary: string;            // Brief overall assessment
}

/**
 * Parsed SSE stream data
 */
export interface ParsedSSE {
  toolCalled: string | null;
  toolArgs?: Record<string, unknown>;  // v260: Capture tool arguments for protocol/exercise accuracy
  responseText: string;
  inputTokens: number;
  outputTokens: number;
}

export interface EvalResult {
  testId: string;
  category: string;
  latencyCategory: 'basic' | 'tool_call' | 'vision';  // v251
  prompt: string;
  model: string;

  // Timing
  timeToFirstToken: number | null;  // ms
  totalResponseTime: number;        // ms

  // Tokens & Cost
  inputTokens: number;
  outputTokens: number;
  estimatedCost: number;

  // Quality - Basic
  toolCalled: string | null;
  toolCalledCorrectly: boolean;
  topicsCovered: string[];
  topicScore: number;               // 0-1
  speedPassed: boolean | null;      // for speed tests

  // v252: Intent detection + multi-turn
  intentScore: 0 | 1;               // Did AI correctly read intent clarity?
  askedForConfirmation: boolean;    // Did AI ask before acting?
  turnCount: number;                // 1 = single turn, 2+ = multi-turn
  finalToolCalled: string | null;   // Tool called after multi-turn (if any)
  toolAccuracy: 'pass' | 'fail';    // Did right tool eventually execute?

  // v253: Multimodal test results
  testType: 'text' | 'vision' | 'url_import';
  extractedContent?: string[];      // Exercises/content extracted from vision/URL
  extractionScore?: number;         // 0-1 based on expectedExtractions match
  visionConfidence?: number;        // 0-1 confidence from vision API
  imageFixtureUsed?: string;        // Which fixture image was used
  importUrlUsed?: string;           // Which URL was imported

  // v260: Protocol and exercise accuracy
  protocolPassed?: string | null;   // Protocol ID that was passed to tool
  protocolCorrect?: boolean;        // Did protocolId match expectedProtocol?
  exercisesPassed?: string[];       // Exercise IDs that were passed to tool
  exercisesCorrect?: boolean;       // Did exerciseIds match expectedExerciseIds?

  // v264: Edge case flag for human review
  edgeCase?: boolean;               // Flag tests needing human attention in reports

  // v265: Test tier classification
  tier: 1 | 2 | 3;                  // 1=Core, 2=Interpretation, 3=Ambiguous

  // v266: Output Quality - Validates tool OUTPUT not just tool call
  outputQuality?: OutputQualityScore | null;
  constraintAccuracy?: number;      // 0-1, shorthand for outputQuality.accuracy

  // Quality - LLM Evaluation
  llmEvaluation?: LLMEvaluation;

  // Raw
  response: string;
  responseText: string;             // Extracted text (no SSE wrapper)
  error?: string;
}

// v251: Latency metrics for a category
export interface LatencyCategoryMetrics {
  count: number;
  avgResponseTime: number;
  minResponseTime: number;
  maxResponseTime: number;
  p95ResponseTime: number;
  outlierCount: number;       // Tests exceeding threshold
  outlierThreshold: number;   // ms
}

export interface EvalSummary {
  model: string;
  timestamp: string;
  totalTests: number;

  // Aggregate scores - Basic (legacy, kept for compatibility)
  toolCallingAccuracy: number;      // 0-1
  fitnessAccuracyScore: number;     // 0-1
  toneScore: number;                // 0-1
  speedPassRate: number;            // 0-1

  // v252: Multi-dimensional scoring
  toolAccuracyRate: number;         // 0-1: % where right tool eventually called
  intentDetectionRate: number;      // 0-1: % where AI correctly read intent clarity
  confirmationAppropriateRate: number;  // 0-1: % with correct confirmation behavior
  combinedScore: number;            // (toolAccuracyRate + intentDetectionRate) / 2

  // v260: Protocol and exercise accuracy
  protocolAccuracyRate: number;     // 0-1: % where expected protocol was passed
  exerciseAccuracyRate: number;     // 0-1: % where expected exercises were passed

  // v265: Tier-based metrics (separated reporting)
  tierMetrics: {
    tier1: { total: number; passed: number; rate: number };  // Core tests
    tier2: { total: number; passed: number; rate: number };  // Interpretation tests
    tier3: { total: number; passed: number; rate: number };  // Ambiguous tests
  };

  // Aggregate scores - LLM Evaluation (1-5 scale)
  llmToolScore: number;
  llmAccuracyScore: number;
  llmToneScore: number;
  llmCompletenessScore: number;
  llmSafetyScore: number;
  llmOverallScore: number;

  // Timing
  avgTimeToFirstToken: number;      // ms
  avgTotalResponseTime: number;     // ms

  // v251: Latency by category (for focused optimization)
  latencyByCategory: {
    basic: LatencyCategoryMetrics;
    tool_call: LatencyCategoryMetrics;
    vision: LatencyCategoryMetrics;
  };

  // Cost
  totalInputTokens: number;
  totalOutputTokens: number;
  totalCost: number;
  avgCostPerRequest: number;

  // Results
  results: EvalResult[];
}

// ============================================================================
// Evaluation Logic
// ============================================================================

// v251: Outlier thresholds by latency category (ms)
const OUTLIER_THRESHOLDS = {
  basic: 3000,      // >3s is slow for basic queries
  tool_call: 10000, // >10s is slow for tool calls
  vision: 20000,    // >20s is slow for vision
};

// v252: Confirmation detection patterns
const CONFIRMATION_PATTERNS = [
  /are you sure/i,
  /do you want me to/i,
  /would you like me to/i,
  /should i (go ahead|proceed|update|create|delete|save)/i,
  /shall i/i,
  /want me to (save|update|create|delete|confirm)/i,
  /i can (update|save|create|delete).+would you like/i,
  /before i (proceed|update|create|delete)/i,
  /just to confirm/i,
  /can i confirm/i,
  /let me confirm/i,
];

/**
 * v252: Detect if AI response is asking for confirmation
 */
export function detectsConfirmationQuestion(responseText: string): boolean {
  if (!responseText) return false;

  const text = responseText.toLowerCase();

  // Check for confirmation patterns
  for (const pattern of CONFIRMATION_PATTERNS) {
    if (pattern.test(text)) {
      return true;
    }
  }

  // Additional heuristic: question mark + action verbs
  if (text.includes('?') &&
      (text.includes('update') || text.includes('save') ||
       text.includes('create') || text.includes('delete') ||
       text.includes('proceed') || text.includes('confirm'))) {
    return true;
  }

  return false;
}

/**
 * v252: Grade intent score based on test expectations and AI behavior
 *
 * Intent Score Logic:
 * - HIGH: "Update my profile to 4 days" → should execute immediately
 *   - If AI asks: loses intent point (0)
 *   - If AI executes: gains intent point (1)
 * - MEDIUM: "My bench 1RM is 225" → ask or execute both OK
 *   - Always returns 1 (either behavior is acceptable)
 * - LOW: "I want to train 4 days" → should ask first
 *   - If AI asks: gains intent point (1)
 *   - If AI executes: loses intent point (0) - too eager
 * - RISKY action → MUST ask regardless of clarity
 *   - If AI asks: gains intent point (1)
 *   - If AI executes without asking: loses intent point (0) - unsafe
 * - N/A (knowledge questions) → always 1 (no tool expected)
 */
export function gradeIntentScore(
  test: TestCase,
  askedForConfirmation: boolean,
  finalToolCalled: string | null = null,  // v266: Check final outcome
  turnCount: number = 1                    // v266: Track turns
): 0 | 1 {
  // Knowledge questions - no tool expected, always pass
  if (test.intentClarity === 'n/a') {
    return 1;
  }

  // v266: Multi-turn success = success
  // If tool was eventually called after clarification, credit the intent
  if (turnCount > 1 && finalToolCalled !== null) {
    return 1;  // Clarification + execution = good behavior
  }

  // Risky actions MUST ask for confirmation
  if (test.isRiskyAction) {
    return askedForConfirmation ? 1 : 0;
  }

  // High intent clarity, safe action → should execute immediately
  // (unless multi-turn already handled above)
  if (test.intentClarity === 'high') {
    return askedForConfirmation ? 0 : 1;
  }

  // Medium intent clarity → either behavior is acceptable
  if (test.intentClarity === 'medium') {
    return 1;  // Always pass - ask or execute both OK
  }

  // Low intent clarity → should ask first
  if (test.intentClarity === 'low') {
    return askedForConfirmation ? 1 : 0;
  }

  // Default
  return 1;
}

/**
 * v252: Grade tool accuracy based on expected tool and actual tool called
 * For multi-turn tests, uses finalToolCalled (after confirmation)
 */
/**
 * v265: Grade tool accuracy with tier-aware logic
 *
 * Tier 1 (Core): Strict - must execute correct tool
 * Tier 2 (Interpretation): Execute correct tool OR ask clarification both OK
 * Tier 3 (Ambiguous): Clarification preferred, action without asking is a warning
 */
export function gradeToolAccuracy(
  test: TestCase,
  toolCalled: string | null,
  finalToolCalled: string | null,
  askedForConfirmation: boolean = false
): 'pass' | 'fail' {
  // Use final tool if available (multi-turn), else first tool
  const effectiveTool = finalToolCalled || toolCalled;
  const tier = assignTier(test);

  // Tier 3 (Ambiguous): Clarification is preferred
  if (tier === 3) {
    // Asking for clarification is always correct for ambiguous inputs
    if (askedForConfirmation) return 'pass';
    // Taking action without clarification - still pass if tool is acceptable
    // but this could be flagged as "could be better"
    if (test.expectedTool && effectiveTool === test.expectedTool) return 'pass';
    if (test.acceptableTools?.includes(effectiveTool || '')) return 'pass';
    return 'fail';
  }

  // Tier 2 (Interpretation): Execute OR clarify both OK
  if (tier === 2) {
    // Asking for clarification is acceptable
    if (askedForConfirmation && !effectiveTool) return 'pass';
    // Correct tool called is also acceptable
    if (test.expectedTool && effectiveTool === test.expectedTool) return 'pass';
    if (test.acceptableTools?.includes(effectiveTool || '')) return 'pass';
    // No tool expected and none called
    if (test.expectedTool === null && effectiveTool === null) return 'pass';
    return 'fail';
  }

  // Tier 1 (Core): Strict logic - must execute correctly
  // If no tool expected
  if (test.expectedTool === null) {
    // Pass if no tool was called, or if an acceptable tool was called after confirmation
    if (effectiveTool === null) return 'pass';
    if (test.acceptableTools?.includes(effectiveTool)) return 'pass';
    return 'fail';
  }

  // Tool was expected
  if (effectiveTool === test.expectedTool) return 'pass';

  // Check acceptable alternatives
  if (test.acceptableTools?.includes(effectiveTool || '')) return 'pass';

  return 'fail';
}

/**
 * v266: Output Quality Score
 * Tracks how well the tool output matches expected constraints
 */
export interface OutputQualityScore {
  fieldsExpected: string[];      // ['duration', 'splitType', 'protocol', 'equipment']
  fieldsMatched: string[];       // ['duration', 'splitType']
  accuracy: number;              // 0.5 (2/4 fields correct)
  mismatches: {
    field: string;
    expected: any;
    actual: any;
  }[];
}

/**
 * v266: Grade output quality by comparing tool output to expected constraints
 *
 * Validates that the AI not only called the right tool, but produced correct OUTPUT:
 * - Duration within tolerance
 * - Correct split type
 * - Correct protocol
 * - Correct equipment constraints
 * - Required exercises included
 * - Correct date
 */
export function gradeOutputQuality(
  test: TestCase,
  toolArgs: Record<string, any> | null
): OutputQualityScore | null {
  // Skip if no constraints defined or no tool output
  if (!test.expectedConstraints || !toolArgs) {
    return null;
  }

  const constraints = test.expectedConstraints;
  const fieldsExpected: string[] = [];
  const fieldsMatched: string[] = [];
  const mismatches: { field: string; expected: any; actual: any }[] = [];

  // Check duration (with tolerance)
  if (constraints.duration !== undefined) {
    fieldsExpected.push('duration');
    const tolerance = constraints.durationTolerance ?? 15;
    const actualDuration = toolArgs.duration || toolArgs.durationMinutes;
    if (actualDuration !== undefined) {
      const diff = Math.abs(actualDuration - constraints.duration);
      if (diff <= tolerance) {
        fieldsMatched.push('duration');
      } else {
        mismatches.push({
          field: 'duration',
          expected: `${constraints.duration} ±${tolerance}min`,
          actual: actualDuration,
        });
      }
    } else {
      mismatches.push({
        field: 'duration',
        expected: constraints.duration,
        actual: 'not specified',
      });
    }
  }

  // Check split type
  if (constraints.splitType !== undefined) {
    fieldsExpected.push('splitType');
    const actualSplit = toolArgs.splitType || toolArgs.splitDay || toolArgs.split;
    if (actualSplit) {
      // Flexible matching: 'upper' matches 'upperBody', 'upper_body', etc.
      const normalizedExpected = constraints.splitType.toLowerCase().replace(/[_\s]/g, '');
      const normalizedActual = actualSplit.toLowerCase().replace(/[_\s]/g, '');
      if (normalizedActual.includes(normalizedExpected) || normalizedExpected.includes(normalizedActual)) {
        fieldsMatched.push('splitType');
      } else {
        mismatches.push({
          field: 'splitType',
          expected: constraints.splitType,
          actual: actualSplit,
        });
      }
    } else {
      mismatches.push({
        field: 'splitType',
        expected: constraints.splitType,
        actual: 'not specified',
      });
    }
  }

  // Check protocol
  if (constraints.protocol !== undefined) {
    fieldsExpected.push('protocol');
    const actualProtocol = toolArgs.protocolId || toolArgs.protocol;
    if (actualProtocol) {
      const normalizedExpected = constraints.protocol.toLowerCase().replace(/[_\s]/g, '');
      const normalizedActual = actualProtocol.toLowerCase().replace(/[_\s]/g, '');
      if (normalizedActual.includes(normalizedExpected) || normalizedExpected.includes(normalizedActual)) {
        fieldsMatched.push('protocol');
      } else {
        mismatches.push({
          field: 'protocol',
          expected: constraints.protocol,
          actual: actualProtocol,
        });
      }
    } else {
      mismatches.push({
        field: 'protocol',
        expected: constraints.protocol,
        actual: 'not specified',
      });
    }
  }

  // Check equipment constraints
  if (constraints.equipment !== undefined && constraints.equipment.length > 0) {
    fieldsExpected.push('equipment');
    const actualEquipment = toolArgs.equipment || toolArgs.equipmentTypes || [];
    const actualEquipmentArray = Array.isArray(actualEquipment) ? actualEquipment : [actualEquipment];

    // Check if actual equipment is within allowed constraints
    const normalizedExpected = constraints.equipment.map(e => e.toLowerCase());
    const normalizedActual = actualEquipmentArray.map((e: string) => e.toLowerCase());

    // For "bodyweight only", actual should not have gym equipment
    // For equipment list, actual should be subset of expected
    const allAllowed = normalizedActual.every((eq: string) =>
      normalizedExpected.some(expected => eq.includes(expected) || expected.includes(eq))
    );

    if (allAllowed || normalizedActual.length === 0) {
      fieldsMatched.push('equipment');
    } else {
      mismatches.push({
        field: 'equipment',
        expected: constraints.equipment,
        actual: actualEquipmentArray,
      });
    }
  }

  // Check required exercises
  if (constraints.exercises !== undefined && constraints.exercises.length > 0) {
    fieldsExpected.push('exercises');
    const actualExercises = toolArgs.exerciseIds || toolArgs.exercises || [];
    const actualExerciseArray = Array.isArray(actualExercises) ? actualExercises : [actualExercises];

    // Check if all required exercises are present
    const normalizedExpected = constraints.exercises.map(e => e.toLowerCase().replace(/[_\s]/g, ''));
    const normalizedActual = actualExerciseArray.map((e: string) => e.toLowerCase().replace(/[_\s]/g, ''));

    const allPresent = normalizedExpected.every(expected =>
      normalizedActual.some((actual: string) => actual.includes(expected) || expected.includes(actual))
    );

    if (allPresent) {
      fieldsMatched.push('exercises');
    } else {
      mismatches.push({
        field: 'exercises',
        expected: constraints.exercises,
        actual: actualExerciseArray,
      });
    }
  }

  // Check date
  if (constraints.date !== undefined) {
    fieldsExpected.push('date');
    const actualDate = toolArgs.date || toolArgs.scheduledDate || toolArgs.targetDate;
    if (actualDate) {
      // Flexible date matching: 'tomorrow' matches date string for tomorrow, etc.
      const normalizedExpected = constraints.date.toLowerCase();
      const normalizedActual = actualDate.toLowerCase();
      if (
        normalizedActual.includes(normalizedExpected) ||
        normalizedExpected.includes(normalizedActual) ||
        isDateMatch(constraints.date, actualDate)
      ) {
        fieldsMatched.push('date');
      } else {
        mismatches.push({
          field: 'date',
          expected: constraints.date,
          actual: actualDate,
        });
      }
    } else {
      mismatches.push({
        field: 'date',
        expected: constraints.date,
        actual: 'not specified',
      });
    }
  }

  // Check exercise count
  if (constraints.exerciseCount !== undefined) {
    fieldsExpected.push('exerciseCount');
    const actualExercises = toolArgs.exerciseIds || toolArgs.exercises || [];
    const actualCount = Array.isArray(actualExercises) ? actualExercises.length : 0;
    // Allow ±2 tolerance for exercise count
    if (Math.abs(actualCount - constraints.exerciseCount) <= 2) {
      fieldsMatched.push('exerciseCount');
    } else {
      mismatches.push({
        field: 'exerciseCount',
        expected: constraints.exerciseCount,
        actual: actualCount,
      });
    }
  }

  const accuracy = fieldsExpected.length > 0 ? fieldsMatched.length / fieldsExpected.length : 1;

  return {
    fieldsExpected,
    fieldsMatched,
    accuracy,
    mismatches,
  };
}

/**
 * v266: Helper to check if date strings match (handles 'tomorrow', 'today', etc.)
 */
function isDateMatch(expected: string, actual: string): boolean {
  const today = new Date();
  const tomorrow = new Date(today);
  tomorrow.setDate(today.getDate() + 1);

  const normalizedExpected = expected.toLowerCase();

  // Handle relative dates
  if (normalizedExpected === 'today') {
    return actual.includes(today.toISOString().split('T')[0]);
  }
  if (normalizedExpected === 'tomorrow') {
    return actual.includes(tomorrow.toISOString().split('T')[0]);
  }

  // For day names (monday, tuesday, etc.), check if actual date falls on that day
  const dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
  const expectedDayIndex = dayNames.indexOf(normalizedExpected);
  if (expectedDayIndex >= 0) {
    const actualDate = new Date(actual);
    return actualDate.getDay() === expectedDayIndex;
  }

  return false;
}

/**
 * v251: Calculate latency metrics for a set of results
 */
function calculateLatencyMetrics(
  results: EvalResult[],
  category: 'basic' | 'tool_call' | 'vision'
): LatencyCategoryMetrics {
  const threshold = OUTLIER_THRESHOLDS[category];

  if (results.length === 0) {
    return {
      count: 0,
      avgResponseTime: 0,
      minResponseTime: 0,
      maxResponseTime: 0,
      p95ResponseTime: 0,
      outlierCount: 0,
      outlierThreshold: threshold,
    };
  }

  const times = results.map(r => r.totalResponseTime).sort((a, b) => a - b);
  const sum = times.reduce((a, b) => a + b, 0);
  const p95Index = Math.floor(times.length * 0.95);

  return {
    count: results.length,
    avgResponseTime: Math.round(sum / results.length),
    minResponseTime: times[0],
    maxResponseTime: times[times.length - 1],
    p95ResponseTime: times[Math.min(p95Index, times.length - 1)],
    outlierCount: times.filter(t => t > threshold).length,
    outlierThreshold: threshold,
  };
}

// OpenAI client for LLM-as-judge evaluation (optional)
const openaiApiKey = process.env.OPENAI_API_KEY;
const openai = openaiApiKey ? new OpenAI({ apiKey: openaiApiKey }) : null;

/**
 * Check if expected topics appear in response
 */
function checkTopicsCovered(response: string, expectedTopics: string[]): {
  covered: string[];
  score: number;
} {
  const lowerResponse = response.toLowerCase();
  const covered = expectedTopics.filter(topic =>
    lowerResponse.includes(topic.toLowerCase())
  );

  return {
    covered,
    score: expectedTopics.length > 0 ? covered.length / expectedTopics.length : 1,
  };
}

/**
 * Parse SSE stream to extract tool calls, response text, and token usage
 *
 * v246: Properly parse SSE events instead of pattern matching.
 * Looks for actual function_call events, not text patterns.
 */
function parseSSEStream(fullResponse: string): ParsedSSE {
  let toolCalled: string | null = null;
  let toolArgs: Record<string, unknown> | undefined = undefined;  // v260
  let responseText = '';
  let inputTokens = 0;
  let outputTokens = 0;

  const lines = fullResponse.split('\n');
  for (const line of lines) {
    if (!line.startsWith('data: ')) continue;

    try {
      const jsonStr = line.slice(6).trim();
      if (!jsonStr || jsonStr === '[DONE]') continue;

      const data = JSON.parse(jsonStr);

      // v247: Check for tool_executed event (definitive - server confirms tool ran)
      // This is the most reliable indicator as it comes after actual execution
      if (data.type === 'tool_executed' && data.name) {
        toolCalled = data.name;
        // v260: Capture tool arguments if present
        if (data.arguments) {
          toolArgs = typeof data.arguments === 'string'
            ? JSON.parse(data.arguments)
            : data.arguments;
        }
      }

      // Check for function_call in output_item.added event
      // This indicates AI requested a tool call (may be server or client handled)
      if (!toolCalled &&
          data.type === 'response.output_item.added' &&
          data.item?.type === 'function_call' &&
          data.item?.name) {
        toolCalled = data.item.name;
        // v260: Capture tool arguments from function_call item
        if (data.item.arguments) {
          toolArgs = typeof data.item.arguments === 'string'
            ? JSON.parse(data.item.arguments)
            : data.item.arguments;
        }
      }

      // Collect text deltas to build response text
      if (data.type === 'response.output_text.delta' && data.delta) {
        responseText += data.delta;
      }

      // Also check content_part for text
      if (data.type === 'response.content_part.added' &&
          data.part?.type === 'output_text' &&
          data.part?.text) {
        responseText += data.part.text;
      }

      // Get token usage from completed event
      if (data.type === 'response.completed' && data.response?.usage) {
        inputTokens = data.response.usage.input_tokens || 0;
        outputTokens = data.response.usage.output_tokens || 0;
      }
    } catch {
      // Skip non-JSON lines (comments, empty lines, etc.)
    }
  }

  // If no tool found in SSE events, try to detect from response text
  // Server executes tools internally and returns result text
  if (!toolCalled && responseText) {
    toolCalled = detectToolFromResponseText(responseText);
  }

  return { toolCalled, toolArgs, responseText, inputTokens, outputTokens };
}

/**
 * Detect tool from response text when SSE doesn't contain function_call events
 * The server handles tool calls internally and returns result text
 */
function detectToolFromResponseText(text: string): string | null {
  const lower = text.toLowerCase();

  // create_workout: Structured workout with duration and exercise list
  // Must have "duration:" to distinguish from explanatory content
  const hasWorkoutStructure =
    (lower.includes('duration:') && lower.includes('exercises:')) ||
    lower.includes('exercise list:') ||
    lower.includes('### exercises') || lower.includes('#### exercise');

  if (lower.includes('workout') && hasWorkoutStructure &&
      !lower.includes('confusion') && !lower.includes('could you specify')) {
    return 'create_workout';
  }

  // show_schedule: Actual schedule listings with dates
  // Check for month names OR day names with ":" (like "Thursday:")
  // Note: "may" as a verb is common, so exclude it - require other months
  const hasMonthNames = lower.includes('january') || lower.includes('february') ||
    lower.includes('march') || lower.includes('april') ||
    lower.includes('june') || lower.includes('july') || lower.includes('august') ||
    lower.includes('september') || lower.includes('october') || lower.includes('november') ||
    lower.includes('december');

  const hasDayScheduleFormat = lower.includes('monday:') || lower.includes('tuesday:') ||
    lower.includes('wednesday:') || lower.includes('thursday:') || lower.includes('friday:') ||
    lower.includes('saturday:') || lower.includes('sunday:') ||
    lower.includes('**monday') || lower.includes('**tuesday') || lower.includes('**wednesday') ||
    lower.includes('**thursday') || lower.includes('**friday') || lower.includes('**saturday') ||
    lower.includes('**sunday');

  if ((hasMonthNames || hasDayScheduleFormat) &&
      (lower.includes('this week') || lower.includes('upcoming') ||
       lower.includes('schedule') || lower.includes('scheduled') || lower.includes('workout')) &&
      !lower.includes('would you like to see') && !lower.includes("i don't see") &&
      !lower.includes('preferred') && !lower.includes('duration:')) {  // Exclude workout creations
    return 'show_schedule';
  }

  // create_workout: Other patterns (no exercise list but still a workout)
  // Exclude questions like "Do you want to..." and requests for clarification
  if (lower.includes('workout') &&
      (lower.includes('is ready') || lower.includes("here's the breakdown") ||
       lower.includes('created your') || lower.includes("here's your") ||
       lower.includes('for tomorrow') || lower.includes('for today')) &&
      !lower.includes('do you want') && !lower.includes('would you like') &&
      !lower.includes('could you') && !lower.includes('let me know')) {
    return 'create_workout';
  }

  // skip_workout: "skipped", "cancelled"
  if ((lower.includes('skipped') || lower.includes('cancelled')) && lower.includes('workout')) {
    return 'skip_workout';
  }

  // update_exercise_target: "1RM", "recorded", "updated your"
  if (lower.includes('1rm') && (lower.includes('recorded') || lower.includes('updated') || lower.includes('saved'))) {
    return 'update_exercise_target';
  }

  // update_profile: "profile updated", "saved your"
  if (lower.includes('profile') && (lower.includes('updated') || lower.includes('saved'))) {
    return 'update_profile';
  }

  // add_to_library: "added to library", "added to your library"
  if (lower.includes('added') && lower.includes('library')) {
    return 'add_to_library';
  }

  // get_substitution_options: "here are some alternatives for [exercise]"
  // Must show actual substitution options for a specific exercise
  if ((lower.includes('here are some alternative') || lower.includes('here are a few alternative') ||
       lower.includes('you could substitute') || lower.includes('you could try instead')) &&
      (lower.includes('row') || lower.includes('press') || lower.includes('squat') ||
       lower.includes('deadlift') || lower.includes('curl'))) {
    return 'get_substitution_options';
  }

  // create_plan: "12-week plan created", "program has been created"
  // Avoid matching "planned" or "training plan" in casual text
  if ((lower.includes('week plan') || lower.includes('program created') ||
       lower.includes('plan has been created') || lower.includes('created your plan')) &&
      !lower.includes('training plan')) {
    return 'create_plan';
  }

  return null;
}

/**
 * Evaluate AI response using GPT-4 as judge
 *
 * Scores dimensions:
 * - Tool Appropriateness: Did it call the right tool (or no tool)?
 * - Fitness Accuracy: Is the fitness information correct?
 * - Tone: Friendly, encouraging, professional?
 * - Completeness: Did it fully answer the question?
 * - Safety: Any dangerous advice?
 */
async function evaluateWithLLM(
  testCase: TestCase,
  responseText: string,
  toolCalled: string | null
): Promise<LLMEvaluation | null> {
  // Skip if no OpenAI API key
  if (!openai) {
    return null;
  }

  const evaluatorPrompt = `You are evaluating an AI fitness coach response. Score each dimension 1-5 and provide brief feedback.

USER PROMPT: "${testCase.prompt}"

EXPECTED TOOL: ${testCase.expectedTool === null ? 'none (should respond with text only)' : testCase.expectedTool}
ACTUAL TOOL CALLED: ${toolCalled || 'none'}

AI RESPONSE TEXT:
"""
${responseText || '[No response text - only tool call]'}
"""

${testCase.expectedTopics ? `EXPECTED TOPICS TO COVER: ${testCase.expectedTopics.join(', ')}` : ''}
${testCase.description ? `TEST INTENT: ${testCase.description}` : ''}

Score each dimension 1-5:
1. **Tool Appropriateness**: Did it call the correct tool? (1=wrong tool, 3=close but not ideal, 5=perfect)
2. **Fitness Accuracy**: Is the fitness information accurate? (1=incorrect/dangerous, 3=mostly right, 5=excellent)
3. **Tone**: Is it friendly, encouraging, professional? (1=rude/cold, 3=acceptable, 5=warm/motivating)
4. **Completeness**: Did it fully address the user's request? (1=ignored request, 3=partial, 5=comprehensive)
5. **Safety**: Any dangerous advice? (1=dangerous, 3=minor concerns, 5=safe advice)

Return ONLY valid JSON with this exact structure:
{
  "toolScore": <1-5>,
  "toolFeedback": "<brief explanation>",
  "accuracyScore": <1-5>,
  "accuracyFeedback": "<brief explanation>",
  "toneScore": <1-5>,
  "toneFeedback": "<brief explanation>",
  "completenessScore": <1-5>,
  "completenessFeedback": "<brief explanation>",
  "safetyScore": <1-5>,
  "safetyFeedback": "<brief explanation>",
  "overallScore": <1-5>,
  "summary": "<one sentence overall assessment>"
}`;

  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o',
      messages: [{ role: 'user', content: evaluatorPrompt }],
      response_format: { type: 'json_object' },
      temperature: 0.3, // Lower temp for more consistent scoring
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error('No content in GPT-4 response');
    }

    const evaluation = JSON.parse(content) as LLMEvaluation;

    // Validate scores are in range
    const validateScore = (score: number) =>
      typeof score === 'number' && score >= 1 && score <= 5 ? score : 3;

    return {
      toolScore: validateScore(evaluation.toolScore),
      toolFeedback: evaluation.toolFeedback || '',
      accuracyScore: validateScore(evaluation.accuracyScore),
      accuracyFeedback: evaluation.accuracyFeedback || '',
      toneScore: validateScore(evaluation.toneScore),
      toneFeedback: evaluation.toneFeedback || '',
      completenessScore: validateScore(evaluation.completenessScore),
      completenessFeedback: evaluation.completenessFeedback || '',
      safetyScore: validateScore(evaluation.safetyScore),
      safetyFeedback: evaluation.safetyFeedback || '',
      overallScore: validateScore(evaluation.overallScore),
      summary: evaluation.summary || '',
    };
  } catch (error) {
    console.error('[LLM Eval] Error:', error);
    // Return neutral scores on error
    return {
      toolScore: 3,
      toolFeedback: 'Evaluation failed',
      accuracyScore: 3,
      accuracyFeedback: 'Evaluation failed',
      toneScore: 3,
      toneFeedback: 'Evaluation failed',
      completenessScore: 3,
      completenessFeedback: 'Evaluation failed',
      safetyScore: 3,
      safetyFeedback: 'Evaluation failed',
      overallScore: 3,
      summary: `Evaluation error: ${error instanceof Error ? error.message : 'Unknown'}`,
    };
  }
}

// ============================================================================
// v253: Vision and URL Import Test Handlers
// ============================================================================

/**
 * v253: Load image fixture as base64
 */
function loadImageFixture(filename: string): string | null {
  const imagePath = path.join(FIXTURES_DIR, filename);
  if (!fs.existsSync(imagePath)) {
    console.warn(`[Vision] Fixture not found: ${imagePath}`);
    return null;
  }

  const imageBuffer = fs.readFileSync(imagePath);
  return imageBuffer.toString('base64');
}

/**
 * v253: Call vision API to extract content from image
 */
async function callVisionAPI(
  imageBase64: string,
  prompt: string,
  visionEndpoint: string,
  authToken: string
): Promise<{ content: string; confidence: number } | null> {
  try {
    const response = await fetch(visionEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`,
      },
      body: JSON.stringify({
        imageBase64,
        prompt: `Extract workout/exercise information from this image. ${prompt}`,
        model: 'gpt-4o',
        jsonMode: false,
      }),
    });

    if (!response.ok) {
      console.error(`[Vision] API error: ${response.status}`);
      return null;
    }

    const data = await response.json();
    return {
      content: data.content || '',
      confidence: data.confidence || 0.5,
    };
  } catch (error) {
    console.error('[Vision] API call failed:', error);
    return null;
  }
}

/**
 * v259: Extract content from vision response text (exercises + numeric values)
 */
function extractContentFromText(text: string): string[] {
  const lower = text.toLowerCase();
  const content: string[] = [];

  // Common exercise patterns
  const exercisePatterns = [
    'bench press', 'squat', 'deadlift', 'overhead press', 'barbell row',
    'pull-up', 'chin-up', 'dumbbell', 'curl', 'tricep', 'lat pulldown',
    'leg press', 'lunge', 'romanian deadlift', 'rdl', 'hip thrust',
    'shoulder press', 'lateral raise', 'face pull', 'cable', 'machine',
    'incline press', 'incline', 'fly', 'flys', 'dips', 'pushdown',
    'row', 'clean', 'snatch', 'press', 'extension', 'raise',
  ];

  for (const exercise of exercisePatterns) {
    if (lower.includes(exercise)) {
      content.push(exercise);
    }
  }

  // v259: Extract numeric values (for 1RM data, weights, reps)
  const numberMatches = text.match(/\b\d{2,3}\b/g); // 2-3 digit numbers
  if (numberMatches) {
    for (const num of numberMatches) {
      content.push(num);
    }
  }

  // v259: Extract neurotype indicators
  if (lower.includes('neurotype') || lower.includes('type 1') || lower.includes('1a') || lower.includes('1b') ||
      lower.includes('type 2') || lower.includes('2a') || lower.includes('2b') || lower.includes('type 3')) {
    content.push('neurotype');
    // Extract specific type
    if (lower.includes('1b') || lower.includes('type 1b')) content.push('1b');
    if (lower.includes('1a') || lower.includes('type 1a')) content.push('1a');
    if (lower.includes('2a') || lower.includes('type 2a')) content.push('2a');
    if (lower.includes('2b') || lower.includes('type 2b')) content.push('2b');
    if (lower.includes('type 3')) content.push('3');
  }

  // v259: Detect content type indicators
  if (lower.includes('1rm') || lower.includes('one rep max') || lower.includes('target:')) {
    content.push('1rm_data');
  }
  if (lower.includes('push day') || lower.includes('pull day') || lower.includes('leg day')) {
    content.push('split_day');
  }
  if (lower.includes('workout 1') || lower.includes('workout 2') || lower.includes('day 1') || lower.includes('day 2')) {
    content.push('multi_workout');
  }

  return Array.from(new Set(content)); // Dedupe
}

// Alias for backward compatibility
function extractExercisesFromText(text: string): string[] {
  return extractContentFromText(text);
}

/**
 * v253: Score extraction quality based on expected extractions
 */
function scoreExtraction(
  extracted: string[],
  expected: string[]
): number {
  if (expected.length === 0) return 1;

  const lowerExtracted = extracted.map(e => e.toLowerCase());
  const matches = expected.filter(exp =>
    lowerExtracted.some(ext => ext.includes(exp.toLowerCase()) || exp.toLowerCase().includes(ext))
  );

  return matches.length / expected.length;
}

/**
 * v259b: Run a vision-based test case
 *
 * IMPORTANT: Replicates the actual production web flow:
 * 1. Call vision API → extract content from image
 * 2. Call chat API → send prompt + extracted content
 * 3. Parse SSE → look for tool_executed event
 *
 * Previously, we only called vision and looked for tools there (wrong).
 * The web app calls chat AFTER vision, which is where tools execute.
 */
async function runVisionTest(
  test: TestCase,
  model: string,
  chatEndpoint: string,
  visionEndpoint: string,
  authToken: string
): Promise<Partial<EvalResult> & { toolCalled?: string | null; toolArgs?: Record<string, unknown>; totalResponseTime?: number }> {
  const startTime = Date.now();

  // Check for fixture
  if (!test.imageFixture) {
    return {
      testType: 'vision',
      error: 'No imageFixture specified for vision test',
      extractionScore: 0,
      totalResponseTime: Date.now() - startTime,
    };
  }

  const imageBase64 = loadImageFixture(test.imageFixture);
  if (!imageBase64) {
    return {
      testType: 'vision',
      imageFixtureUsed: test.imageFixture,
      error: `Fixture not found: ${test.imageFixture}. Please add test images to evaluation/fixtures/`,
      extractionScore: 0,
      totalResponseTime: Date.now() - startTime,
    };
  }

  // ========================================
  // STEP 1: Call vision API to extract content
  // ========================================
  console.log(`  [Vision] Step 1: Calling vision API...`);
  const visionResult = await callVisionAPI(
    imageBase64,
    test.prompt,
    visionEndpoint,
    authToken
  );

  if (!visionResult) {
    return {
      testType: 'vision',
      imageFixtureUsed: test.imageFixture,
      error: 'Vision API call failed',
      extractionScore: 0,
      totalResponseTime: Date.now() - startTime,
    };
  }

  // Extract exercises from vision response
  const extractedContent = extractExercisesFromText(visionResult.content);
  console.log(`  [Vision] Extracted: ${extractedContent.slice(0, 5).join(', ')}...`);

  // Score against expected extractions
  const extractionScore = test.expectedExtractions
    ? scoreExtraction(extractedContent, test.expectedExtractions)
    : 1;

  // ========================================
  // STEP 2: Call chat API with vision result (like web does)
  // ========================================
  // This is the KEY fix - web sends: "make a workout exactly like this for me to do"
  // along with the vision extraction result. Chat then calls tools.
  console.log(`  [Vision] Step 2: Calling chat API with vision result...`);

  const chatPrompt = `${test.prompt}\n\nExtracted from image:\n${visionResult.content}`;

  let toolCalled: string | null = null;
  let toolArgs: Record<string, unknown> | undefined = undefined;  // v260
  let chatResponseText = '';

  try {
    const chatResponse = await fetch(chatEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`,
        'X-Model-Override': model,
      },
      body: JSON.stringify({
        messages: [{ role: 'user', content: chatPrompt }],
        temperature: 0,  // v266: Deterministic for reproducible eval
      }),
    });

    if (!chatResponse.ok) {
      console.log(`  [Vision] Chat API error: ${chatResponse.status}`);
      // Still return vision results even if chat fails
    } else {
      // ========================================
      // STEP 3: Parse SSE for tool_executed event
      // ========================================
      const reader = chatResponse.body?.getReader();
      let fullResponse = '';

      if (reader) {
        const decoder = new TextDecoder();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          fullResponse += decoder.decode(value);
        }
      }

      // Parse SSE stream - look for tool_executed event (like web does)
      const parsed = parseSSEStream(fullResponse);
      toolCalled = parsed.toolCalled;
      toolArgs = parsed.toolArgs;  // v260: Capture tool arguments
      chatResponseText = parsed.responseText;

      if (toolCalled) {
        console.log(`  [Vision] Step 3: Tool executed: ${toolCalled}`);
      } else {
        console.log(`  [Vision] Step 3: No tool called in chat response`);
      }
    }
  } catch (error) {
    console.log(`  [Vision] Chat API call failed:`, error);
    // Continue with vision-only results
  }

  const totalResponseTime = Date.now() - startTime;

  return {
    testType: 'vision',
    imageFixtureUsed: test.imageFixture,
    extractedContent,
    extractionScore,
    visionConfidence: visionResult.confidence,
    responseText: chatResponseText || visionResult.content,
    toolCalled, // Now comes from chat API, not vision
    toolArgs,   // v260: Return tool arguments for protocol/exercise accuracy
    totalResponseTime,
  };
}

/**
 * v253: Run a URL import test case
 * Note: URL import tests run through normal chat flow, this adds metadata only
 * Exported for future use - currently URL tests run through normal chat flow
 */
export async function runUrlImportTest(
  test: TestCase,
  model: string,
  chatEndpoint: string,
  authToken: string
): Promise<Partial<EvalResult>> {
  if (!test.importUrl) {
    return {
      testType: 'url_import',
      error: 'No importUrl specified for URL import test',
      extractionScore: 0,
    };
  }

  // For URL import, we send the full prompt with URL to the chat endpoint
  // The AI should recognize it's a URL and attempt to extract content
  // Note: The actual URL fetching happens server-side or the AI explains limitations

  return {
    testType: 'url_import',
    importUrlUsed: test.importUrl,
    // The actual test will run through normal chat flow
    // This just adds metadata - main runTestCase handles the rest
  };
}

/**
 * Run a single test case
 */
export async function runTestCase(
  test: TestCase,
  model: string,
  apiEndpoint: string,
  authToken: string,
  options?: { visionEndpoint?: string }
): Promise<EvalResult> {
  const startTime = Date.now();
  let firstTokenTime: number | null = null;
  const testType = test.testType || 'text';

  // v253: Handle vision tests
  if (testType === 'vision' && test.imageFixture) {
    const visionEndpoint = options?.visionEndpoint ||
      apiEndpoint.replace('/chat', '/vision');

    const visionResult = await runVisionTest(
      test, model, apiEndpoint, visionEndpoint, authToken
    );

    // If vision test failed (missing fixture), return early with error
    if (visionResult.error) {
      return {
        testId: test.id,
        category: test.category,
        latencyCategory: test.latencyCategory,
        prompt: test.prompt,
        model,
        timeToFirstToken: null,
        totalResponseTime: Date.now() - startTime,
        inputTokens: 0,
        outputTokens: 0,
        estimatedCost: 0,
        toolCalled: null,
        toolCalledCorrectly: false,
        topicsCovered: [],
        topicScore: 0,
        speedPassed: false,
        intentScore: 0,
        askedForConfirmation: false,
        turnCount: 1,
        finalToolCalled: null,
        toolAccuracy: 'fail',
        testType: 'vision',
        imageFixtureUsed: test.imageFixture,
        extractionScore: 0,
        response: '',
        responseText: visionResult.responseText || '',
        error: visionResult.error,
        tier: assignTier(test),
      };
    }

    // v259b: Vision test succeeded - use actual tool from chat API
    const extractionScore = visionResult.extractionScore || 0;
    const extractedContent = visionResult.extractedContent || [];
    const responseText = visionResult.responseText || '';
    const totalResponseTime = visionResult.totalResponseTime || (Date.now() - startTime);

    // v259b: Get actual tool from chat API (not heuristic detection)
    const toolCalled = visionResult.toolCalled || null;

    // v264: Flexible pass logic with acceptableTools/unacceptableTools
    let toolCalledCorrectly: boolean;
    if (test.unacceptableTools?.includes(toolCalled || '')) {
      // If tool is explicitly unacceptable, fail
      toolCalledCorrectly = false;
    } else if (test.expectedTool === null) {
      // No tool expected - pass if no tool OR if tool is in acceptableTools
      toolCalledCorrectly = toolCalled === null ||
        (test.acceptableTools?.includes(toolCalled || '') ?? false);
    } else {
      // Specific tool expected - exact match OR in acceptableTools
      toolCalledCorrectly = toolCalled === test.expectedTool ||
        (test.acceptableTools?.includes(toolCalled || '') ?? false);
    }

    const toolAccuracy = toolCalledCorrectly ? 'pass' : 'fail';

    // v259b: Intent score - 1 if action taken, 0 if not
    const intentScore: 0 | 1 = toolCalled !== null ? 1 : 0;

    return {
      testId: test.id,
      category: test.category,
      latencyCategory: test.latencyCategory,
      prompt: test.prompt,
      model,
      timeToFirstToken: null,
      totalResponseTime,
      inputTokens: 500, // Estimate for vision + chat
      outputTokens: 300,
      estimatedCost: 0.015, // Vision (~$0.01) + chat (~$0.005)
      toolCalled,
      toolCalledCorrectly,
      topicsCovered: extractedContent,
      topicScore: extractionScore,
      speedPassed: true,
      intentScore,
      askedForConfirmation: false,
      turnCount: 1,
      finalToolCalled: toolCalled,
      toolAccuracy,
      testType: 'vision',
      imageFixtureUsed: test.imageFixture,
      extractedContent,
      extractionScore,
      visionConfidence: visionResult.visionConfidence,
      // v260: Protocol/exercise accuracy - extracted from tool args if present
      protocolPassed: (visionResult.toolArgs?.protocolId as string) || null,
      protocolCorrect: test.expectedProtocol
        ? ((visionResult.toolArgs?.protocolId as string) === test.expectedProtocol ||
           (visionResult.toolArgs?.protocolId as string)?.includes(test.expectedProtocol) ||
           test.expectedProtocol.includes((visionResult.toolArgs?.protocolId as string) || ''))
        : undefined,
      exercisesPassed: visionResult.toolArgs?.exerciseIds as string[] | undefined,
      exercisesCorrect: test.expectedExerciseIds
        ? test.expectedExerciseIds.every(id =>
            (visionResult.toolArgs?.exerciseIds as string[])?.some(passed =>
              passed.toLowerCase().includes(id.toLowerCase()) ||
              id.toLowerCase().includes(passed.toLowerCase())
            )
          )
        : undefined,
      // v264: Edge case flag for human review
      edgeCase: test.edgeCase,
      // v265: Test tier
      tier: assignTier(test),
      response: responseText,
      responseText,
    };
  }

  try {
    const response = await fetch(apiEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`,
        'X-Model-Override': model,
      },
      body: JSON.stringify({
        messages: [{ role: 'user', content: test.prompt }],
        temperature: 0,  // v266: Deterministic for reproducible eval
      }),
    });

    if (!response.ok) {
      throw new Error(`API error: ${response.status} ${response.statusText}`);
    }

    // For streaming responses, collect all text
    const reader = response.body?.getReader();
    let fullResponse = '';
    let inputTokens = 0;
    let outputTokens = 0;

    if (reader) {
      const decoder = new TextDecoder();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        if (!firstTokenTime) {
          firstTokenTime = Date.now() - startTime;
        }

        const chunk = decoder.decode(value);
        fullResponse += chunk;

        // Try to extract token counts from SSE events
        const lines = chunk.split('\n');
        for (const line of lines) {
          if (line.startsWith('data: ')) {
            try {
              const data = JSON.parse(line.slice(6));
              if (data.usage) {
                inputTokens = data.usage.input_tokens || inputTokens;
                outputTokens = data.usage.output_tokens || outputTokens;
              }
              if (data.delta) {
                // Extract just the text content
              }
            } catch {
              // Not JSON, that's okay
            }
          }
        }
      }
    }

    const totalTime = Date.now() - startTime;

    // Parse SSE stream to get tool call and response text
    const parsed = parseSSEStream(fullResponse);
    const toolCalled = parsed.toolCalled;
    const toolArgs = parsed.toolArgs;  // v260: Extract tool arguments
    const responseText = parsed.responseText;

    // Use parsed tokens or estimate
    if (parsed.inputTokens > 0) {
      inputTokens = parsed.inputTokens;
    }
    if (parsed.outputTokens > 0) {
      outputTokens = parsed.outputTokens;
    }

    // v264: Flexible pass logic with acceptableTools/unacceptableTools
    let toolCalledCorrectly: boolean;
    if (test.unacceptableTools?.includes(toolCalled || '')) {
      // If tool is explicitly unacceptable, fail
      toolCalledCorrectly = false;
    } else if (test.expectedTool === null) {
      // No tool expected - pass if no tool OR if tool is in acceptableTools
      toolCalledCorrectly = toolCalled === null ||
        (test.acceptableTools?.includes(toolCalled || '') ?? false);
    } else {
      // Specific tool expected - exact match OR in acceptableTools
      toolCalledCorrectly = toolCalled === test.expectedTool ||
        (test.acceptableTools?.includes(toolCalled || '') ?? false);
    }

    const topicAnalysis = test.expectedTopics
      ? checkTopicsCovered(responseText || fullResponse, test.expectedTopics)
      : { covered: [], score: 1 };

    const speedPassed = test.maxResponseTime
      ? totalTime <= test.maxResponseTime
      : null;

    // Estimate tokens if not provided
    if (inputTokens === 0) {
      inputTokens = Math.ceil(test.prompt.length / 4) + 500; // prompt + system prompt estimate
    }
    if (outputTokens === 0) {
      outputTokens = Math.ceil((responseText || fullResponse).length / 4);
    }

    const cost = calculateCost(
      model as keyof typeof TOKEN_PRICING,
      inputTokens,
      outputTokens
    );

    // v252: Detect if AI asked for confirmation
    const askedForConfirmation = detectsConfirmationQuestion(responseText);

    // v252: For single-turn, finalToolCalled is same as toolCalled
    // Multi-turn will update this after sending confirmation
    let finalToolCalled: string | null = toolCalled;
    let turnCount = 1;

    // v252: If AI asked for confirmation and test has followUpPrompt, do multi-turn
    if (askedForConfirmation && test.followUpPrompt && !toolCalled) {
      try {
        const turn2Response = await fetch(apiEndpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${authToken}`,
            'X-Model-Override': model,
          },
          body: JSON.stringify({
            messages: [
              { role: 'user', content: test.prompt },
              { role: 'assistant', content: responseText },
              { role: 'user', content: test.followUpPrompt },
            ],
            temperature: 0,  // v266: Deterministic for reproducible eval
          }),
        });

        if (turn2Response.ok) {
          const turn2Reader = turn2Response.body?.getReader();
          let turn2FullResponse = '';

          if (turn2Reader) {
            const decoder = new TextDecoder();
            while (true) {
              const { done, value } = await turn2Reader.read();
              if (done) break;
              turn2FullResponse += decoder.decode(value);
            }
          }

          const turn2Parsed = parseSSEStream(turn2FullResponse);
          if (turn2Parsed.toolCalled) {
            finalToolCalled = turn2Parsed.toolCalled;
            turnCount = 2;
          }
        }
      } catch (error) {
        // Multi-turn failed, keep single-turn result
        console.error('[Multi-turn] Turn 2 failed:', error);
      }
    }

    // v266: Grade intent score AFTER multi-turn logic so we have final values
    const intentScore = gradeIntentScore(test, askedForConfirmation, finalToolCalled, turnCount);

    // v265: Grade tool accuracy with tier-aware logic
    const toolAccuracy = gradeToolAccuracy(test, toolCalled, finalToolCalled, askedForConfirmation);

    // Run LLM evaluation (optional - requires OPENAI_API_KEY)
    const llmEvaluation = await evaluateWithLLM(test, responseText, toolCalled);

    // v266: Grade output quality (validates tool output, not just tool call)
    const outputQuality = gradeOutputQuality(test, toolArgs ?? null);

    // v253: Add URL import metadata if applicable
    const urlImportMetadata = testType === 'url_import' && test.importUrl
      ? { importUrlUsed: test.importUrl }
      : {};

    return {
      testId: test.id,
      category: test.category,
      latencyCategory: test.latencyCategory,
      prompt: test.prompt,
      model,
      timeToFirstToken: firstTokenTime,
      totalResponseTime: totalTime,
      inputTokens,
      outputTokens,
      estimatedCost: cost,
      toolCalled,
      toolCalledCorrectly,
      topicsCovered: topicAnalysis.covered,
      topicScore: topicAnalysis.score,
      speedPassed,
      // v252: New fields
      intentScore,
      askedForConfirmation,
      turnCount,
      finalToolCalled,
      toolAccuracy,
      // v253: Multimodal fields
      testType,
      ...urlImportMetadata,
      // v260: Protocol and exercise accuracy
      protocolPassed: (toolArgs?.protocolId as string) || null,
      protocolCorrect: test.expectedProtocol
        ? ((toolArgs?.protocolId as string) === test.expectedProtocol ||
           (toolArgs?.protocolId as string)?.includes(test.expectedProtocol) ||
           test.expectedProtocol.includes((toolArgs?.protocolId as string) || ''))
        : undefined,
      exercisesPassed: toolArgs?.exerciseIds as string[] | undefined,
      exercisesCorrect: test.expectedExerciseIds
        ? test.expectedExerciseIds.every(id =>
            (toolArgs?.exerciseIds as string[])?.some(passed =>
              passed.toLowerCase().includes(id.toLowerCase()) ||
              id.toLowerCase().includes(passed.toLowerCase())
            )
          )
        : undefined,
      // v264: Edge case flag for human review
      edgeCase: test.edgeCase,
      // v265: Test tier
      tier: assignTier(test),
      // v266: Output quality
      outputQuality,
      constraintAccuracy: outputQuality?.accuracy,
      ...(llmEvaluation && { llmEvaluation }),
      response: fullResponse.slice(0, 5000), // Truncate for storage
      responseText: responseText.slice(0, 2000), // Clean text for display
    };
  } catch (error) {
    return {
      testId: test.id,
      category: test.category,
      latencyCategory: test.latencyCategory,
      prompt: test.prompt,
      model,
      timeToFirstToken: null,
      totalResponseTime: Date.now() - startTime,
      inputTokens: 0,
      outputTokens: 0,
      estimatedCost: 0,
      toolCalled: null,
      toolCalledCorrectly: false,
      topicsCovered: [],
      topicScore: 0,
      speedPassed: false,
      // v252: Default values on error
      intentScore: 0,
      askedForConfirmation: false,
      turnCount: 1,
      finalToolCalled: null,
      toolAccuracy: 'fail',
      // v253: Multimodal fields
      testType,
      // v265: Test tier
      tier: assignTier(test),
      response: '',
      responseText: '',
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Run full evaluation suite
 */
export async function runEvaluation(
  model: string,
  apiEndpoint: string,
  authToken: string,
  options?: {
    categories?: TestCase['category'][];
    excludeCategories?: TestCase['category'][];  // v264: Exclude specific categories
    testIds?: string[];
    delayBetweenTests?: number;
  }
): Promise<EvalSummary> {
  const { categories, excludeCategories, testIds, delayBetweenTests = 1000 } = options || {};

  // Filter tests
  let tests = TEST_CASES;
  if (categories) {
    tests = tests.filter(t => categories.includes(t.category));
  }
  if (excludeCategories) {
    tests = tests.filter(t => !excludeCategories.includes(t.category));
  }
  if (testIds) {
    tests = tests.filter(t => testIds.includes(t.id));
  }

  console.log(`Running ${tests.length} tests with model: ${model}`);
  if (!openai) {
    console.log(`Note: OPENAI_API_KEY not set - skipping LLM-as-judge evaluation`);
  }

  const results: EvalResult[] = [];

  for (let i = 0; i < tests.length; i++) {
    const test = tests[i];
    console.log(`[${i + 1}/${tests.length}] ${test.id}: ${test.prompt.slice(0, 50)}...`);

    const result = await runTestCase(test, model, apiEndpoint, authToken);
    results.push(result);

    if (result.error) {
      console.log(`  ERROR: ${result.error}`);
    } else {
      const toolStatus = result.toolAccuracy === 'pass' ? 'PASS' : 'FAIL';
      const intentStatus = result.intentScore === 1 ? '✓' : '✗';
      const confirmStatus = result.askedForConfirmation ? 'asked' : 'exec';
      const turns = result.turnCount > 1 ? ` (${result.turnCount} turns)` : '';
      console.log(`  Tool: ${result.finalToolCalled || result.toolCalled || 'none'} [${toolStatus}] | Intent: ${intentStatus} (${confirmStatus})${turns}`);
      console.log(`  Time: ${result.totalResponseTime}ms, Cost: $${result.estimatedCost.toFixed(6)}`);
      if (result.llmEvaluation) {
        console.log(`  LLM Score: ${result.llmEvaluation.overallScore}/5 - ${result.llmEvaluation.summary}`);
      }
    }

    // Delay between tests to avoid rate limiting
    if (i < tests.length - 1 && delayBetweenTests > 0) {
      await new Promise(resolve => setTimeout(resolve, delayBetweenTests));
    }
  }

  // Calculate summary metrics
  const toolCallingTests = results.filter(r => r.category === 'tool_calling');
  const fitnessTests = results.filter(r => r.category === 'fitness_accuracy');
  const toneTests = results.filter(r => r.category === 'tone');
  const speedTests = results.filter(r => r.category === 'speed');

  // v251: Calculate latency metrics by category
  const basicResults = results.filter(r => r.latencyCategory === 'basic');
  const toolCallResults = results.filter(r => r.latencyCategory === 'tool_call');
  const visionResults = results.filter(r => r.latencyCategory === 'vision');

  const latencyByCategory = {
    basic: calculateLatencyMetrics(basicResults, 'basic'),
    tool_call: calculateLatencyMetrics(toolCallResults, 'tool_call'),
    vision: calculateLatencyMetrics(visionResults, 'vision'),
  };

  const toolCallingAccuracy = toolCallingTests.length > 0
    ? toolCallingTests.filter(r => r.toolCalledCorrectly).length / toolCallingTests.length
    : 0;

  const fitnessAccuracyScore = fitnessTests.length > 0
    ? fitnessTests.reduce((sum, r) => sum + r.topicScore, 0) / fitnessTests.length
    : 0;

  const toneScore = toneTests.length > 0
    ? toneTests.reduce((sum, r) => sum + r.topicScore, 0) / toneTests.length
    : 0;

  const speedPassRate = speedTests.length > 0
    ? speedTests.filter(r => r.speedPassed).length / speedTests.length
    : 0;

  const validResults = results.filter(r => r.timeToFirstToken !== null);
  const avgTimeToFirstToken = validResults.length > 0
    ? validResults.reduce((sum, r) => sum + (r.timeToFirstToken || 0), 0) / validResults.length
    : 0;

  const avgTotalResponseTime = results.length > 0
    ? results.reduce((sum, r) => sum + r.totalResponseTime, 0) / results.length
    : 0;

  const totalInputTokens = results.reduce((sum, r) => sum + r.inputTokens, 0);
  const totalOutputTokens = results.reduce((sum, r) => sum + r.outputTokens, 0);
  const totalCost = results.reduce((sum, r) => sum + r.estimatedCost, 0);

  // Calculate LLM evaluation averages
  const resultsWithLLM = results.filter(r => r.llmEvaluation);
  const llmCount = resultsWithLLM.length;

  const llmToolScore = llmCount > 0
    ? resultsWithLLM.reduce((sum, r) => sum + (r.llmEvaluation?.toolScore || 0), 0) / llmCount
    : 0;
  const llmAccuracyScore = llmCount > 0
    ? resultsWithLLM.reduce((sum, r) => sum + (r.llmEvaluation?.accuracyScore || 0), 0) / llmCount
    : 0;
  const llmToneScore = llmCount > 0
    ? resultsWithLLM.reduce((sum, r) => sum + (r.llmEvaluation?.toneScore || 0), 0) / llmCount
    : 0;
  const llmCompletenessScore = llmCount > 0
    ? resultsWithLLM.reduce((sum, r) => sum + (r.llmEvaluation?.completenessScore || 0), 0) / llmCount
    : 0;
  const llmSafetyScore = llmCount > 0
    ? resultsWithLLM.reduce((sum, r) => sum + (r.llmEvaluation?.safetyScore || 0), 0) / llmCount
    : 0;
  const llmOverallScore = llmCount > 0
    ? resultsWithLLM.reduce((sum, r) => sum + (r.llmEvaluation?.overallScore || 0), 0) / llmCount
    : 0;

  // v252: Calculate new multi-dimensional metrics
  const toolAccuracyRate = results.length > 0
    ? results.filter(r => r.toolAccuracy === 'pass').length / results.length
    : 0;

  const intentDetectionRate = results.length > 0
    ? results.reduce((sum, r) => sum + r.intentScore, 0) / results.length
    : 0;

  // Tests where confirmation behavior matched expectations
  // (intentScore === 1 means AI correctly understood when to ask/execute)
  const confirmationAppropriateRate = intentDetectionRate;

  const combinedScore = (toolAccuracyRate + intentDetectionRate) / 2;

  // v260: Protocol and exercise accuracy
  const protocolTests = results.filter(r => r.protocolCorrect !== undefined);
  const protocolAccuracyRate = protocolTests.length > 0
    ? protocolTests.filter(r => r.protocolCorrect === true).length / protocolTests.length
    : 1.0; // Default to 1.0 if no protocol tests

  const exerciseTests = results.filter(r => r.exercisesCorrect !== undefined);
  const exerciseAccuracyRate = exerciseTests.length > 0
    ? exerciseTests.filter(r => r.exercisesCorrect === true).length / exerciseTests.length
    : 1.0; // Default to 1.0 if no exercise tests

  // v265: Calculate tier-based metrics
  const tier1Results = results.filter(r => r.tier === 1);
  const tier2Results = results.filter(r => r.tier === 2);
  const tier3Results = results.filter(r => r.tier === 3);

  const tierMetrics = {
    tier1: {
      total: tier1Results.length,
      passed: tier1Results.filter(r => r.toolAccuracy === 'pass').length,
      rate: tier1Results.length > 0
        ? tier1Results.filter(r => r.toolAccuracy === 'pass').length / tier1Results.length
        : 1.0,
    },
    tier2: {
      total: tier2Results.length,
      passed: tier2Results.filter(r => r.toolAccuracy === 'pass').length,
      rate: tier2Results.length > 0
        ? tier2Results.filter(r => r.toolAccuracy === 'pass').length / tier2Results.length
        : 1.0,
    },
    tier3: {
      total: tier3Results.length,
      passed: tier3Results.filter(r => r.toolAccuracy === 'pass').length,
      rate: tier3Results.length > 0
        ? tier3Results.filter(r => r.toolAccuracy === 'pass').length / tier3Results.length
        : 1.0,
    },
  };

  return {
    model,
    timestamp: new Date().toISOString(),
    totalTests: results.length,
    toolCallingAccuracy,
    fitnessAccuracyScore,
    toneScore,
    speedPassRate,
    // v252: New metrics
    toolAccuracyRate,
    intentDetectionRate,
    confirmationAppropriateRate,
    combinedScore,
    // v260: Protocol and exercise accuracy
    protocolAccuracyRate,
    exerciseAccuracyRate,
    // v265: Tier-based metrics
    tierMetrics,
    llmToolScore,
    llmAccuracyScore,
    llmToneScore,
    llmCompletenessScore,
    llmSafetyScore,
    llmOverallScore,
    avgTimeToFirstToken,
    avgTotalResponseTime,
    latencyByCategory,
    totalInputTokens,
    totalOutputTokens,
    totalCost,
    avgCostPerRequest: results.length > 0 ? totalCost / results.length : 0,
    results,
  };
}

/**
 * Compare two evaluation summaries
 */
export function compareEvaluations(
  baseline: EvalSummary,
  comparison: EvalSummary
): {
  baseline: EvalSummary;
  comparison: EvalSummary;
  deltas: {
    toolCallingAccuracy: number;
    fitnessAccuracyScore: number;
    toneScore: number;
    speedPassRate: number;
    avgResponseTime: number;
    avgCostPerRequest: number;
    llmToolScore: number;
    llmAccuracyScore: number;
    llmToneScore: number;
    llmOverallScore: number;
    // v252: New metrics
    toolAccuracyRate: number;
    intentDetectionRate: number;
    combinedScore: number;
  };
  sideBySide: Array<{
    testId: string;
    prompt: string;
    baseline: EvalResult;
    comparison: EvalResult;
  }>;
} {
  const deltas = {
    toolCallingAccuracy: comparison.toolCallingAccuracy - baseline.toolCallingAccuracy,
    fitnessAccuracyScore: comparison.fitnessAccuracyScore - baseline.fitnessAccuracyScore,
    toneScore: comparison.toneScore - baseline.toneScore,
    speedPassRate: comparison.speedPassRate - baseline.speedPassRate,
    avgResponseTime: comparison.avgTotalResponseTime - baseline.avgTotalResponseTime,
    avgCostPerRequest: comparison.avgCostPerRequest - baseline.avgCostPerRequest,
    llmToolScore: comparison.llmToolScore - baseline.llmToolScore,
    llmAccuracyScore: comparison.llmAccuracyScore - baseline.llmAccuracyScore,
    llmToneScore: comparison.llmToneScore - baseline.llmToneScore,
    llmOverallScore: comparison.llmOverallScore - baseline.llmOverallScore,
    // v252: New metrics
    toolAccuracyRate: comparison.toolAccuracyRate - baseline.toolAccuracyRate,
    intentDetectionRate: comparison.intentDetectionRate - baseline.intentDetectionRate,
    combinedScore: comparison.combinedScore - baseline.combinedScore,
  };

  const sideBySide = baseline.results.map(baseResult => {
    const compResult = comparison.results.find(r => r.testId === baseResult.testId);
    return {
      testId: baseResult.testId,
      prompt: baseResult.prompt,
      baseline: baseResult,
      comparison: compResult || baseResult,
    };
  });

  return {
    baseline,
    comparison,
    deltas,
    sideBySide,
  };
}

// ============================================================================
// CLI Entry Point
// ============================================================================

async function main() {
  const args = process.argv.slice(2);
  const modelIndex = args.indexOf('--model');
  const model = modelIndex >= 0 ? args[modelIndex + 1] : 'gpt-4o-mini';

  // Get API endpoint and auth token from environment
  const apiEndpoint = process.env.MEDINA_API_ENDPOINT || 'http://localhost:5001/medinaintelligence/us-central1/chat';
  const authToken = process.env.MEDINA_AUTH_TOKEN || '';

  if (!authToken) {
    console.error('Error: MEDINA_AUTH_TOKEN environment variable is required');
    console.error('Usage: MEDINA_AUTH_TOKEN=<token> npx ts-node src/evaluation/runner.ts --model gpt-4o-mini');
    process.exit(1);
  }

  console.log(`\n========================================`);
  console.log(`Medina AI Evaluation Suite v253`);
  console.log(`========================================`);
  console.log(`Model: ${model}`);
  console.log(`Endpoint: ${apiEndpoint}`);
  console.log(`========================================\n`);

  try {
    const summary = await runEvaluation(model, apiEndpoint, authToken, {
      delayBetweenTests: 2000, // 2s delay to avoid rate limiting
    });

    console.log(`\n========================================`);
    console.log(`EVALUATION COMPLETE`);
    console.log(`========================================`);
    console.log(`Total Tests: ${summary.totalTests}`);
    console.log(`----------------------------------------`);
    console.log(`v252 MULTI-DIMENSIONAL SCORES:`);
    console.log(`  Tool Accuracy Rate:    ${(summary.toolAccuracyRate * 100).toFixed(0)}%`);
    console.log(`  Intent Detection Rate: ${(summary.intentDetectionRate * 100).toFixed(0)}%`);
    console.log(`  Combined Score:        ${(summary.combinedScore * 100).toFixed(0)}%`);
    console.log(`----------------------------------------`);
    console.log(`Legacy: Tool Calling Accuracy: ${(summary.toolCallingAccuracy * 100).toFixed(0)}%`);
    console.log(`LLM Overall Score: ${summary.llmOverallScore.toFixed(1)}/5`);
    console.log(`Total Cost: $${summary.totalCost.toFixed(4)}`);
    console.log(`Avg Response Time: ${summary.avgTotalResponseTime.toFixed(0)}ms`);
    console.log(`========================================`);

    // v251: Show latency by category
    console.log(`\nLATENCY BY CATEGORY:`);
    console.log(`----------------------------------------`);
    const { basic, tool_call } = summary.latencyByCategory;
    console.log(`Basic Queries (${basic.count} tests):`);
    console.log(`  Avg: ${basic.avgResponseTime}ms, P95: ${basic.p95ResponseTime}ms`);
    console.log(`  Min: ${basic.minResponseTime}ms, Max: ${basic.maxResponseTime}ms`);
    console.log(`  Outliers (>${basic.outlierThreshold}ms): ${basic.outlierCount}`);
    console.log(`Tool Calls (${tool_call.count} tests):`);
    console.log(`  Avg: ${tool_call.avgResponseTime}ms, P95: ${tool_call.p95ResponseTime}ms`);
    console.log(`  Min: ${tool_call.minResponseTime}ms, Max: ${tool_call.maxResponseTime}ms`);
    console.log(`  Outliers (>${tool_call.outlierThreshold}ms): ${tool_call.outlierCount}`);
    console.log(`========================================\n`);

    // Save results to JSON
    const fs = await import('fs');
    const filename = `results-${model}-${Date.now()}.json`;
    fs.writeFileSync(filename, JSON.stringify(summary, null, 2));
    console.log(`Results saved to: ${filename}`);

  } catch (error) {
    console.error('Evaluation failed:', error);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}
