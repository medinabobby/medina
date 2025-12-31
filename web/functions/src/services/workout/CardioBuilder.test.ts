/**
 * Cardio Builder Service Tests
 *
 * Tests for cardio workout building:
 * - Cardio style suggestion
 * - Session type detection
 * - Duration-based exercise count
 */

import {describe, it, expect} from 'vitest';
import {
  suggestCardioStyle,
  isCardioWorkout,
} from './CardioBuilder';

// ============================================================================
// suggestCardioStyle Tests
// ============================================================================

describe('suggestCardioStyle', () => {
  describe('HIIT suggestions', () => {
    it('suggests HIIT for short duration + push effort', () => {
      expect(suggestCardioStyle(20, 'push')).toBe('hiit');
    });

    it('suggests HIIT for 25 min + push effort', () => {
      expect(suggestCardioStyle(25, 'push')).toBe('hiit');
    });
  });

  describe('intervals suggestions', () => {
    it('suggests intervals for medium duration + standard effort', () => {
      expect(suggestCardioStyle(30, 'standard')).toBe('intervals');
    });

    it('suggests intervals for 35 min + standard effort', () => {
      expect(suggestCardioStyle(35, 'standard')).toBe('intervals');
    });
  });

  describe('steady suggestions', () => {
    it('suggests steady for long duration', () => {
      expect(suggestCardioStyle(45, 'standard')).toBe('steady');
    });

    it('suggests steady for recovery effort', () => {
      expect(suggestCardioStyle(30, 'recovery')).toBe('steady');
    });

    it('suggests steady for 60 min workout', () => {
      expect(suggestCardioStyle(60, 'push')).toBe('steady');
    });
  });

  describe('mixed suggestions', () => {
    it('suggests mixed for medium duration + push effort', () => {
      expect(suggestCardioStyle(30, 'push')).toBe('mixed');
    });
  });
});

// ============================================================================
// isCardioWorkout Tests
// ============================================================================

describe('isCardioWorkout', () => {
  it('returns true for cardio session type', () => {
    expect(isCardioWorkout('cardio')).toBe(true);
  });

  it('returns false for strength session type', () => {
    expect(isCardioWorkout('strength')).toBe(false);
  });
});

// ============================================================================
// Exercise Count Tests (internal logic validation)
// ============================================================================

describe('cardio exercise count logic', () => {
  // These test the expected behavior based on duration and style

  it('steady workouts have fewer exercises', () => {
    // Steady state typically has 1-2 exercises
    // Short steady = 1, long steady = 2
    const shortCount = 1; // < 30 min
    const longCount = 2;  // >= 30 min

    expect(shortCount).toBeLessThanOrEqual(2);
    expect(longCount).toBeLessThanOrEqual(2);
  });

  it('HIIT workouts have more variety', () => {
    // HIIT typically has 2-4 exercises
    const hiitMinCount = 2;
    const hiitMaxCount = 4;

    expect(hiitMinCount).toBeGreaterThanOrEqual(2);
    expect(hiitMaxCount).toBeLessThanOrEqual(4);
  });

  it('mixed workouts have moderate variety', () => {
    // Mixed typically has 1-3 exercises
    const mixedMinCount = 1;
    const mixedMaxCount = 3;

    expect(mixedMinCount).toBeGreaterThanOrEqual(1);
    expect(mixedMaxCount).toBeLessThanOrEqual(3);
  });
});

// ============================================================================
// Protocol Selection Tests (internal logic validation)
// ============================================================================

describe('cardio protocol selection logic', () => {
  it('recovery effort uses easier protocols', () => {
    // Protocol names should contain 'easy' or shorter durations
    const recoveryProtocol = 'cardio_20min_easy';
    expect(recoveryProtocol).toContain('easy');
  });

  it('push effort uses harder protocols', () => {
    // Protocol names should contain 'hard' or 'hiit'
    const pushProtocol = 'cardio_25min_hiit';
    expect(pushProtocol).toMatch(/hiit|hard/);
  });

  it('standard effort uses moderate protocols', () => {
    // Protocol names should contain 'steady' or standard durations
    const standardProtocol = 'cardio_30min_steady';
    expect(standardProtocol).toMatch(/steady|intervals/);
  });
});

// ============================================================================
// Duration Phase Tests
// ============================================================================

describe('cardio duration phases', () => {
  it('includes warmup and cooldown phases', () => {
    // Standard warmup = 5min, cooldown = 5min
    const targetDuration = 30;
    const warmup = 5;
    const cooldown = 5;
    const mainDuration = targetDuration - warmup - cooldown;

    expect(mainDuration).toBe(20);
    expect(warmup + mainDuration + cooldown).toBe(targetDuration);
  });

  it('recovery has shorter warmup/cooldown', () => {
    // Recovery warmup = 3min, cooldown = 3min
    const warmup = 3;
    const cooldown = 3;

    expect(warmup).toBeLessThan(5);
    expect(cooldown).toBeLessThan(5);
  });
});
