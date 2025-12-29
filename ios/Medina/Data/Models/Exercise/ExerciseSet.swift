//
// ExerciseSet.swift
// Medina
//
// Last reviewed: October 2025
// v101.0: Added cardio fields (targetDuration, actualDuration, targetDistance, actualDistance)
//

import Foundation

struct ExerciseSet: Identifiable, Codable {
    let id: String
    let exerciseInstanceId: String
    var setNumber: Int

    // MARK: - Strength Training Fields
    var targetWeight: Double?
    var targetReps: Int?
    var targetRPE: Int?  // v80.5: For bands/bodyweight that use RPE instead of weight
    var actualWeight: Double?
    var actualReps: Int?

    // MARK: - Cardio Fields (v101.0)
    var targetDuration: Int?      // Target duration in seconds (e.g., 1200 = 20 min)
    var targetDistance: Double?   // Target distance in miles (e.g., 2.5)
    var actualDuration: Int?      // Actual duration performed in seconds
    var actualDistance: Double?   // Actual distance covered in miles

    // MARK: - Common Fields
    var completion: ExecutionStatus?
    var startTime: Date?
    var endTime: Date?
    var notes: String?
    var recordedDate: Date?

    /// Standard memberwise initializer (required because custom Codable init prevents auto-generation)
    init(
        id: String,
        exerciseInstanceId: String,
        setNumber: Int,
        targetWeight: Double? = nil,
        targetReps: Int? = nil,
        targetRPE: Int? = nil,
        actualWeight: Double? = nil,
        actualReps: Int? = nil,
        targetDuration: Int? = nil,
        targetDistance: Double? = nil,
        actualDuration: Int? = nil,
        actualDistance: Double? = nil,
        completion: ExecutionStatus? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        notes: String? = nil,
        recordedDate: Date? = nil
    ) {
        self.id = id
        self.exerciseInstanceId = exerciseInstanceId
        self.setNumber = setNumber
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.targetRPE = targetRPE
        self.actualWeight = actualWeight
        self.actualReps = actualReps
        self.targetDuration = targetDuration
        self.targetDistance = targetDistance
        self.actualDuration = actualDuration
        self.actualDistance = actualDistance
        self.completion = completion
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.recordedDate = recordedDate
    }

    // v27.1: Custom decoding to map recordedReps/recordedWeight → actualReps/actualWeight
    // v101.0: Added cardio fields
    enum CodingKeys: String, CodingKey {
        case id
        case exerciseInstanceId
        case setNumber
        case targetWeight
        case targetReps
        case targetRPE  // v80.5
        case actualWeight
        case actualReps
        case recordedWeight  // JSON alias for actualWeight
        case recordedReps    // JSON alias for actualReps
        // v101.0: Cardio fields
        case targetDuration
        case targetDistance
        case actualDuration
        case actualDistance
        case completion
        case startTime
        case endTime
        case notes
        case recordedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        exerciseInstanceId = try container.decode(String.self, forKey: .exerciseInstanceId)
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        targetWeight = try container.decodeIfPresent(Double.self, forKey: .targetWeight)
        targetReps = try container.decodeIfPresent(Int.self, forKey: .targetReps)
        targetRPE = try container.decodeIfPresent(Int.self, forKey: .targetRPE)

        // Try actualWeight first, fallback to recordedWeight
        if let actual = try container.decodeIfPresent(Double.self, forKey: .actualWeight) {
            actualWeight = actual
        } else {
            actualWeight = try container.decodeIfPresent(Double.self, forKey: .recordedWeight)
        }

        // Try actualReps first, fallback to recordedReps
        if let actual = try container.decodeIfPresent(Int.self, forKey: .actualReps) {
            actualReps = actual
        } else {
            actualReps = try container.decodeIfPresent(Int.self, forKey: .recordedReps)
        }

        // v101.0: Cardio fields
        targetDuration = try container.decodeIfPresent(Int.self, forKey: .targetDuration)
        targetDistance = try container.decodeIfPresent(Double.self, forKey: .targetDistance)
        actualDuration = try container.decodeIfPresent(Int.self, forKey: .actualDuration)
        actualDistance = try container.decodeIfPresent(Double.self, forKey: .actualDistance)

        completion = try container.decodeIfPresent(ExecutionStatus.self, forKey: .completion)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        recordedDate = try container.decodeIfPresent(Date.self, forKey: .recordedDate)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(exerciseInstanceId, forKey: .exerciseInstanceId)
        try container.encode(setNumber, forKey: .setNumber)
        try container.encodeIfPresent(targetWeight, forKey: .targetWeight)
        try container.encodeIfPresent(targetReps, forKey: .targetReps)
        try container.encodeIfPresent(targetRPE, forKey: .targetRPE)
        try container.encodeIfPresent(actualWeight, forKey: .actualWeight)
        try container.encodeIfPresent(actualReps, forKey: .actualReps)
        // v101.0: Cardio fields
        try container.encodeIfPresent(targetDuration, forKey: .targetDuration)
        try container.encodeIfPresent(targetDistance, forKey: .targetDistance)
        try container.encodeIfPresent(actualDuration, forKey: .actualDuration)
        try container.encodeIfPresent(actualDistance, forKey: .actualDistance)
        try container.encodeIfPresent(completion, forKey: .completion)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(recordedDate, forKey: .recordedDate)
    }
}

// MARK: - Cardio Helpers (v101.0)

extension ExerciseSet {
    /// Whether this set has cardio targets (duration-based rather than reps-based)
    var isCardioSet: Bool {
        targetDuration != nil
    }

    /// Formatted duration string (e.g., "20:00" for 1200 seconds)
    var formattedTargetDuration: String? {
        guard let duration = targetDuration else { return nil }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formatted actual duration string
    var formattedActualDuration: String? {
        guard let duration = actualDuration else { return nil }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}