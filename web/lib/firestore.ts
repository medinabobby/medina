// Firestore queries for Medina Web

import {
  collection,
  query,
  where,
  orderBy,
  getDocs,
  doc,
  getDoc,
  Timestamp,
} from 'firebase/firestore';
import { getFirebaseDb } from './firebase';
import type { Plan, Program, Workout, Exercise, Conversation } from './types';

// ============================================
// Helper: Convert Firestore timestamp to Date
// Handles: Firestore Timestamp, Date, ISO string, undefined
// ============================================

function toDate(timestamp: Timestamp | Date | string | undefined): Date | undefined {
  if (!timestamp) return undefined;
  if (timestamp instanceof Date) return timestamp;
  // ISO string format (from some handlers)
  if (typeof timestamp === 'string') {
    const parsed = new Date(timestamp);
    return isNaN(parsed.getTime()) ? undefined : parsed;
  }
  // Firestore Timestamp
  if (typeof timestamp === 'object' && 'toDate' in timestamp) {
    return (timestamp as Timestamp).toDate();
  }
  return undefined;
}

// ============================================
// Plans
// ============================================

export async function getPlans(uid: string): Promise<Plan[]> {
  const db = getFirebaseDb();
  const plansRef = collection(db, 'users', uid, 'plans');
  const q = query(plansRef, orderBy('createdAt', 'desc'));

  const snapshot = await getDocs(q);
  return snapshot.docs.map(doc => ({
    id: doc.id,
    userId: uid,
    ...doc.data(),
    createdAt: toDate(doc.data().createdAt) || new Date(),
    updatedAt: toDate(doc.data().updatedAt) || new Date(),
    startDate: toDate(doc.data().startDate),
    endDate: toDate(doc.data().endDate),
  } as Plan));
}

export async function getPlan(uid: string, planId: string): Promise<Plan | null> {
  const db = getFirebaseDb();
  const planRef = doc(db, 'users', uid, 'plans', planId);
  const snapshot = await getDoc(planRef);

  if (!snapshot.exists()) return null;

  return {
    id: snapshot.id,
    userId: uid,
    ...snapshot.data(),
    createdAt: toDate(snapshot.data().createdAt) || new Date(),
    updatedAt: toDate(snapshot.data().updatedAt) || new Date(),
  } as Plan;
}

// ============================================
// Programs
// ============================================

export async function getPrograms(uid: string, planId: string): Promise<Program[]> {
  const db = getFirebaseDb();
  const programsRef = collection(db, 'users', uid, 'plans', planId, 'programs');
  const q = query(programsRef, orderBy('weekNumber', 'asc'));

  const snapshot = await getDocs(q);
  return snapshot.docs.map(doc => ({
    id: doc.id,
    planId,
    ...doc.data(),
  } as Program));
}

// ============================================
// Workouts
// ============================================

export async function getWorkouts(uid: string): Promise<Workout[]> {
  const db = getFirebaseDb();
  const workoutsRef = collection(db, 'users', uid, 'workouts');
  const q = query(workoutsRef, orderBy('scheduledDate', 'desc'));

  const snapshot = await getDocs(q);
  return snapshot.docs.map(doc => ({
    id: doc.id,
    userId: uid,
    ...doc.data(),
    scheduledDate: toDate(doc.data().scheduledDate),
    completedDate: toDate(doc.data().completedDate),
  } as Workout));
}

export async function getWorkout(uid: string, workoutId: string): Promise<Workout | null> {
  const db = getFirebaseDb();
  const workoutRef = doc(db, 'users', uid, 'workouts', workoutId);
  const snapshot = await getDoc(workoutRef);

  if (!snapshot.exists()) return null;

  return {
    id: snapshot.id,
    userId: uid,
    ...snapshot.data(),
    scheduledDate: toDate(snapshot.data().scheduledDate),
    completedDate: toDate(snapshot.data().completedDate),
  } as Workout;
}

export async function getRecentWorkouts(uid: string, limit: number = 10): Promise<Workout[]> {
  const db = getFirebaseDb();
  const workoutsRef = collection(db, 'users', uid, 'workouts');
  const q = query(
    workoutsRef,
    orderBy('scheduledDate', 'desc'),
  );

  const snapshot = await getDocs(q);
  return snapshot.docs.slice(0, limit).map(doc => ({
    id: doc.id,
    userId: uid,
    ...doc.data(),
    scheduledDate: toDate(doc.data().scheduledDate),
    completedDate: toDate(doc.data().completedDate),
  } as Workout));
}

// ============================================
// Exercises (shared collection)
// ============================================

export async function getExercises(): Promise<Exercise[]> {
  const db = getFirebaseDb();
  const exercisesRef = collection(db, 'exercises');
  const q = query(exercisesRef, orderBy('name', 'asc'));

  const snapshot = await getDocs(q);
  return snapshot.docs.map(doc => ({
    id: doc.id,
    ...doc.data(),
  } as Exercise));
}

export async function getExercise(exerciseId: string): Promise<Exercise | null> {
  const db = getFirebaseDb();
  const exerciseRef = doc(db, 'exercises', exerciseId);
  const snapshot = await getDoc(exerciseRef);

  if (!snapshot.exists()) return null;

  return {
    id: snapshot.id,
    ...snapshot.data(),
  } as Exercise;
}

// ============================================
// Conversations (chat history)
// ============================================

export async function getConversations(uid: string): Promise<Conversation[]> {
  const db = getFirebaseDb();
  const convsRef = collection(db, 'users', uid, 'conversations');
  const q = query(convsRef, orderBy('updatedAt', 'desc'));

  const snapshot = await getDocs(q);
  return snapshot.docs.map(doc => ({
    id: doc.id,
    userId: uid,
    ...doc.data(),
    createdAt: toDate(doc.data().createdAt) || new Date(),
    updatedAt: toDate(doc.data().updatedAt) || new Date(),
  } as Conversation));
}

// ============================================
// User Profile
// ============================================

export async function getUserProfile(uid: string) {
  const db = getFirebaseDb();
  const userRef = doc(db, 'users', uid);
  const snapshot = await getDoc(userRef);

  if (!snapshot.exists()) return null;

  return {
    uid: snapshot.id,
    ...snapshot.data(),
  };
}
