//
// ExerciseProtocol.swift
// Medina
//
// Last reviewed: October 2025
// v52: Simplified to single ProtocolConfig struct with educational content
// v101.0: Added duration field for cardio protocols (replaces tempo hack)
//

import Foundation

struct ProtocolConfig: Identifiable, Codable {
    let id: String
    let protocolFamily: String?         // Grouping label (e.g., "gbc", "pyramid", "waves")
    var variantName: String             // "GBC Compound", "5-Set Pyramid"
    var reps: [Int]                     // [10, 10, 10]
    var intensityAdjustments: [Double]  // Relative to program intensity: [0.0, 0.05, 0.10]
    var restBetweenSets: [Int]          // [90, 90] (seconds between sets)
    var tempo: String?                  // Strength tempo notation (e.g., "3010")
    var rpe: [Double]?                  // RPE per set
    var loadingPattern: LoadingPattern? // Optional loading pattern

    // v101.0: Cardio support
    var duration: Int?                  // Duration in seconds for cardio (e.g., 1200 = 20 min)

    // Instructions and Educational Content
    var executionNotes: String          // How to execute (technical details)
    var methodology: String?            // What/Why the protocol works (educational)

    // Hierarchical Permission System
    var createdByMemberId: String?
    var createdByTrainerId: String?
    var createdByGymId: String?

    // MARK: - Codable with Backward Compatibility

    enum CodingKeys: String, CodingKey {
        case id, protocolFamily, variantName, reps, intensityAdjustments
        case restBetweenSets, tempo, rpe, loadingPattern
        case duration  // v101.0: Cardio duration
        case executionNotes, methodology
        case createdByMemberId, createdByTrainerId, createdByGymId
        case protocolId  // Legacy key
        case defaultInstructions  // Legacy key
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        // Backward compatibility: protocolId → protocolFamily
        if let family = try? container.decodeIfPresent(String.self, forKey: .protocolFamily) {
            protocolFamily = family
        } else {
            protocolFamily = try container.decodeIfPresent(String.self, forKey: .protocolId)
        }

        variantName = try container.decode(String.self, forKey: .variantName)
        reps = try container.decode([Int].self, forKey: .reps)
        intensityAdjustments = try container.decode([Double].self, forKey: .intensityAdjustments)
        restBetweenSets = try container.decode([Int].self, forKey: .restBetweenSets)
        tempo = try container.decodeIfPresent(String.self, forKey: .tempo)
        rpe = try container.decodeIfPresent([Double].self, forKey: .rpe)
        loadingPattern = try container.decodeIfPresent(LoadingPattern.self, forKey: .loadingPattern)

        // v101.0: Cardio duration
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)

        // Backward compatibility: defaultInstructions → executionNotes
        if let notes = try? container.decodeIfPresent(String.self, forKey: .executionNotes) {
            executionNotes = notes
        } else {
            executionNotes = try container.decode(String.self, forKey: .defaultInstructions)
        }

        methodology = try container.decodeIfPresent(String.self, forKey: .methodology)
        createdByMemberId = try container.decodeIfPresent(String.self, forKey: .createdByMemberId)
        createdByTrainerId = try container.decodeIfPresent(String.self, forKey: .createdByTrainerId)
        createdByGymId = try container.decodeIfPresent(String.self, forKey: .createdByGymId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(protocolFamily, forKey: .protocolFamily)
        try container.encode(variantName, forKey: .variantName)
        try container.encode(reps, forKey: .reps)
        try container.encode(intensityAdjustments, forKey: .intensityAdjustments)
        try container.encode(restBetweenSets, forKey: .restBetweenSets)
        try container.encodeIfPresent(tempo, forKey: .tempo)
        try container.encodeIfPresent(rpe, forKey: .rpe)
        try container.encodeIfPresent(loadingPattern, forKey: .loadingPattern)
        // v101.0: Cardio duration
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(executionNotes, forKey: .executionNotes)
        try container.encodeIfPresent(methodology, forKey: .methodology)
        try container.encodeIfPresent(createdByMemberId, forKey: .createdByMemberId)
        try container.encodeIfPresent(createdByTrainerId, forKey: .createdByTrainerId)
        try container.encodeIfPresent(createdByGymId, forKey: .createdByGymId)
    }

    // MARK: - v51.0 Library Support

    /// Helper computed properties for library UI compatibility
    var sets: Int { reps.count }
    var repsMin: Int { reps.min() ?? 0 }
    var repsMax: Int { reps.max() ?? 0 }
    var restSeconds: Int { restBetweenSets.first ?? 90 }
    var name: String { variantName }  // Alias for backward compatibility

    // MARK: - v88.0 Protocol Family Grouping

    /// Display name for the protocol family (e.g., "Straight Sets", "GBC (Giant Sets)")
    var familyDisplayName: String {
        guard let family = protocolFamily else { return variantName }
        switch family {
        case "gbc": return "GBC (Giant Sets)"
        case "straightSets": return "Straight Sets"
        case "myoReps": return "Myo-Reps"
        case "wave": return "Wave Loading"
        case "pyramid": return "Pyramid Sets"
        case "dropSet": return "Drop Sets"
        case "restPause": return "Rest-Pause"
        case "cluster": return "Cluster Sets"
        default: return variantName
        }
    }

    /// Short variant label for chip selector (e.g., "3x8", "Accessory", "5/4/3")
    var variantLabel: String {
        guard let family = protocolFamily else { return variantName }
        switch family {
        case "gbc":
            // "GBC Accessory" → "Accessory", "GBC Compound" → "Compound"
            return variantName.replacingOccurrences(of: "GBC ", with: "")
        case "straightSets":
            // "Straight 3x8" → "3x8", "Straight 4x6" → "4x6"
            return variantName.replacingOccurrences(of: "Straight ", with: "")
        case "wave":
            // "5/4/3 Wave" → "5/4/3", "7/5/3 Wave" → "7/5/3"
            return variantName.replacingOccurrences(of: " Wave", with: "")
        case "pyramid":
            // "Ascending Pyramid" → "Ascending", "Descending Pyramid" → "Descending"
            return variantName.replacingOccurrences(of: " Pyramid", with: "")
        default:
            return variantName
        }
    }
}