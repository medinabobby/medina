// Script to add createdAt/updatedAt timestamps to existing plans
// Run with: node scripts/add-plan-timestamps.js

const admin = require('firebase-admin');

// Initialize with default credentials (from firebase login)
admin.initializeApp({
  projectId: 'medinaintelligence'
});

const db = admin.firestore();

async function addTimestampsToPlans() {
  console.log('Fetching all users...');

  const usersSnapshot = await db.collection('users').get();
  console.log(`Found ${usersSnapshot.size} users`);

  for (const userDoc of usersSnapshot.docs) {
    const userId = userDoc.id;
    console.log(`\nChecking user: ${userId}`);

    // Get plans for this user
    const plansSnapshot = await db.collection('users').doc(userId).collection('plans').get();

    if (plansSnapshot.empty) {
      console.log('  No plans found');
      continue;
    }

    console.log(`  Found ${plansSnapshot.size} plans`);

    for (const planDoc of plansSnapshot.docs) {
      const planData = planDoc.data();
      const planId = planDoc.id;

      // Check if timestamps already exist
      if (planData.createdAt && planData.updatedAt) {
        console.log(`  Plan "${planData.name}" already has timestamps`);
        continue;
      }

      // Add timestamps
      const now = admin.firestore.FieldValue.serverTimestamp();
      await planDoc.ref.update({
        createdAt: planData.createdAt || now,
        updatedAt: now
      });

      console.log(`  ✓ Added timestamps to plan: "${planData.name}"`);
    }
  }

  console.log('\n✅ Done!');
  process.exit(0);
}

addTimestampsToPlans().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
