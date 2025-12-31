/**
 * Protocol Assigner Service
 *
 * Assigns protocols to exercises based on effort level and exercise type.
 * Uses simple lookup tables instead of complex data-driven selection.
 *
 * Key features:
 * - Lookup table for protocol selection by effort level + exercise type
 * - Duration estimation per protocol
 * - Override support for specific protocols
 */

import {
  ExerciseDoc,
  ExerciseType,
  EffortLevel,
  ProtocolAssignmentRequest,
  ProtocolAssignmentResult,
  PROTOCOL_MAP,
  EFFORT_INTENSITY,
} from './types';

// ============================================================================
// Protocol Duration Constants
// ============================================================================

/**
 * Estimated duration per protocol (minutes)
 * Based on sets × (work time + rest time)
 */
const PROTOCOL_DURATION: Record<string, number> = {
  // Strength protocols
  'strength_3x5_moderate': 8,    // 3 sets × (30s work + 2min rest) ≈ 8min
  'strength_3x5_heavy': 9,       // 3 sets × (30s work + 2.5min rest) ≈ 9min
  'strength_3x3_heavy': 8,       // 3 sets × (20s work + 2.5min rest) ≈ 8min

  // Accessory protocols
  'accessory_3x12_light': 7,     // 3 sets × (45s work + 1.5min rest) ≈ 7min
  'accessory_3x10_rpe8': 8,      // 3 sets × (40s work + 2min rest) ≈ 8min
  'accessory_3x8_rpe8': 7,       // 3 sets × (30s work + 2min rest) ≈ 7min

  // Cardio protocols
  'cardio_30min_steady': 30,
  'cardio_30min_intervals': 30,
  'cardio_20min_hiit': 20,
};

/**
 * Default duration when protocol not in lookup
 */
const DEFAULT_DURATION = 8;

// ============================================================================
// Main Function
// ============================================================================

/**
 * Assign protocols to exercises
 *
 * @param request - Assignment request with exercises and effort level
 * @returns Protocol IDs for each exercise position and estimated total duration
 */
export function assignProtocols(
  request: ProtocolAssignmentRequest
): ProtocolAssignmentResult {
  const { exercises, effortLevel, protocolOverride } = request;
  const protocolIds: Record<number, string> = {};
  let totalDuration = 0;

  for (let i = 0; i < exercises.length; i++) {
    const exercise = exercises[i];

    // Use override if provided, otherwise look up by effort level + exercise type
    const protocolId = protocolOverride || getProtocolForExercise(exercise, effortLevel);

    protocolIds[i] = protocolId;
    totalDuration += getProtocolDuration(protocolId);
  }

  console.log(
    `[ProtocolAssigner] Assigned ${exercises.length} protocols, ` +
    `estimated ${totalDuration}min total`
  );

  return {
    protocolIds,
    estimatedDuration: totalDuration,
  };
}

// ============================================================================
// Protocol Selection
// ============================================================================

/**
 * Get protocol ID for an exercise based on effort level
 */
function getProtocolForExercise(
  exercise: ExerciseDoc,
  effortLevel: EffortLevel
): string {
  const exerciseType = exercise.exerciseType || 'compound';

  // Look up in protocol map
  const effortMap = PROTOCOL_MAP[effortLevel];
  if (effortMap && effortMap[exerciseType]) {
    return effortMap[exerciseType];
  }

  // Fallback based on exercise type
  return getDefaultProtocol(exerciseType);
}

/**
 * Get default protocol for exercise type
 */
function getDefaultProtocol(exerciseType: ExerciseType): string {
  switch (exerciseType) {
  case 'compound':
    return 'strength_3x5_moderate';
  case 'isolation':
    return 'accessory_3x10_rpe8';
  case 'cardio':
    return 'cardio_30min_steady';
  default:
    return 'strength_3x5_moderate';
  }
}

// ============================================================================
// Duration Calculation
// ============================================================================

/**
 * Get estimated duration for a protocol
 */
export function getProtocolDuration(protocolId: string): number {
  return PROTOCOL_DURATION[protocolId] || DEFAULT_DURATION;
}

/**
 * Calculate total workout duration from protocols
 */
export function calculateWorkoutDuration(protocolIds: Record<number, string>): number {
  let total = 0;
  for (const protocolId of Object.values(protocolIds)) {
    total += getProtocolDuration(protocolId);
  }
  return total;
}

// ============================================================================
// Intensity
// ============================================================================

/**
 * Get intensity percentage from effort level
 */
export function getIntensity(effortLevel: EffortLevel): number {
  return EFFORT_INTENSITY[effortLevel] || 0.75;
}

/**
 * Calculate target weight from 1RM and intensity
 */
export function calculateTargetWeight(
  oneRepMax: number | undefined,
  intensity: number
): number | undefined {
  if (!oneRepMax) return undefined;

  // Round to nearest 5
  const raw = oneRepMax * intensity;
  return Math.round(raw / 5) * 5;
}
