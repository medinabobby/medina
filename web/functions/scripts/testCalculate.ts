/**
 * Test Calculate Endpoint
 *
 * Tests all 5 calculation types against the deployed Firebase function.
 * Uses Firebase Auth REST API to get a real ID token.
 *
 * Usage: npx ts-node scripts/testCalculate.ts
 */

import * as dotenv from 'dotenv';
import * as path from 'path';

// Load test environment
dotenv.config({ path: path.join(__dirname, '.env.test') });

const FIREBASE_API_KEY = process.env.FIREBASE_API_KEY || '';
const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'test@medinaintelligence.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'TestUser2024!';
const CALCULATE_URL = 'https://calculate-dpkc2km3oa-uc.a.run.app';

interface TestResult {
  name: string;
  passed: boolean;
  expected: number | null;
  actual: number | null;
  error?: string;
}

const results: TestResult[] = [];

async function getIdToken(): Promise<string> {
  console.log('🔐 Authenticating...');

  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: TEST_EMAIL,
        password: TEST_PASSWORD,
        returnSecureToken: true
      })
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Auth failed: ${JSON.stringify(error)}`);
  }

  const data = await response.json();
  console.log('✅ Authenticated successfully\n');
  return data.idToken;
}

async function testCalculate(
  token: string,
  name: string,
  body: object,
  expectedResult: number | null
): Promise<void> {
  try {
    const response = await fetch(CALCULATE_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify(body)
    });

    const data = await response.json();

    if (data.error) {
      results.push({ name, passed: false, expected: expectedResult, actual: null, error: data.error });
      console.log(`❌ ${name}: ERROR - ${data.error}`);
      return;
    }

    const actual = data.result;
    const tolerance = 0.1; // Allow 0.1 lb tolerance for rounding
    const passed = expectedResult === null
      ? actual === null
      : Math.abs(actual - expectedResult) <= tolerance;

    results.push({ name, passed, expected: expectedResult, actual });

    if (passed) {
      console.log(`✅ ${name}: ${actual} (expected ${expectedResult})`);
    } else {
      console.log(`❌ ${name}: got ${actual}, expected ${expectedResult}`);
    }
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    results.push({ name, passed: false, expected: expectedResult, actual: null, error: errorMsg });
    console.log(`❌ ${name}: EXCEPTION - ${errorMsg}`);
  }
}

async function runTests(token: string): Promise<void> {
  console.log('🧪 Running Calculation Tests\n');
  console.log('─'.repeat(50));

  // Test 1: Basic 1RM (Epley formula)
  // 175 × (1 + 5/30) = 175 × 1.167 = 204.17
  console.log('\n📊 1RM Calculations (Epley Formula)');
  await testCalculate(token, 'oneRM: 175 lbs × 5 reps',
    { type: 'oneRM', weight: 175, reps: 5 },
    204.17
  );

  await testCalculate(token, 'oneRM: 225 lbs × 3 reps',
    { type: 'oneRM', weight: 225, reps: 3 },
    247.5
  );

  await testCalculate(token, 'oneRM: invalid (0 reps)',
    { type: 'oneRM', weight: 175, reps: 0 },
    null
  );

  // Test 2: Weight for Reps (Inverse Epley)
  // 220 / (1 + 5/30) = 220 / 1.167 = 188.57
  console.log('\n📊 Weight for Reps (Inverse Epley)');
  await testCalculate(token, 'weightForReps: 220 1RM @ 5 reps',
    { type: 'weightForReps', oneRM: 220, targetReps: 5 },
    188.57
  );

  await testCalculate(token, 'weightForReps: 200 1RM @ 8 reps',
    { type: 'weightForReps', oneRM: 200, targetReps: 8 },
    157.89  // 200 / (1 + 8/30) = 200 / 1.267
  );

  // Test 3: Quality-weighted best 1RM
  // Set 1: 185×(1+5/30)=215.83, quality=1.0×1.0=1.0
  // Set 2: 175×(1+8/30)=221.67, quality=0.9×0.8=0.72
  // Set 3: 165×(1+10/30)=220, quality=0.7×0.6=0.42
  // Weighted avg = (215.83×1 + 221.67×0.72 + 220×0.42) / (1 + 0.72 + 0.42) = 218.61
  console.log('\n📊 Best 1RM (Quality-Weighted)');
  await testCalculate(token, 'best1RM: 3 sets with fatigue',
    {
      type: 'best1RM',
      sets: [
        { weight: 185, reps: 5, setIndex: 0 },  // Best quality: 5 reps, fresh
        { weight: 175, reps: 8, setIndex: 1 },  // Good: 8 reps, some fatigue
        { weight: 165, reps: 10, setIndex: 2 }  // Lower: 10 reps, tired
      ]
    },
    218.61
  );

  // Test 4: Target weight for compound
  // 220 × (0.65 + (-0.05)) = 220 × 0.60 = 132, rounded to 132.5
  console.log('\n📊 Target Weight (Compound)');
  await testCalculate(token, 'targetWeight: compound 220 1RM @ 60%',
    {
      type: 'targetWeight',
      exerciseType: 'compound',
      oneRM: 220,
      baseIntensity: 0.65,
      intensityOffset: -0.05
    },
    132.5
  );

  await testCalculate(token, 'targetWeight: compound 200 1RM @ 75%',
    {
      type: 'targetWeight',
      exerciseType: 'compound',
      oneRM: 200,
      baseIntensity: 0.75,
      intensityOffset: 0
    },
    150.0
  );

  // Test 5: Target weight for isolation (RPE-based)
  // Working weight 50, ±10% = 45-55, RPE 9 = high end = 55, rounded to 55
  console.log('\n📊 Target Weight (Isolation)');
  await testCalculate(token, 'targetWeight: isolation 50 lbs @ RPE 9',
    {
      type: 'targetWeight',
      exerciseType: 'isolation',
      workingWeight: 50,
      rpe: 9
    },
    55.0
  );

  await testCalculate(token, 'targetWeight: isolation 50 lbs @ RPE 7',
    {
      type: 'targetWeight',
      exerciseType: 'isolation',
      workingWeight: 50,
      rpe: 7
    },
    45.0
  );

  // Test 6: Recency-weighted 1RM
  // now: weight=1.0, 7d ago: weight=0.71, 14d ago: weight=0.5, 28d ago: weight=0.25
  // Weighted avg = (220×1 + 210×0.71 + 200×0.5 + 190×0.25) / (1 + 0.71 + 0.5 + 0.25)
  //              = 516.6 / 2.46 = 210.0
  console.log('\n📊 Recency 1RM (14-day half-life)');
  const now = new Date();
  const oneWeekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const twoWeeksAgo = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000);
  const fourWeeksAgo = new Date(now.getTime() - 28 * 24 * 60 * 60 * 1000);

  await testCalculate(token, 'recency1RM: recent sessions weighted higher',
    {
      type: 'recency1RM',
      sessions: [
        { date: now.toISOString(), best1RM: 220 },         // Weight ~1.0
        { date: oneWeekAgo.toISOString(), best1RM: 210 },  // Weight ~0.71
        { date: twoWeeksAgo.toISOString(), best1RM: 200 }, // Weight ~0.5
        { date: fourWeeksAgo.toISOString(), best1RM: 190 } // Weight ~0.25
      ]
    },
    210.0
  );
}

function printSummary(): void {
  console.log('\n' + '═'.repeat(50));
  console.log('📋 TEST SUMMARY');
  console.log('═'.repeat(50));

  const passed = results.filter(r => r.passed).length;
  const total = results.length;
  const percentage = Math.round((passed / total) * 100);

  console.log(`\nPassed: ${passed}/${total} (${percentage}%)\n`);

  if (passed < total) {
    console.log('Failed tests:');
    results.filter(r => !r.passed).forEach(r => {
      console.log(`  - ${r.name}`);
      if (r.error) console.log(`    Error: ${r.error}`);
      else console.log(`    Expected: ${r.expected}, Got: ${r.actual}`);
    });
  }

  console.log('\n' + '═'.repeat(50));

  if (passed === total) {
    console.log('🎉 All tests passed!');
  } else {
    console.log('⚠️  Some tests failed. Check calculations.');
  }
}

async function main(): Promise<void> {
  console.log('🧮 Calculate Endpoint Test Suite\n');

  if (!FIREBASE_API_KEY) {
    console.error('❌ Missing FIREBASE_API_KEY in .env.test');
    console.log('\nGet it from Firebase Console → Project Settings → Web API Key');
    process.exit(1);
  }

  try {
    const token = await getIdToken();
    await runTests(token);
    printSummary();

    const allPassed = results.every(r => r.passed);
    process.exit(allPassed ? 0 : 1);
  } catch (error) {
    console.error('❌ Test suite failed:', error);
    process.exit(1);
  }
}

main();
