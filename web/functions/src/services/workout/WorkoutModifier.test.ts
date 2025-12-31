/**
 * Workout Modifier Service Tests
 *
 * Tests for workout modification logic:
 * - Change classification (metadata vs structural vs substitution)
 * - Change description generation
 * - In-place updates vs rebuilds
 */

import {describe, it, expect} from 'vitest';
import {
  classifyChange,
  describeChanges,
  ModifyWorkoutRequest,
} from './WorkoutModifier';
import type {WorkoutDocument} from './types';

// ============================================================================
// Test Data
// ============================================================================

const BASE_WORKOUT: WorkoutDocument = {
  id: 'test_workout_123',
  name: 'Upper Body Strength',
  scheduledDate: '2024-01-15T10:00:00.000Z',
  type: 'strength',
  splitDay: 'upper',
  status: 'scheduled',
  exerciseIds: ['bench_press', 'rows', 'overhead_press'],
  protocolVariantIds: {0: 'strength_3x5_heavy', 1: 'strength_3x5_heavy', 2: 'accessory_3x10_rpe8'},
  createdAt: '2024-01-10T10:00:00.000Z',
  updatedAt: '2024-01-10T10:00:00.000Z',
  effortLevel: 'standard',
  targetDuration: 45,
};

const BASE_REQUEST: ModifyWorkoutRequest = {
  userId: 'user_123',
  workoutId: 'test_workout_123',
};

// ============================================================================
// classifyChange Tests
// ============================================================================

describe('classifyChange', () => {
  describe('metadata changes', () => {
    it('classifies name change as metadata', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newName: 'New Workout Name',
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('metadata');
    });

    it('classifies date change as metadata', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newScheduledDate: new Date('2024-01-20'),
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('metadata');
    });

    it('classifies effort level change as metadata', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newEffortLevel: 'push',
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('metadata');
    });

    it('classifies combined metadata changes as metadata', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newName: 'New Name',
        newScheduledDate: new Date('2024-01-20'),
        newEffortLevel: 'recovery',
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('metadata');
    });
  });

  describe('structural changes', () => {
    it('classifies split day change as structural', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newSplitDay: 'lower',
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('structural');
    });

    it('classifies session type change as structural', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newSessionType: 'cardio',
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('structural');
    });

    it('classifies large duration change (>15 min) as structural', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newDuration: 75, // 45 + 30 = 75
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('structural');
    });

    it('classifies small duration change (<=15 min) as metadata', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newDuration: 55, // 45 + 10 = 55
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('metadata');
    });

    it('classifies training location change as structural', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newTrainingLocation: 'home',
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('structural');
    });

    it('classifies equipment change as structural', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newAvailableEquipment: ['bodyweight', 'dumbbells'],
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('structural');
    });
  });

  describe('substitution changes', () => {
    it('classifies exercise substitutions as substitution', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        exerciseSubstitutions: [
          {position: 0, newExerciseId: 'dumbbell_bench_press', reason: 'No barbell'},
        ],
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('substitution');
    });

    it('classifies multiple substitutions as substitution', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        exerciseSubstitutions: [
          {position: 0, newExerciseId: 'dumbbell_bench_press'},
          {position: 1, newExerciseId: 'cable_rows'},
        ],
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('substitution');
    });
  });

  describe('priority order', () => {
    it('structural takes priority over substitution', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newSplitDay: 'lower',
        exerciseSubstitutions: [{position: 0, newExerciseId: 'squat'}],
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('structural');
    });

    it('substitution takes priority over metadata', () => {
      const request: ModifyWorkoutRequest = {
        ...BASE_REQUEST,
        newName: 'New Name',
        exerciseSubstitutions: [{position: 0, newExerciseId: 'dumbbell_bench'}],
      };

      expect(classifyChange(BASE_WORKOUT, request)).toBe('substitution');
    });
  });
});

// ============================================================================
// describeChanges Tests
// ============================================================================

describe('describeChanges', () => {
  it('describes name change', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
      newName: 'New Workout',
    };

    const description = describeChanges(BASE_WORKOUT, request, 'metadata');

    expect(description).toContain('name:');
    expect(description).toContain('Upper Body Strength');
    expect(description).toContain('New Workout');
  });

  it('describes date change', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
      newScheduledDate: new Date('2024-01-20'),
    };

    const description = describeChanges(BASE_WORKOUT, request, 'metadata');

    expect(description).toContain('date:');
    expect(description).toContain('2024-01-15');
    expect(description).toContain('2024-01-20');
  });

  it('describes effort level change', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
      newEffortLevel: 'push',
    };

    const description = describeChanges(BASE_WORKOUT, request, 'metadata');

    expect(description).toContain('effort:');
    expect(description).toContain('standard');
    expect(description).toContain('push');
  });

  it('describes split day change', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
      newSplitDay: 'lower',
    };

    const description = describeChanges(BASE_WORKOUT, request, 'structural');

    expect(description).toContain('split:');
    expect(description).toContain('upper');
    expect(description).toContain('lower');
  });

  it('describes duration change', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
      newDuration: 60,
    };

    const description = describeChanges(BASE_WORKOUT, request, 'structural');

    expect(description).toContain('duration:');
    expect(description).toContain('45min');
    expect(description).toContain('60min');
  });

  it('describes exercise substitutions', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
      exerciseSubstitutions: [
        {position: 0, newExerciseId: 'dumbbell_bench'},
        {position: 1, newExerciseId: 'cable_rows'},
      ],
    };

    const description = describeChanges(BASE_WORKOUT, request, 'substitution');

    expect(description).toContain('2 exercise substitution(s)');
  });

  it('describes multiple changes', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
      newName: 'New Name',
      newScheduledDate: new Date('2024-01-20'),
      newEffortLevel: 'push',
    };

    const description = describeChanges(BASE_WORKOUT, request, 'metadata');

    expect(description).toContain('name:');
    expect(description).toContain('date:');
    expect(description).toContain('effort:');
  });

  it('returns "no changes" when nothing changed', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
    };

    const description = describeChanges(BASE_WORKOUT, request, 'metadata');

    expect(description).toBe('no changes');
  });

  it('handles same-value changes as no change', () => {
    const request: ModifyWorkoutRequest = {
      ...BASE_REQUEST,
      newName: BASE_WORKOUT.name, // Same name
      newEffortLevel: BASE_WORKOUT.effortLevel, // Same effort
    };

    const description = describeChanges(BASE_WORKOUT, request, 'metadata');

    expect(description).toBe('no changes');
  });
});
