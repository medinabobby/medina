//
// DateFormatters.swift
// Medina
//
// Created: October 2025
// Purpose: Centralized date formatting utilities for consistent display across the app
//

import Foundation

/// Shared date formatters for consistent date display throughout the app
/// Used by CardDisplayable extensions, handlers, and anywhere dates need formatting
enum DateFormatters {

    /// Format: "Jan 1, 2025 at 3:00 PM"
    /// Used for: Detailed timestamps (e.g., set recording times)
    static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Format: "Jan 1, 2025"
    /// Used for: Date-only display (no time)
    static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Format: "Jan 1" (short month + day)
    /// Used for: Entity display names, date ranges
    /// Most commonly used formatter (15 usages across app)
    static let shortMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Format: "Mon" (short day name)
    /// Used for: Schedule views, day-of-week indicators
    static let dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
