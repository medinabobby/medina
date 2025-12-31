/**
 * Protocol Assigner Service Tests
 *
 * Tests for protocol assignment logic:
 * - Protocol selection by effort level + exercise type
 * - Duration calculation
 * - Target weight calculation
 */

import { describe, it, expect } from 'vitest';
import {
  assignProtocols,
  getProtocolDuration,
  calculateWorkoutDuration,
  getIntensity,
  calculateTargetWeight,
} from './ProtocolAssigner';
import type { ExerciseDoc, EffortLevel } from './types';

// ============================================================================
// Test Data
// ============================================================================

const COMPOUND_EXERCISE: ExerciseDoc = {
  id: 'barbell_bench_press',
  name: 'Barbell Bench Press',
  muscleGroups: ['chest', 'triceps'],
  exerciseType: 'compound',
  equipment: 'barbell',
};

const ISOLATION_EXERCISE: ExerciseDoc = {
  id: 'bicep_curl',
  name: 'Bicep Curl',
  muscleGroups: ['biceps'],
  exerciseType: 'isolation',
  equipment: 'dumbbells',
};

const CARDIO_EXERCISE: ExerciseDoc = {
  id: 'treadmill_run',
  name: 'Treadmill Run',
  muscleGroups: ['cardio'],
  exerciseType: 'cardio',
  equipment: 'machine',
};

// ============================================================================
// assignProtocols Tests
// ============================================================================

describe('assignProtocols', () => {
  describe('recovery effort level', () => {
    it('assigns moderate protocol to compound exercises', () => {
      const result = assignProtocols({
        exercises: [COMPOUND_EXERCISE],
        effortLevel: 'recovery',
      });

      expect(result.protocolIds[0]).toBe('strength_3x5_moderate');
    });

    it('assigns light protocol to isolation exercises', () => {
      const result = assignProtocols({
        exercises: [ISOLATION_EXERCISE],
        effortLevel: 'recovery',
      });

      expect(result.protocolIds[0]).toBe('accessory_3x12_light');
    });
  });

  describe('standard effort level', () => {
    it('assigns heavy protocol to compound exercises', () => {
      const result = assignProtocols({
        exercises: [COMPOUND_EXERCISE],
        effortLevel: 'standard',
      });

      expect(result.protocolIds[0]).toBe('strength_3x5_heavy');
    });

    it('assigns rpe8 protocol to isolation exercises', () => {
      const result = assignProtocols({
        exercises: [ISOLATION_EXERCISE],
        effortLevel: 'standard',
      });

      expect(result.protocolIds[0]).toBe('accessory_3x10_rpe8');
    });
  });

  describe('push effort level', () => {
    it('assigns 3x3 heavy protocol to compound exercises', () => {
      const result = assignProtocols({
        exercises: [COMPOUND_EXERCISE],
        effortLevel: 'push',
      });

      expect(result.protocolIds[0]).toBe('strength_3x3_heavy');
    });

    it('assigns 3x8 rpe8 protocol to isolation exercises', () => {
      const result = assignProtocols({
        exercises: [ISOLATION_EXERCISE],
        effortLevel: 'push',
      });

      expect(result.protocolIds[0]).toBe('accessory_3x8_rpe8');
    });
  });

  describe('cardio exercises', () => {
    it('assigns cardio protocol regardless of effort level', () => {
      const efforts: EffortLevel[] = ['recovery', 'standard', 'push'];

      for (const effort of efforts) {
        const result = assignProtocols({
          exercises: [CARDIO_EXERCISE],
          effortLevel: effort,
        });

        expect(result.protocolIds[0]).toContain('cardio');
      }
    });
  });

  describe('mixed exercises', () => {
    it('assigns appropriate protocols to each exercise type', () => {
      const result = assignProtocols({
        exercises: [COMPOUND_EXERCISE, ISOLATION_EXERCISE],
        effortLevel: 'standard',
      });

      expect(result.protocolIds[0]).toBe('strength_3x5_heavy');
      expect(result.protocolIds[1]).toBe('accessory_3x10_rpe8');
    });
  });

  describe('protocol override', () => {
    it('uses override protocol for all exercises when specified', () => {
      const result = assignProtocols({
        exercises: [COMPOUND_EXERCISE, ISOLATION_EXERCISE],
        effortLevel: 'standard',
        protocolOverride: 'gbc_protocol',
      });

      expect(result.protocolIds[0]).toBe('gbc_protocol');
      expect(result.protocolIds[1]).toBe('gbc_protocol');
    });
  });

  describe('duration estimation', () => {
    it('calculates total duration from all protocols', () => {
      const result = assignProtocols({
        exercises: [COMPOUND_EXERCISE, ISOLATION_EXERCISE],
        effortLevel: 'standard',
      });

      // strength_3x5_heavy = 9min, accessory_3x10_rpe8 = 8min
      expect(result.estimatedDuration).toBe(17);
    });
  });
});

// ============================================================================
// getProtocolDuration Tests
// ============================================================================

describe('getProtocolDuration', () => {
  it('returns correct duration for strength protocols', () => {
    expect(getProtocolDuration('strength_3x5_moderate')).toBe(8);
    expect(getProtocolDuration('strength_3x5_heavy')).toBe(9);
    expect(getProtocolDuration('strength_3x3_heavy')).toBe(8);
  });

  it('returns correct duration for accessory protocols', () => {
    expect(getProtocolDuration('accessory_3x12_light')).toBe(7);
    expect(getProtocolDuration('accessory_3x10_rpe8')).toBe(8);
    expect(getProtocolDuration('accessory_3x8_rpe8')).toBe(7);
  });

  it('returns correct duration for cardio protocols', () => {
    expect(getProtocolDuration('cardio_30min_steady')).toBe(30);
    expect(getProtocolDuration('cardio_20min_hiit')).toBe(20);
  });

  it('returns default duration for unknown protocols', () => {
    expect(getProtocolDuration('unknown_protocol')).toBe(8);
  });
});

// ============================================================================
// calculateWorkoutDuration Tests
// ============================================================================

describe('calculateWorkoutDuration', () => {
  it('sums all protocol durations', () => {
    const protocolIds = {
      0: 'strength_3x5_heavy', // 9min
      1: 'accessory_3x10_rpe8', // 8min
      2: 'accessory_3x12_light', // 7min
    };

    expect(calculateWorkoutDuration(protocolIds)).toBe(24);
  });

  it('returns 0 for empty protocol list', () => {
    expect(calculateWorkoutDuration({})).toBe(0);
  });
});

// ============================================================================
// getIntensity Tests
// ============================================================================

describe('getIntensity', () => {
  it('returns 60% for recovery', () => {
    expect(getIntensity('recovery')).toBe(0.60);
  });

  it('returns 75% for standard', () => {
    expect(getIntensity('standard')).toBe(0.75);
  });

  it('returns 85% for push', () => {
    expect(getIntensity('push')).toBe(0.85);
  });
});

// ============================================================================
// calculateTargetWeight Tests
// ============================================================================

describe('calculateTargetWeight', () => {
  it('calculates target weight from 1RM and intensity', () => {
    // 200 lb 1RM × 0.75 intensity = 150 lb
    expect(calculateTargetWeight(200, 0.75)).toBe(150);
  });

  it('rounds to nearest 5', () => {
    // 225 × 0.75 = 168.75 → rounds to 170
    expect(calculateTargetWeight(225, 0.75)).toBe(170);

    // 225 × 0.60 = 135 → stays 135
    expect(calculateTargetWeight(225, 0.60)).toBe(135);

    // 100 × 0.85 = 85 → stays 85
    expect(calculateTargetWeight(100, 0.85)).toBe(85);
  });

  it('returns undefined when no 1RM', () => {
    expect(calculateTargetWeight(undefined, 0.75)).toBeUndefined();
  });

  it('handles low intensities', () => {
    // 100 × 0.50 = 50
    expect(calculateTargetWeight(100, 0.50)).toBe(50);
  });
});
