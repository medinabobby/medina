/**
 * Seed Exercises to Firestore using REST API
 *
 * Usage:
 *   cd /Users/bobbytulsiani/Desktop/medina-web/functions
 *   node scripts/seed-firestore-rest.js
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const PROJECT_ID = 'medinaintelligence';
const EXERCISES_PATH = path.join(__dirname, '../../../medina/Resources/Data/exercises.json');

// Read token from firebase-tools config
const configPath = path.join(process.env.HOME, '.config/configstore/firebase-tools.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const accessToken = config.tokens.access_token;

// Read exercises
const exercises = JSON.parse(fs.readFileSync(EXERCISES_PATH, 'utf8'));
const exerciseIds = Object.keys(exercises);

console.log(`Found ${exerciseIds.length} exercises to seed`);
console.log(`Token: ${accessToken.substring(0, 20)}...`);

// Convert exercise to Firestore document format
function toFirestoreValue(value) {
  if (value === null || value === undefined) {
    return { nullValue: null };
  }
  if (typeof value === 'string') {
    return { stringValue: value };
  }
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === 'boolean') {
    return { booleanValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toFirestoreValue) } };
  }
  if (typeof value === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(value)) {
      fields[k] = toFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
}

function exerciseToDocument(exercise) {
  const fields = {};
  for (const [key, value] of Object.entries(exercise)) {
    fields[key] = toFirestoreValue(value);
  }
  return { fields };
}

// Write a single exercise
async function writeExercise(exerciseId, exercise) {
  return new Promise((resolve, reject) => {
    const doc = exerciseToDocument(exercise);
    const body = JSON.stringify(doc);

    const options = {
      hostname: 'firestore.googleapis.com',
      path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/exercises/${exerciseId}`,
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
        'Content-Length': Buffer.byteLength(body)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve({ success: true });
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// Main seeding function
async function seedExercises() {
  let success = 0;
  let failed = 0;

  // Process in batches of 10 to avoid rate limiting
  const BATCH_SIZE = 10;

  for (let i = 0; i < exerciseIds.length; i += BATCH_SIZE) {
    const batch = exerciseIds.slice(i, i + BATCH_SIZE);
    const promises = batch.map(id => writeExercise(id, exercises[id]));

    try {
      const results = await Promise.allSettled(promises);
      results.forEach((result, idx) => {
        if (result.status === 'fulfilled') {
          success++;
        } else {
          failed++;
          console.error(`Failed ${batch[idx]}:`, result.reason.message.substring(0, 100));
        }
      });

      console.log(`Progress: ${success + failed}/${exerciseIds.length} (${success} success, ${failed} failed)`);
    } catch (error) {
      console.error('Batch error:', error.message);
    }

    // Small delay to avoid rate limiting
    await new Promise(r => setTimeout(r, 100));
  }

  console.log(`\n✅ Seeded ${success}/${exerciseIds.length} exercises`);
  if (failed > 0) {
    console.log(`❌ ${failed} exercises failed`);
  }
}

seedExercises().catch(console.error);
