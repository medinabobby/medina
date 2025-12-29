//
// ProtocolService.swift
// Medina
//
// v28.4: Consolidated protocol service (config data access + metadata formatting)
// Merged from ProtocolConfigService.swift + ProtocolMetadataBuilder.swift
// Last reviewed: October 2025
//

import Foundation

enum ProtocolService {

    // MARK: - Config Data Access

    /// Get intensity adjustment for a specific set within a protocol
    /// - Parameters:
    ///   - setNumber: Set number (1-indexed)
    ///   - protocolVariantId: Protocol variant ID from ExerciseInstance
    /// - Returns: Intensity adjustment (e.g., -0.20 for 80% of 1RM), or nil if not found
    static func intensityAdjustment(forSet setNumber: Int, protocolVariantId: String) -> Double? {
        guard let protocolConfig = TestDataManager.shared.protocolConfigs[protocolVariantId] else {
            Logger.log(.debug, component: "ProtocolService",
                      message: "Protocol config not found: \(protocolVariantId)")
            return nil
        }

        // Set numbers are 1-indexed, array is 0-indexed
        let index = setNumber - 1
        guard index >= 0 && index < protocolConfig.intensityAdjustments.count else {
            Logger.log(.warning, component: "ProtocolService",
                      message: "Set number \(setNumber) out of range for protocol \(protocolVariantId)")
            return nil
        }

        return protocolConfig.intensityAdjustments[index]
    }

    /// Get target reps for a specific set within a protocol
    /// - Parameters:
    ///   - setNumber: Set number (1-indexed)
    ///   - protocolVariantId: Protocol variant ID from ExerciseInstance
    /// - Returns: Target reps for this set, or nil if not found
    static func targetReps(forSet setNumber: Int, protocolVariantId: String) -> Int? {
        guard let protocolConfig = TestDataManager.shared.protocolConfigs[protocolVariantId] else {
            return nil
        }

        let index = setNumber - 1
        guard index >= 0 && index < protocolConfig.reps.count else {
            return nil
        }

        return protocolConfig.reps[index]
    }

    /// Get RPE (Rate of Perceived Exertion) for a specific set within a protocol
    /// - Parameters:
    ///   - setNumber: Set number (1-indexed)
    ///   - protocolVariantId: Protocol variant ID from ExerciseInstance
    /// - Returns: Target RPE for this set, or nil if not found
    static func targetRPE(forSet setNumber: Int, protocolVariantId: String) -> Double? {
        guard let protocolConfig = TestDataManager.shared.protocolConfigs[protocolVariantId] else {
            return nil
        }

        guard let rpeArray = protocolConfig.rpe else {
            return nil
        }

        let index = setNumber - 1
        guard index >= 0 && index < rpeArray.count else {
            return nil
        }

        return rpeArray[index]
    }

    /// Get rest time for a specific set within a protocol (v19.5)
    /// - Parameters:
    ///   - setNumber: Set number (1-indexed)
    ///   - protocolVariantId: Protocol variant ID from ExerciseInstance
    /// - Returns: Rest time in seconds for this set, or nil if not found
    static func restTime(forSet setNumber: Int, protocolVariantId: String) -> Int? {
        guard let protocolConfig = TestDataManager.shared.protocolConfigs[protocolVariantId] else {
            return nil
        }

        let index = setNumber - 1
        guard index >= 0 && index < protocolConfig.restBetweenSets.count else {
            return nil
        }

        return protocolConfig.restBetweenSets[index]
    }

    // MARK: - Metadata Formatting

    /// Build protocol metadata subtitle for set cards
    /// - Parameters:
    ///   - setNumber: Set number (1-indexed)
    ///   - protocolVariantId: Protocol variant ID from ExerciseInstance
    /// - Returns: Formatted string (e.g., "RPE 9.0  •  Tempo: 20X0  •  15s between sets")
    static func buildSubtitle(setNumber: Int, protocolVariantId: String) -> String? {
        guard let protocolConfig = TestDataManager.shared.protocolConfigs[protocolVariantId] else {
            return nil
        }

        var parts: [String] = []

        // RPE (Rate of Perceived Exertion)
        if let rpe = targetRPE(forSet: setNumber, protocolVariantId: protocolVariantId) {
            parts.append("RPE \(String(format: "%.1f", rpe))")
        }

        // Tempo
        if let tempo = protocolConfig.tempo {
            parts.append("Tempo: \(tempo)")
        }

        // Rest time
        if let restSeconds = restTime(forSet: setNumber, protocolVariantId: protocolVariantId) {
            parts.append("\(restSeconds)s between sets")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "  •  ")
    }

    /// Build smart protocol display for exercise instance rows (workout detail cards)
    /// Shows special protocol names OR standard tempo/RPE info
    /// - Parameter instance: Exercise instance with protocol variant ID
    /// - Returns: Formatted string for instance subtitle
    static func buildInstanceSubtitle(for instance: ExerciseInstance) -> String {
        guard let config = TestDataManager.shared.protocolConfigs[instance.protocolVariantId] else {
            // Fallback to old format if config not found
            let setCount = instance.setIds.count
            let setText = setCount == 1 ? "set" : "sets"
            return "\(setCount) \(setText)"
        }

        return buildProtocolSubtitle(config: config)
    }

    /// Build protocol display from ProtocolConfig directly (v45)
    /// Used for exercises that don't have instances yet (not started)
    /// - Parameter config: Protocol configuration
    /// - Returns: Formatted string for protocol subtitle
    static func buildProtocolSubtitle(config: ProtocolConfig) -> String {
        // Special protocols: Show variant name only
        let specialProtocols = ["calibration_5rm", "calibration_8rm", "myo_rest_pause_variant",
                                "waves_5_4_3_2_1_variant", "ratchet_1_3_fall_intensity",
                                "pyramid_5set_variant", "pyramid_up_6_5_4_3_2_1_variant_heavy"]

        if specialProtocols.contains(config.id) {
            return config.variantName
        }

        // Standard protocols: Show Set×Rep + Tempo + RPE
        var parts: [String] = []

        // v40.6: Add set×rep notation (e.g., "3×8")
        let setCount = config.reps.count
        if let firstReps = config.reps.first {
            let allSameReps = config.reps.allSatisfy { $0 == firstReps }
            if allSameReps {
                // Straight sets: "3×8" (all sets same reps)
                parts.append("\(setCount)×\(firstReps)")
            }
            // If reps vary, don't show set×rep notation (variant name will be used)
        }

        // Tempo (if available and not default)
        if let tempo = config.tempo, !tempo.isEmpty, tempo != "0000" {
            parts.append("Tempo \(tempo)")
        }

        // RPE (average if multiple sets)
        if let rpeValues = config.rpe, !rpeValues.isEmpty {
            let avgRPE = rpeValues.reduce(0.0, +) / Double(rpeValues.count)
            parts.append("RPE \(String(format: "%.1f", avgRPE))")
        }

        if parts.isEmpty {
            // Fallback if no tempo/RPE: show variant name
            return config.variantName
        }

        return parts.joined(separator: " • ")
    }
}
