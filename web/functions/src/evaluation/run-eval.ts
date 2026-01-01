/**
 * Run evaluation with Firebase authentication
 *
 * Usage: npx ts-node src/evaluation/run-eval.ts --model gpt-4o-mini
 */

import { runEvaluation } from './runner';
import { generateSingleModelSummary } from './memo';

const TEST_EMAIL = 'test@medinaintelligence.com';
const TEST_PASSWORD = 'TestUser2024!';
const FIREBASE_API_KEY = 'AIzaSyDtJOFTjww_JtkutjQzjWN55AmuR4tCwOY';

async function getAuthToken(): Promise<string> {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: TEST_EMAIL,
        password: TEST_PASSWORD,
        returnSecureToken: true,
      }),
    }
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Auth failed: ${error}`);
  }

  const data = await response.json();
  return data.idToken;
}

async function main() {
  const args = process.argv.slice(2);
  const modelIndex = args.indexOf('--model');
  const model = modelIndex >= 0 ? args[modelIndex + 1] : 'gpt-4o-mini';

  // Use production endpoint
  const apiEndpoint = 'https://us-central1-medinaintelligence.cloudfunctions.net/chat';

  console.log(`\n========================================`);
  console.log(`Medina AI Evaluation Suite v246`);
  console.log(`========================================`);
  console.log(`Model: ${model}`);
  console.log(`Endpoint: ${apiEndpoint}`);
  console.log(`========================================\n`);

  // Get auth token
  console.log('Authenticating...');
  const authToken = await getAuthToken();
  console.log('Authenticated successfully!\n');

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

    // Print summary
    console.log(generateSingleModelSummary(summary));

    // Save results to JSON
    const fs = await import('fs');
    const filename = `results-${model}-v246-${Date.now()}.json`;
    fs.writeFileSync(filename, JSON.stringify(summary, null, 2));
    console.log(`\nResults saved to: ${filename}`);

  } catch (error) {
    console.error('Evaluation failed:', error);
    process.exit(1);
  }
}

main();
