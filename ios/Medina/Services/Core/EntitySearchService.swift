//
// EntitySearchService.swift
// Medina
//
// Created: November 13, 2025
// Purpose: Unified search across plans, programs, workouts, exercises, and protocols
//

import Foundation

// MARK: - Search Results

struct SearchResults {
    let plans: [Plan]
    let programs: [Program]
    let workouts: [Workout]
    let exercises: [Exercise]
    let protocolFamilies: [ProtocolFamilySearchResult]  // v88.0: Grouped by family
    // v186: Removed classInstances (class booking deferred for beta)

    var isEmpty: Bool {
        plans.isEmpty && programs.isEmpty && workouts.isEmpty && exercises.isEmpty && protocolFamilies.isEmpty
    }

    var totalCount: Int {
        plans.count + programs.count + workouts.count + exercises.count + protocolFamilies.count
    }

    // v88.0: Backward compatibility - returns flat protocol list
    var protocols: [ProtocolSearchResult] {
        protocolFamilies.flatMap { family in
            family.variants.map { config in
                ProtocolSearchResult(
                    id: config.id,
                    variantName: config.variantName,
                    familyName: config.protocolFamily ?? "",
                    protocolConfig: config
                )
            }
        }
    }
}

struct ProtocolSearchResult: Identifiable {
    let id: String  // protocolConfigId
    let variantName: String
    let familyName: String
    let protocolConfig: ProtocolConfig
}

// v88.0: Protocol family search result
struct ProtocolFamilySearchResult: Identifiable {
    let id: String  // Family ID
    let displayName: String
    let variants: [ProtocolConfig]
    let variantCount: Int

    var hasMultipleVariants: Bool { variantCount > 1 }
}

// v186: Removed ClassInstanceSearchResult (class booking deferred for beta)

// MARK: - Search Service

class EntitySearchService {

    /// Perform unified search across all entity types
    static func performSearch(query: String, memberId: String) -> SearchResults {
        guard !query.isEmpty else {
            return SearchResults(plans: [], programs: [], workouts: [], exercises: [], protocolFamilies: [])
        }

        let lowercased = query.lowercased()
        let userContext = UserContext(userId: memberId)

        // Search plans
        let matchingPlans = searchPlans(query: lowercased, memberId: memberId)

        // Search programs
        let matchingPrograms = searchPrograms(query: lowercased, memberId: memberId)

        // Search workouts
        let matchingWorkouts = searchWorkouts(query: lowercased, memberId: memberId)

        // Search exercises
        let matchingExercises = ExerciseResolver.searchExercises(query: query, for: userContext)

        // v88.0: Search protocol families
        let matchingProtocolFamilies = searchProtocolFamilies(query: lowercased)

        // v186: Removed class instance search (class booking deferred for beta)

        return SearchResults(
            plans: matchingPlans,
            programs: matchingPrograms,
            workouts: matchingWorkouts,
            exercises: matchingExercises,
            protocolFamilies: matchingProtocolFamilies
        )
    }

    // MARK: - Plan Search

    private static func searchPlans(query: String, memberId: String) -> [Plan] {
        let allPlans = PlanResolver.allPlans(for: memberId)

        return allPlans.filter { plan in
            // Search name
            if plan.name.lowercased().contains(query) {
                return true
            }

            // Search description
            if plan.description.lowercased().contains(query) {
                return true
            }

            // Search goal (enum to string)
            if plan.goal.rawValue.lowercased().contains(query) {
                return true
            }

            return false
        }
    }

    // MARK: - Program Search

    private static func searchPrograms(query: String, memberId: String) -> [Program] {
        let allPrograms = ProgramResolver.programs(
            for: memberId,
            status: nil,
            temporal: .unspecified
        )

        return allPrograms.filter { program in
            // Search name
            if program.name.lowercased().contains(query) {
                return true
            }

            // Search focus (enum to string)
            if program.focus.rawValue.lowercased().contains(query) {
                return true
            }

            // Search rationale (non-optional)
            if program.rationale.lowercased().contains(query) {
                return true
            }

            return false
        }
    }

    // MARK: - Workout Search

    private static func searchWorkouts(query: String, memberId: String) -> [Workout] {
        let allWorkouts = WorkoutResolver.workouts(
            for: memberId,
            temporal: .unspecified,
            status: nil,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: nil,
            program: nil,
            dateInterval: nil
        )

        return allWorkouts.filter { workout in
            // Search name
            workout.name.lowercased().contains(query)
        }
    }

    // MARK: - Protocol Search

    /// v88.0: Search protocol families (grouped by family)
    private static func searchProtocolFamilies(query: String) -> [ProtocolFamilySearchResult] {
        let allFamilies = ProtocolGroupingService.getProtocolFamilies()

        return allFamilies.compactMap { family in
            // Match family display name
            if family.displayName.lowercased().contains(query) {
                return ProtocolFamilySearchResult(
                    id: family.id,
                    displayName: family.displayName,
                    variants: family.variants,
                    variantCount: family.variantCount
                )
            }

            // Match family ID
            if family.id.lowercased().contains(query) {
                return ProtocolFamilySearchResult(
                    id: family.id,
                    displayName: family.displayName,
                    variants: family.variants,
                    variantCount: family.variantCount
                )
            }

            // Match any variant in the family
            let matchingVariants = family.variants.filter { config in
                matchesProtocolQuery(config: config, query: query)
            }

            if !matchingVariants.isEmpty {
                return ProtocolFamilySearchResult(
                    id: family.id,
                    displayName: family.displayName,
                    variants: matchingVariants,
                    variantCount: family.variantCount
                )
            }

            return nil
        }
    }

    /// v83.5: Search both user's library AND global protocols (legacy - kept for backward compatibility)
    private static func searchProtocols(query: String, memberId: String) -> [ProtocolSearchResult] {
        var results: [ProtocolSearchResult] = []
        var addedIds: Set<String> = []

        // 1. Search user's library first (if they have one)
        if let library = TestDataManager.shared.libraries[memberId] {
            for protocolEntry in library.protocols {
                guard let config = TestDataManager.shared.protocolConfigs[protocolEntry.protocolConfigId] else {
                    continue
                }

                if matchesProtocolQuery(config: config, query: query) {
                    results.append(ProtocolSearchResult(
                        id: protocolEntry.protocolConfigId,
                        variantName: config.variantName,
                        familyName: config.protocolFamily ?? "",
                        protocolConfig: config
                    ))
                    addedIds.insert(protocolEntry.protocolConfigId)
                }
            }
        }

        // 2. Also search ALL global protocols (v83.5)
        for (configId, config) in TestDataManager.shared.protocolConfigs {
            // Skip if already added from user library
            guard !addedIds.contains(configId) else { continue }

            if matchesProtocolQuery(config: config, query: query) {
                results.append(ProtocolSearchResult(
                    id: configId,
                    variantName: config.variantName,
                    familyName: config.protocolFamily ?? "",
                    protocolConfig: config
                ))
            }
        }

        return results
    }

    /// Helper to check if a protocol config matches the search query
    private static func matchesProtocolQuery(config: ProtocolConfig, query: String) -> Bool {
        // Search variant name
        if config.variantName.lowercased().contains(query) {
            return true
        }

        // Search protocol ID (for searching "gbc", "strength", etc.)
        if config.id.lowercased().contains(query) {
            return true
        }

        // Search protocol family
        if let family = config.protocolFamily, family.lowercased().contains(query) {
            return true
        }

        // Search execution notes
        if config.executionNotes.lowercased().contains(query) {
            return true
        }

        // Search methodology
        if let methodology = config.methodology, methodology.lowercased().contains(query) {
            return true
        }

        return false
    }

    // v186: Removed class search (class booking deferred for beta)
}
