//
// RestTimer.swift
// Medina
//
// v19.0 - Rest timer tracking for workout sessions
// Last reviewed: October 2025
//

import Foundation

/// Rest timer for tracking rest periods between sets
/// Persists in Session model to survive app backgrounding/restart
struct RestTimer: Codable {
    let startTime: Date
    var endTime: Date  // Mutable - can be adjusted with +10s/-10s actions
    let originalDuration: TimeInterval  // For UI display (total progress bar length)
    let setJustCompleted: Int  // Which set index triggered this rest period
    var skipped: Bool

    init(startTime: Date, duration: TimeInterval, setJustCompleted: Int) {
        self.startTime = startTime
        self.endTime = startTime.addingTimeInterval(duration)
        self.originalDuration = duration
        self.setJustCompleted = setJustCompleted
        self.skipped = false
    }

    /// Remaining time until rest period ends (always >= 0)
    var remainingTime: TimeInterval {
        max(0, endTime.timeIntervalSinceNow)
    }

    /// Check if rest period has expired
    var isExpired: Bool {
        Date() >= endTime
    }

    /// Adjust end time by delta seconds (positive = extend, negative = shorten)
    /// - Parameter delta: Seconds to add/subtract (e.g., +10, -10)
    mutating func adjustTime(by delta: TimeInterval) {
        endTime = endTime.addingTimeInterval(delta)

        // Don't allow negative remaining time (can't go back in time)
        let now = Date()
        if endTime < now {
            endTime = now
        }
    }
}
