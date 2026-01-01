/**
 * Executive Memo Generator
 *
 * v246: Generates markdown executive summary with LLM evaluation feedback.
 */

import { EvalSummary, EvalResult, compareEvaluations } from './runner';

/**
 * Format percentage with sign
 */
function formatDelta(value: number, isPercent = true): string {
  const formatted = isPercent
    ? `${(value * 100).toFixed(1)}%`
    : value.toFixed(2);

  if (value > 0) return `+${formatted}`;
  if (value < 0) return formatted;
  return formatted;
}

/**
 * Format cost
 */
function formatCost(value: number): string {
  if (value < 0.01) return `$${value.toFixed(6)}`;
  return `$${value.toFixed(4)}`;
}

/**
 * Get recommendation based on comparison
 */
function getRecommendation(
  baseline: EvalSummary,
  comparison: EvalSummary
): {
  decision: 'KEEP' | 'UPGRADE' | 'TEST_MORE';
  rationale: string[];
  nextSteps: string[];
} {
  const toolDelta = comparison.toolCallingAccuracy - baseline.toolCallingAccuracy;
  const fitnessDelta = comparison.fitnessAccuracyScore - baseline.fitnessAccuracyScore;
  const costMultiplier = comparison.avgCostPerRequest / baseline.avgCostPerRequest;

  const rationale: string[] = [];
  const nextSteps: string[] = [];

  // Significant quality improvement with reasonable cost?
  if (toolDelta >= 0.1 || fitnessDelta >= 0.1) {
    rationale.push(`Quality improvement: Tool accuracy ${formatDelta(toolDelta)}, Fitness accuracy ${formatDelta(fitnessDelta)}`);

    if (costMultiplier <= 20) {
      rationale.push(`Cost increase (${costMultiplier.toFixed(0)}x) is acceptable for quality gains`);
      nextSteps.push(`Deploy ${comparison.model} to production`);
      nextSteps.push(`Monitor costs for 2 weeks`);
      nextSteps.push(`Set up cost alerts at 150% of projected`);
      return { decision: 'UPGRADE', rationale, nextSteps };
    } else {
      rationale.push(`Cost increase (${costMultiplier.toFixed(0)}x) is significant`);
      nextSteps.push(`Consider testing Claude 3.5 Haiku (similar quality, lower cost)`);
      nextSteps.push(`Review if premium quality justifies premium price`);
      return { decision: 'TEST_MORE', rationale, nextSteps };
    }
  }

  // Marginal improvement?
  if (toolDelta >= 0.05 || fitnessDelta >= 0.05) {
    rationale.push(`Marginal improvement: Tool accuracy ${formatDelta(toolDelta)}, Fitness accuracy ${formatDelta(fitnessDelta)}`);
    rationale.push(`Cost increase (${costMultiplier.toFixed(0)}x) may not be justified`);
    nextSteps.push(`Consider prompt improvements first (FREE)`);
    nextSteps.push(`Re-evaluate after prompt optimization`);
    return { decision: 'KEEP', rationale, nextSteps };
  }

  // No significant improvement
  rationale.push(`No significant quality improvement detected`);
  rationale.push(`Tool accuracy: ${formatDelta(toolDelta)}, Fitness accuracy: ${formatDelta(fitnessDelta)}`);
  nextSteps.push(`Keep current model (${baseline.model})`);
  nextSteps.push(`Focus on prompt improvements`);
  nextSteps.push(`Consider testing alternative models (Claude, Grok)`);
  return { decision: 'KEEP', rationale, nextSteps };
}

/**
 * Generate executive memo markdown
 */
export function generateExecutiveMemo(
  baseline: EvalSummary,
  comparison: EvalSummary,
  options?: {
    dailyRequests?: number;
  }
): string {
  const { dailyRequests = 1000 } = options || {};

  const comp = compareEvaluations(baseline, comparison);
  const recommendation = getRecommendation(baseline, comparison);

  // Calculate cost projections
  const baselineMonthly = baseline.avgCostPerRequest * dailyRequests * 30;
  const comparisonMonthly = comparison.avgCostPerRequest * dailyRequests * 30;

  // Find interesting side-by-side examples
  const interestingExamples = comp.sideBySide.filter(s =>
    s.baseline.toolCalledCorrectly !== s.comparison.toolCalledCorrectly ||
    Math.abs(s.baseline.topicScore - s.comparison.topicScore) > 0.3 ||
    Math.abs(s.baseline.totalResponseTime - s.comparison.totalResponseTime) > 1000
  ).slice(0, 3);

  let memo = `# AI Model Evaluation - Executive Summary

**Date:** ${new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}
**Models Tested:** ${baseline.model} (baseline) vs ${comparison.model}
**Test Cases:** ${baseline.totalTests}

---

## Key Findings

### Basic Metrics

| Metric | ${baseline.model} | ${comparison.model} | Delta |
|--------|-------------------|---------------------|-------|
| Tool Calling Accuracy | ${(baseline.toolCallingAccuracy * 100).toFixed(0)}% | ${(comparison.toolCallingAccuracy * 100).toFixed(0)}% | ${formatDelta(comp.deltas.toolCallingAccuracy)} |
| Fitness Accuracy Score | ${(baseline.fitnessAccuracyScore * 100).toFixed(0)}% | ${(comparison.fitnessAccuracyScore * 100).toFixed(0)}% | ${formatDelta(comp.deltas.fitnessAccuracyScore)} |
| Tone Score | ${(baseline.toneScore * 100).toFixed(0)}% | ${(comparison.toneScore * 100).toFixed(0)}% | ${formatDelta(comp.deltas.toneScore)} |
| Speed Pass Rate | ${(baseline.speedPassRate * 100).toFixed(0)}% | ${(comparison.speedPassRate * 100).toFixed(0)}% | ${formatDelta(comp.deltas.speedPassRate)} |
| Avg Response Time | ${baseline.avgTotalResponseTime.toFixed(0)}ms | ${comparison.avgTotalResponseTime.toFixed(0)}ms | ${formatDelta(comp.deltas.avgResponseTime, false)}ms |
| Avg Cost per Request | ${formatCost(baseline.avgCostPerRequest)} | ${formatCost(comparison.avgCostPerRequest)} | ${formatDelta(comp.deltas.avgCostPerRequest, false)} |

### LLM-as-Judge Scores (1-5 scale)

| Dimension | ${baseline.model} | ${comparison.model} | Delta |
|-----------|-------------------|---------------------|-------|
| Tool Appropriateness | ${baseline.llmToolScore.toFixed(1)} | ${comparison.llmToolScore.toFixed(1)} | ${formatDelta(comp.deltas.llmToolScore, false)} |
| Fitness Accuracy | ${baseline.llmAccuracyScore.toFixed(1)} | ${comparison.llmAccuracyScore.toFixed(1)} | ${formatDelta(comp.deltas.llmAccuracyScore, false)} |
| Tone & Style | ${baseline.llmToneScore.toFixed(1)} | ${comparison.llmToneScore.toFixed(1)} | ${formatDelta(comp.deltas.llmToneScore, false)} |
| **Overall** | **${baseline.llmOverallScore.toFixed(1)}** | **${comparison.llmOverallScore.toFixed(1)}** | **${formatDelta(comp.deltas.llmOverallScore, false)}** |

---

## Cost Projection (${dailyRequests.toLocaleString()} requests/day)

| Model | Monthly Cost | Annual Cost |
|-------|--------------|-------------|
| ${baseline.model} | $${baselineMonthly.toFixed(0)} | $${(baselineMonthly * 12).toFixed(0)} |
| ${comparison.model} | $${comparisonMonthly.toFixed(0)} | $${(comparisonMonthly * 12).toFixed(0)} |
| **Difference** | +$${(comparisonMonthly - baselineMonthly).toFixed(0)}/mo | +$${((comparisonMonthly - baselineMonthly) * 12).toFixed(0)}/yr |

---

`;

  // Side-by-side examples
  if (interestingExamples.length > 0) {
    memo += `## Side-by-Side Examples

`;

    for (const example of interestingExamples) {
      const baseEval = example.baseline.llmEvaluation;
      const compEval = example.comparison.llmEvaluation;

      memo += `### ${example.testId}: "${example.prompt}"

| | ${baseline.model} | ${comparison.model} |
|-|-------------------|---------------------|
| Tool Called | ${example.baseline.toolCalled || 'none'} ${example.baseline.toolCalledCorrectly ? '✅' : '❌'} | ${example.comparison.toolCalled || 'none'} ${example.comparison.toolCalledCorrectly ? '✅' : '❌'} |
| Response Time | ${example.baseline.totalResponseTime}ms | ${example.comparison.totalResponseTime}ms |
| LLM Overall Score | ${baseEval?.overallScore || 'N/A'}/5 | ${compEval?.overallScore || 'N/A'}/5 |

**${baseline.model} Response:** ${example.baseline.responseText?.slice(0, 150) || example.baseline.response.slice(0, 150)}...

${baseEval ? `> **GPT-4 Feedback:** ${baseEval.summary}` : ''}

**${comparison.model} Response:** ${example.comparison.responseText?.slice(0, 150) || example.comparison.response.slice(0, 150)}...

${compEval ? `> **GPT-4 Feedback:** ${compEval.summary}` : ''}

`;
    }
  }

  // Recommendation
  memo += `---

## Recommendation

**${recommendation.decision === 'UPGRADE' ? '✅ UPGRADE' : recommendation.decision === 'KEEP' ? '⏸️ KEEP CURRENT' : '🔍 TEST MORE'}**

### Rationale
${recommendation.rationale.map(r => `- ${r}`).join('\n')}

### Next Steps
${recommendation.nextSteps.map((s, i) => `${i + 1}. ${s}`).join('\n')}

---

## Detailed Results

### Tool Calling Tests (${comp.sideBySide.filter(s => s.baseline.category === 'tool_calling').length} tests)

| Test ID | Prompt | ${baseline.model} | ${comparison.model} |
|---------|--------|-------------------|---------------------|
${comp.sideBySide
  .filter(s => s.baseline.category === 'tool_calling')
  .map(s => `| ${s.testId} | ${s.prompt.slice(0, 40)}... | ${s.baseline.toolCalled || 'none'} ${s.baseline.toolCalledCorrectly ? '✅' : '❌'} | ${s.comparison.toolCalled || 'none'} ${s.comparison.toolCalledCorrectly ? '✅' : '❌'} |`)
  .join('\n')}

### Fitness Accuracy Tests (${comp.sideBySide.filter(s => s.baseline.category === 'fitness_accuracy').length} tests)

| Test ID | Prompt | ${baseline.model} | ${comparison.model} |
|---------|--------|-------------------|---------------------|
${comp.sideBySide
  .filter(s => s.baseline.category === 'fitness_accuracy')
  .map(s => `| ${s.testId} | ${s.prompt.slice(0, 40)}... | ${(s.baseline.topicScore * 100).toFixed(0)}% | ${(s.comparison.topicScore * 100).toFixed(0)}% |`)
  .join('\n')}

---

*Generated by Medina AI Evaluation Suite v246*
`;

  return memo;
}

/**
 * Format LLM feedback for a result
 */
function formatLLMFeedback(result: EvalResult): string {
  if (!result.llmEvaluation) return '';

  const e = result.llmEvaluation;
  return `
  - **Tool**: ${e.toolScore}/5 - ${e.toolFeedback}
  - **Accuracy**: ${e.accuracyScore}/5 - ${e.accuracyFeedback}
  - **Tone**: ${e.toneScore}/5 - ${e.toneFeedback}
  - **Overall**: ${e.overallScore}/5 - ${e.summary}`;
}

/**
 * Generate summary for single model evaluation
 */
export function generateSingleModelSummary(summary: EvalSummary): string {
  // Get notable feedback (best and worst)
  const resultsWithLLM = summary.results.filter(r => r.llmEvaluation);
  const sortedByScore = [...resultsWithLLM].sort(
    (a, b) => (b.llmEvaluation?.overallScore || 0) - (a.llmEvaluation?.overallScore || 0)
  );
  const bestResponses = sortedByScore.slice(0, 3);
  const worstResponses = sortedByScore.slice(-3).reverse();

  return `# ${summary.model} Evaluation Summary

**Date:** ${new Date(summary.timestamp).toLocaleDateString()}
**Tests Run:** ${summary.totalTests}

## Basic Scores

| Metric | Score |
|--------|-------|
| Tool Calling Accuracy | ${(summary.toolCallingAccuracy * 100).toFixed(0)}% |
| Fitness Accuracy | ${(summary.fitnessAccuracyScore * 100).toFixed(0)}% |
| Tone Score | ${(summary.toneScore * 100).toFixed(0)}% |
| Speed Pass Rate | ${(summary.speedPassRate * 100).toFixed(0)}% |

## LLM-as-Judge Scores (1-5 scale)

| Dimension | Average Score |
|-----------|---------------|
| Tool Appropriateness | ${summary.llmToolScore.toFixed(1)} |
| Fitness Accuracy | ${summary.llmAccuracyScore.toFixed(1)} |
| Tone & Style | ${summary.llmToneScore.toFixed(1)} |
| Completeness | ${summary.llmCompletenessScore.toFixed(1)} |
| Safety | ${summary.llmSafetyScore.toFixed(1)} |
| **Overall** | **${summary.llmOverallScore.toFixed(1)}** |

## Performance

| Metric | Value |
|--------|-------|
| Avg Time to First Token | ${summary.avgTimeToFirstToken.toFixed(0)}ms |
| Avg Total Response Time | ${summary.avgTotalResponseTime.toFixed(0)}ms |
| Total Input Tokens | ${summary.totalInputTokens.toLocaleString()} |
| Total Output Tokens | ${summary.totalOutputTokens.toLocaleString()} |
| Total Cost | ${formatCost(summary.totalCost)} |
| Avg Cost per Request | ${formatCost(summary.avgCostPerRequest)} |

## Best Responses (GPT-4 Feedback)

${bestResponses.map(r => `### ${r.testId}: "${r.prompt}"
${formatLLMFeedback(r)}
`).join('\n')}

## Areas for Improvement (GPT-4 Feedback)

${worstResponses.map(r => `### ${r.testId}: "${r.prompt}"
${formatLLMFeedback(r)}
`).join('\n')}

## Failed Tests

${summary.results
  .filter(r => !r.toolCalledCorrectly || r.topicScore < 0.5 || r.error)
  .map(r => `- **${r.testId}**: ${r.error || (r.toolCalledCorrectly ? `Low topic score (${(r.topicScore * 100).toFixed(0)}%)` : `Wrong tool called (${r.toolCalled || 'none'} instead of expected)`)}`)
  .join('\n') || 'None - all tests passed!'}

---
*Generated by Medina AI Evaluation Suite v246*
`;
}

/**
 * Save results to JSON file
 */
export function saveResultsToJSON(summary: EvalSummary, filename: string): string {
  const json = JSON.stringify(summary, null, 2);
  // In real implementation, write to file
  console.log(`Would save to ${filename}:`);
  console.log(json.slice(0, 500) + '...');
  return json;
}
