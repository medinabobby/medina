/**
 * Training Data Context Builder
 *
 * v2: Migrated from iOS TrainingDataContextBuilder.swift
 * Builds strength baselines and exercise affinity for AI personalization
 *
 * Flywheel concept: More user data -> better workouts -> better results -> more data
 */

export interface StrengthTarget {
  exerciseId: string;
  exerciseName: string;
  oneRepMax: number;
  lastTested?: string;
}

export interface ExerciseAffinity {
  favorites: string[];
  highCompletion: string[];
  oftensSkipped: string[];
  excluded: string[];
}

/**
 * Build strength baselines section for AI weight prescription
 * Provides 1RM data so AI can prescribe accurate percentages
 */
export function buildStrengthBaselines(targets: StrengthTarget[]): string {
  if (!targets || targets.length === 0) return '';

  const rows = targets.slice(0, 8).map(t => {
    const dateStr = t.lastTested || 'Unknown';
    return `| ${t.exerciseName} | ${Math.round(t.oneRepMax)} lbs | ${dateStr} |`;
  });

  return `## STRENGTH BASELINES (Use for weight prescription)
| Lift | 1RM | Last Tested |
|------|-----|-------------|
${rows.join('\n')}

When prescribing weights, use percentages: "75% of your 225lb bench = 170lbs"`;
}

/**
 * Build exercise affinity section based on completion rates
 * Guides AI to favor exercises user actually completes
 */
export function buildExerciseAffinity(affinity: ExerciseAffinity): string {
  const sections: string[] = [];

  if (affinity.favorites && affinity.favorites.length > 0) {
    sections.push(`**Favorites** (always prioritize): ${affinity.favorites.join(', ')}`);
  }

  if (affinity.highCompletion && affinity.highCompletion.length > 0) {
    sections.push(`**High completion** (favor these): ${affinity.highCompletion.join(', ')}`);
  }

  if (affinity.oftensSkipped && affinity.oftensSkipped.length > 0) {
    sections.push(`**Often skipped** (consider alternatives): ${affinity.oftensSkipped.join(', ')}`);
  }

  if (sections.length === 0) return '';

  return `## EXERCISE AFFINITY (Completion-Weighted)
${sections.join('\n')}`;
}

/**
 * Build excluded exercises list
 * Hard blocks - never suggest these exercises to this user
 */
export function buildExclusions(excluded: string[]): string {
  if (!excluded || excluded.length === 0) return '';

  return `## EXCLUDED EXERCISES (Never suggest)
${excluded.slice(0, 10).join(', ')}`;
}

/**
 * Build all training data context
 * Combines strength baselines, exercise affinity, and exclusions
 */
export function buildTrainingDataContext(
  targets?: StrengthTarget[],
  affinity?: ExerciseAffinity
): string {
  const sections: string[] = [];

  if (targets && targets.length > 0) {
    sections.push(buildStrengthBaselines(targets));
  }

  if (affinity) {
    const affinitySection = buildExerciseAffinity(affinity);
    if (affinitySection) sections.push(affinitySection);

    const exclusionSection = buildExclusions(affinity.excluded);
    if (exclusionSection) sections.push(exclusionSection);
  }

  if (sections.length === 0) return '';

  return `# PERSONALIZED TRAINING DATA

${sections.join('\n\n')}`;
}
