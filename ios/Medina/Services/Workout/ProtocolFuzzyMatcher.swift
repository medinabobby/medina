//
//  ProtocolFuzzyMatcher.swift
//  Medina
//
//  v102.4 - Fuzzy matching for AI-provided protocol IDs
//  v102.5 - Added semantic mappings (hypertrophy→strength, endurance→strength)
//  Created: December 2025
//
//  Problem: AI hallucinates protocol IDs using different terminology than our system.
//
//  Examples:
//  - hypertrophy_3x8 → strength_3x8_moderate (semantic mapping)
//  - endurance_3x15 → strength_3x15_light (semantic mapping)
//  - hypertrophy_3x8_12 → strength_3x8_moderate (strip suffix + semantic)
//

import Foundation

/// Fuzzy matching for AI-provided protocol IDs
/// Handles common AI mistakes: wrong terminology, extra suffixes, rep range confusion
enum ProtocolFuzzyMatcher {

    // MARK: - Semantic Mappings

    /// Maps AI terminology to our actual protocol naming
    /// Our system uses "strength" for all rep ranges, AI uses "hypertrophy/endurance"
    private static let semanticMappings: [String: String] = [
        // Hypertrophy → Strength (moderate intensity)
        "hypertrophy_3x8": "strength_3x8_moderate",
        "hypertrophy_3x10": "strength_3x10_moderate",
        "hypertrophy_3x12": "strength_3x12_light",
        "hypertrophy_4x8": "accessory_4x8_rpe8",
        "hypertrophy_4x10": "accessory_4x10_rpe8",
        "hypertrophy_4x12": "accessory_4x12_moderate",

        // Endurance → Strength (light intensity)
        "endurance_3x12": "strength_3x12_light",
        "endurance_3x15": "strength_3x15_light",
        "endurance_3x20": "strength_3x15_light",  // Closest match

        // Accessory variations
        "accessory_3x10": "accessory_3x10_rpe8",
        "accessory_3x12": "accessory_3x12_moderate",
        "accessory_3x15": "accessory_3x15_light",
        "accessory_4x10": "accessory_4x10_rpe8",

        // RPE variations AI might use
        "hypertrophy_3x12_rpe8": "accessory_3x12_moderate",
        "hypertrophy_3x10_rpe8": "accessory_3x10_rpe8",
        "strength_3x8_rpe8": "strength_3x8_moderate",
    ]

    // MARK: - Main Entry Point

    /// Try to match an AI-provided ID to an actual protocol
    /// Returns the ProtocolConfig if found, nil otherwise
    static func match(_ aiId: String) -> ProtocolConfig? {
        let protocols = LocalDataStore.shared.protocolConfigs

        // 1. Exact match (most common case - fast path)
        if let config = protocols[aiId] {
            return config
        }

        // 2. Try normalized version (lowercase, trim whitespace)
        let normalized = aiId.lowercased().trimmingCharacters(in: .whitespaces)
        if normalized != aiId, let config = protocols[normalized] {
            Logger.log(.info, component: "ProtocolFuzzyMatcher",
                message: "✓ Normalized '\(aiId)' → '\(normalized)'")
            return config
        }

        // 3. Try semantic mapping (hypertrophy → strength, etc.)
        if let mappedId = semanticMappings[normalized], let config = protocols[mappedId] {
            Logger.log(.info, component: "ProtocolFuzzyMatcher",
                message: "✓ Semantic mapped '\(aiId)' → '\(mappedId)'")
            return config
        }

        // 4. Try removing trailing number suffix then semantic mapping
        // e.g., "hypertrophy_3x8_12" → "hypertrophy_3x8" → "strength_3x8_moderate"
        if let config = findByRemovingTrailingSuffix(normalized, in: protocols) {
            Logger.log(.info, component: "ProtocolFuzzyMatcher",
                message: "✓ Suffix removed '\(aiId)' → '\(config.id)'")
            return config
        }

        // 5. Try prefix match (find protocols that start with the AI's ID)
        if let config = findByPrefix(normalized, in: protocols) {
            Logger.log(.info, component: "ProtocolFuzzyMatcher",
                message: "✓ Prefix matched '\(aiId)' → '\(config.id)'")
            return config
        }

        // 6. Try word-based matching (same words, different order)
        if let config = findByWordMatch(normalized, in: protocols) {
            Logger.log(.info, component: "ProtocolFuzzyMatcher",
                message: "✓ Word matched '\(aiId)' → '\(config.id)'")
            return config
        }

        // 7. Try pattern extraction and best-effort match
        if let config = findByPatternExtraction(normalized, in: protocols) {
            Logger.log(.info, component: "ProtocolFuzzyMatcher",
                message: "✓ Pattern extracted '\(aiId)' → '\(config.id)'")
            return config
        }

        // No match found
        return nil
    }

    // MARK: - Matching Strategies

    /// Remove trailing numeric suffix and try again
    /// e.g., "hypertrophy_3x8_12" → "hypertrophy_3x8" → semantic lookup
    private static func findByRemovingTrailingSuffix(_ id: String, in protocols: [String: ProtocolConfig]) -> ProtocolConfig? {
        let parts = id.split(separator: "_")
        guard parts.count >= 2 else { return nil }

        // Try removing last part if it's a number or RPE modifier
        if let lastPart = parts.last,
           Int(lastPart) != nil || String(lastPart).hasPrefix("rpe") {
            let shortened = parts.dropLast().joined(separator: "_")

            // Direct match
            if let config = protocols[shortened] {
                return config
            }

            // Semantic mapping after suffix removal
            if let mappedId = semanticMappings[shortened], let config = protocols[mappedId] {
                return config
            }
        }

        // Try removing last two parts if they're numbers (e.g., "_3x8_12" pattern)
        if parts.count >= 3,
           let last = parts.last, Int(last) != nil {
            // Check if second-to-last contains "x" (like "3x8")
            let secondLast = parts[parts.count - 2]
            if secondLast.contains("x") {
                // This is likely a set/rep pattern, keep it
                let shortened = parts.dropLast().joined(separator: "_")

                // Direct match
                if let config = protocols[shortened] {
                    return config
                }

                // Semantic mapping after suffix removal
                if let mappedId = semanticMappings[shortened], let config = protocols[mappedId] {
                    return config
                }
            }
        }

        return nil
    }

    /// Find protocol that starts with the given prefix
    private static func findByPrefix(_ id: String, in protocols: [String: ProtocolConfig]) -> ProtocolConfig? {
        // Find exact prefix matches
        let matches = protocols.filter { $0.key.hasPrefix(id) || id.hasPrefix($0.key) }

        // Return the shortest match (most specific)
        return matches.min { $0.key.count < $1.key.count }?.value
    }

    /// Find protocol by matching key words
    private static func findByWordMatch(_ id: String, in protocols: [String: ProtocolConfig]) -> ProtocolConfig? {
        let idWords = Set(id.split(separator: "_").map(String.init))

        // Look for protocols with significant word overlap
        var bestMatch: (ProtocolConfig, Int)?

        for (protocolId, config) in protocols {
            let protocolWords = Set(protocolId.split(separator: "_").map(String.init))
            let overlap = idWords.intersection(protocolWords).count

            // Need at least 2 matching words
            if overlap >= 2 {
                if bestMatch == nil || overlap > bestMatch!.1 {
                    bestMatch = (config, overlap)
                }
            }
        }

        return bestMatch?.0
    }

    /// Extract set/rep pattern and find best matching protocol
    /// e.g., "hypertrophy_3x8" extracts 3x8 and finds strength_3x8_moderate
    private static func findByPatternExtraction(_ id: String, in protocols: [String: ProtocolConfig]) -> ProtocolConfig? {
        // Extract NxM pattern (e.g., "3x8", "4x10")
        let pattern = #"(\d+)x(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
              let setsRange = Range(match.range(at: 1), in: id),
              let repsRange = Range(match.range(at: 2), in: id) else {
            return nil
        }

        let sets = String(id[setsRange])
        let reps = String(id[repsRange])
        let setRepPattern = "\(sets)x\(reps)"

        // Find protocols containing this pattern
        let candidates = protocols.filter { $0.key.contains(setRepPattern) }

        // Prefer "strength_" or "accessory_" protocols
        if let strengthMatch = candidates.first(where: { $0.key.hasPrefix("strength_") }) {
            return strengthMatch.value
        }
        if let accessoryMatch = candidates.first(where: { $0.key.hasPrefix("accessory_") }) {
            return accessoryMatch.value
        }

        // Return any match
        return candidates.first?.value
    }
}
