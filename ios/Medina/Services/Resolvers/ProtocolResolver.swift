//
// ProtocolResolver.swift
// Medina
//
// v84.1: Protocol resolution - mirrors ExerciseResolver pattern
// Created: December 5, 2025
//
// Data-driven protocol lookup from protocol_configs.json
// No hardcoded enums - scales with library growth
//

import Foundation

/// Protocol resolution service - mirrors ExerciseResolver pattern
/// Looks up protocols from LocalDataStore.shared.protocolConfigs
enum ProtocolResolver {

    // MARK: - Common Name Aliases

    /// Maps user-friendly names to protocol IDs
    /// These are convenience aliases - AI can also use any protocol ID directly
    private static let aliases: [String: String] = [
        // GBC variants
        "gbc": "gbc_relative_compound",
        "german body composition": "gbc_relative_compound",
        "gbc compound": "gbc_relative_compound",
        "gbc accessory": "gbc_relative_accessory",

        // Strength variants
        "strength": "strength_3x5_moderate",
        "heavy": "strength_3x3_heavy",
        "5x5": "strength_5x5_straight",
        "linear": "linear_5x5_variant_standard",

        // Hypertrophy/Volume
        "hypertrophy": "straight_4x10_variant_volume",
        "volume": "straight_4x10_variant_volume",
        "bodybuilding": "straight_3x12_variant_standard",

        // Special methods
        "drop set": "machine_drop_set",
        "drop sets": "machine_drop_set",
        "dropset": "machine_drop_set",
        "myo": "myo_rest_pause_variant",
        "myo reps": "myo_rest_pause_variant",
        "rest pause": "rest_pause_85pct",
        "rest-pause": "rest_pause_85pct",

        // Waves/Pyramids
        "waves": "waves_5_4_3_2_1_variant_standard",
        "wave": "waves_5_4_3_2_1_variant_standard",
        "pyramid": "pyramid_12_10_8_ascending",
        "ascending pyramid": "pyramid_12_10_8_ascending",

        // Endurance
        "endurance": "strength_3x15_light",
        "high rep": "bodyweight_high_rep",
        "pump": "band_high_rep_pump",

        // Specialty
        "wendler": "wendler_531_80pct",
        "531": "wendler_531_80pct",
        "5/3/1": "wendler_531_80pct",
        "hyrox": "hyrox_conditioning",
        "kettlebell": "kettlebell_for_time",

        // Tempo
        "tempo": "bodyweight_tempo_4040",
        "slow tempo": "bodyweight_tempo_4040",
        "time under tension": "bodyweight_tempo_4040",
        "tut": "bodyweight_tempo_4040"
    ]

    // MARK: - Resolution

    /// Resolve a protocol name or ID to a ProtocolConfig
    /// - Parameter nameOrId: User-friendly name (e.g., "gbc", "drop sets") OR protocol ID
    /// - Returns: ProtocolConfig if found, nil otherwise
    static func resolve(_ nameOrId: String) -> ProtocolConfig? {
        let lowercased = nameOrId.lowercased().trimmingCharacters(in: .whitespaces)

        // 1. Try direct ID lookup first
        if let config = LocalDataStore.shared.protocolConfigs[lowercased] {
            return config
        }

        // 2. Try alias lookup
        if let protocolId = aliases[lowercased],
           let config = LocalDataStore.shared.protocolConfigs[protocolId] {
            return config
        }

        // 3. Try partial match on protocol IDs
        let matchingId = LocalDataStore.shared.protocolConfigs.keys.first { id in
            id.lowercased().contains(lowercased) || lowercased.contains(id.lowercased())
        }
        if let id = matchingId, let config = LocalDataStore.shared.protocolConfigs[id] {
            return config
        }

        // 4. Try matching variant name
        let matchingConfig = LocalDataStore.shared.protocolConfigs.values.first { config in
            config.variantName.lowercased().contains(lowercased)
        }
        if let config = matchingConfig {
            return config
        }

        return nil
    }

    /// Resolve to protocol ID (for cases where you need the ID, not the config)
    static func resolveId(_ nameOrId: String) -> String? {
        let lowercased = nameOrId.lowercased().trimmingCharacters(in: .whitespaces)

        // 1. Direct ID exists
        if LocalDataStore.shared.protocolConfigs[lowercased] != nil {
            return lowercased
        }

        // 2. Alias lookup
        if let protocolId = aliases[lowercased],
           LocalDataStore.shared.protocolConfigs[protocolId] != nil {
            return protocolId
        }

        // 3. Partial match
        if let matchingId = LocalDataStore.shared.protocolConfigs.keys.first(where: { id in
            id.lowercased().contains(lowercased) || lowercased.contains(id.lowercased())
        }) {
            return matchingId
        }

        return nil
    }

    // MARK: - Search

    /// Search protocols by query (name, family, methodology)
    /// - Parameter query: Search query
    /// - Returns: Array of matching (id, config) tuples
    static func search(query: String) -> [(id: String, config: ProtocolConfig)] {
        let lowercased = query.lowercased()

        return LocalDataStore.shared.protocolConfigs.compactMap { (id, config) in
            // Match on ID
            if id.lowercased().contains(lowercased) {
                return (id, config)
            }
            // Match on variant name
            if config.variantName.lowercased().contains(lowercased) {
                return (id, config)
            }
            // Match on family
            if let family = config.protocolFamily, family.lowercased().contains(lowercased) {
                return (id, config)
            }
            // Match on methodology
            if let methodology = config.methodology, methodology.lowercased().contains(lowercased) {
                return (id, config)
            }
            return nil
        }
    }

    /// Get all protocols in a family (e.g., "strength", "gbc", "waves")
    static func byFamily(_ family: String) -> [(id: String, config: ProtocolConfig)] {
        let lowercased = family.lowercased()

        return LocalDataStore.shared.protocolConfigs.compactMap { (id, config) in
            if let protocolFamily = config.protocolFamily,
               protocolFamily.lowercased().contains(lowercased) {
                return (id, config)
            }
            // Also check if ID starts with family name
            if id.lowercased().hasPrefix(lowercased) {
                return (id, config)
            }
            return nil
        }
    }

    // MARK: - Listing

    /// Get all available protocol IDs
    static var allProtocolIds: [String] {
        Array(LocalDataStore.shared.protocolConfigs.keys).sorted()
    }

    /// Get all aliases (for AI prompt)
    static var allAliases: [String] {
        Array(aliases.keys).sorted()
    }

    /// Get protocol families
    static var families: [String] {
        let families = Set(LocalDataStore.shared.protocolConfigs.values.compactMap { $0.protocolFamily })
        return Array(families).sorted()
    }
}
