/**
 * Medina Shared Constants
 *
 * Cross-platform configuration values used by both iOS and Web.
 */

import type { TrainingFocus, EffortLevel } from '../types';

// ============================================================================
// Intensity Ranges by Training Focus
// ============================================================================

export const INTENSITY_RANGES: Record<TrainingFocus, { min: number; max: number; rpe: string }> = {
  foundation:   { min: 0.60, max: 0.70, rpe: '6-7' },
  development:  { min: 0.70, max: 0.80, rpe: '7-8' },
  peak:         { min: 0.80, max: 0.90, rpe: '8-9+' },
  maintenance:  { min: 0.65, max: 0.75, rpe: '7-8' },
  deload:       { min: 0.50, max: 0.60, rpe: '5-6' },
};

// ============================================================================
// Effort Level Mapping (Single Workout)
// ============================================================================

export const EFFORT_LEVELS: Record<EffortLevel, { intensity: [number, number]; rpe: string; description: string }> = {
  recovery: {
    intensity: [0.55, 0.65],
    rpe: '6-7',
    description: 'Active recovery, deload',
  },
  standard: {
    intensity: [0.65, 0.75],
    rpe: '7-8',
    description: 'Regular training session',
  },
  pushIt: {
    intensity: [0.75, 0.85],
    rpe: '8-9+',
    description: 'High intensity day',
  },
};

// ============================================================================
// Protocol Defaults
// ============================================================================

export const PROTOCOL_DEFAULTS = {
  // Compound exercises
  compound: {
    lowIntensity:  { sets: 3, reps: 5, rest: 180, rpe: 7 },   // 3x5 moderate
    midIntensity:  { sets: 3, reps: 5, rest: 180, rpe: 8 },   // 3x5 heavy
    highIntensity: { sets: 3, reps: 3, rest: 240, rpe: 9 },   // 3x3 peak
  },
  // Isolation exercises
  isolation: {
    lowIntensity:  { sets: 3, reps: 12, rest: 60, rpe: 7 },   // 3x12 light
    midIntensity:  { sets: 3, reps: 10, rest: 90, rpe: 8 },   // 3x10 moderate
    highIntensity: { sets: 3, reps: 8, rest: 90, rpe: 8.5 },  // 3x8 heavy
  },
};

// ============================================================================
// Workout Duration Defaults
// ============================================================================

export const DURATION_DEFAULTS = {
  minSessionMinutes: 30,
  defaultSessionMinutes: 60,
  maxSessionMinutes: 90,
  warmupPercentage: 0.10,  // 10% of session reserved for warmup/transitions
  compoundTimeAllocation: 0.60,  // 60% of exercise time for compounds
};

// ============================================================================
// Plan Duration Thresholds
// ============================================================================

export const PLAN_DURATION = {
  minWeeks: 4,
  shortPlanWeeks: 8,    // 2 programs (Foundation -> Development)
  mediumPlanWeeks: 12,  // 3 programs (Foundation -> Development -> Peak)
  longPlanWeeks: 24,    // 4+ programs with optional deload
};

// ============================================================================
// Weight Calculation (Epley Formula)
// ============================================================================

export const WEIGHT_CALCULATION = {
  // 1RM = weight × (1 + reps/30)
  epleyDivisor: 30,
  // Minimum weight increment (lbs)
  minWeightIncrement: 2.5,
  // Round to nearest increment
  roundToNearest: 5,
};
