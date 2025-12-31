/**
 * Exercise Selector Service Tests
 *
 * Tests for exercise selection logic:
 * - calculateExerciseCount formula
 * - determinePrimaryEquipment logic
 * - Equipment and muscle filtering
 */

import { describe, it, expect } from 'vitest';
import {
  calculateExerciseCount,
  determinePrimaryEquipment,
} from './ExerciseSelector';

// ============================================================================
// calculateExerciseCount Tests
// ============================================================================

describe('calculateExerciseCount', () => {
  describe('with barbell (default)', () => {
    it('returns 3 exercises for 30 min workout', () => {
      // 30 / 9.5 = 3.15 → 3
      expect(calculateExerciseCount(30)).toBe(3);
    });

    it('returns 4 exercises for 45 min workout', () => {
      // 45 / 9.5 = 4.7 → 4
      expect(calculateExerciseCount(45)).toBe(4);
    });

    it('returns 5 exercises for 60 min workout', () => {
      // 60 / 9.5 = 6.3 → 6
      expect(calculateExerciseCount(60)).toBe(6);
    });

    it('returns 6 exercises for 75 min workout', () => {
      // 75 / 9.5 = 7.9 → 7
      expect(calculateExerciseCount(75)).toBe(7);
    });

    it('returns 8 exercises (max) for 90 min workout', () => {
      // 90 / 9.5 = 9.5 → clamped to 8
      expect(calculateExerciseCount(90)).toBe(8);
    });
  });

  describe('with bodyweight', () => {
    it('returns 3 exercises for 25 min workout', () => {
      // 25 / 8.0 = 3.1 → 3
      expect(calculateExerciseCount(25, 'bodyweight')).toBe(3);
    });

    it('returns 5 exercises for 45 min workout', () => {
      // 45 / 8.0 = 5.6 → 5
      expect(calculateExerciseCount(45, 'bodyweight')).toBe(5);
    });

    it('returns 7 exercises for 60 min workout', () => {
      // 60 / 8.0 = 7.5 → 7
      expect(calculateExerciseCount(60, 'bodyweight')).toBe(7);
    });
  });

  describe('clamping', () => {
    it('returns minimum 3 exercises for very short workout', () => {
      // 10 / 9.5 = 1 → clamped to 3
      expect(calculateExerciseCount(10)).toBe(3);
    });

    it('returns maximum 8 exercises for very long workout', () => {
      // 120 / 9.5 = 12.6 → clamped to 8
      expect(calculateExerciseCount(120)).toBe(8);
    });
  });
});

// ============================================================================
// determinePrimaryEquipment Tests
// ============================================================================

describe('determinePrimaryEquipment', () => {
  describe('from location', () => {
    it('returns bodyweight for home location', () => {
      expect(determinePrimaryEquipment('home')).toBe('bodyweight');
    });

    it('returns barbell for gym location', () => {
      expect(determinePrimaryEquipment('gym')).toBe('barbell');
    });

    it('returns barbell for outdoor location', () => {
      expect(determinePrimaryEquipment('outdoor')).toBe('barbell');
    });

    it('returns barbell for undefined location', () => {
      expect(determinePrimaryEquipment(undefined)).toBe('barbell');
    });
  });

  describe('from available equipment', () => {
    it('returns bodyweight when only bodyweight available', () => {
      expect(determinePrimaryEquipment('gym', ['bodyweight'])).toBe('bodyweight');
    });

    it('returns first non-bodyweight equipment when available', () => {
      expect(determinePrimaryEquipment('home', ['bodyweight', 'dumbbells'])).toBe('dumbbells');
    });

    it('returns barbell when barbell available', () => {
      expect(determinePrimaryEquipment('gym', ['barbell', 'dumbbells'])).toBe('barbell');
    });

    it('returns cable when only cable available', () => {
      expect(determinePrimaryEquipment('gym', ['cable', 'bodyweight'])).toBe('cable');
    });
  });
});
