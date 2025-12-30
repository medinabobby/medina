/**
 * Test Import Endpoint
 *
 * Tests CSV import functionality against the deployed Firebase function.
 * Uses Firebase Auth REST API to get a real ID token.
 *
 * Usage: npx ts-node scripts/testImport.ts
 */

import * as dotenv from 'dotenv';
import * as path from 'path';

// Load test environment
dotenv.config({ path: path.join(__dirname, '.env.test') });

const FIREBASE_API_KEY = process.env.FIREBASE_API_KEY || '';
const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'test@medinaintelligence.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'TestUser2024!';
const IMPORT_URL = 'https://importcsv-dpkc2km3oa-uc.a.run.app';

// Sample CSV data matching expected format
// Note: Dates use MM/dd/yyyy to avoid comma issues
// Workout number only appears on first line of each workout
const SAMPLE_CSV = `Workout,Date,Exercise,Sets x Reps,Weight
1,12/01/2024,Barbell Squat,3x5,185 lb barbell
,,Bench Press,3x8,135 lb barbell
,,Deadlift,1x5,225 lb barbell
2,12/04/2024,Barbell Squat,3x5,195 lb barbell
,,Overhead Press,3x8,95 lb barbell
,,Barbell Row,3x8,135 lb barbell
3,12/08/2024,Barbell Squat,3x5,205 lb barbell
,,Bench Press,3x8,145 lb barbell
,,Deadlift,1x5,245 lb barbell
4,12/11/2024,Barbell Squat,3x5,215 lb barbell
,,Overhead Press,3x8,100 lb barbell
,,Barbell Row,3x8,145 lb barbell
5,12/15/2024,Barbell Squat,3x3,225 lb barbell
,,Bench Press,3x5,155 lb barbell
,,Deadlift,1x3,275 lb barbell
`;

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

async function testImport(token: string): Promise<void> {
  console.log('📤 Testing CSV Import\n');
  console.log('─'.repeat(50));

  // Encode CSV as base64
  const csvBase64 = Buffer.from(SAMPLE_CSV).toString('base64');

  console.log('Sample CSV:');
  console.log(SAMPLE_CSV.split('\n').slice(0, 6).join('\n'));
  console.log('...\n');

  // Test 1: Import without historical workouts
  console.log('Test 1: Import CSV (targets only)');
  try {
    const response = await fetch(IMPORT_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        csvData: csvBase64,
        createHistoricalWorkouts: false,
        userWeight: 180  // For relative strength scoring
      })
    });

    const data = await response.json();

    if (data.error) {
      console.log(`❌ ERROR: ${data.error}\n`);
      return;
    }

    console.log('✅ Import successful!\n');

    console.log('📊 Summary:');
    console.log(`   Sessions imported: ${data.summary.sessionsImported}`);
    console.log(`   Exercises matched: ${data.summary.exercisesMatched}`);
    console.log(`   Exercises unmatched: ${data.summary.exercisesUnmatched.length}`);
    if (data.summary.exercisesUnmatched.length > 0) {
      console.log(`     → ${data.summary.exercisesUnmatched.join(', ')}`);
    }
    console.log(`   Targets created: ${data.summary.targetsCreated}`);
    console.log(`   Workouts created: ${data.summary.workoutsCreated}`);

    console.log('\n🧠 Intelligence Analysis:');
    console.log(`   Experience Level: ${data.intelligence.inferredExperience}`);
    console.log(`   Training Style: ${data.intelligence.trainingStyle}`);
    console.log(`   Top Muscles: ${data.intelligence.topMuscleGroups.join(', ')}`);
    console.log(`   Inferred Split: ${data.intelligence.inferredSplit || 'Not detected'}`);
    console.log(`   Session Duration: ${data.intelligence.estimatedSessionDuration} min`);
    console.log(`   Confidence: ${(data.intelligence.confidenceScore * 100).toFixed(0)}%`);

    console.log('\n📈 Experience Indicators:');
    const ind = data.intelligence.indicators;
    if (ind.strengthScore !== undefined) console.log(`   Strength: ${ind.strengthScore.toFixed(1)}/3.0`);
    if (ind.historyScore !== undefined) console.log(`   History: ${ind.historyScore.toFixed(1)}/3.0`);
    if (ind.volumeScore !== undefined) console.log(`   Volume: ${ind.volumeScore.toFixed(1)}/3.0`);
    if (ind.varietyScore !== undefined) console.log(`   Variety: ${ind.varietyScore.toFixed(1)}/3.0`);

  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.log(`❌ EXCEPTION: ${errorMsg}\n`);
  }

  // Test 2: Import with historical workouts
  console.log('\n' + '─'.repeat(50));
  console.log('Test 2: Import CSV (with historical workouts)');
  try {
    const response = await fetch(IMPORT_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        csvData: csvBase64,
        createHistoricalWorkouts: true
      })
    });

    const data = await response.json();

    if (data.error) {
      console.log(`❌ ERROR: ${data.error}\n`);
      return;
    }

    console.log('✅ Import with history successful!');
    console.log(`   Workouts created: ${data.summary.workoutsCreated}`);

  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.log(`❌ EXCEPTION: ${errorMsg}\n`);
  }

  // Test 3: Error handling - empty CSV
  console.log('\n' + '─'.repeat(50));
  console.log('Test 3: Error handling (empty CSV)');
  try {
    const response = await fetch(IMPORT_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({
        csvData: Buffer.from('Header\n').toString('base64')
      })
    });

    const data = await response.json();

    if (data.error) {
      console.log(`✅ Correctly returned error: ${data.error}`);
    } else {
      console.log('❌ Should have returned an error for empty CSV');
    }

  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    console.log(`❌ EXCEPTION: ${errorMsg}\n`);
  }
}

async function main(): Promise<void> {
  console.log('📥 Import Endpoint Test Suite\n');

  if (!FIREBASE_API_KEY) {
    console.error('❌ Missing FIREBASE_API_KEY in .env.test');
    process.exit(1);
  }

  try {
    const token = await getIdToken();
    await testImport(token);

    console.log('\n' + '═'.repeat(50));
    console.log('🎉 Import tests complete!');
    console.log('═'.repeat(50));

  } catch (error) {
    console.error('❌ Test suite failed:', error);
    process.exit(1);
  }
}

main();
