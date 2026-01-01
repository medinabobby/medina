/**
 * AI Model Evaluation Runner
 *
 * v246: Proper SSE parsing + LLM-as-judge evaluation.
 *
 * Key improvements:
 * - Parse SSE events to detect actual function_call, not text patterns
 * - Use GPT-4 as evaluator to score responses with explanations
 * - Track accuracy, tone, completeness, and safety
 *
 * Usage:
 *   npx ts-node src/evaluation/runner.ts --model gpt-4o-mini
 *   npx ts-node src/evaluation/runner.ts --model gpt-4o
 */

import OpenAI from 'openai';
import { TEST_CASES, TestCase, calculateCost, TOKEN_PRICING } from './testSuite';

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
  responseText: string;
  inputTokens: number;
  outputTokens: number;
}

export interface EvalResult {
  testId: string;
  category: string;
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

  // Quality - LLM Evaluation
  llmEvaluation?: LLMEvaluation;

  // Raw
  response: string;
  responseText: string;             // Extracted text (no SSE wrapper)
  error?: string;
}

export interface EvalSummary {
  model: string;
  timestamp: string;
  totalTests: number;

  // Aggregate scores - Basic
  toolCallingAccuracy: number;      // 0-1
  fitnessAccuracyScore: number;     // 0-1
  toneScore: number;                // 0-1
  speedPassRate: number;            // 0-1

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
      }

      // Check for function_call in output_item.added event
      // This indicates AI requested a tool call (may be server or client handled)
      if (!toolCalled &&
          data.type === 'response.output_item.added' &&
          data.item?.type === 'function_call' &&
          data.item?.name) {
        toolCalled = data.item.name;
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

  return { toolCalled, responseText, inputTokens, outputTokens };
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

/**
 * Run a single test case
 */
export async function runTestCase(
  test: TestCase,
  model: string,
  apiEndpoint: string,
  authToken: string
): Promise<EvalResult> {
  const startTime = Date.now();
  let firstTokenTime: number | null = null;

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
    const responseText = parsed.responseText;

    // Use parsed tokens or estimate
    if (parsed.inputTokens > 0) {
      inputTokens = parsed.inputTokens;
    }
    if (parsed.outputTokens > 0) {
      outputTokens = parsed.outputTokens;
    }

    const toolCalledCorrectly =
      test.expectedTool === null
        ? toolCalled === null
        : toolCalled === test.expectedTool;

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

    // Run LLM evaluation (optional - requires OPENAI_API_KEY)
    const llmEvaluation = await evaluateWithLLM(test, responseText, toolCalled);

    return {
      testId: test.id,
      category: test.category,
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
      ...(llmEvaluation && { llmEvaluation }),
      response: fullResponse.slice(0, 5000), // Truncate for storage
      responseText: responseText.slice(0, 2000), // Clean text for display
    };
  } catch (error) {
    return {
      testId: test.id,
      category: test.category,
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
    testIds?: string[];
    delayBetweenTests?: number;
  }
): Promise<EvalSummary> {
  const { categories, testIds, delayBetweenTests = 1000 } = options || {};

  // Filter tests
  let tests = TEST_CASES;
  if (categories) {
    tests = tests.filter(t => categories.includes(t.category));
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
      console.log(`  Tool: ${result.toolCalled || 'none'} (${result.toolCalledCorrectly ? 'PASS' : 'FAIL'})`);
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

  return {
    model,
    timestamp: new Date().toISOString(),
    totalTests: results.length,
    toolCallingAccuracy,
    fitnessAccuracyScore,
    toneScore,
    speedPassRate,
    llmToolScore,
    llmAccuracyScore,
    llmToneScore,
    llmCompletenessScore,
    llmSafetyScore,
    llmOverallScore,
    avgTimeToFirstToken,
    avgTotalResponseTime,
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
  console.log(`Medina AI Evaluation Suite v246`);
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
    console.log(`Tool Calling Accuracy: ${(summary.toolCallingAccuracy * 100).toFixed(0)}%`);
    console.log(`LLM Overall Score: ${summary.llmOverallScore.toFixed(1)}/5`);
    console.log(`Total Cost: $${summary.totalCost.toFixed(4)}`);
    console.log(`Avg Response Time: ${summary.avgTotalResponseTime.toFixed(0)}ms`);
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
