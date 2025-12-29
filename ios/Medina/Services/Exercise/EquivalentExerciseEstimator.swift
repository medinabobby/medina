//
// EquivalentExerciseEstimator.swift
// Medina
//
// v72.4: Estimates 1RM for exercises based on equivalent exercise data
// When user has 1RM for barbell bench, estimate dumbbell bench (and vice versa)
//

import Foundation

/// Estimates 1RM for exercises based on equivalent exercises with known 1RMs
/// Uses baseExercise grouping and equipment conversion factors
enum EquivalentExerciseEstimator {

    // MARK: - Result Types

    struct EstimatedTarget {
        let exerciseId: String
        let estimated1RM: Double
        let sourceExerciseId: String
        let sourceExerciseName: String
        let source1RM: Double
        let conversionFactor: Double
        let confidence: Confidence

        enum Confidence: String {
            case high = "high"       // Same movement, similar equipment (e.g., barbell → dumbbell)
            case medium = "medium"   // Same base exercise, different equipment class
            case low = "low"         // Same muscle group, different movement
        }
    }

    // MARK: - Equipment Conversion Factors

    /// Conversion factors when going FROM one equipment TO another
    /// Factor is multiplied by source 1RM to get target estimate
    ///
    /// Example: 100 lb barbell bench → 40 lb dumbbells (each hand)
    /// barbellToDumbbell = 0.40 (per dumbbell)
    private static let conversionFactors: [Equipment: [Equipment: Double]] = [
        // From barbell to...
        .barbell: [
            .dumbbells: 0.40,       // 100 lb barbell → 40 lb each dumbbell
            .machine: 1.15,         // Machines allow slightly more due to stability
            .cableMachine: 0.45,    // Similar to dumbbells
            .kettlebell: 0.35,      // Less due to grip/stability
            .bodyweight: 0.70,      // Rough estimate
            .smith: 1.10            // Smith machine provides some stability
        ],
        // From dumbbells to...
        .dumbbells: [
            .barbell: 2.30,         // 40 lb dumbbells → ~92 lb barbell (add ~15% for stability)
            .machine: 2.50,         // Machines more stable
            .cableMachine: 1.05,    // Very similar
            .kettlebell: 0.90,      // Similar but grip differs
            .bodyweight: 1.50,
            .smith: 2.40
        ],
        // From machine to...
        .machine: [
            .barbell: 0.80,         // Free weights require more stabilization
            .dumbbells: 0.35,       // Per dumbbell
            .cableMachine: 0.90,    // Similar assistance
            .kettlebell: 0.30,
            .bodyweight: 0.60,
            .smith: 0.95
        ],
        // From cable machine to...
        .cableMachine: [
            .barbell: 2.10,
            .dumbbells: 0.95,       // Very similar to dumbbells
            .machine: 1.10,
            .kettlebell: 0.85,
            .bodyweight: 1.40,
            .smith: 2.20
        ],
        // From kettlebell to...
        .kettlebell: [
            .barbell: 2.50,
            .dumbbells: 1.10,
            .machine: 2.80,
            .cableMachine: 1.15,
            .bodyweight: 1.60,
            .smith: 2.60
        ],
        // From smith machine to...
        .smith: [
            .barbell: 0.90,         // Smith provides some stability, so barbell is slightly harder
            .dumbbells: 0.38,
            .machine: 1.05,
            .cableMachine: 0.42,
            .kettlebell: 0.32,
            .bodyweight: 0.65
        ]
    ]

    // MARK: - Public API

    /// Estimate 1RM for an exercise based on equivalent exercises the user has data for
    /// - Parameters:
    ///   - exerciseId: The exercise to estimate 1RM for
    ///   - userId: The user to check targets for
    /// - Returns: Estimated target if found, nil if no equivalent data available
    static func estimate1RM(for exerciseId: String, userId: String) -> EstimatedTarget? {
        // Get the target exercise
        guard let targetExercise = TestDataManager.shared.exercises[exerciseId] else {
            return nil
        }

        // Find all exercises with the same baseExercise
        let equivalentExercises = TestDataManager.shared.exercises.values.filter { exercise in
            exercise.baseExercise == targetExercise.baseExercise &&
            exercise.id != exerciseId
        }

        if equivalentExercises.isEmpty {
            return nil
        }

        // Check if user has targets for any equivalent exercises
        var bestEstimate: EstimatedTarget?
        var bestConfidence: EstimatedTarget.Confidence = .low

        for equivalentExercise in equivalentExercises {
            let targetId = "\(userId)-\(equivalentExercise.id)"
            guard let target = TestDataManager.shared.targets[targetId],
                  let source1RM = target.currentTarget else {
                continue
            }

            // Calculate conversion factor
            let factor = conversionFactor(from: equivalentExercise.equipment, to: targetExercise.equipment)
            let estimated = source1RM * factor
            let confidence = calculateConfidence(source: equivalentExercise, target: targetExercise)

            // Keep the highest confidence estimate
            if bestEstimate == nil || confidence.rawValue > bestConfidence.rawValue ||
               (confidence == bestConfidence && source1RM > (bestEstimate?.source1RM ?? 0)) {
                bestEstimate = EstimatedTarget(
                    exerciseId: exerciseId,
                    estimated1RM: roundToPlate(estimated),
                    sourceExerciseId: equivalentExercise.id,
                    sourceExerciseName: equivalentExercise.name,
                    source1RM: source1RM,
                    conversionFactor: factor,
                    confidence: confidence
                )
                bestConfidence = confidence
            }
        }

        return bestEstimate
    }

    /// Get working weight suggestion based on estimated 1RM
    /// - Parameters:
    ///   - exerciseId: Exercise to get suggestion for
    ///   - userId: User ID
    ///   - percentage: Percentage of 1RM (e.g., 0.75 for 75%)
    /// - Returns: Suggested weight rounded to nearest plate increment
    static func suggestedWorkingWeight(for exerciseId: String, userId: String, percentage: Double = 0.75) -> Double? {
        // First check if user has direct 1RM
        let targetId = "\(userId)-\(exerciseId)"
        if let target = TestDataManager.shared.targets[targetId],
           let direct1RM = target.currentTarget {
            return roundToPlate(direct1RM * percentage)
        }

        // Fall back to estimated 1RM
        guard let estimate = estimate1RM(for: exerciseId, userId: userId) else {
            return nil
        }

        return roundToPlate(estimate.estimated1RM * percentage)
    }

    // MARK: - Private Helpers

    private static func conversionFactor(from source: Equipment, to target: Equipment) -> Double {
        if source == target {
            return 1.0
        }

        // Look up specific conversion
        if let sourceFactors = conversionFactors[source],
           let factor = sourceFactors[target] {
            return factor
        }

        // Default fallback - rough estimate based on equipment "stability"
        let stabilityRanking: [Equipment: Double] = [
            .machine: 1.2,
            .smith: 1.1,
            .cableMachine: 1.0,
            .barbell: 0.95,
            .dumbbells: 0.85,
            .kettlebell: 0.80,
            .bodyweight: 0.75,
            .resistanceBand: 0.70
        ]

        let sourceStability = stabilityRanking[source] ?? 0.85
        let targetStability = stabilityRanking[target] ?? 0.85

        return targetStability / sourceStability
    }

    private static func calculateConfidence(source: Exercise, target: Exercise) -> EstimatedTarget.Confidence {
        // Same equipment type = high confidence
        if source.equipment == target.equipment {
            return .high
        }

        // Similar equipment classes
        let freeWeights: Set<Equipment> = [.barbell, .dumbbells, .kettlebell]
        let assistedWeights: Set<Equipment> = [.machine, .cableMachine, .smith]

        if (freeWeights.contains(source.equipment) && freeWeights.contains(target.equipment)) ||
           (assistedWeights.contains(source.equipment) && assistedWeights.contains(target.equipment)) {
            return .high
        }

        // Cross-class (free weight to machine or vice versa) = medium
        if (freeWeights.contains(source.equipment) && assistedWeights.contains(target.equipment)) ||
           (assistedWeights.contains(source.equipment) && freeWeights.contains(target.equipment)) {
            return .medium
        }

        // Everything else
        return .low
    }

    /// Round weight to nearest 5 lbs (standard plate increment)
    private static func roundToPlate(_ weight: Double) -> Double {
        return (weight / 5.0).rounded() * 5.0
    }
}
