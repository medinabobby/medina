/**
 * Regression Tracking for AI Model Evaluation
 *
 * v265: Only alert on Tier 1 (Core) regressions - edge case noise ignored.
 * v264: Compare evaluation results across versions to detect regressions.
 *
 * Features:
 * - Compare against v252 baseline (first comprehensive test suite)
 * - v265: Only alert on Tier 1 regressions (not Tier 2/3 edge cases)
 * - Alert on Tier 1 drops >10% from previous version
 * - Alert on Tier 1 drops >20% from baseline
 * - Track score evolution over time
 *
 * Usage:
 *   npm run eval:diff v263 v264
 *   npm run eval:regression v264
 */

import * as fs from 'fs';
import { EvalSummary } from './runner';

// Baseline version for regression tracking
const BASELINE_VERSION = 'v252';

export interface RegressionAlert {
  category: string;
  metric: string;
  current: number;
  baseline: number;
  delta: number;
  severity: 'warning' | 'critical';
  message: string;
  tier?: 1 | 2 | 3;  // v265: Which tier this alert is for
}

export interface RegressionReport {
  currentVersion: string;
  baselineVersion: string;
  previousVersion?: string;
  timestamp: string;
  alerts: RegressionAlert[];
  categoryScores: {
    category: string;
    current: number;
    baseline: number;
    previous?: number;
    deltaToPrevious?: number;
    deltaToBaseline: number;
  }[];
  summary: {
    totalTests: number;
    regressions: number;
    improvements: number;
    stable: number;
  };
  // v265: Tier-based metrics (Tier 1 is primary)
  tierMetrics?: {
    tier1: { current: number; baseline: number; delta: number };
    tier2: { current: number; baseline: number; delta: number };
    tier3: { current: number; baseline: number; delta: number };
  };
}

/**
 * Calculate per-category scores from evaluation results
 */
function calculateCategoryScores(summary: EvalSummary): Map<string, number> {
  const categoryScores = new Map<string, number>();

  // Group results by category
  const resultsByCategory = new Map<string, typeof summary.results>();
  for (const result of summary.results) {
    if (!resultsByCategory.has(result.category)) {
      resultsByCategory.set(result.category, []);
    }
    resultsByCategory.get(result.category)!.push(result);
  }

  // Calculate scores per category
  Array.from(resultsByCategory.entries()).forEach(([category, results]) => {
    const passCount = results.filter(r => r.toolCalledCorrectly).length;
    const score = results.length > 0 ? passCount / results.length : 0;
    categoryScores.set(category, score);
  });

  return categoryScores;
}

/**
 * v265: Calculate tier-specific pass rate
 */
function calculateTierPassRate(summary: EvalSummary, tier: 1 | 2 | 3): number {
  const tierResults = summary.results.filter(r => r.tier === tier);
  if (tierResults.length === 0) return 1.0;
  return tierResults.filter(r => r.toolAccuracy === 'pass').length / tierResults.length;
}

/**
 * Generate regression report comparing current to baseline and optionally previous version
 *
 * v265: Only alerts on Tier 1 (Core) regressions - edge case noise is ignored
 */
export function generateRegressionReport(
  current: EvalSummary,
  baseline: EvalSummary,
  previous?: EvalSummary
): RegressionReport {
  const alerts: RegressionAlert[] = [];
  const categoryScores: RegressionReport['categoryScores'] = [];

  const currentScores = calculateCategoryScores(current);
  const baselineScores = calculateCategoryScores(baseline);
  const previousScores = previous ? calculateCategoryScores(previous) : undefined;

  // v265: Calculate tier-based metrics
  const currentTier1Rate = calculateTierPassRate(current, 1);
  const baselineTier1Rate = calculateTierPassRate(baseline, 1);
  const previousTier1Rate = previous ? calculateTierPassRate(previous, 1) : undefined;

  const tier1DeltaToBaseline = currentTier1Rate - baselineTier1Rate;
  const tier1DeltaToPrevious = previousTier1Rate !== undefined ? currentTier1Rate - previousTier1Rate : undefined;

  // v265: Only alert on Tier 1 regressions (not Tier 2/3 edge cases)
  // Critical: >20% drop from baseline
  if (tier1DeltaToBaseline < -0.20) {
    alerts.push({
      category: 'tier1_core',
      metric: 'tier1_pass_rate',
      current: currentTier1Rate,
      baseline: baselineTier1Rate,
      delta: tier1DeltaToBaseline,
      severity: 'critical',
      tier: 1,
      message: `Tier 1 (Core) dropped ${Math.abs(Math.round(tier1DeltaToBaseline * 100))}% from baseline (${Math.round(baselineTier1Rate * 100)}% → ${Math.round(currentTier1Rate * 100)}%) - THIS IS A BUG`,
    });
  }

  // Warning: >10% drop from previous
  if (tier1DeltaToPrevious !== undefined && tier1DeltaToPrevious < -0.10) {
    alerts.push({
      category: 'tier1_core',
      metric: 'tier1_pass_rate',
      current: currentTier1Rate,
      baseline: previousTier1Rate!,
      delta: tier1DeltaToPrevious,
      severity: 'warning',
      tier: 1,
      message: `Tier 1 (Core) dropped ${Math.abs(Math.round(tier1DeltaToPrevious * 100))}% from previous (${Math.round(previousTier1Rate! * 100)}% → ${Math.round(currentTier1Rate * 100)}%)`,
    });
  }

  // Check each category (for informational purposes, but don't alert on Tier 2/3)
  Array.from(currentScores.entries()).forEach(([category, currentScore]) => {
    const baselineScore = baselineScores.get(category);
    const previousScore = previousScores?.get(category);

    const deltaToBaseline = baselineScore !== undefined ? (currentScore - baselineScore) : 0;
    const deltaToPrevious = previousScore !== undefined ? (currentScore - previousScore) : undefined;

    categoryScores.push({
      category,
      current: Math.round(currentScore * 100),
      baseline: baselineScore !== undefined ? Math.round(baselineScore * 100) : 0,
      previous: previousScore !== undefined ? Math.round(previousScore * 100) : undefined,
      deltaToPrevious: deltaToPrevious !== undefined ? Math.round(deltaToPrevious * 100) : undefined,
      deltaToBaseline: Math.round(deltaToBaseline * 100),
    });

    // v265: Category-level alerts are now informational only, logged but not critical
    // Tier 1 alerts above are the primary regression signal
  });

  // Calculate summary
  let regressions = 0;
  let improvements = 0;
  let stable = 0;

  for (const score of categoryScores) {
    if (score.deltaToBaseline < -5) {
      regressions++;
    } else if (score.deltaToBaseline > 5) {
      improvements++;
    } else {
      stable++;
    }
  }

  // v265: Build tier metrics
  const tierMetrics = {
    tier1: {
      current: Math.round(currentTier1Rate * 100),
      baseline: Math.round(baselineTier1Rate * 100),
      delta: Math.round(tier1DeltaToBaseline * 100),
    },
    tier2: {
      current: Math.round(calculateTierPassRate(current, 2) * 100),
      baseline: Math.round(calculateTierPassRate(baseline, 2) * 100),
      delta: Math.round((calculateTierPassRate(current, 2) - calculateTierPassRate(baseline, 2)) * 100),
    },
    tier3: {
      current: Math.round(calculateTierPassRate(current, 3) * 100),
      baseline: Math.round(calculateTierPassRate(baseline, 3) * 100),
      delta: Math.round((calculateTierPassRate(current, 3) - calculateTierPassRate(baseline, 3)) * 100),
    },
  };

  return {
    currentVersion: extractVersionFromFilename(current) || 'current',
    baselineVersion: extractVersionFromFilename(baseline) || BASELINE_VERSION,
    previousVersion: previous ? extractVersionFromFilename(previous) : undefined,
    timestamp: new Date().toISOString(),
    alerts,
    categoryScores,
    summary: {
      totalTests: current.results.length,
      regressions,
      improvements,
      stable,
    },
    // v265: Tier-based metrics
    tierMetrics,
  };
}

/**
 * Extract version from filename (e.g., "results-gpt-4o-mini-v264.json" → "v264")
 */
function extractVersionFromFilename(summary: EvalSummary): string | undefined {
  // Look for version pattern in any string field or metadata
  // This is a heuristic - ideally version would be stored in the summary
  return undefined;
}

/**
 * Format regression report as markdown
 */
export function formatRegressionReportMarkdown(report: RegressionReport): string {
  let md = `# Regression Report\n\n`;
  md += `**Current:** ${report.currentVersion}\n`;
  md += `**Baseline:** ${report.baselineVersion}\n`;
  if (report.previousVersion) {
    md += `**Previous:** ${report.previousVersion}\n`;
  }
  md += `**Generated:** ${report.timestamp}\n\n`;

  // Alerts section
  if (report.alerts.length > 0) {
    md += `## Alerts\n\n`;
    for (const alert of report.alerts) {
      const icon = alert.severity === 'critical' ? '🔴' : '🟡';
      md += `${icon} **${alert.severity.toUpperCase()}**: ${alert.message}\n`;
    }
    md += '\n';
  } else {
    md += `## Alerts\n\n✅ No regressions detected.\n\n`;
  }

  // Category scores table
  md += `## Category Scores\n\n`;
  md += `| Category | Current | Baseline | Δ Baseline |`;
  if (report.previousVersion) {
    md += ` Previous | Δ Previous |`;
  }
  md += `\n`;

  md += `|----------|---------|----------|------------|`;
  if (report.previousVersion) {
    md += `----------|------------|`;
  }
  md += `\n`;

  for (const score of report.categoryScores) {
    const deltaBaselineStr = score.deltaToBaseline >= 0 ? `+${score.deltaToBaseline}%` : `${score.deltaToBaseline}%`;
    md += `| ${score.category} | ${score.current}% | ${score.baseline}% | ${deltaBaselineStr} |`;

    if (report.previousVersion && score.previous !== undefined && score.deltaToPrevious !== undefined) {
      const deltaPreviousStr = score.deltaToPrevious >= 0 ? `+${score.deltaToPrevious}%` : `${score.deltaToPrevious}%`;
      md += ` ${score.previous}% | ${deltaPreviousStr} |`;
    }
    md += `\n`;
  }

  md += `\n`;

  // v265: Tier Metrics (Primary quality indicator)
  if (report.tierMetrics) {
    md += `## Tier Metrics (v265)\n\n`;
    md += `**Tier 1 (Core)** is the primary quality metric. Alerts are only triggered for Tier 1 regressions.\n\n`;
    md += `| Tier | Current | Baseline | Δ | Notes |\n`;
    md += `|------|---------|----------|---|-------|\n`;
    const t1 = report.tierMetrics.tier1;
    const t2 = report.tierMetrics.tier2;
    const t3 = report.tierMetrics.tier3;
    const t1Delta = t1.delta >= 0 ? `+${t1.delta}%` : `${t1.delta}%`;
    const t2Delta = t2.delta >= 0 ? `+${t2.delta}%` : `${t2.delta}%`;
    const t3Delta = t3.delta >= 0 ? `+${t3.delta}%` : `${t3.delta}%`;
    md += `| **Tier 1 (Core)** | ${t1.current}% | ${t1.baseline}% | ${t1Delta} | Failures = bugs |\n`;
    md += `| Tier 2 (Interpret) | ${t2.current}% | ${t2.baseline}% | ${t2Delta} | Informational |\n`;
    md += `| Tier 3 (Ambiguous) | ${t3.current}% | ${t3.baseline}% | ${t3Delta} | Clarification OK |\n`;
    md += `\n`;
  }

  // Summary
  md += `## Summary\n\n`;
  md += `- **Total Tests:** ${report.summary.totalTests}\n`;
  md += `- **Regressions:** ${report.summary.regressions} categories\n`;
  md += `- **Improvements:** ${report.summary.improvements} categories\n`;
  md += `- **Stable:** ${report.summary.stable} categories\n`;

  return md;
}

/**
 * Load evaluation summary from JSON file
 */
export function loadEvalSummary(filepath: string): EvalSummary {
  const content = fs.readFileSync(filepath, 'utf-8');
  return JSON.parse(content);
}

/**
 * CLI helper to run regression check
 */
export function runRegressionCheck(
  currentFile: string,
  baselineFile: string,
  previousFile?: string
): RegressionReport {
  const current = loadEvalSummary(currentFile);
  const baseline = loadEvalSummary(baselineFile);
  const previous = previousFile ? loadEvalSummary(previousFile) : undefined;

  return generateRegressionReport(current, baseline, previous);
}
