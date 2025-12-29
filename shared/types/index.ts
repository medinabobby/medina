/**
 * Medina Shared Types
 *
 * Cross-platform type definitions used by both iOS and Web.
 * iOS can generate Swift types from these via codegen.
 */

// ============================================================================
// User Types
// ============================================================================

export type UserRole = 'member' | 'trainer' | 'admin' | 'gymOwner';

export interface UserProfile {
  birthdate?: string;
  heightInches?: number;
  currentWeight?: number;
  fitnessGoal?: FitnessGoal;
  experienceLevel?: ExperienceLevel;
  preferredDays?: DayOfWeek[];
  sessionDuration?: number;
  gender?: Gender;
  personalMotivation?: string;
}

export type FitnessGoal = 'strength' | 'muscle' | 'fatLoss' | 'general';
export type ExperienceLevel = 'beginner' | 'intermediate' | 'advanced';
export type Gender = 'male' | 'female' | 'other' | 'preferNotToSay';
export type DayOfWeek = 'monday' | 'tuesday' | 'wednesday' | 'thursday' | 'friday' | 'saturday' | 'sunday';

// ============================================================================
// Training Types
// ============================================================================

export type TrainingFocus =
  | 'foundation'    // 60-70% intensity, RPE 6-7
  | 'development'   // 70-80% intensity, RPE 7-8
  | 'peak'          // 80-90% intensity, RPE 8-9+
  | 'maintenance'   // 65-75% intensity, RPE 7-8
  | 'deload';       // 50-60% intensity, RPE 5-6

export type ProgressionType = 'linear' | 'wave' | 'static';

export type SplitType =
  | 'fullBody'
  | 'upperLower'
  | 'pushPullLegs'
  | 'bro';

export type SplitDay =
  | 'push'
  | 'pull'
  | 'legs'
  | 'upper'
  | 'lower'
  | 'fullBody'
  | 'chest'
  | 'back'
  | 'shoulders'
  | 'arms';

export type TrainingLocation = 'gym' | 'home';

// ============================================================================
// Workout Types
// ============================================================================

export type WorkoutStatus = 'scheduled' | 'inProgress' | 'completed' | 'skipped';
export type InstanceStatus = 'pending' | 'inProgress' | 'completed' | 'skipped';
export type PlanStatus = 'draft' | 'active' | 'completed' | 'abandoned';

// ============================================================================
// Exercise Types
// ============================================================================

export type ExerciseCategory = 'compound' | 'isolation';

export type MovementPattern =
  | 'push'
  | 'pull'
  | 'squat'
  | 'hinge'
  | 'carry'
  | 'rotation';

export type MuscleGroup =
  | 'chest'
  | 'back'
  | 'shoulders'
  | 'biceps'
  | 'triceps'
  | 'forearms'
  | 'core'
  | 'quadriceps'
  | 'hamstrings'
  | 'glutes'
  | 'calves';

export type Equipment =
  | 'barbell'
  | 'dumbbell'
  | 'cable'
  | 'machine'
  | 'bodyweight'
  | 'kettlebell'
  | 'bands'
  | 'smith';

// ============================================================================
// Effort Levels (Single Workout)
// ============================================================================

export type EffortLevel = 'recovery' | 'standard' | 'pushIt';
