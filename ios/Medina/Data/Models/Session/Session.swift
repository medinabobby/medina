//
// Session.swift
// Medina
//
// v17.0 - Active workout session tracking
// v19.0 - Rest timer support
// v55.0 - Removed executionMode (guided-only)
// Last reviewed: November 2025
//

import Foundation

struct Session: Identifiable, Codable {
    let id: String
    let workoutId: String
    let memberId: String
    let startTime: Date
    var endTime: Date?
    var currentExerciseIndex: Int
    var currentSetIndex: Int
    var status: SessionStatus
    var pausedAt: Date?
    var totalPauseTime: TimeInterval
    var activeRestTimer: RestTimer?  // v19.0: Current rest timer (nil if no active rest)

    // v50: Superset Support
    var currentSupersetCycleSet: Int?  // Tracks which set # in superset cycle (nil for standalone exercises)

    enum SessionStatus: String, Codable {
        case active
        case paused
        case completed
        case abandoned
    }

    // v55.0: Custom coding keys for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, workoutId, memberId, startTime, endTime
        case currentExerciseIndex, currentSetIndex, status
        case pausedAt, totalPauseTime, activeRestTimer, currentSupersetCycleSet
        case executionMode  // Keep for migration, but don't decode
    }

    init(
        id: String = UUID().uuidString,
        workoutId: String,
        memberId: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        currentExerciseIndex: Int = 0,
        currentSetIndex: Int = 0,
        status: SessionStatus = .active,
        pausedAt: Date? = nil,
        totalPauseTime: TimeInterval = 0,
        activeRestTimer: RestTimer? = nil,
        currentSupersetCycleSet: Int? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.memberId = memberId
        self.startTime = startTime
        self.endTime = endTime
        self.currentExerciseIndex = currentExerciseIndex
        self.currentSetIndex = currentSetIndex
        self.status = status
        self.pausedAt = pausedAt
        self.totalPauseTime = totalPauseTime
        self.activeRestTimer = activeRestTimer
        self.currentSupersetCycleSet = currentSupersetCycleSet
    }

    // v55.0: Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        workoutId = try container.decode(String.self, forKey: .workoutId)
        memberId = try container.decode(String.self, forKey: .memberId)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        currentExerciseIndex = try container.decode(Int.self, forKey: .currentExerciseIndex)
        currentSetIndex = try container.decode(Int.self, forKey: .currentSetIndex)
        status = try container.decode(SessionStatus.self, forKey: .status)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        totalPauseTime = try container.decode(TimeInterval.self, forKey: .totalPauseTime)
        activeRestTimer = try container.decodeIfPresent(RestTimer.self, forKey: .activeRestTimer)
        currentSupersetCycleSet = try container.decodeIfPresent(Int.self, forKey: .currentSupersetCycleSet)

        // v55.0: Ignore old executionMode (migration - don't crash on old JSON)
        _ = try? container.decodeIfPresent(ExecutionMode.self, forKey: .executionMode)
    }

    // v55.0: Custom encoder (don't write executionMode)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(workoutId, forKey: .workoutId)
        try container.encode(memberId, forKey: .memberId)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encode(currentExerciseIndex, forKey: .currentExerciseIndex)
        try container.encode(currentSetIndex, forKey: .currentSetIndex)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(pausedAt, forKey: .pausedAt)
        try container.encode(totalPauseTime, forKey: .totalPauseTime)
        try container.encodeIfPresent(activeRestTimer, forKey: .activeRestTimer)
        try container.encodeIfPresent(currentSupersetCycleSet, forKey: .currentSupersetCycleSet)
        // v55.0: Don't encode executionMode
    }

    /// Duration of the workout session excluding pauses
    var activeDuration: TimeInterval {
        let end = endTime ?? Date()
        let elapsed = end.timeIntervalSince(startTime)
        return elapsed - totalPauseTime
    }

    /// Check if session is currently active (not paused, completed, or abandoned)
    var isActive: Bool {
        return status == .active
    }
}
