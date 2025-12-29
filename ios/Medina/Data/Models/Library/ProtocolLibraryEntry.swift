//
// ProtocolLibraryEntry.swift
// Medina
//
// v51.0 - Exercise & Protocol Library (Phase 1a)
// Created: November 5, 2025
//
// Purpose: Protocol templates with selection criteria
// Matches protocols to exercises based on type, intensity, and goal
//

import Foundation

struct ProtocolLibraryEntry: Codable, Identifiable, Hashable {
    let id: String
    let protocolConfigId: String  // References ProtocolConfig.id
    var isEnabled: Bool
    var addedDate: Date

    // Selection criteria
    var applicableTo: [ExerciseType]  // [.compound] or [.isolation] or both
    var intensityRange: ClosedRange<Double>  // 0.65...0.85 for strength
    var preferredGoals: [FitnessGoal]  // [.strength, .muscleGain]

    // v82.0: Equipment preference for smarter protocol selection
    // If set, this protocol is preferred when exercise uses matching equipment
    // e.g., bodyweight_tempo_4040 prefers [.bodyweight] equipment
    var preferredEquipment: [Equipment]?

    // Phase 3: Preference signals (future)
    var selectionWeight: Double = 1.0

    init(
        protocolConfigId: String,
        isEnabled: Bool = true,
        applicableTo: [ExerciseType],
        intensityRange: ClosedRange<Double>,
        preferredGoals: [FitnessGoal],
        preferredEquipment: [Equipment]? = nil
    ) {
        self.id = UUID().uuidString
        self.protocolConfigId = protocolConfigId
        self.isEnabled = isEnabled
        self.addedDate = Date()
        self.applicableTo = applicableTo
        self.intensityRange = intensityRange
        self.preferredGoals = preferredGoals
        self.preferredEquipment = preferredEquipment
    }
}

// MARK: - Custom Coding for ProtocolLibraryEntry

extension ProtocolLibraryEntry {
    enum CodingKeys: String, CodingKey {
        case id, protocolConfigId, isEnabled, addedDate
        case applicableTo, intensityRange, preferredGoals, selectionWeight
        case preferredEquipment  // v82.0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        protocolConfigId = try container.decode(String.self, forKey: .protocolConfigId)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        addedDate = try container.decode(Date.self, forKey: .addedDate)
        applicableTo = try container.decode([ExerciseType].self, forKey: .applicableTo)
        preferredGoals = try container.decode([FitnessGoal].self, forKey: .preferredGoals)
        selectionWeight = try container.decode(Double.self, forKey: .selectionWeight)

        // v82.0: Decode preferredEquipment (optional, may not exist in old data)
        preferredEquipment = try container.decodeIfPresent([Equipment].self, forKey: .preferredEquipment)

        // Custom decoding for intensityRange
        let rangeContainer = try container.nestedContainer(keyedBy: RangeCodingKeys.self, forKey: .intensityRange)
        let lower = try rangeContainer.decode(Double.self, forKey: .lowerBound)
        let upper = try rangeContainer.decode(Double.self, forKey: .upperBound)
        intensityRange = lower...upper
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(protocolConfigId, forKey: .protocolConfigId)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(addedDate, forKey: .addedDate)
        try container.encode(applicableTo, forKey: .applicableTo)
        try container.encode(preferredGoals, forKey: .preferredGoals)
        try container.encode(selectionWeight, forKey: .selectionWeight)

        // v82.0: Encode preferredEquipment if present
        try container.encodeIfPresent(preferredEquipment, forKey: .preferredEquipment)

        // Custom encoding for intensityRange
        var rangeContainer = container.nestedContainer(keyedBy: RangeCodingKeys.self, forKey: .intensityRange)
        try rangeContainer.encode(intensityRange.lowerBound, forKey: .lowerBound)
        try rangeContainer.encode(intensityRange.upperBound, forKey: .upperBound)
    }

    private enum RangeCodingKeys: String, CodingKey {
        case lowerBound
        case upperBound
    }
}
