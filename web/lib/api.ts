/**
 * Firebase API Client for Web
 *
 * Thin service layer matching iOS pattern - all business logic lives in Firebase Functions.
 * This file provides typed helpers for calling the deployed endpoints.
 *
 * Endpoints:
 * - /api/calculate - 1RM calculations, weight suggestions
 * - /api/import - CSV import with intelligence analysis
 * - /api/selectExercises - Library-first exercise selection
 * - /api/tts - Text-to-speech
 * - /api/vision - Image analysis
 * - /api/chatSimple - Simple AI completion
 */

// =============================================================================
// TYPES
// =============================================================================

// Calculate endpoint types
export type CalculationType =
  | 'oneRM'
  | 'weightForReps'
  | 'best1RM'
  | 'recency1RM'
  | 'targetWeight';

export interface CalculateRequest {
  type: CalculationType;
  // oneRM
  weight?: number;
  reps?: number;
  // weightForReps
  oneRM?: number;
  targetReps?: number;
  // best1RM
  sets?: Array<{ weight: number; reps: number; setIndex: number }>;
  // recency1RM
  sessions?: Array<{ date: string; best1RM: number }>;
  // targetWeight
  exerciseType?: 'compound' | 'isolation';
  baseIntensity?: number;
  intensityOffset?: number;
  rpe?: number;
  workingWeight?: number;
}

export interface CalculateResponse {
  result: number | null;
  isEstimated?: boolean;
  error?: string;
}

// Import endpoint types
export interface ImportRequest {
  csvData: string; // Base64 encoded
  createHistoricalWorkouts?: boolean;
  userWeight?: number;
}

export interface ImportResponse {
  success?: boolean;
  summary?: {
    sessionsImported: number;
    exercisesMatched: number;
    exercisesUnmatched: string[];
    targetsCreated: number;
    workoutsCreated: number;
  };
  intelligence?: {
    inferredExperience: string;
    trainingStyle: string;
    topMuscleGroups: string[];
    inferredSplit: string | null;
    estimatedSessionDuration: number;
    confidenceScore: number;
    indicators: Record<string, number>;
  };
  error?: string;
}

// Exercise selection types
export type MuscleGroup =
  | 'chest' | 'back' | 'shoulders' | 'biceps' | 'triceps' | 'quadriceps'
  | 'hamstrings' | 'glutes' | 'calves' | 'core' | 'forearms' | 'lats'
  | 'traps' | 'abs' | 'full_body';

export type Equipment =
  | 'barbell' | 'dumbbells' | 'cable_machine' | 'bodyweight' | 'kettlebell'
  | 'resistance_band' | 'machine' | 'smith' | 'trx' | 'bench' | 'squat_rack'
  | 'pullup_bar' | 'dip_station' | 'none';

export type ExperienceLevel = 'beginner' | 'intermediate' | 'advanced' | 'expert';

export type SplitDay =
  | 'upper' | 'lower' | 'push' | 'pull' | 'legs' | 'full_body'
  | 'chest' | 'back' | 'shoulders' | 'arms' | 'not_applicable';

export interface SelectExercisesRequest {
  splitDay: SplitDay;
  muscleTargets: MuscleGroup[];
  compoundCount: number;
  isolationCount: number;
  emphasizedMuscles?: MuscleGroup[];
  availableEquipment: Equipment[];
  excludedExerciseIds?: string[];
  userExperienceLevel: ExperienceLevel;
  libraryExerciseIds: string[];
  preferBodyweightCompounds?: boolean;
}

export interface SelectExercisesResponse {
  result?: {
    exerciseIds: string[];
    fromLibrary: string[];
    introduced: string[];
    usedFallback: boolean;
  };
  error?: string;
}

// =============================================================================
// API BASE URL
// =============================================================================

// Cloud Run URLs (deployed Firebase Functions v2)
const API_URLS = {
  calculate: 'https://calculate-dpkc2km3oa-uc.a.run.app',
  import: 'https://importcsv-dpkc2km3oa-uc.a.run.app',
  selectExercises: 'https://selectexercises-dpkc2km3oa-uc.a.run.app',
  tts: 'https://tts-dpkc2km3oa-uc.a.run.app',
  vision: '/api/vision',  // Routed via Firebase Hosting to avoid CORS
  chatSimple: 'https://chatsimple-dpkc2km3oa-uc.a.run.app',
};

// =============================================================================
// CALCULATE API
// =============================================================================

/**
 * Call the calculate endpoint
 */
export async function calculate(
  token: string,
  request: CalculateRequest
): Promise<CalculateResponse> {
  const response = await fetch(API_URLS.calculate, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify(request),
  });

  return response.json();
}

/**
 * Calculate 1RM using Epley formula
 * Formula: weight × (1 + reps/30)
 */
export async function calculateOneRM(
  token: string,
  weight: number,
  reps: number
): Promise<number | null> {
  const response = await calculate(token, { type: 'oneRM', weight, reps });
  return response.result;
}

/**
 * Calculate working weight for target reps (inverse Epley)
 * Formula: oneRM / (1 + reps/30)
 */
export async function calculateWeightForReps(
  token: string,
  oneRM: number,
  targetReps: number
): Promise<number | null> {
  const response = await calculate(token, { type: 'weightForReps', oneRM, targetReps });
  return response.result;
}

/**
 * Calculate target weight based on intensity percentage
 * Returns weight rounded to nearest plate increment
 */
export async function calculateTargetWeight(
  token: string,
  oneRM: number,
  intensity: number,
  exerciseType: 'compound' | 'isolation' = 'compound'
): Promise<number | null> {
  const response = await calculate(token, {
    type: 'targetWeight',
    oneRM,
    exerciseType,
    baseIntensity: intensity,
    intensityOffset: 0,
  });
  return response.result;
}

/**
 * Calculate working weight suggestion (simple percentage)
 * Matches iOS: rounds to nearest 5 lbs
 */
export function calculateWorkingWeight(oneRM: number, percentage: number): number {
  return Math.round((oneRM * percentage) / 5) * 5;
}

/**
 * Format weight as display string
 */
export function formatWeight(weight: number): string {
  return `${weight} lbs`;
}

// =============================================================================
// IMPORT API
// =============================================================================

/**
 * Import CSV workout history
 */
export async function importCSV(
  token: string,
  csvData: string,
  options?: { createHistoricalWorkouts?: boolean; userWeight?: number }
): Promise<ImportResponse> {
  const response = await fetch(API_URLS.import, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      csvData,
      createHistoricalWorkouts: options?.createHistoricalWorkouts ?? true,
      userWeight: options?.userWeight,
    }),
  });

  return response.json();
}

// =============================================================================
// EXERCISE SELECTION API
// =============================================================================

/**
 * Select exercises using library-first approach
 */
export async function selectExercises(
  token: string,
  request: SelectExercisesRequest
): Promise<SelectExercisesResponse> {
  const response = await fetch(API_URLS.selectExercises, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify(request),
  });

  return response.json();
}

// =============================================================================
// TTS API
// =============================================================================

export interface TTSOptions {
  voice?: 'alloy' | 'echo' | 'fable' | 'onyx' | 'nova' | 'shimmer';
  speed?: number;
}

/**
 * Generate speech audio from text
 * Returns audio blob for playback
 */
export async function textToSpeech(
  token: string,
  text: string,
  options?: TTSOptions
): Promise<Blob> {
  const response = await fetch(API_URLS.tts, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      text,
      voice: options?.voice ?? 'nova',
      speed: options?.speed ?? 1.0,
    }),
  });

  if (!response.ok) {
    throw new Error('TTS request failed');
  }

  return response.blob();
}

/**
 * Play text as speech
 */
export async function speakText(
  token: string,
  text: string,
  options?: TTSOptions
): Promise<void> {
  const audioBlob = await textToSpeech(token, text, options);
  const audioUrl = URL.createObjectURL(audioBlob);
  const audio = new Audio(audioUrl);

  return new Promise((resolve, reject) => {
    audio.onended = () => {
      URL.revokeObjectURL(audioUrl);
      resolve();
    };
    audio.onerror = () => {
      URL.revokeObjectURL(audioUrl);
      reject(new Error('Audio playback failed'));
    };
    audio.play();
  });
}

// =============================================================================
// VISION API
// =============================================================================

export interface VisionOptions {
  model?: 'gpt-4o' | 'gpt-4o-mini';
  jsonMode?: boolean;
}

/**
 * Analyze image with AI
 */
export async function analyzeImage(
  token: string,
  imageBase64: string,
  prompt: string,
  options?: VisionOptions
): Promise<string> {
  const response = await fetch(API_URLS.vision, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      imageBase64,
      prompt,
      model: options?.model ?? 'gpt-4o',
      jsonMode: options?.jsonMode ?? false,
    }),
  });

  const data = await response.json();

  if (data.error) {
    throw new Error(data.error);
  }

  return data.content;
}

// =============================================================================
// CHAT SIMPLE API
// =============================================================================

export interface ChatMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface ChatSimpleOptions {
  model?: string;
  temperature?: number;
}

/**
 * Simple chat completion (non-streaming)
 */
export async function chatSimple(
  token: string,
  messages: ChatMessage[],
  options?: ChatSimpleOptions
): Promise<string> {
  const response = await fetch(API_URLS.chatSimple, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      messages,
      model: options?.model ?? 'gpt-4o-mini',
      temperature: options?.temperature ?? 0.7,
    }),
  });

  const data = await response.json();

  if (data.error) {
    throw new Error(data.error);
  }

  return data.content;
}
