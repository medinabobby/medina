/**
 * Seed Test User Script
 *
 * Creates a test user with 12 months of training data showing progressive improvement:
 * - Q1: Beginner (lower weights, ~70% completion)
 * - Q2: Building (moderate weights, ~80% completion)
 * - Q3: Intermediate (higher weights, ~85% completion)
 * - Q4: Advanced (highest weights, ~90% completion)
 *
 * Usage: npx ts-node scripts/seedTestUser.ts
 */

import * as admin from 'firebase-admin';

// Initialize with service account or default credentials
const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (serviceAccountPath) {
  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
} else {
  admin.initializeApp();
}

const db = admin.firestore();
const auth = admin.auth();

// Test user config
const TEST_USER = {
  email: 'test@medinaintelligence.com',
  password: 'TestUser2024!',
  displayName: 'Test User'
};

// Core compound exercises to track (with realistic starting weights)
const EXERCISES = {
  squat: { id: 'barbell-back-squat', name: 'Barbell Back Squat', startingMax: 135 },
  bench: { id: 'barbell-bench-press', name: 'Barbell Bench Press', startingMax: 95 },
  deadlift: { id: 'barbell-deadlift', name: 'Barbell Deadlift', startingMax: 155 },
  ohp: { id: 'barbell-overhead-press', name: 'Overhead Press', startingMax: 65 },
  row: { id: 'barbell-row', name: 'Barbell Row', startingMax: 85 }
};

// Quarterly progression multipliers (simulating strength gains)
const QUARTER_PROGRESSION = {
  Q1: { multiplier: 1.0, completionRate: 0.70, workoutsPerWeek: 3 },
  Q2: { multiplier: 1.15, completionRate: 0.80, workoutsPerWeek: 3 },
  Q3: { multiplier: 1.30, completionRate: 0.85, workoutsPerWeek: 4 },
  Q4: { multiplier: 1.45, completionRate: 0.90, workoutsPerWeek: 4 }
};

function generateWorkoutDate(monthsAgo: number, dayOffset: number): Date {
  const date = new Date();
  date.setMonth(date.getMonth() - monthsAgo);
  date.setDate(date.getDate() + dayOffset);
  date.setHours(9, 0, 0, 0);
  return date;
}

function shouldComplete(completionRate: number): boolean {
  return Math.random() < completionRate;
}

// Generate sets with slight variation (realistic training)
function generateSets(oneRM: number, targetReps: number, setCount: number): Array<{weight: number, reps: number, completed: boolean}> {
  const workingWeight = Math.round((oneRM * 0.75) / 5) * 5; // ~75% of 1RM, rounded to 5
  const sets = [];

  for (let i = 0; i < setCount; i++) {
    // Slight fatigue: later sets might have fewer reps
    const repVariation = i < 2 ? 0 : Math.floor(Math.random() * 2);
    const actualReps = Math.max(targetReps - repVariation, targetReps - 2);

    sets.push({
      weight: workingWeight,
      reps: actualReps,
      completed: true
    });
  }

  return sets;
}

async function createTestUser(): Promise<string> {
  console.log('Creating test user...');

  try {
    // Check if user exists
    const existingUser = await auth.getUserByEmail(TEST_USER.email).catch(() => null);

    if (existingUser) {
      console.log(`Test user already exists: ${existingUser.uid}`);
      return existingUser.uid;
    }

    // Create new user
    const userRecord = await auth.createUser({
      email: TEST_USER.email,
      password: TEST_USER.password,
      displayName: TEST_USER.displayName,
      emailVerified: true
    });

    console.log(`Created test user: ${userRecord.uid}`);
    return userRecord.uid;
  } catch (error) {
    console.error('Error creating user:', error);
    throw error;
  }
}

async function seedUserProfile(uid: string): Promise<void> {
  console.log('Seeding user profile...');

  const profile = {
    uid,
    email: TEST_USER.email,
    displayName: TEST_USER.displayName,
    profile: {
      birthdate: '1990-05-15',
      heightInches: 70,
      currentWeight: 175,
      fitnessGoal: 'strength',
      experienceLevel: 'intermediate',
      preferredDays: ['monday', 'wednesday', 'friday', 'saturday'],
      sessionDuration: 60
    },
    role: 'member',
    createdAt: new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString(), // 1 year ago
    updatedAt: new Date().toISOString()
  };

  await db.collection('users').doc(uid).set(profile);
  console.log('User profile created');
}

async function seedExerciseTargets(uid: string): Promise<void> {
  console.log('Seeding exercise targets (current 1RMs)...');

  const batch = db.batch();
  const q4 = QUARTER_PROGRESSION.Q4;

  for (const [, exercise] of Object.entries(EXERCISES)) {
    const current1RM = Math.round(exercise.startingMax * q4.multiplier / 5) * 5;
    const targetKey = `${uid}-${exercise.id}`;

    const target = {
      odid: targetKey,
      odtype: 'ExerciseTarget',
      exerciseId: exercise.id,
      memberId: uid,
      targetType: 'max',
      currentTarget: current1RM,
      targetHistory: [
        { date: new Date().toISOString(), value: current1RM }
      ],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    batch.set(db.collection('users').doc(uid).collection('targets').doc(targetKey), target);
    console.log(`  ${exercise.name}: ${current1RM} lbs`);
  }

  await batch.commit();
  console.log('Exercise targets created');
}

async function seedPlans(uid: string): Promise<string[]> {
  console.log('Seeding 4 quarterly plans...');

  const planIds: string[] = [];
  const quarters = ['Q1', 'Q2', 'Q3', 'Q4'] as const;
  const planNames = [
    'Foundation Builder',
    'Strength Development',
    'Intermediate Progression',
    'Advanced Training'
  ];

  for (let i = 0; i < 4; i++) {
    const quarter = quarters[i];
    const monthsAgo = 12 - (i * 3); // Q1 = 12mo ago, Q4 = 3mo ago
    const startDate = generateWorkoutDate(monthsAgo, 0);
    const endDate = generateWorkoutDate(monthsAgo - 3, 0);

    const planId = `plan-${quarter.toLowerCase()}-${uid.slice(0, 8)}`;

    const plan = {
      odid: planId,
      odtype: 'Plan',
      name: planNames[i],
      description: `${quarter} training plan - ${planNames[i]}`,
      memberId: uid,
      status: i === 3 ? 'active' : 'completed',
      startDate: startDate.toISOString(),
      endDate: endDate.toISOString(),
      workoutsPerWeek: QUARTER_PROGRESSION[quarter].workoutsPerWeek,
      createdAt: startDate.toISOString(),
      updatedAt: new Date().toISOString()
    };

    await db.collection('users').doc(uid).collection('plans').doc(planId).set(plan);
    planIds.push(planId);
    console.log(`  Created: ${planNames[i]} (${quarter})`);
  }

  return planIds;
}

async function seedWorkouts(uid: string, planIds: string[]): Promise<void> {
  console.log('Seeding workouts with progressive improvement...');

  const quarters = ['Q1', 'Q2', 'Q3', 'Q4'] as const;
  let totalWorkouts = 0;
  let completedWorkouts = 0;

  for (let q = 0; q < 4; q++) {
    const quarter = quarters[q];
    const planId = planIds[q];
    const config = QUARTER_PROGRESSION[quarter];
    const monthsAgoStart = 12 - (q * 3);

    // Generate ~12-13 weeks of workouts per quarter
    for (let week = 0; week < 13; week++) {
      const monthsAgo = monthsAgoStart - (week / 4.33);

      for (let dayOfWeek = 0; dayOfWeek < config.workoutsPerWeek; dayOfWeek++) {
        const workoutDate = generateWorkoutDate(Math.floor(monthsAgo), (week * 7) + (dayOfWeek * 2));

        // Skip future dates
        if (workoutDate > new Date()) continue;

        const isCompleted = shouldComplete(config.completionRate);
        totalWorkouts++;
        if (isCompleted) completedWorkouts++;

        const workoutId = `workout-${quarter.toLowerCase()}-w${week}-d${dayOfWeek}-${uid.slice(0, 6)}`;

        // Alternate workout types
        const workoutType = dayOfWeek % 2 === 0 ? 'upper' : 'lower';
        const exercises = workoutType === 'upper'
          ? [EXERCISES.bench, EXERCISES.ohp, EXERCISES.row]
          : [EXERCISES.squat, EXERCISES.deadlift];

        const exerciseInstances = exercises.map((exercise, idx) => {
          const current1RM = Math.round(exercise.startingMax * config.multiplier / 5) * 5;
          const sets = isCompleted ? generateSets(current1RM, 5, 4) : [];

          // Calculate estimated 1RM from the sets (for verification)
          let estimated1RM = null;
          if (sets.length > 0) {
            const bestSet = sets[0]; // First set is typically best
            estimated1RM = Math.round(bestSet.weight * (1 + bestSet.reps / 30));
          }

          return {
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            orderIndex: idx,
            sets: sets,
            estimated1RM: estimated1RM,
            targetWeight: Math.round(current1RM * 0.75 / 5) * 5,
            targetReps: 5,
            targetSets: 4
          };
        });

        const workout = {
          odid: workoutId,
          odtype: 'Workout',
          name: `${workoutType.charAt(0).toUpperCase() + workoutType.slice(1)} ${quarter}`,
          memberId: uid,
          planId: planId,
          status: isCompleted ? 'completed' : 'skipped',
          scheduledDate: workoutDate.toISOString(),
          completedDate: isCompleted ? workoutDate.toISOString() : null,
          exercises: exerciseInstances,
          duration: isCompleted ? 45 + Math.floor(Math.random() * 30) : null,
          createdAt: workoutDate.toISOString(),
          updatedAt: workoutDate.toISOString()
        };

        await db.collection('users').doc(uid).collection('workouts').doc(workoutId).set(workout);
      }
    }

    console.log(`  ${quarter}: ~${Math.round(13 * config.workoutsPerWeek)} workouts seeded`);
  }

  console.log(`Total: ${totalWorkouts} workouts (${completedWorkouts} completed, ${Math.round(completedWorkouts/totalWorkouts*100)}% rate)`);
}

async function printSummary(uid: string): Promise<void> {
  console.log('\n========== TEST USER SUMMARY ==========');
  console.log(`Email: ${TEST_USER.email}`);
  console.log(`Password: ${TEST_USER.password}`);
  console.log(`UID: ${uid}`);
  console.log('\nExpected 1RM Progression:');

  for (const [, exercise] of Object.entries(EXERCISES)) {
    const q1 = Math.round(exercise.startingMax * QUARTER_PROGRESSION.Q1.multiplier / 5) * 5;
    const q4 = Math.round(exercise.startingMax * QUARTER_PROGRESSION.Q4.multiplier / 5) * 5;
    const gain = q4 - q1;
    console.log(`  ${exercise.name}: ${q1} → ${q4} lbs (+${gain} lbs, +${Math.round(gain/q1*100)}%)`);
  }

  console.log('\nQuarterly Completion Rates:');
  console.log('  Q1: ~70% (beginner consistency)');
  console.log('  Q2: ~80% (building habits)');
  console.log('  Q3: ~85% (intermediate dedication)');
  console.log('  Q4: ~90% (advanced commitment)');
  console.log('==========================================\n');
}

async function main() {
  try {
    console.log('🏋️ Seeding Test User with 12 Months of Training Data\n');

    // 1. Use provided UID or create user
    const providedUid = process.argv[2];
    let uid: string;

    if (providedUid) {
      console.log(`Using provided UID: ${providedUid}`);
      uid = providedUid;
    } else {
      uid = await createTestUser();
    }

    // 2. Create user profile in Firestore
    await seedUserProfile(uid);

    // 3. Create current exercise targets (1RMs)
    await seedExerciseTargets(uid);

    // 4. Create 4 quarterly plans
    const planIds = await seedPlans(uid);

    // 5. Create workouts with progressive data
    await seedWorkouts(uid, planIds);

    // 6. Print summary
    await printSummary(uid);

    console.log('✅ Test user seeding complete!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }
}

main();
