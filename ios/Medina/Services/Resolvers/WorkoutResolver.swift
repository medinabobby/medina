//
// WorkoutResolver.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

enum WorkoutResolver {

    static func nextWorkout(
        for memberId: String,
        temporal: TemporalSlot,
        status: WorkoutStatus?,
        modality: ModalitySlot,
        splitDay: SplitDay? = nil,
        source: EntityRelationship?,
        plan: Plan?,
        program: Program? = nil,
        dateInterval: DateInterval?
    ) -> Workout? {
        WorkoutDataStore.nextWorkout(
            for: memberId,
            temporal: temporal,
            status: status,
            modality: modality,
            splitDay: splitDay,
            source: source,
            plan: plan,
            program: program,
            dateInterval: dateInterval
        )
    }

    static func workouts(
        for memberId: String,
        temporal: TemporalSlot,
        status: WorkoutStatus?,
        modality: ModalitySlot,
        splitDay: SplitDay? = nil,
        source: EntityRelationship?,
        plan: Plan?,
        program: Program? = nil,
        dateInterval: DateInterval?
    ) -> [Workout] {
        WorkoutDataStore.workouts(
            for: memberId,
            temporal: temporal,
            status: status,
            modality: modality,
            splitDay: splitDay,
            source: source,
            plan: plan,
            program: program,
            dateInterval: dateInterval
        )
    }


    /// Extended nextWorkout method with rawText support for special keywords
    static func nextWorkout(
        for memberId: String,
        temporal: TemporalSlot,
        status: WorkoutStatus?,
        modality: ModalitySlot,
        splitDay: SplitDay? = nil,
        source: EntityRelationship?,
        plan: Plan?,
        program: Program? = nil,
        dateInterval: DateInterval?,
        rawText: String?
    ) -> Workout? {
        // Handle special keyword filtering using StatusFilteringService
        if let filtered = StatusFilteringService.handleSpecialKeywords(
            in: rawText,
            fallbackFilter: {
                if let workout = nextWorkout(
                    for: memberId,
                    temporal: temporal,
                    status: status,
                    modality: modality,
                    splitDay: splitDay,
                    source: source,
                    plan: plan,
                    program: program,
                    dateInterval: dateInterval
                ) {
                    return [workout]
                } else {
                    return []
                }
            },
            keywordHandlers: [
                "draft": { draftWorkouts(for: memberId) }
            ]
        ) {
            return filtered.first
        }

        // Otherwise use normal filtering
        return nextWorkout(
            for: memberId,
            temporal: temporal,
            status: status,
            modality: modality,
            splitDay: splitDay,
            source: source,
            plan: plan,
            program: program,
            dateInterval: dateInterval
        )
    }

    /// Extended workouts method with rawText support for special keywords
    static func workouts(
        for memberId: String,
        temporal: TemporalSlot,
        status: WorkoutStatus?,
        modality: ModalitySlot,
        splitDay: SplitDay? = nil,
        source: EntityRelationship?,
        plan: Plan?,
        program: Program? = nil,
        dateInterval: DateInterval?,
        rawText: String?
    ) -> [Workout] {
        // Handle special keyword filtering using StatusFilteringService
        if let filtered = StatusFilteringService.handleSpecialKeywords(
            in: rawText,
            fallbackFilter: {
                workouts(
                    for: memberId,
                    temporal: temporal,
                    status: status,
                    modality: modality,
                    splitDay: splitDay,
                    source: source,
                    plan: plan,
                    program: program,
                    dateInterval: dateInterval
                )
            },
            keywordHandlers: [
                "draft": { draftWorkouts(for: memberId) }
            ]
        ) {
            return filtered
        }

        // Otherwise use normal filtering
        return workouts(
            for: memberId,
            temporal: temporal,
            status: status,
            modality: modality,
            splitDay: splitDay,
            source: source,
            plan: plan,
            program: program,
            dateInterval: dateInterval
        )
    }

    static func draftWorkouts(for memberId: String) -> [Workout] {
        return WorkoutDataStore.workouts(
            for: memberId,
            temporal: .upcoming
        ).filter { workout in
            // Workouts could be considered "draft" if they haven't been completed
            workout.status != .completed &&
            (workout.scheduledDate ?? Date.distantFuture) > Date()
        }
    }
}
