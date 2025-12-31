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
import type {
  Plan,
  Program,
  Workout,
  Exercise,
  Conversation,
  PlanDetails,
  ProgramDetails,
  WorkoutDetails,
  ExerciseInstanceDetails,
  ExerciseDetails,
  ExerciseSet,
} from './types';

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

// v234: Training preferences interface matching iOS MemberProfile
export interface TrainingPreferences {
  fitnessGoal?: string;
  experienceLevel?: string;
  preferredSessionDuration?: number;
  preferredWorkoutDays?: string[];
  preferredSplitType?: string;
  preferredCardioDays?: number;
  trainingLocation?: string;
  availableEquipment?: string[];
  emphasizedMuscleGroups?: string[];
  excludedMuscleGroups?: string[];
}

// v234: Get training preferences from user's memberProfile
export async function getTrainingPreferences(uid: string): Promise<TrainingPreferences | null> {
  const db = getFirebaseDb();
  const userRef = doc(db, 'users', uid);
  const snapshot = await getDoc(userRef);

  if (!snapshot.exists()) return null;

  const data = snapshot.data();
  const memberProfile = data.memberProfile;

  if (!memberProfile) return null;

  return {
    fitnessGoal: memberProfile.fitnessGoal,
    experienceLevel: memberProfile.experienceLevel,
    preferredSessionDuration: memberProfile.preferredSessionDuration,
    preferredWorkoutDays: memberProfile.preferredWorkoutDays,
    preferredSplitType: memberProfile.preferredSplitType,
    preferredCardioDays: memberProfile.preferredCardioDays,
    trainingLocation: memberProfile.trainingLocation,
    availableEquipment: memberProfile.availableEquipment,
    emphasizedMuscleGroups: memberProfile.emphasizedMuscleGroups,
    excludedMuscleGroups: memberProfile.excludedMuscleGroups,
  };
}

// v234: Update training preferences in user's memberProfile
export async function updateTrainingPreferences(
  uid: string,
  preferences: Partial<TrainingPreferences>
): Promise<void> {
  const { updateDoc, setDoc } = await import('firebase/firestore');
  const db = getFirebaseDb();
  const userRef = doc(db, 'users', uid);

  // Build memberProfile update object
  const memberProfileUpdate: Record<string, unknown> = {};

  if (preferences.fitnessGoal !== undefined) {
    memberProfileUpdate['memberProfile.fitnessGoal'] = preferences.fitnessGoal;
  }
  if (preferences.experienceLevel !== undefined) {
    memberProfileUpdate['memberProfile.experienceLevel'] = preferences.experienceLevel;
  }
  if (preferences.preferredSessionDuration !== undefined) {
    memberProfileUpdate['memberProfile.preferredSessionDuration'] = preferences.preferredSessionDuration;
  }
  if (preferences.preferredWorkoutDays !== undefined) {
    memberProfileUpdate['memberProfile.preferredWorkoutDays'] = preferences.preferredWorkoutDays;
  }
  if (preferences.preferredSplitType !== undefined) {
    memberProfileUpdate['memberProfile.preferredSplitType'] = preferences.preferredSplitType;
  }
  if (preferences.preferredCardioDays !== undefined) {
    memberProfileUpdate['memberProfile.preferredCardioDays'] = preferences.preferredCardioDays;
  }

  try {
    await updateDoc(userRef, memberProfileUpdate);
  } catch (error) {
    // If document doesn't exist, create it with memberProfile
    const newDoc = {
      memberProfile: {
        fitnessGoal: preferences.fitnessGoal || 'strength',
        experienceLevel: preferences.experienceLevel || 'intermediate',
        preferredSessionDuration: preferences.preferredSessionDuration || 60,
        membershipStatus: 'active',
        memberSince: new Date().toISOString(),
      }
    };
    await setDoc(userRef, newDoc, { merge: true });
  }
}

// ============================================
// Detail View Queries
// ============================================

export async function getPlanWithPrograms(uid: string, planId: string): Promise<PlanDetails | null> {
  const db = getFirebaseDb();

  // Get plan
  const planRef = doc(db, 'users', uid, 'plans', planId);
  const planSnap = await getDoc(planRef);

  if (!planSnap.exists()) return null;

  const planData = planSnap.data();

  // Get programs
  const programsRef = collection(db, 'users', uid, 'plans', planId, 'programs');
  const programsQuery = query(programsRef, orderBy('startDate', 'asc'));
  const programsSnap = await getDocs(programsQuery);

  const programs: Program[] = programsSnap.docs.map(doc => ({
    id: doc.id,
    planId,
    ...doc.data(),
  } as Program));

  // v241: Count workouts by querying with programId (server doesn't populate workoutIds)
  const workoutsRef = collection(db, 'users', uid, 'workouts');
  let workoutCount = 0;

  for (const program of programs) {
    const workoutsQuery = query(workoutsRef, where('programId', '==', program.id));
    const workoutsSnap = await getDocs(workoutsQuery);
    const count = workoutsSnap.size;

    // Attach count to program for display
    (program as any).workoutCount = count;
    workoutCount += count;
  }

  return {
    id: planSnap.id,
    userId: uid,
    name: planData.name || 'Untitled Plan',
    status: planData.status || 'draft',
    programIds: planData.programIds || [],
    createdAt: toDate(planData.createdAt) || new Date(),
    updatedAt: toDate(planData.updatedAt) || new Date(),
    startDate: toDate(planData.startDate),
    endDate: toDate(planData.endDate),
    programs,
    workoutCount,
    goal: planData.goal,
    emphasizedMuscleGroups: planData.emphasizedMuscleGroups,
    trainingLocation: planData.trainingLocation,
    splitType: planData.splitType,
    daysPerWeek: planData.daysPerWeek,
    // v228: Additional fields for iOS parity
    weightliftingDays: planData.weightliftingDays,
    cardioDays: planData.cardioDays,
    preferredDays: planData.preferredDays,
  };
}

export async function getProgramWithWorkouts(
  uid: string,
  planId: string,
  programId: string
): Promise<ProgramDetails | null> {
  const db = getFirebaseDb();

  // Get program
  const programRef = doc(db, 'users', uid, 'plans', planId, 'programs', programId);
  const programSnap = await getDoc(programRef);

  if (!programSnap.exists()) return null;

  const programData = programSnap.data();

  // Get parent plan for context
  const planRef = doc(db, 'users', uid, 'plans', planId);
  const planSnap = await getDoc(planRef);
  const parentPlan = planSnap.exists()
    ? {
        id: planSnap.id,
        userId: uid,
        ...planSnap.data(),
        createdAt: toDate(planSnap.data().createdAt) || new Date(),
        updatedAt: toDate(planSnap.data().updatedAt) || new Date(),
      } as Plan
    : undefined;

  // Get workouts for this program by querying programId
  // v239: Query by programId instead of relying on workoutIds array
  const workoutsRef = collection(db, 'users', uid, 'workouts');
  const workoutsQuery = query(
    workoutsRef,
    where('programId', '==', programId),
    orderBy('scheduledDate', 'asc')
  );
  const workoutsSnap = await getDocs(workoutsQuery);

  const workouts: Workout[] = workoutsSnap.docs.map(workoutSnap => {
    const data = workoutSnap.data();
    return {
      id: workoutSnap.id,
      userId: uid,
      name: data.name || 'Untitled Workout',
      status: data.status || 'scheduled',
      exerciseIds: data.exerciseIds || [],
      scheduledDate: toDate(data.scheduledDate),
      completedDate: toDate(data.completedDate),
      splitDay: data.splitDay,
      sessionType: data.sessionType,
      estimatedDuration: data.estimatedDuration,
      actualDuration: data.actualDuration,
      programId: data.programId,
      planId: data.planId,
    };
  });

  return {
    id: programSnap.id,
    planId,
    name: programData.name || 'Untitled Program',
    phase: programData.phase || '',
    weekNumber: programData.weekNumber || 1,
    status: programData.status || 'pending',
    workoutIds: workouts.map(w => w.id),  // v239: Derive from query
    workouts,
    parentPlan,
    progressionType: programData.progressionType,
    intensity: programData.intensity,
    focus: programData.focus,
    startDate: toDate(programData.startDate),
    endDate: toDate(programData.endDate),
  };
}

export async function getWorkoutWithExercises(uid: string, workoutId: string): Promise<WorkoutDetails | null> {
  const db = getFirebaseDb();

  // Get workout
  const workoutRef = doc(db, 'users', uid, 'workouts', workoutId);
  const workoutSnap = await getDoc(workoutRef);

  if (!workoutSnap.exists()) return null;

  const workoutData = workoutSnap.data();

  // Get exercise instances
  const instancesRef = collection(db, 'users', uid, 'workouts', workoutId, 'exerciseInstances');
  const instancesQuery = query(instancesRef, orderBy('position', 'asc'));
  const instancesSnap = await getDocs(instancesQuery);

  const exercises: ExerciseInstanceDetails[] = [];

  for (const instanceDoc of instancesSnap.docs) {
    const instanceData = instanceDoc.data();

    // Get exercise details from global collection
    let exerciseName = 'Unknown Exercise';
    let equipment: string | undefined;

    if (instanceData.exerciseId) {
      const exerciseRef = doc(db, 'exercises', instanceData.exerciseId);
      const exerciseSnap = await getDoc(exerciseRef);
      if (exerciseSnap.exists()) {
        const exData = exerciseSnap.data();
        exerciseName = exData.name || exerciseName;
        equipment = exData.equipment;
      }
    }

    // Get sets for this instance
    const setsRef = collection(db, 'users', uid, 'workouts', workoutId, 'exerciseInstances', instanceDoc.id, 'sets');
    const setsQuery = query(setsRef, orderBy('setNumber', 'asc'));
    const setsSnap = await getDocs(setsQuery);

    const sets: ExerciseSet[] = setsSnap.docs.map(setDoc => ({
      id: setDoc.id,
      instanceId: instanceDoc.id,
      ...setDoc.data(),
    } as ExerciseSet));

    // Build prescription string
    const setCount = sets.length || instanceData.targetSets || 3;
    const reps = instanceData.targetReps || '8-12';
    const prescription = `${setCount} × ${reps}`;

    exercises.push({
      id: instanceDoc.id,
      workoutId,
      exerciseId: instanceData.exerciseId || '',
      position: instanceData.position || 0,
      protocolVariantId: instanceData.protocolVariantId,
      isCompleted: instanceData.isCompleted || false,
      name: exerciseName,
      equipment,
      prescription,
      status: instanceData.isCompleted ? 'completed' : (sets.some(s => s.isCompleted) ? 'in_progress' : 'pending'),
      sets,
    });
  }

  // Get parent program/plan if available
  let parentProgram: Program | undefined;
  let parentPlan: Plan | undefined;

  if (workoutData.programId && workoutData.planId) {
    const programRef = doc(db, 'users', uid, 'plans', workoutData.planId, 'programs', workoutData.programId);
    const programSnap = await getDoc(programRef);
    if (programSnap.exists()) {
      parentProgram = {
        id: programSnap.id,
        planId: workoutData.planId,
        ...programSnap.data(),
      } as Program;
    }

    const planRef = doc(db, 'users', uid, 'plans', workoutData.planId);
    const planSnap = await getDoc(planRef);
    if (planSnap.exists()) {
      parentPlan = {
        id: planSnap.id,
        userId: uid,
        ...planSnap.data(),
        createdAt: toDate(planSnap.data().createdAt) || new Date(),
        updatedAt: toDate(planSnap.data().updatedAt) || new Date(),
      } as Plan;
    }
  }

  return {
    id: workoutSnap.id,
    userId: uid,
    name: workoutData.name || 'Untitled Workout',
    status: workoutData.status || 'scheduled',
    exerciseIds: workoutData.exerciseIds || [],
    scheduledDate: toDate(workoutData.scheduledDate),
    completedDate: toDate(workoutData.completedDate),
    splitDay: workoutData.splitDay,
    sessionType: workoutData.sessionType,
    estimatedDuration: workoutData.estimatedDuration,
    actualDuration: workoutData.actualDuration,
    programId: workoutData.programId,
    planId: workoutData.planId,
    exercises,
    parentProgram,
    parentPlan,
  };
}

export async function getExerciseDetails(exerciseId: string, uid?: string): Promise<ExerciseDetails | null> {
  const db = getFirebaseDb();

  // Get exercise from global collection
  const exerciseRef = doc(db, 'exercises', exerciseId);
  const exerciseSnap = await getDoc(exerciseRef);

  if (!exerciseSnap.exists()) return null;

  const data = exerciseSnap.data();

  // Get user stats if uid provided
  let userStats: ExerciseDetails['userStats'];

  if (uid) {
    const statsRef = doc(db, 'users', uid, 'exerciseStats', exerciseId);
    const statsSnap = await getDoc(statsRef);

    if (statsSnap.exists()) {
      const statsData = statsSnap.data();
      userStats = {
        current1RM: statsData.current1RM,
        lastCalibrated: toDate(statsData.lastCalibrated),
      };
    }
  }

  return {
    id: exerciseSnap.id,
    name: data.name || 'Unknown Exercise',
    baseExercise: data.baseExercise,
    equipment: data.equipment,
    muscleGroups: data.muscleGroups || [],
    movementPattern: data.movementPattern,
    description: data.description,
    videoUrl: data.videoUrl,
    primaryMuscles: data.primaryMuscles || data.muscleGroups || [],
    secondaryMuscles: data.secondaryMuscles || [],
    difficulty: data.difficulty,
    instructions: data.instructions || data.description,
    userStats,
  };
}

// ============================================
// Library / Favorites (v242)
// Uses iOS Firestore path: users/{uid}/preferences/exercise.favorites
// ============================================

/**
 * Check if an exercise is in the user's library
 */
export async function isExerciseInLibrary(uid: string, exerciseId: string): Promise<boolean> {
  const db = getFirebaseDb();
  const prefsRef = doc(db, 'users', uid, 'preferences', 'exercise');
  const prefsSnap = await getDoc(prefsRef);

  if (!prefsSnap.exists()) return false;

  const favorites: string[] = prefsSnap.data()?.favorites || [];
  const normalizedId = exerciseId.toLowerCase().replace(/\s+/g, '_').replace(/-/g, '_');

  return favorites.includes(normalizedId);
}

/**
 * Get all library exercises with their details
 */
export async function getLibraryExercises(uid: string): Promise<Exercise[]> {
  const db = getFirebaseDb();

  // Get user's favorites from preferences
  const prefsRef = doc(db, 'users', uid, 'preferences', 'exercise');
  const prefsSnap = await getDoc(prefsRef);

  if (!prefsSnap.exists()) return [];

  const favorites: string[] = prefsSnap.data()?.favorites || [];
  if (favorites.length === 0) return [];

  // Fetch exercise details for each favorite
  const exercises: Exercise[] = [];
  for (const exerciseId of favorites) {
    const exerciseRef = doc(db, 'exercises', exerciseId);
    const exerciseSnap = await getDoc(exerciseRef);
    if (exerciseSnap.exists()) {
      exercises.push({
        id: exerciseSnap.id,
        ...exerciseSnap.data()
      } as Exercise);
    }
  }

  return exercises;
}

/**
 * Add an exercise to the user's library
 */
export async function addToLibrary(uid: string, exerciseId: string): Promise<void> {
  const { setDoc, arrayUnion } = await import('firebase/firestore');
  const db = getFirebaseDb();
  const prefsRef = doc(db, 'users', uid, 'preferences', 'exercise');

  const normalizedId = exerciseId.toLowerCase().replace(/\s+/g, '_').replace(/-/g, '_');

  await setDoc(prefsRef, {
    favorites: arrayUnion(normalizedId),
    lastModified: new Date()
  }, { merge: true });
}

/**
 * Remove an exercise from the user's library
 */
export async function removeFromLibrary(uid: string, exerciseId: string): Promise<void> {
  const { setDoc, arrayRemove } = await import('firebase/firestore');
  const db = getFirebaseDb();
  const prefsRef = doc(db, 'users', uid, 'preferences', 'exercise');

  const normalizedId = exerciseId.toLowerCase().replace(/\s+/g, '_').replace(/-/g, '_');

  await setDoc(prefsRef, {
    favorites: arrayRemove(normalizedId),
    lastModified: new Date()
  }, { merge: true });
}
