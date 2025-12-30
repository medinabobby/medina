/**
 * Test Select Exercises Endpoint
 *
 * Tests exercise selection functionality against the deployed Firebase function.
 * Uses Firebase Auth REST API to get a real ID token.
 *
 * Usage: npx ts-node scripts/testSelectExercises.ts
 */

import * as dotenv from "dotenv";
import * as path from "path";

// Load test environment
dotenv.config({path: path.join(__dirname, ".env.test")});

const FIREBASE_API_KEY = process.env.FIREBASE_API_KEY || "";
const TEST_EMAIL = process.env.TEST_USER_EMAIL || "test@medinaintelligence.com";
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || "TestUser2024!";
const SELECT_URL = "https://selectexercises-dpkc2km3oa-uc.a.run.app";

interface TestResult {
  name: string;
  passed: boolean;
  details?: string;
  error?: string;
}

const results: TestResult[] = [];

async function getIdToken(): Promise<string> {
  console.log("🔐 Authenticating...");

  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        email: TEST_EMAIL,
        password: TEST_PASSWORD,
        returnSecureToken: true,
      }),
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new Error(`Auth failed: ${JSON.stringify(error)}`);
  }

  const data = await response.json();
  console.log("✅ Authenticated successfully\n");
  return data.idToken;
}

async function testSelection(
  token: string,
  name: string,
  body: object,
  expectedCompounds: number,
  expectedIsolations: number
): Promise<void> {
  try {
    const response = await fetch(SELECT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    });

    const data = await response.json();

    if (data.error) {
      results.push({name, passed: false, error: data.error});
      console.log(`❌ ${name}: ERROR - ${data.error}`);
      return;
    }

    const result = data.result;
    const totalExpected = expectedCompounds + expectedIsolations;
    const passed = result.exerciseIds.length === totalExpected;

    results.push({
      name,
      passed,
      details: `${result.exerciseIds.length} exercises (${result.fromLibrary.length} library, ${result.introduced.length} introduced), fallback: ${result.usedFallback}`,
    });

    if (passed) {
      console.log(`✅ ${name}:`);
      console.log(`   Selected: ${result.exerciseIds.length} exercises`);
      console.log(`   From library: ${result.fromLibrary.length}`);
      console.log(`   Introduced: ${result.introduced.length}`);
      console.log(`   Used fallback: ${result.usedFallback}`);
    } else {
      console.log(
        `❌ ${name}: got ${result.exerciseIds.length} exercises, expected ${totalExpected}`
      );
    }
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    results.push({name, passed: false, error: errorMsg});
    console.log(`❌ ${name}: EXCEPTION - ${errorMsg}`);
  }
}

async function runTests(token: string): Promise<void> {
  console.log("🏋️ Running Exercise Selection Tests\n");
  console.log("─".repeat(50));

  // Test 1: Push day selection (full gym equipment)
  console.log("\n📊 Test 1: Push Day Selection (Full Gym)");
  await testSelection(
    token,
    "Push day: 3 compounds + 2 isolations",
    {
      splitDay: "push",
      muscleTargets: ["chest", "shoulders", "triceps"],
      compoundCount: 3,
      isolationCount: 2,
      availableEquipment: [
        "barbell",
        "dumbbells",
        "cable_machine",
        "machine",
        "bench",
        "bodyweight",
      ],
      userExperienceLevel: "intermediate",
      libraryExerciseIds: [], // Empty library, will use fallback
    },
    3, // expected compounds
    2 // expected isolations
  );

  // Test 2: Pull day with library exercises
  console.log("\n📊 Test 2: Pull Day Selection (With Library)");
  await testSelection(
    token,
    "Pull day: 2 compounds + 3 isolations (with library)",
    {
      splitDay: "pull",
      muscleTargets: ["back", "lats", "biceps"],
      compoundCount: 2,
      isolationCount: 3,
      availableEquipment: [
        "barbell",
        "dumbbells",
        "cable_machine",
        "machine",
        "pullup_bar",
        "bodyweight",
      ],
      userExperienceLevel: "intermediate",
      libraryExerciseIds: [
        "barbell_bent_over_row",
        "lat_pulldown",
        "barbell_biceps_curl",
        "cable_face_pull",
        "dumbbell_hammer_curl",
      ],
    },
    2, // expected compounds
    3 // expected isolations
  );

  // Test 3: Leg day (bodyweight preference for home)
  console.log("\n📊 Test 3: Leg Day Selection (Home - Bodyweight Preferred)");
  await testSelection(
    token,
    "Legs: 2 compounds + 1 isolation (home workout)",
    {
      splitDay: "legs",
      muscleTargets: ["quadriceps", "hamstrings", "glutes", "calves"],
      compoundCount: 2,
      isolationCount: 1,
      availableEquipment: ["bodyweight", "dumbbells", "resistance_band"],
      userExperienceLevel: "beginner",
      libraryExerciseIds: [],
      preferBodyweightCompounds: true,
    },
    2, // expected compounds
    1 // expected isolations
  );

  // Test 4: Upper body with emphasis
  console.log("\n📊 Test 4: Upper Body with Chest Emphasis");
  await testSelection(
    token,
    "Upper: 4 compounds + 2 isolations (chest emphasis)",
    {
      splitDay: "upper",
      muscleTargets: ["chest", "back", "shoulders", "biceps", "triceps"],
      compoundCount: 4,
      isolationCount: 2,
      emphasizedMuscles: ["chest"],
      availableEquipment: [
        "barbell",
        "dumbbells",
        "cable_machine",
        "machine",
        "bench",
        "pullup_bar",
        "bodyweight",
      ],
      userExperienceLevel: "advanced",
      libraryExerciseIds: [],
    },
    4, // expected compounds
    2 // expected isolations
  );

  // Test 5: Beginner full body
  console.log("\n📊 Test 5: Beginner Full Body");
  await testSelection(
    token,
    "Full body: 3 compounds + 1 isolation (beginner)",
    {
      splitDay: "full_body",
      muscleTargets: ["chest", "back", "shoulders", "quadriceps", "core"],
      compoundCount: 3,
      isolationCount: 1,
      availableEquipment: ["barbell", "dumbbells", "bodyweight", "bench"],
      userExperienceLevel: "beginner",
      libraryExerciseIds: [],
    },
    3, // expected compounds
    1 // expected isolations
  );

  // Test 6: Error case - insufficient parameters
  console.log("\n📊 Test 6: Error Handling (Missing Required Fields)");
  try {
    const response = await fetch(SELECT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`,
      },
      body: JSON.stringify({
        splitDay: "push",
        // Missing muscleTargets, availableEquipment, etc.
      }),
    });

    const data = await response.json();

    if (data.error) {
      results.push({
        name: "Error handling: missing fields",
        passed: true,
        details: `Correctly returned error: ${data.error}`,
      });
      console.log(`✅ Error handling: Correctly returned error: ${data.error}`);
    } else {
      results.push({
        name: "Error handling: missing fields",
        passed: false,
        error: "Should have returned an error",
      });
      console.log("❌ Error handling: Should have returned an error");
    }
  } catch (error) {
    const errorMsg = error instanceof Error ? error.message : String(error);
    results.push({
      name: "Error handling: missing fields",
      passed: false,
      error: errorMsg,
    });
    console.log(`❌ Error handling: EXCEPTION - ${errorMsg}`);
  }
}

function printSummary(): void {
  console.log("\n" + "═".repeat(50));
  console.log("📋 TEST SUMMARY");
  console.log("═".repeat(50));

  const passed = results.filter((r) => r.passed).length;
  const total = results.length;
  const percentage = Math.round((passed / total) * 100);

  console.log(`\nPassed: ${passed}/${total} (${percentage}%)\n`);

  if (passed < total) {
    console.log("Failed tests:");
    results
      .filter((r) => !r.passed)
      .forEach((r) => {
        console.log(`  - ${r.name}`);
        if (r.error) console.log(`    Error: ${r.error}`);
      });
  }

  console.log("\n" + "═".repeat(50));

  if (passed === total) {
    console.log("🎉 All tests passed!");
  } else {
    console.log("⚠️  Some tests failed. Check implementation.");
  }
}

async function main(): Promise<void> {
  console.log("🏋️ Select Exercises Endpoint Test Suite\n");

  if (!FIREBASE_API_KEY) {
    console.error("❌ Missing FIREBASE_API_KEY in .env.test");
    console.log(
      "\nGet it from Firebase Console → Project Settings → Web API Key"
    );
    process.exit(1);
  }

  try {
    const token = await getIdToken();
    await runTests(token);
    printSummary();

    const allPassed = results.every((r) => r.passed);
    process.exit(allPassed ? 0 : 1);
  } catch (error) {
    console.error("❌ Test suite failed:", error);
    process.exit(1);
  }
}

main();
