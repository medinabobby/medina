#!/usr/bin/env npx ts-node
/**
 * AI Model Evaluation CLI
 *
 * v243: Command-line interface for running evaluations.
 *
 * Usage:
 *   # Run evaluation against a model
 *   npx ts-node src/evaluation/cli.ts run --model gpt-4o-mini --endpoint https://your-endpoint
 *
 *   # Compare two saved results
 *   npx ts-node src/evaluation/cli.ts compare --baseline results-gpt-4o-mini.json --comparison results-gpt-4o.json
 *
 *   # Generate memo from comparison
 *   npx ts-node src/evaluation/cli.ts memo --baseline results-gpt-4o-mini.json --comparison results-gpt-4o.json
 */

import * as fs from 'fs';
import { runEvaluation, compareEvaluations, EvalSummary } from './runner';
import { generateExecutiveMemo, generateSingleModelSummary } from './memo';
import { getTestSuiteSummary, TestCase, getTierSummary, getTestsByTier } from './testSuite';
import { runRegressionCheck, formatRegressionReportMarkdown } from './regression';

// Parse command line arguments
const args = process.argv.slice(2);
const command = args[0];

function getArg(name: string): string | undefined {
  const index = args.indexOf(`--${name}`);
  if (index === -1 || index + 1 >= args.length) return undefined;
  return args[index + 1];
}

// v264: Get all values for repeatable arguments (--category, --exclude, --test)
function getAllArgs(name: string): string[] {
  const values: string[] = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === `--${name}` && i + 1 < args.length) {
      values.push(args[i + 1]);
    }
  }
  return values;
}

function printUsage() {
  console.log(`
AI Model Evaluation CLI

Commands:
  info                         Show test suite summary
  run                          Run evaluation against a model
  compare                      Compare two saved results
  memo                         Generate executive memo
  regression                   Check for regressions against baseline

Options for 'run':
  --model <name>               Model to test (gpt-4o-mini, gpt-4o, etc.)
  --endpoint <url>             API endpoint URL
  --token <token>              Auth token (or set EVAL_AUTH_TOKEN env var)
  --output <file>              Output JSON file (default: results-{model}.json)
  --delay <ms>                 Delay between tests (default: 1000)
  --category <name>            Run only tests in category (can repeat)
  --exclude <name>             Exclude category from run (can repeat)
  --test <id>                  Run only specific test IDs (can repeat)
  --tier <1|2|3>               v265: Run only tests in tier (1=Core, 2=Interpret, 3=Ambiguous)

Options for 'compare' and 'memo':
  --baseline <file>            Baseline results JSON file
  --comparison <file>          Comparison results JSON file
  --output <file>              Output file (default: stdout for memo)

Options for 'regression':
  --current <file>             Current results JSON file
  --baseline <file>            Baseline results (default: v252)
  --previous <file>            Previous version results (optional)

Examples:
  npx ts-node src/evaluation/cli.ts info
  npx ts-node src/evaluation/cli.ts run --model gpt-4o-mini --endpoint https://us-central1-medina-ai.cloudfunctions.net/chat
  npx ts-node src/evaluation/cli.ts memo --baseline results-gpt-4o-mini.json --comparison results-gpt-4o.json > memo.md
  npx ts-node src/evaluation/cli.ts regression --current results-v264.json --baseline results-v252.json
`);
}

async function main() {
  if (!command || command === 'help' || command === '--help') {
    printUsage();
    process.exit(0);
  }

  switch (command) {
    case 'info': {
      const summary = getTestSuiteSummary();
      const tierSummary = getTierSummary();
      console.log('\n📋 Test Suite Summary\n');
      console.log(`Total tests: ${summary.total}`);
      console.log('\nBy category:');
      for (const [category, count] of Object.entries(summary.byCategory)) {
        console.log(`  ${category}: ${count}`);
      }
      console.log('\nBy latency category:');
      for (const [category, count] of Object.entries(summary.byLatencyCategory)) {
        console.log(`  ${category}: ${count}`);
      }
      // v265: Show tier breakdown
      console.log('\nBy tier (v265):');
      console.log(`  Tier 1 (Core):          ${tierSummary.tier1} tests - Medina terminology, must pass`);
      console.log(`  Tier 2 (Interpretation): ${tierSummary.tier2} tests - Varied language, clarify OK`);
      console.log(`  Tier 3 (Ambiguous):      ${tierSummary.tier3} tests - Clarification preferred`);
      console.log('');
      break;
    }

    case 'run': {
      const model = getArg('model');
      const endpoint = getArg('endpoint');
      const token = getArg('token') || process.env.EVAL_AUTH_TOKEN;
      const output = getArg('output') || `results-${model}.json`;
      const delay = parseInt(getArg('delay') || '1000', 10);

      // v264: Category filtering
      const includeCategories = getAllArgs('category') as TestCase['category'][];
      const excludeCategories = getAllArgs('exclude') as TestCase['category'][];
      let testIds = getAllArgs('test');

      // v265: Tier filtering
      const tierArg = getArg('tier');
      if (tierArg) {
        const tier = parseInt(tierArg, 10) as 1 | 2 | 3;
        if (![1, 2, 3].includes(tier)) {
          console.error('Error: --tier must be 1, 2, or 3');
          process.exit(1);
        }
        // Get test IDs for this tier
        const tierTests = getTestsByTier(tier);
        const tierTestIds = tierTests.map(t => t.id);
        // If testIds already specified, intersect with tier tests
        if (testIds.length > 0) {
          testIds = testIds.filter(id => tierTestIds.includes(id));
        } else {
          testIds = tierTestIds;
        }
        console.log(`   Tier ${tier} filter: ${tierTestIds.length} tests`);
      }

      if (!model) {
        console.error('Error: --model is required');
        process.exit(1);
      }
      if (!endpoint) {
        console.error('Error: --endpoint is required');
        process.exit(1);
      }
      if (!token) {
        console.error('Error: --token is required (or set EVAL_AUTH_TOKEN env var)');
        process.exit(1);
      }

      console.log(`\n🚀 Running evaluation`);
      console.log(`   Model: ${model}`);
      console.log(`   Endpoint: ${endpoint}`);
      console.log(`   Output: ${output}`);
      console.log(`   Delay: ${delay}ms`);
      if (includeCategories.length > 0) {
        console.log(`   Categories: ${includeCategories.join(', ')}`);
      }
      if (excludeCategories.length > 0) {
        console.log(`   Excluding: ${excludeCategories.join(', ')}`);
      }
      if (testIds.length > 0) {
        console.log(`   Tests: ${testIds.join(', ')}`);
      }
      console.log('');

      const results = await runEvaluation(model, endpoint, token, {
        delayBetweenTests: delay,
        categories: includeCategories.length > 0 ? includeCategories : undefined,
        excludeCategories: excludeCategories.length > 0 ? excludeCategories : undefined,
        testIds: testIds.length > 0 ? testIds : undefined,
      });

      // Save results
      fs.writeFileSync(output, JSON.stringify(results, null, 2));
      console.log(`\n✅ Results saved to ${output}`);

      // Print summary
      console.log('\n📊 Summary:');
      console.log('   ----------------------------------------');
      console.log('   v260 MULTI-DIMENSIONAL SCORES:');
      console.log(`   Tool Accuracy Rate:    ${(results.toolAccuracyRate * 100).toFixed(0)}%`);
      console.log(`   Intent Detection Rate: ${(results.intentDetectionRate * 100).toFixed(0)}%`);
      console.log(`   Combined Score:        ${(results.combinedScore * 100).toFixed(0)}%`);
      console.log('   ----------------------------------------');
      console.log('   v260 PROTOCOL/EXERCISE ACCURACY:');
      console.log(`   Protocol Accuracy:     ${(results.protocolAccuracyRate * 100).toFixed(0)}%`);
      console.log(`   Exercise Accuracy:     ${(results.exerciseAccuracyRate * 100).toFixed(0)}%`);
      console.log('   ----------------------------------------');
      console.log(`   Legacy Tool Calling Accuracy: ${(results.toolCallingAccuracy * 100).toFixed(0)}%`);
      console.log(`   Fitness Accuracy: ${(results.fitnessAccuracyScore * 100).toFixed(0)}%`);
      console.log(`   Tone Score: ${(results.toneScore * 100).toFixed(0)}%`);
      console.log(`   Speed Pass Rate: ${(results.speedPassRate * 100).toFixed(0)}%`);
      console.log(`   Avg Response Time: ${results.avgTotalResponseTime.toFixed(0)}ms`);
      console.log(`   Total Cost: $${results.totalCost.toFixed(4)}`);

      // v265: Show tier metrics (PRIMARY QUALITY INDICATOR)
      if (results.tierMetrics) {
        console.log('   ----------------------------------------');
        console.log('   v265 TIER METRICS (Primary Quality):');
        const tm = results.tierMetrics;
        console.log(`   Tier 1 (Core):     ${tm.tier1.passed}/${tm.tier1.total} (${(tm.tier1.rate * 100).toFixed(0)}%) ← MUST PASS`);
        console.log(`   Tier 2 (Interpret): ${tm.tier2.passed}/${tm.tier2.total} (${(tm.tier2.rate * 100).toFixed(0)}%)`);
        console.log(`   Tier 3 (Ambiguous): ${tm.tier3.passed}/${tm.tier3.total} (${(tm.tier3.rate * 100).toFixed(0)}%)`);

        // List Tier 1 failures
        const tier1Failures = results.results.filter(r => r.tier === 1 && r.toolAccuracy === 'fail');
        if (tier1Failures.length > 0) {
          console.log(`\n   ⚠️  Tier 1 FAILURES (Bugs): ${tier1Failures.map(r => r.testId).join(', ')}`);
        }
      }

      // v251: Show latency by category
      console.log('\n⏱️  Latency by Category:');
      const { basic, tool_call } = results.latencyByCategory;
      console.log(`   Basic Queries (${basic.count} tests): avg ${basic.avgResponseTime}ms, p95 ${basic.p95ResponseTime}ms, ${basic.outlierCount} outliers`);
      console.log(`   Tool Calls (${tool_call.count} tests): avg ${tool_call.avgResponseTime}ms, p95 ${tool_call.p95ResponseTime}ms, ${tool_call.outlierCount} outliers`);
      console.log('');
      break;
    }

    case 'compare': {
      const baselineFile = getArg('baseline');
      const comparisonFile = getArg('comparison');

      if (!baselineFile || !comparisonFile) {
        console.error('Error: --baseline and --comparison are required');
        process.exit(1);
      }

      const baseline: EvalSummary = JSON.parse(fs.readFileSync(baselineFile, 'utf-8'));
      const comparison: EvalSummary = JSON.parse(fs.readFileSync(comparisonFile, 'utf-8'));

      const comp = compareEvaluations(baseline, comparison);

      console.log(`\n📊 Comparison: ${baseline.model} vs ${comparison.model}\n`);
      console.log('v252 Multi-Dimensional Deltas:');
      console.log(`   Tool Accuracy Rate:    ${(comp.deltas.toolAccuracyRate * 100).toFixed(1)}%`);
      console.log(`   Intent Detection Rate: ${(comp.deltas.intentDetectionRate * 100).toFixed(1)}%`);
      console.log(`   Combined Score:        ${(comp.deltas.combinedScore * 100).toFixed(1)}%`);
      console.log('Legacy Deltas:');
      console.log(`   Tool Calling: ${(comp.deltas.toolCallingAccuracy * 100).toFixed(1)}%`);
      console.log(`   Fitness Accuracy: ${(comp.deltas.fitnessAccuracyScore * 100).toFixed(1)}%`);
      console.log(`   Tone Score: ${(comp.deltas.toneScore * 100).toFixed(1)}%`);
      console.log(`   Speed Pass Rate: ${(comp.deltas.speedPassRate * 100).toFixed(1)}%`);
      console.log(`   Response Time: ${comp.deltas.avgResponseTime.toFixed(0)}ms`);
      console.log(`   Cost per Request: $${comp.deltas.avgCostPerRequest.toFixed(6)}`);

      // v259: Vision-specific comparison
      console.log('\n=== VISION IMPORT METRICS (v259) ===');
      const baseVision = baseline.latencyByCategory?.vision;
      const compVision = comparison.latencyByCategory?.vision;
      if (baseVision && compVision) {
        console.log(`   ${baseline.model.padEnd(15)} | ${comparison.model}`);
        console.log(`   Avg Latency:  ${baseVision.avgResponseTime.toFixed(0)}ms       | ${compVision.avgResponseTime.toFixed(0)}ms`);
        console.log(`   P95 Latency:  ${baseVision.p95ResponseTime.toFixed(0)}ms       | ${compVision.p95ResponseTime.toFixed(0)}ms`);
        console.log(`   Test Count:   ${baseVision.count}            | ${compVision.count}`);
      }

      // Show vision test side-by-side results
      const visionTests = comp.sideBySide.filter(s =>
        s.baseline.testType === 'vision' || s.testId.startsWith('VIS') || s.testId.startsWith('IM')
      );
      if (visionTests.length > 0) {
        console.log('\n   Vision Test Results:');
        console.log('   ID     | Intent          | ' + baseline.model.substring(0, 10) + ' | ' + comparison.model.substring(0, 10));
        console.log('   -------|-----------------|----------|----------');
        for (const test of visionTests) {
          const bTool = test.baseline.toolCalled || 'none';
          const bPass = test.baseline.toolCalledCorrectly ? '✅' : '❌';
          const cPass = test.comparison.toolCalledCorrectly ? '✅' : '❌';
          console.log(`   ${test.testId.padEnd(6)} | ${bTool.substring(0, 15).padEnd(15)} | ${bPass}        | ${cPass}`);
        }
      }

      console.log('');
      break;
    }

    case 'memo': {
      const baselineFile = getArg('baseline');
      const comparisonFile = getArg('comparison');
      const outputFile = getArg('output');

      if (!baselineFile || !comparisonFile) {
        console.error('Error: --baseline and --comparison are required');
        process.exit(1);
      }

      const baseline: EvalSummary = JSON.parse(fs.readFileSync(baselineFile, 'utf-8'));
      const comparison: EvalSummary = JSON.parse(fs.readFileSync(comparisonFile, 'utf-8'));

      const memo = generateExecutiveMemo(baseline, comparison);

      if (outputFile) {
        fs.writeFileSync(outputFile, memo);
        console.log(`✅ Memo saved to ${outputFile}`);
      } else {
        console.log(memo);
      }
      break;
    }

    case 'summary': {
      const inputFile = getArg('input');
      if (!inputFile) {
        console.error('Error: --input is required');
        process.exit(1);
      }

      const summary: EvalSummary = JSON.parse(fs.readFileSync(inputFile, 'utf-8'));
      console.log(generateSingleModelSummary(summary));
      break;
    }

    case 'regression': {
      const currentFile = getArg('current');
      const baselineFile = getArg('baseline');
      const previousFile = getArg('previous');
      const outputFile = getArg('output');

      if (!currentFile || !baselineFile) {
        console.error('Error: --current and --baseline are required');
        process.exit(1);
      }

      console.log(`\n📊 Running regression check...`);
      console.log(`   Current: ${currentFile}`);
      console.log(`   Baseline: ${baselineFile}`);
      if (previousFile) {
        console.log(`   Previous: ${previousFile}`);
      }
      console.log('');

      const report = runRegressionCheck(currentFile, baselineFile, previousFile);
      const markdown = formatRegressionReportMarkdown(report);

      if (outputFile) {
        fs.writeFileSync(outputFile, markdown);
        console.log(`✅ Report saved to ${outputFile}`);
      } else {
        console.log(markdown);
      }

      // Exit with error code if there are critical alerts
      const criticalAlerts = report.alerts.filter(a => a.severity === 'critical');
      if (criticalAlerts.length > 0) {
        console.log(`\n🔴 ${criticalAlerts.length} critical regression(s) detected!`);
        process.exit(1);
      }
      break;
    }

    default:
      console.error(`Unknown command: ${command}`);
      printUsage();
      process.exit(1);
  }
}

main().catch((error) => {
  console.error('Error:', error);
  process.exit(1);
});
