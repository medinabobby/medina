//
// StatusFilteringService.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

// MARK: - Status Filtering Service

/// Provides common status filtering utilities used across all entity resolvers.
/// Extracts shared patterns for date-based filtering, status mapping, and raw text context handling.
enum StatusFilteringService {


    /// Check if an entity is currently active (within its date range)
    static func isActive<T: TemporalEntity>(_ entity: T, referenceDate: Date = Date()) -> Bool {
        return entity.startDate <= referenceDate && entity.endDate >= referenceDate
    }

    /// Check if an entity is upcoming (starts in the future)
    static func isUpcoming<T: TemporalEntity>(_ entity: T, referenceDate: Date = Date()) -> Bool {
        return entity.startDate > referenceDate
    }

    /// Check if an entity is past (ended already)
    static func isPast<T: TemporalEntity>(_ entity: T, referenceDate: Date = Date()) -> Bool {
        return entity.endDate < referenceDate
    }

    // MARK: - Raw Text Context Handling

    /// Handle special keyword filtering that requires context preservation
    /// Returns nil if no special handling is needed, otherwise returns the filtered results
    static func handleSpecialKeywords<T>(
        in rawText: String?,
        fallbackFilter: () -> [T],
        keywordHandlers: [String: () -> [T]]
    ) -> [T]? {
        guard let rawText = rawText?.lowercased() else { return nil }

        for (keyword, handler) in keywordHandlers {
            if rawText.contains(keyword) {
                return handler()
            }
        }

        return nil
    }

}

// MARK: - Supporting Types

/// Protocol for entities that have date ranges (Plans, Programs)
protocol TemporalEntity {
    var startDate: Date { get }
    var endDate: Date { get }
}

/// Common temporal categories for consistent filtering
enum TemporalCategory {
    case current, future, past, all, none
}

// MARK: - Entity Protocol Conformance

extension Plan: TemporalEntity {}
extension Program: TemporalEntity {}