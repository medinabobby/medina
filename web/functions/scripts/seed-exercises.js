/**
 * Seed Exercises to Firestore
 *
 * Usage:
 *   cd /Users/bobbytulsiani/Desktop/medina-web/functions
 *   node scripts/seed-exercises.js
 *
 * Prerequisites:
 *   - Firebase CLI logged in: firebase login
 *   - Or set GOOGLE_APPLICATION_CREDENTIALS env var to service account key
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Path to exercises.json - v257: Using comprehensive exercise database in functions/data
const EXERCISES_PATH = path.join(__dirname, '../data/exercises.json');

// Initialize Firebase Admin
// Uses Application Default Credentials when running locally with 'firebase login'
// Or GOOGLE_APPLICATION_CREDENTIALS environment variable
admin.initializeApp({
  projectId: 'medinaintelligence'
});

const db = admin.firestore();

async function seedExercises() {
  console.log('Reading exercises from:', EXERCISES_PATH);

  // Read exercises.json
  const exercisesJson = fs.readFileSync(EXERCISES_PATH, 'utf8');
  const exercises = JSON.parse(exercisesJson);

  const exerciseIds = Object.keys(exercises);
  console.log(`Found ${exerciseIds.length} exercises to seed`);

  // Firestore batch writes are limited to 500 operations
  // Split into chunks of 500
  const BATCH_SIZE = 500;
  const chunks = [];
  for (let i = 0; i < exerciseIds.length; i += BATCH_SIZE) {
    chunks.push(exerciseIds.slice(i, i + BATCH_SIZE));
  }

  console.log(`Splitting into ${chunks.length} batch(es)`);

  let totalWritten = 0;

  for (let chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
    const chunk = chunks[chunkIndex];
    const batch = db.batch();

    for (const exerciseId of chunk) {
      const exercise = exercises[exerciseId];
      const docRef = db.collection('exercises').doc(exerciseId);
      batch.set(docRef, exercise);
    }

    await batch.commit();
    totalWritten += chunk.length;
    console.log(`Batch ${chunkIndex + 1}/${chunks.length} complete (${totalWritten}/${exerciseIds.length})`);
  }

  console.log(`\n✅ Successfully seeded ${totalWritten} exercises to Firestore`);
  console.log('Verify at: https://console.firebase.google.com/project/medinaintelligence/firestore/data/~2Fexercises');
}

// Run the seeder
seedExercises()
  .then(() => {
    console.log('\nDone!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Error seeding exercises:', error);
    process.exit(1);
  });
