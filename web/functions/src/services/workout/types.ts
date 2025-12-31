/**
 * Workout Service Types
 *
 * Shared types for the workout service layer.
 * Used by StrengthBuilder, CardioBuilder, ExerciseSelector, ProtocolAssigner, InstanceCreator.
 */

import type * as admin from 'firebase-admin';

// ============================================================================
// Enums
// ============================================================================

/**
 * Split day types (matches iOS SplitDay enum)
 */
export type SplitDay =
  | 'upper'
  | 'lower'
  | 'push'
  | 'pull'
  | 'legs'
  | 'fullBody'
  | 'chest'
  | 'back'
  | 'shoulders'
  | 'arms'
  | 'notApplicable';

/**
 * Effort level types (matches iOS EffortLevel enum)
 */
export type EffortLevel = 'recovery' | 'standard' | 'push';

/**
 * Session type (strength or cardio)
 */
export type SessionType = 'strength' | 'cardio';

/**
 * Workout status types
 */
export type WorkoutStatus = 'scheduled' | 'inProgress' | 'completed' | 'skipped';

/**
 * Training location types
 */
export type TrainingLocation = 'home' | 'gym' | 'outdoor' | 'hybrid';

/**
 * Equipment types
 */
export type Equipment =
  | 'barbell'
  | 'dumbbells'
  | 'machine'
  | 'cable'
  | 'bodyweight'
  | 'resistanceBand'
  | 'kettlebell'
  | 'none';

/**
 * Exercise type (compound vs isolation)
 */
export type ExerciseType = 'compound' | 'isolation' | 'cardio';

// ============================================================================
// Exercise Types
// ============================================================================

/**
 * Exercise document from Firestore
 */
export interface ExerciseDoc {
  id: string;
  name: string;
  muscleGroups: string[];
  exerciseType: ExerciseType;
  equipment: Equipment;
  baseExercise?: string; // For deduplication (e.g., "bench press" for both barbell and dumbbell variants)
}

/**
 * Exercise target (user's 1RM data)
 */
export interface ExerciseTargetDoc {
  exerciseId: string;
  oneRepMax?: number;
  lastUpdated?: string;
}

// ============================================================================
// Workout Documents
// ============================================================================

/**
 * Workout document structure for Firestore
 */
export interface WorkoutDocument {
  id: string;
  name: string;
  scheduledDate: string;
  type: SessionType;
  splitDay: SplitDay;
  status: WorkoutStatus;
  exerciseIds: string[];
  protocolVariantIds: Record<string, string>;
  planId?: string;
  programId?: string;
  createdAt: string;
  updatedAt: string;
  // v236: Added for modification tracking
  version?: number;
  effortLevel?: EffortLevel;
  targetDuration?: number;
}

/**
 * Exercise instance document for Firestore
 */
export interface ExerciseInstanceDocument {
  id: string;
  workoutId: string;
  exerciseId: string;
  protocolVariantId: string;
  position: number;
  targetWeight?: number;
  createdAt: string;
  // v236: Added for substitution tracking
  substitutedFrom?: string;
  substitutionReason?: string;
}

/**
 * Exercise set document for Firestore
 */
export interface ExerciseSetDocument {
  id: string;
  instanceId: string;
  setNumber: number;
  targetReps: number;
  targetWeight?: number;
  createdAt: string;
}

// ============================================================================
// Builder Types
// ============================================================================

/**
 * Request to build a workout
 */
export interface WorkoutBuildRequest {
  userId: string;
  targetDuration: number; // minutes
  splitDay: SplitDay;
  effortLevel: EffortLevel;
  sessionType: SessionType;
  name: string;
  scheduledDate: Date;

  // Optional constraints
  exerciseIds?: string[]; // AI-provided (validated)
  availableEquipment?: Equipment[];
  trainingLocation?: TrainingLocation;
  protocolOverride?: string; // Force specific protocol

  // Plan context
  planId?: string;
  programId?: string;

  // v236: For modification (rebuild while preserving ID)
  existingWorkoutId?: string;
}

/**
 * Result of workout building
 */
export interface WorkoutBuildResult {
  workout: WorkoutDocument;
  instances: ExerciseInstanceDocument[];
  sets: ExerciseSetDocument[];
  actualDuration: number; // minutes
  exerciseCount: number;
}

// ============================================================================
// Selection Types
// ============================================================================

/**
 * Request for exercise selection
 */
export interface ExerciseSelectionRequest {
  splitDay: SplitDay;
  sessionType: SessionType;
  targetCount: number;
  requestedExerciseIds?: string[];
  availableEquipment?: Equipment[];
  trainingLocation?: TrainingLocation;
}

/**
 * Result of exercise selection
 */
export interface ExerciseSelectionResult {
  exercises: ExerciseDoc[];
  wasSupplemented: boolean; // True if library exercises were added
  aiExerciseCount: number;
  supplementedCount: number;
}

// ============================================================================
// Protocol Types
// ============================================================================

/**
 * Request for protocol assignment
 */
export interface ProtocolAssignmentRequest {
  exercises: ExerciseDoc[];
  effortLevel: EffortLevel;
  protocolOverride?: string;
}

/**
 * Result of protocol assignment
 */
export interface ProtocolAssignmentResult {
  protocolIds: Record<number, string>; // position -> protocolId
  estimatedDuration: number; // minutes
}

// ============================================================================
// Context Types
// ============================================================================

/**
 * Service context for database access
 */
export interface ServiceContext {
  userId: string;
  db: admin.firestore.Firestore;
}

// ============================================================================
// Constants
// ============================================================================

/**
 * Muscle groups for each split day
 */
export const SPLIT_DAY_MUSCLES: Record<SplitDay, string[]> = {
  upper: ['chest', 'back', 'lats', 'shoulders', 'biceps', 'triceps'],
  lower: ['quadriceps', 'hamstrings', 'glutes', 'calves'],
  push: ['chest', 'shoulders', 'triceps'],
  pull: ['back', 'lats', 'biceps', 'traps'],
  legs: ['quadriceps', 'hamstrings', 'glutes', 'calves'],
  fullBody: ['chest', 'back', 'lats', 'quadriceps', 'hamstrings', 'shoulders', 'biceps', 'triceps', 'glutes'],
  chest: ['chest', 'triceps'],
  back: ['back', 'lats', 'biceps', 'traps'],
  shoulders: ['shoulders', 'traps'],
  arms: ['biceps', 'triceps', 'forearms'],
  notApplicable: [],
};

/**
 * Average time per exercise by equipment type (minutes)
 * Based on real workout data: includes work time + setup + transition
 */
export const AVG_TIME_PER_EXERCISE: Record<Equipment, number> = {
  bodyweight: 8.0,
  resistanceBand: 8.0,
  cable: 8.5,
  machine: 8.0,
  dumbbells: 9.0,
  barbell: 9.5,
  kettlebell: 8.5,
  none: 8.0,
};

/**
 * Effort level to intensity mapping
 */
export const EFFORT_INTENSITY: Record<EffortLevel, number> = {
  recovery: 0.60,
  standard: 0.75,
  push: 0.85,
};

/**
 * Protocol lookup table by effort level and exercise type
 */
export const PROTOCOL_MAP: Record<EffortLevel, Record<ExerciseType, string>> = {
  recovery: {
    compound: 'strength_3x5_moderate',
    isolation: 'accessory_3x12_light',
    cardio: 'cardio_30min_steady',
  },
  standard: {
    compound: 'strength_3x5_heavy',
    isolation: 'accessory_3x10_rpe8',
    cardio: 'cardio_30min_intervals',
  },
  push: {
    compound: 'strength_3x3_heavy',
    isolation: 'accessory_3x8_rpe8',
    cardio: 'cardio_20min_hiit',
  },
};
