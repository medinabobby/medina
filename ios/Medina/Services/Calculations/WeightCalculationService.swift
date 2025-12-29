//
// WeightCalculationService.swift
// Medina
//
// v28.4: Consolidated weight calculation logic (1RM formulas + target weights)
// Merged from EpleyFormulaCalculator.swift + TargetWeightCalculator.swift
// v52.2: Added dual-path targeting system (1RM-based for compounds, RPE-based for isolations)
// v72.4: Added estimated 1RM fallback from equivalent exercises
// v74.7: Delegates to OneRMCalculationService for formula calculations
// Last reviewed: December 2025
//

import Foundation

enum WeightCalculationService {

    // MARK: - Result Types (v72.4)

    /// Result of 1RM lookup - indicates if value is actual or estimated
    struct OneRMResult {
        let value: Double
        let isEstimated: Bool
        let sourceExerciseName: String?  // Only set if estimated

        /// Simple display string (e.g., "195" or "~180")
        var displayString: String {
            isEstimated ? "~\(Int(value))" : "\(Int(value))"
        }
    }

    // MARK: - Epley Formula (1RM Calculations)

    /// Calculate estimated 1RM using Epley formula (via OneRMCalculationService)
    /// Formula: 1RM = weight × (1 + reps/30)
    ///
    /// - Parameters:
    ///   - weight: Weight lifted for the test
    ///   - reps: Number of reps completed
    /// - Returns: Estimated 1RM
    ///
    /// Example:
    /// ```
    /// let oneRM = WeightCalculationService.calculate1RM(weight: 175, reps: 5)
    /// // Returns: 204.2 lbs (175 × 1.167)
    /// ```
    static func calculate1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 && reps <= 10 else {
            Logger.log(.warning, component: "WeightCalculationService",
                      message: "Epley formula most accurate for 1-10 reps (given: \(reps))")
            return weight
        }

        // v74.7: Delegate to centralized service
        return OneRMCalculationService.calculate(weight: weight, reps: reps) ?? weight
    }

    /// Calculate weight needed for a target rep range given a known 1RM
    /// Inverse Epley: weight = 1RM / (1 + reps/30)
    ///
    /// - Parameters:
    ///   - oneRM: Known or estimated 1RM
    ///   - targetReps: Desired rep target
    /// - Returns: Recommended weight for target reps
    ///
    /// Example:
    /// ```
    /// let weight = WeightCalculationService.weightForReps(oneRM: 220, targetReps: 5)
    /// // Returns: 188.6 lbs (220 / 1.167)
    /// ```
    static func weightForReps(oneRM: Double, targetReps: Int) -> Double {
        guard targetReps > 0 else {
            return oneRM
        }

        let multiplier = 1.0 + (Double(targetReps) / 30.0)
        return oneRM / multiplier
    }

    // MARK: - Target Weight Calculation

    /// Calculate target weight for a set based on exercise type and training data
    ///
    /// v54.5: Now uses base intensity (from program progression) + protocol offset
    ///
    /// - Parameters:
    ///   - memberId: The member performing the exercise
    ///   - exerciseId: The exercise being performed
    ///   - exerciseType: Type of exercise (compound or isolation)
    ///   - baseIntensity: Base intensity from program progression (0.0-1.0, e.g., 0.6 = 60%)
    ///   - intensityOffset: Protocol per-set adjustment (e.g., 0.0 = no change, -0.05 = -5%)
    ///   - rpe: Target RPE (for isolations, determines position in working weight range)
    /// - Returns: Calculated target weight, or nil if uncalibrated
    ///
    /// **Example:**
    /// - baseIntensity: 0.65 (65% from week 2 of program)
    /// - intensityOffset: -0.05 (pyramid set 1)
    /// - Final intensity: 0.60 (60% of 1RM)
    static func calculateTargetWeight(
        memberId: String,
        exerciseId: String,
        exerciseType: ExerciseType,
        baseIntensity: Double,
        intensityOffset: Double,
        rpe: Int? = nil
    ) -> Double? {
        switch exerciseType {
        case .compound:
            // Compound exercises: Use 1RM × (base intensity + offset)
            return calculate1RMBasedWeight(
                memberId: memberId,
                exerciseId: exerciseId,
                baseIntensity: baseIntensity,
                intensityOffset: intensityOffset
            )
        case .isolation:
            // Isolation exercises: Use working weight approach
            return calculateWorkingWeight(
                memberId: memberId,
                exerciseId: exerciseId,
                rpe: rpe ?? 9
            )
        case .warmup, .cooldown, .cardio:
            // No target weight for warmup, cooldown, or cardio exercises
            return nil
        }
    }

    /// Calculate 1RM-based weight for compound exercises
    ///
    /// v54.5: Now combines base intensity + protocol offset
    /// v72.4: Now uses estimation fallback if no direct 1RM exists
    ///
    /// - Parameters:
    ///   - memberId: Member ID
    ///   - exerciseId: Exercise ID
    ///   - baseIntensity: Base intensity from program (e.g., 0.65 = 65%)
    ///   - intensityOffset: Protocol adjustment (e.g., -0.05 = -5%)
    /// - Returns: Target weight rounded to nearest plate
    private static func calculate1RMBasedWeight(
        memberId: String,
        exerciseId: String,
        baseIntensity: Double,
        intensityOffset: Double
    ) -> Double? {
        // v72.4: Get member's 1RM (actual or estimated)
        guard let oneRMResult = get1RMWithEstimate(memberId: memberId, exerciseId: exerciseId) else {
            return nil
        }

        // Calculate final intensity (base + protocol offset)
        // Example: 0.65 + (-0.05) = 0.60 (60% of 1RM)
        let finalIntensity = baseIntensity + intensityOffset
        let targetWeight = oneRMResult.value * finalIntensity

        // Round to nearest 2.5 lbs (standard gym plate increment)
        return roundToNearestPlate(targetWeight)
    }

    /// Calculate working weight for isolation exercises based on RPE and history
    private static func calculateWorkingWeight(
        memberId: String,
        exerciseId: String,
        rpe: Int
    ) -> Double? {
        // Get working weight from target history
        guard let workingWeight = getWorkingWeight(memberId: memberId, exerciseId: exerciseId) else {
            // No calibration data - return nil (shows "Calibration needed")
            return nil
        }

        // RPE determines position in working weight range
        // Assume ±10% range around stored working weight
        let rangeSize = workingWeight * 0.10
        let lowEnd = workingWeight - rangeSize
        let highEnd = workingWeight + rangeSize

        // Position based on RPE: RPE 9 = high end, RPE 7 = low end
        let rpePosition: Double
        switch rpe {
        case 9...: rpePosition = 1.0  // High end of range
        case 8: rpePosition = 0.5     // Middle of range
        default: rpePosition = 0.0    // Low end of range (RPE 7 or below)
        }

        let targetWeight = lowEnd + (highEnd - lowEnd) * rpePosition

        // Round to nearest 5 lbs for dumbbells (common increment)
        return round(targetWeight / 5.0) * 5.0
    }

    /// Get working weight range for an isolation exercise
    /// Returns tuple of (low, high) or nil if uncalibrated
    static func getWorkingWeightRange(memberId: String, exerciseId: String) -> (Double, Double)? {
        guard let workingWeight = getWorkingWeight(memberId: memberId, exerciseId: exerciseId) else {
            return nil
        }

        // ±10% range
        let rangeSize = workingWeight * 0.10
        let lowEnd = round((workingWeight - rangeSize) / 5.0) * 5.0
        let highEnd = round((workingWeight + rangeSize) / 5.0) * 5.0

        return (lowEnd, highEnd)
    }

    /// Calculate the intensity percentage from an intensity adjustment
    /// e.g., -0.20 → "80%", -0.15 → "85%"
    static func intensityPercentage(from adjustment: Double) -> String {
        let percentage = (1.0 + adjustment) * 100.0
        return "\(Int(percentage))%"
    }

    // MARK: - Private Helpers

    /// Get member's 1RM for an exercise from targets.json
    /// Returns nil if no direct target exists (does NOT use estimation)
    static func get1RM(memberId: String, exerciseId: String) -> Double? {
        let manager = TestDataManager.shared
        let targetKey = "\(memberId)-\(exerciseId)"

        guard let target = manager.targets[targetKey] else {
            // v63.1: Silently return nil - missing targets are expected for new users
            return nil
        }

        guard target.targetType == .max else {
            return nil
        }

        return target.currentTarget
    }

    /// v72.4: Get member's 1RM with estimation fallback
    /// Returns actual 1RM if available, otherwise estimates from equivalent exercises
    static func get1RMWithEstimate(memberId: String, exerciseId: String) -> OneRMResult? {
        // First try direct 1RM
        if let direct1RM = get1RM(memberId: memberId, exerciseId: exerciseId) {
            return OneRMResult(value: direct1RM, isEstimated: false, sourceExerciseName: nil)
        }

        // Fall back to estimated from equivalent exercises
        if let estimate = EquivalentExerciseEstimator.estimate1RM(for: exerciseId, userId: memberId) {
            return OneRMResult(
                value: estimate.estimated1RM,
                isEstimated: true,
                sourceExerciseName: estimate.sourceExerciseName
            )
        }

        return nil
    }

    /// Get member's working weight for an isolation exercise
    private static func getWorkingWeight(memberId: String, exerciseId: String) -> Double? {
        let manager = TestDataManager.shared
        let targetKey = "\(memberId)-\(exerciseId)"

        guard let target = manager.targets[targetKey] else {
            // v63.1: Silently return nil - missing targets are expected for new users
            return nil
        }

        guard target.targetType == .working else {
            return nil
        }

        return target.currentTarget
    }

    /// Round weight to nearest 2.5 lbs (standard gym plate increment)
    private static func roundToNearestPlate(_ weight: Double) -> Double {
        return round(weight / 2.5) * 2.5
    }
}
