/**
 * Calculate endpoint - centralized calculation logic for iOS and web
 *
 * POST /api/calculate
 * Requires: Authorization header with Firebase ID token
 *
 * Operations:
 * - oneRM: Epley formula (weight × (1 + reps/30))
 * - weightForReps: Inverse Epley (oneRM / (1 + reps/30))
 * - best1RM: Quality-weighted selection from multiple sets
 * - recency1RM: 14-day half-life weighted historical average
 * - targetWeight: Compound (1RM × intensity) or Isolation (RPE positioning)
 */

import {onRequest} from "firebase-functions/v2/https";

// Lazy-loaded admin module
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminModule: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminApp: any = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getAdmin(): any {
  if (!adminModule) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    adminModule = require("firebase-admin");
  }
  if (!adminApp) {
    // Initialize only if not already initialized
    if (adminModule.apps.length === 0) {
      adminApp = adminModule.initializeApp();
    } else {
      adminApp = adminModule.apps[0];
    }
  }
  return adminModule;
}

// Types
interface SetData {
  weight: number;
  reps: number;
  setIndex: number;
}

interface SessionData {
  date: string; // ISO date string
  best1RM: number;
}

interface CalculateRequest {
  type: "oneRM" | "weightForReps" | "best1RM" | "recency1RM" | "targetWeight";
  // oneRM
  weight?: number;
  reps?: number;
  // weightForReps
  oneRM?: number;
  targetReps?: number;
  // best1RM
  sets?: SetData[];
  // recency1RM
  sessions?: SessionData[];
  // targetWeight
  exerciseType?: "compound" | "isolation";
  baseIntensity?: number;
  intensityOffset?: number;
  rpe?: number;
  workingWeight?: number;
}

interface CalculateResponse {
  result: number | null;
  isEstimated?: boolean;
  error?: string;
}

// MARK: - Core Formulas

/**
 * Epley formula: 1RM = weight × (1 + reps/30)
 * Most accurate for 3-10 reps
 */
function calculateOneRM(weight: number, reps: number): number | null {
  if (reps <= 0 || reps >= 37 || weight <= 0) {
    return null;
  }
  return weight * (1 + reps / 30);
}

/**
 * Inverse Epley: weight = 1RM / (1 + reps/30)
 */
function calculateWeightForReps(oneRM: number, targetReps: number): number | null {
  if (targetReps <= 0 || oneRM <= 0) {
    return null;
  }
  return oneRM / (1 + targetReps / 30);
}

// MARK: - Quality Scoring

/**
 * Rep accuracy score - 3-5 reps are most accurate for 1RM estimation
 */
function getRepScore(reps: number): number {
  if (reps >= 3 && reps <= 5) return 1.0; // Optimal
  if (reps >= 1 && reps <= 2) return 0.8; // Too heavy, form may suffer
  if (reps >= 6 && reps <= 8) return 0.9; // Good
  if (reps >= 9 && reps <= 10) return 0.7; // Moderate
  if (reps >= 11 && reps <= 15) return 0.5; // Lower accuracy
  return 0.3; // 16+ poor accuracy
}

/**
 * Freshness score - earlier sets are less fatigued
 * First set = 1.0, last set = 0.6
 */
function getFreshnessScore(setIndex: number, totalSets: number): number {
  if (totalSets <= 1) return 1.0;
  return 1.0 - (setIndex / (totalSets - 1)) * 0.4;
}

/**
 * Quality-weighted 1RM selection from multiple sets
 * Returns weighted average favoring high-quality sets
 */
function calculateBest1RM(sets: SetData[]): number | null {
  if (!sets || sets.length === 0) return null;

  const totalSets = sets.length;
  const scored: Array<{rm: number; score: number}> = [];

  for (const set of sets) {
    const rm = calculateOneRM(set.weight, set.reps);
    if (rm === null) continue;

    const repScore = getRepScore(set.reps);
    const freshnessScore = getFreshnessScore(set.setIndex, totalSets);
    const qualityScore = repScore * freshnessScore;

    scored.push({rm, score: qualityScore});
  }

  if (scored.length === 0) return null;

  // Weighted average
  const totalWeight = scored.reduce((sum, s) => sum + s.score, 0);
  if (totalWeight <= 0) return scored[0].rm;

  return scored.reduce((sum, s) => sum + s.rm * s.score, 0) / totalWeight;
}

// MARK: - Recency Weighting

const HALF_LIFE_DAYS = 14;

/**
 * Recency-weighted 1RM from historical sessions
 * Uses exponential decay with 14-day half-life
 */
function calculateRecency1RM(sessions: SessionData[]): number | null {
  if (!sessions || sessions.length === 0) return null;

  const now = Date.now();
  const scored: Array<{rm: number; weight: number}> = [];

  for (const session of sessions) {
    const sessionDate = new Date(session.date).getTime();
    const daysAgo = (now - sessionDate) / 86400000; // ms to days

    // Exponential decay: weight halves every 14 days
    const recencyWeight = Math.pow(0.5, daysAgo / HALF_LIFE_DAYS);

    scored.push({rm: session.best1RM, weight: recencyWeight});
  }

  if (scored.length === 0) return null;

  // Weighted average
  const totalWeight = scored.reduce((sum, s) => sum + s.weight, 0);
  if (totalWeight <= 0) return scored[0].rm;

  return scored.reduce((sum, s) => sum + s.rm * s.weight, 0) / totalWeight;
}

// MARK: - Target Weight Calculation

/**
 * Calculate target weight based on exercise type
 * - Compound: 1RM × (baseIntensity + offset), rounded to 2.5 lb
 * - Isolation: Working weight ±10% positioned by RPE, rounded to 5 lb
 */
function calculateTargetWeight(
  exerciseType: "compound" | "isolation",
  oneRM: number | undefined,
  baseIntensity: number | undefined,
  intensityOffset: number | undefined,
  rpe: number | undefined,
  workingWeight: number | undefined
): number | null {
  if (exerciseType === "compound") {
    // Compound: 1RM-based
    if (!oneRM || baseIntensity === undefined) return null;

    const finalIntensity = baseIntensity + (intensityOffset ?? 0);
    const targetWeight = oneRM * finalIntensity;

    // Round to nearest 2.5 lbs (standard gym plate)
    return Math.round(targetWeight / 2.5) * 2.5;
  } else if (exerciseType === "isolation") {
    // Isolation: Working weight + RPE positioning
    if (!workingWeight) return null;

    const rangeSize = workingWeight * 0.10;
    const lowEnd = workingWeight - rangeSize;
    const highEnd = workingWeight + rangeSize;

    // RPE determines position in range
    const rpeValue = rpe ?? 9;
    let rpePosition: number;
    if (rpeValue >= 9) {
      rpePosition = 1.0; // High end
    } else if (rpeValue === 8) {
      rpePosition = 0.5; // Middle
    } else {
      rpePosition = 0.0; // Low end
    }

    const targetWeight = lowEnd + (highEnd - lowEnd) * rpePosition;

    // Round to nearest 5 lbs (dumbbell increment)
    return Math.round(targetWeight / 5.0) * 5.0;
  }

  return null;
}

// MARK: - HTTP Handler

export const calculate = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 30},
  async (req, res) => {
    // Only allow POST
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      // Verify auth
      const authHeader = req.headers.authorization;
      if (!authHeader?.startsWith("Bearer ")) {
        res.status(401).json({error: "Unauthorized"});
        return;
      }

      const idToken = authHeader.split("Bearer ")[1];
      const admin = getAdmin();

      try {
        await admin.auth().verifyIdToken(idToken);
      } catch {
        res.status(401).json({error: "Invalid token"});
        return;
      }

      // Parse request
      const body = req.body as CalculateRequest;
      const {type} = body;

      if (!type) {
        res.status(400).json({error: "Missing 'type' parameter"});
        return;
      }

      let response: CalculateResponse;

      switch (type) {
        case "oneRM": {
          const {weight, reps} = body;
          if (weight === undefined || reps === undefined) {
            res.status(400).json({error: "oneRM requires 'weight' and 'reps'"});
            return;
          }
          response = {result: calculateOneRM(weight, reps)};
          break;
        }

        case "weightForReps": {
          const {oneRM, targetReps} = body;
          if (oneRM === undefined || targetReps === undefined) {
            res.status(400).json({error: "weightForReps requires 'oneRM' and 'targetReps'"});
            return;
          }
          response = {result: calculateWeightForReps(oneRM, targetReps)};
          break;
        }

        case "best1RM": {
          const {sets} = body;
          if (!sets || !Array.isArray(sets)) {
            res.status(400).json({error: "best1RM requires 'sets' array"});
            return;
          }
          response = {result: calculateBest1RM(sets)};
          break;
        }

        case "recency1RM": {
          const {sessions} = body;
          if (!sessions || !Array.isArray(sessions)) {
            res.status(400).json({error: "recency1RM requires 'sessions' array"});
            return;
          }
          response = {result: calculateRecency1RM(sessions)};
          break;
        }

        case "targetWeight": {
          const {exerciseType, oneRM, baseIntensity, intensityOffset, rpe, workingWeight} = body;
          if (!exerciseType) {
            res.status(400).json({error: "targetWeight requires 'exerciseType'"});
            return;
          }
          response = {
            result: calculateTargetWeight(
              exerciseType,
              oneRM,
              baseIntensity,
              intensityOffset,
              rpe,
              workingWeight
            ),
          };
          break;
        }

        default:
          res.status(400).json({error: `Unknown type: ${type}`});
          return;
      }

      res.json(response);
    } catch (error) {
      console.error("Calculate error:", error);
      const errorMessage = error instanceof Error ? error.message : "Internal server error";
      res.status(500).json({error: errorMessage});
    }
  }
);
