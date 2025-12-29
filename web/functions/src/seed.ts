/**
 * Firestore Seeding Script for v196: Zero Local JSONs
 *
 * Seeds protocols and gyms from iOS app's JSON files to Firestore.
 * Run once to migrate reference data to cloud.
 *
 * Usage:
 *   npm run seed
 *   (Requires: gcloud auth application-default login)
 */

import * as admin from 'firebase-admin';
import * as fs from 'fs';
import * as path from 'path';

// Initialize Firebase Admin with ADC (Application Default Credentials)
// Run `gcloud auth application-default login` first if not authenticated
admin.initializeApp({
  projectId: 'medinaintelligence',
});

const db = admin.firestore();

// Path to iOS JSON files
const IOS_DATA_PATH = '/Users/bobbytulsiani/Desktop/medina/Resources/Data';

interface ProtocolConfig {
  id: string;
  protocolId?: string;
  protocolFamily?: string;
  variantName: string;
  reps: number[];
  intensityAdjustments: number[];
  restBetweenSets: number[];
  tempo?: string | null;
  rpe: number[];
  defaultInstructions?: string;
  executionNotes?: string;
  duration?: number;
  methodology?: string;
  createdByMemberId?: string | null;
  createdByTrainerId?: string | null;
  createdByGymId?: string | null;
}

interface Gym {
  id: string;
  name: string;
  address: string;
  neighborhood: string;
  city: string;
  state: string;
  zipCode: string;
  phone: string;
  email: string;
  website: string;
  hours: Record<string, string>;
  facility: {
    type: string;
    squareFeet: number;
    levels: number;
    description: string;
  };
  services: string[];
  amenities: string[];
  membershipTiers: Array<{
    id: string;
    name: string;
    price: number;
    classCredits: number;
    benefits: string[];
  }>;
  foundedDate: string;
  memberCapacity: number;
  activeMembers: number;
  instagram: string;
  currentStatus: string;
  classTypes: string[];
}

async function seedProtocols() {
  console.log('\n📋 Seeding protocols...');

  const protocolsPath = path.join(IOS_DATA_PATH, 'protocol_configs.json');
  if (!fs.existsSync(protocolsPath)) {
    console.error('Error: protocol_configs.json not found at', protocolsPath);
    return;
  }

  const protocolsData = JSON.parse(fs.readFileSync(protocolsPath, 'utf-8')) as Record<string, ProtocolConfig>;
  const protocols = Object.values(protocolsData);

  console.log(`Found ${protocols.length} protocols to seed`);

  // Use batched writes for efficiency
  const batch = db.batch();
  let count = 0;

  for (const protocol of protocols) {
    const docRef = db.collection('protocols').doc(protocol.id);
    batch.set(docRef, {
      ...protocol,
      // Ensure all fields are properly typed for Firestore
      reps: protocol.reps || [],
      intensityAdjustments: protocol.intensityAdjustments || [],
      restBetweenSets: protocol.restBetweenSets || [],
      rpe: protocol.rpe || [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    count++;

    // Firestore batch limit is 500 operations
    if (count % 450 === 0) {
      await batch.commit();
      console.log(`  Committed ${count} protocols...`);
    }
  }

  await batch.commit();
  console.log(`✅ Seeded ${count} protocols to Firestore`);
}

async function seedGyms() {
  console.log('\n🏋️ Seeding gyms...');

  const gymsPath = path.join(IOS_DATA_PATH, 'gyms.json');
  if (!fs.existsSync(gymsPath)) {
    console.error('Error: gyms.json not found at', gymsPath);
    return;
  }

  const gymsData = JSON.parse(fs.readFileSync(gymsPath, 'utf-8')) as Record<string, Gym>;
  const gyms = Object.values(gymsData);

  console.log(`Found ${gyms.length} gyms to seed`);

  const batch = db.batch();

  for (const gym of gyms) {
    const docRef = db.collection('gyms').doc(gym.id);
    batch.set(docRef, {
      ...gym,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
  console.log(`✅ Seeded ${gyms.length} gyms to Firestore`);
}

async function verifySeeding() {
  console.log('\n🔍 Verifying seeding...');

  const protocolsSnapshot = await db.collection('protocols').get();
  const gymsSnapshot = await db.collection('gyms').get();

  console.log(`  Protocols in Firestore: ${protocolsSnapshot.size}`);
  console.log(`  Gyms in Firestore: ${gymsSnapshot.size}`);

  // Sample a protocol
  if (protocolsSnapshot.size > 0) {
    const sample = protocolsSnapshot.docs[0];
    console.log(`  Sample protocol: ${sample.id} - ${sample.data().variantName}`);
  }

  // Sample a gym
  if (gymsSnapshot.size > 0) {
    const sample = gymsSnapshot.docs[0];
    console.log(`  Sample gym: ${sample.id} - ${sample.data().name}`);
  }
}

async function main() {
  console.log('🚀 Medina v196: Seeding reference data to Firestore');
  console.log('================================================');

  try {
    await seedProtocols();
    await seedGyms();
    await verifySeeding();

    console.log('\n✅ Seeding complete!');
    console.log('\nNext steps:');
    console.log('1. Verify data in Firebase Console');
    console.log('2. Create FirestoreProtocolRepository.swift');
    console.log('3. Create FirestoreGymRepository.swift');
    console.log('4. Update LocalDataLoader to fetch from Firestore');
    console.log('5. Delete local JSON files from iOS app');

  } catch (error) {
    console.error('❌ Seeding failed:', error);
    process.exit(1);
  }

  process.exit(0);
}

main();
