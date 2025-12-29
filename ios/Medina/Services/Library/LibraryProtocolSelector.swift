//
// LibraryProtocolSelector.swift
// Medina
//
// v51.0 - Exercise & Protocol Library (Phase 1b)
// v82.0 - Equipment-aware protocol preference scoring
// Created: November 5, 2025
//
// Purpose: Protocol selection and matching from user library
// Algorithm: Filter by exercise type → intensity range → goal preference → rank by weight + equipment boost
//

import Foundation

struct LibraryProtocolSelector {

    // MARK: - v82.0: Equipment Preference Boost

    /// Boost applied when protocol's preferredEquipment matches exercise equipment
    private static let equipmentMatchBoost: Double = 2.0

    // MARK: - Main Selection

    /// Match protocol to exercise based on type, intensity, goal, and equipment
    /// v80.5: Added equipment parameter to filter incompatible protocols for bands/bodyweight
    /// v82.0: Added equipment preference scoring - protocols optimized for equipment get priority
    /// Returns: protocolConfigId, or nil if no match
    static func match(
        from library: UserLibrary,
        exerciseType: ExerciseType,
        currentIntensity: Double,
        goal: FitnessGoal,
        equipment: Equipment
    ) -> String? {

        // STEP 1: Filter to enabled protocols
        let enabledProtocols = library.enabledProtocols()

        // STEP 2: Filter by exercise type (compound vs isolation)
        let typeFiltered = enabledProtocols.filter { entry in
            entry.applicableTo.contains(exerciseType)
        }

        // STEP 2.5: v80.5 - Filter by equipment compatibility
        let equipmentFiltered = typeFiltered.filter { entry in
            isEquipmentCompatible(protocolId: entry.protocolConfigId, equipment: equipment)
        }

        // STEP 3: Filter by intensity range
        let intensityFiltered = equipmentFiltered.filter { entry in
            entry.intensityRange.contains(currentIntensity)
        }

        // STEP 4: Filter by goal preference (optional)
        let goalFiltered = intensityFiltered.filter { entry in
            entry.preferredGoals.isEmpty || entry.preferredGoals.contains(goal)
        }

        // STEP 5: v82.0 - Rank by selection weight with equipment preference boost
        let ranked = goalFiltered.sorted { entry1, entry2 in
            let score1 = calculateSelectionScore(entry: entry1, equipment: equipment)
            let score2 = calculateSelectionScore(entry: entry2, equipment: equipment)
            return score1 > score2
        }

        // STEP 6: Return top match
        if let best = ranked.first {
            let wasEquipmentMatch = best.preferredEquipment?.contains(equipment) == true
            Logger.log(.info, component: "LibraryProtocolSelector", message:
                "Matched protocol \(best.protocolConfigId) for \(exerciseType.displayName) (\(equipment.rawValue)) at \(Int(currentIntensity * 100))% intensity\(wasEquipmentMatch ? " [equipment-optimized]" : "")"
            )
            return best.protocolConfigId
        }

        // STEP 7: Log failure for observability
        Logger.log(.warning, component: "LibraryProtocolSelector", message:
            "No protocol match for \(exerciseType.displayName) (\(equipment.rawValue)), intensity \(Int(currentIntensity * 100))%, goal \(goal.rawValue)"
        )
        return nil
    }

    // MARK: - v82.0: Selection Score Calculation

    /// Calculate selection score including equipment preference boost
    /// - Parameters:
    ///   - entry: Protocol library entry
    ///   - equipment: Exercise equipment type
    /// - Returns: Selection score (higher = more preferred)
    private static func calculateSelectionScore(entry: ProtocolLibraryEntry, equipment: Equipment) -> Double {
        var score = entry.selectionWeight

        // v82.0: Boost score if protocol is optimized for this equipment
        if let preferredEquipment = entry.preferredEquipment,
           preferredEquipment.contains(equipment) {
            score *= equipmentMatchBoost
        }

        return score
    }

    // MARK: - Equipment Compatibility

    /// v80.5: Check if a protocol is compatible with given equipment
    /// - Parameters:
    ///   - protocolId: Protocol config ID (e.g., "gbc_compound", "drop_set")
    ///   - equipment: Equipment type
    /// - Returns: true if compatible
    private static func isEquipmentCompatible(protocolId: String, equipment: Equipment) -> Bool {
        switch equipment {
        case .resistanceBand:
            // Bands can't do: drop sets (quick weight changes), heavy negatives, cluster sets
            let incompatible = ["drop_set", "heavy_negative", "cluster", "wave_loading", "pyramid"]
            return !incompatible.contains(where: { protocolId.lowercased().contains($0) })

        case .bodyweight:
            // Bodyweight can't do percentage-based loading protocols
            let incompatible = ["wave_loading", "pyramid", "drop_set"]
            return !incompatible.contains(where: { protocolId.lowercased().contains($0) })

        default:
            // Standard equipment (barbell, dumbbells, machine, cable) supports all protocols
            return true
        }
    }

    // MARK: - Protocol Validation

    /// Check if library has sufficient protocol coverage
    /// Returns: Array of missing protocol types
    static func validateCoverage(library: UserLibrary) -> [ProtocolGap] {
        var gaps: [ProtocolGap] = []

        let enabledProtocols = library.enabledProtocols()

        // Check compound protocol coverage
        let compoundProtocols = enabledProtocols.filter { $0.applicableTo.contains(.compound) }
        if compoundProtocols.count < 3 {
            gaps.append(.insufficientCompoundProtocols(available: compoundProtocols.count, recommended: 3))
        }

        // Check isolation protocol coverage
        let isolationProtocols = enabledProtocols.filter { $0.applicableTo.contains(.isolation) }
        if isolationProtocols.count < 2 {
            gaps.append(.insufficientIsolationProtocols(available: isolationProtocols.count, recommended: 2))
        }

        // Check intensity range coverage
        let intensityRanges = enabledProtocols.map { $0.intensityRange }
        let minIntensity = intensityRanges.map { $0.lowerBound }.min() ?? 1.0
        let maxIntensity = intensityRanges.map { $0.upperBound }.max() ?? 0.0

        if minIntensity > 0.60 {
            gaps.append(.missingLowIntensityProtocols(minAvailable: minIntensity))
        }

        if maxIntensity < 0.85 {
            gaps.append(.missingHighIntensityProtocols(maxAvailable: maxIntensity))
        }

        return gaps
    }
}

// MARK: - ProtocolGap

/// Represents missing protocol coverage in library
enum ProtocolGap {
    case insufficientCompoundProtocols(available: Int, recommended: Int)
    case insufficientIsolationProtocols(available: Int, recommended: Int)
    case missingLowIntensityProtocols(minAvailable: Double)
    case missingHighIntensityProtocols(maxAvailable: Double)

    var userMessage: String {
        switch self {
        case .insufficientCompoundProtocols(let available, let recommended):
            return "Only \(available) compound protocols in library. Add at least \(recommended) for better variety."
        case .insufficientIsolationProtocols(let available, let recommended):
            return "Only \(available) isolation protocols in library. Add at least \(recommended) for better variety."
        case .missingLowIntensityProtocols(let minAvailable):
            return "No low-intensity protocols (below \(Int(minAvailable * 100))%). Add protocols for endurance/warmup work."
        case .missingHighIntensityProtocols(let maxAvailable):
            return "No high-intensity protocols (above \(Int(maxAvailable * 100))%). Add protocols for strength/power work."
        }
    }
}
