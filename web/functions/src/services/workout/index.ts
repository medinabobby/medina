/**
 * Workout Service Layer
 *
 * Unified export for all workout-related services.
 *
 * Services:
 * - StrengthBuilder: Main orchestrator for strength workouts
 * - ExerciseSelector: Selects exercises based on constraints
 * - ProtocolAssigner: Assigns protocols to exercises
 * - InstanceCreator: Creates exercise instances and sets
 * - WorkoutModifier: In-place workout modifications with history tracking
 *
 * Future:
 * - CardioBuilder: Separate service for cardio workouts
 * - SupersetPairer: Superset logic (migrated from iOS)
 */

// Types
export * from './types';

// Main builder
export {
  buildStrengthWorkout,
  getActivePlan,
  validateBuildRequest,
  parseScheduledDate,
  formatDate,
} from './StrengthBuilder';

// Exercise selection
export {
  selectExercises,
  calculateExerciseCount,
  determinePrimaryEquipment,
} from './ExerciseSelector';

// Protocol assignment
export {
  assignProtocols,
  getProtocolDuration,
  calculateWorkoutDuration,
  getIntensity,
  calculateTargetWeight,
} from './ProtocolAssigner';

// Instance creation
export {
  createInstances,
  CreateInstancesRequest,
  CreateInstancesResult,
} from './InstanceCreator';

// Workout modification
export {
  modifyWorkout,
  classifyChange,
  describeChanges,
  saveHistory,
  ModifyWorkoutRequest,
  ModifyWorkoutResult,
  ExerciseSubstitution,
  ChangeType,
  WorkoutHistoryEntry,
} from './WorkoutModifier';

// Superset pairing
export {
  createSupersets,
  loadExerciseInfo,
  SupersetStyle,
  SupersetGroupIntent,
  SupersetGroup,
  SupersetResult,
  ExerciseInfo,
} from './SupersetPairer';
