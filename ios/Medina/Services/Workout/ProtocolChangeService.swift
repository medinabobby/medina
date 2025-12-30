//
// ProtocolChangeService.swift
// Medina
//
// v84.0: Clean in-place protocol modification
// Created: December 5, 2025
//
// Direct path: workout → instances → sets → update in place
// NO delete/recreate, NO WorkoutCreationService, NO DurationAwareWorkoutBuilder
//

import Foundation

/// Errors for protocol changes
enum ProtocolChangeError: LocalizedError {
    case workoutNotFound(String)
    case noInstances(String)
    case cannotModifyActive(String)
    case cannotModifyCompleted(String)
    case protocolNotFound(String)  // v84.1

    var errorDescription: String? {
        switch self {
        case .workoutNotFound(let id):
            return "Workout not found: \(id)"
        case .noInstances(let id):
            return "No exercises found for workout: \(id)"
        case .cannotModifyActive(let name):
            return "Cannot modify active workout '\(name)'"
        case .cannotModifyCompleted(let name):
            return "Cannot modify completed workout '\(name)'"
        case .protocolNotFound(let name):
            return "Protocol not found: '\(name)'"
        }
    }

    var userMessage: String {
        switch self {
        case .workoutNotFound:
            return "I couldn't find that workout."
        case .noInstances:
            return "This workout has no exercises to modify."
        case .cannotModifyActive(let name):
            return "'\(name)' is currently active. End it first to make changes."
        case .cannotModifyCompleted(let name):
            return "'\(name)' is completed. Would you like me to create a new workout instead?"
        case .protocolNotFound(let name):
            return "I don't recognize the protocol '\(name)'. Try 'gbc', 'drop sets', 'waves', 'pyramid', or 'strength'."
        }
    }
}

/// Result of protocol change
struct ProtocolChangeResult {
    let workoutId: String
    let workoutName: String
    let exerciseCount: Int
    let setsUpdated: Int
    let protocolId: String?        // v84.1: Protocol ID from configs
    let protocolName: String?      // v84.1: Display name
    let newReps: Int
    let newRest: Int
    let newTempo: String
    let newRPE: Double
}

/// Service for changing workout protocols in place
/// Direct modification - no delete/recreate pattern
enum ProtocolChangeService {

    // MARK: - Main Entry Point (v84.1: Uses ProtocolResolver)

    /// Change protocol for a workout using a protocol name or ID
    /// - Parameters:
    ///   - workoutId: Workout to modify
    ///   - protocolNameOrId: Protocol name (e.g., "gbc", "drop sets") or ID (e.g., "machine_drop_set")
    ///   - repsOverride: Override the protocol's reps (optional)
    ///   - setsOverride: Override the protocol's sets (optional)
    ///   - restOverride: Override the protocol's rest (optional)
    ///   - tempoOverride: Override the protocol's tempo (optional)
    ///   - rpeOverride: Override the protocol's RPE (optional)
    ///   - userId: User ID for persistence
    /// - Returns: Result with details of what was changed
    static func changeProtocol(
        workoutId: String,
        to protocolNameOrId: String,
        repsOverride: Int? = nil,
        setsOverride: Int? = nil,
        restOverride: Int? = nil,
        tempoOverride: String? = nil,
        rpeOverride: Double? = nil,
        userId: String
    ) throws -> ProtocolChangeResult {
        // v84.1: Use ProtocolResolver to find the protocol config
        guard let config = ProtocolResolver.resolve(protocolNameOrId) else {
            throw ProtocolChangeError.protocolNotFound(protocolNameOrId)
        }

        let resolvedId = ProtocolResolver.resolveId(protocolNameOrId)

        // Extract values from config, apply overrides
        let baseReps = config.reps.first ?? 10
        let baseRest = config.restBetweenSets.first ?? 60
        let baseRPE = config.rpe?.first ?? 8.0

        return try changeProtocol(
            workoutId: workoutId,
            targetReps: repsOverride ?? baseReps,
            targetSets: setsOverride ?? config.reps.count,
            restBetweenSets: restOverride ?? baseRest,
            tempo: tempoOverride ?? config.tempo,
            targetRPE: rpeOverride ?? baseRPE,
            protocolId: resolvedId,
            protocolName: config.variantName,
            userId: userId
        )
    }

    /// Change protocol for a workout using custom values
    /// - Parameters:
    ///   - workoutId: Workout to modify
    ///   - targetReps: New target reps (nil = keep existing)
    ///   - targetSets: New number of sets (nil = keep existing)
    ///   - restBetweenSets: New rest in seconds (nil = keep existing)
    ///   - tempo: New tempo string (nil = keep existing)
    ///   - targetRPE: New RPE (nil = keep existing)
    ///   - protocolId: Protocol ID if resolved from name (for logging/display)
    ///   - protocolName: Protocol display name (for logging/display)
    ///   - userId: User ID for persistence
    /// - Returns: Result with details of what was changed
    static func changeProtocol(
        workoutId: String,
        targetReps: Int? = nil,
        targetSets: Int? = nil,
        restBetweenSets: Int? = nil,
        tempo: String? = nil,
        targetRPE: Double? = nil,
        protocolId: String? = nil,
        protocolName: String? = nil,
        userId: String
    ) throws -> ProtocolChangeResult {

        // 1. Find and validate workout
        guard var workout = LocalDataStore.shared.workouts[workoutId] else {
            throw ProtocolChangeError.workoutNotFound(workoutId)
        }

        switch workout.status {
        case .inProgress:
            throw ProtocolChangeError.cannotModifyActive(workout.name)
        case .completed:
            throw ProtocolChangeError.cannotModifyCompleted(workout.name)
        case .scheduled, .skipped:
            break // OK to modify
        }

        // 2. Find all instances for this workout
        let instances = LocalDataStore.shared.exerciseInstances.values.filter {
            $0.workoutId == workoutId
        }

        guard !instances.isEmpty else {
            throw ProtocolChangeError.noInstances(workoutId)
        }

        // 3. Update sets in place AND update instance protocolVariantId
        var setsUpdated = 0
        let finalReps = targetReps ?? 10
        let finalRest = restBetweenSets ?? 60
        let finalTempo = tempo ?? "2010"
        let finalRPE = targetRPE ?? 8.0

        for instance in instances {
            // v84.1: Update instance's protocolVariantId so card displays correctly
            if let newProtocolId = protocolId {
                var updatedInstance = instance
                let oldProtocolId = updatedInstance.protocolVariantId
                updatedInstance.protocolVariantId = newProtocolId
                LocalDataStore.shared.exerciseInstances[instance.id] = updatedInstance
                Logger.log(.info, component: "ProtocolChangeService",
                          message: "📝 Updated instance '\(instance.id)' protocolVariantId: '\(oldProtocolId)' → '\(newProtocolId)'")
            }

            setsUpdated += updateSets(
                for: instance,
                targetReps: targetReps,
                targetSets: targetSets,
                restBetweenSets: restBetweenSets,
                tempo: tempo,
                targetRPE: targetRPE
            )
        }

        // 4. Update workout name if protocol was specified
        if let name = protocolName {
            // Append protocol name if not already present
            let shortName = name.components(separatedBy: " ").first ?? name
            if !workout.name.lowercased().contains(shortName.lowercased()) {
                workout.name = "\(workout.name) - \(shortName)"
                LocalDataStore.shared.workouts[workoutId] = workout
            }
        }

        // 5. Persist changes
        persistChanges(userId: userId)

        Logger.log(.info, component: "ProtocolChangeService",
                  message: "✅ v84.0: Changed protocol for '\(workout.name)': \(setsUpdated) sets updated to \(finalReps) reps, \(finalRest)s rest, \(finalTempo) tempo, RPE \(finalRPE)")

        return ProtocolChangeResult(
            workoutId: workoutId,
            workoutName: workout.name,
            exerciseCount: instances.count,
            setsUpdated: setsUpdated,
            protocolId: protocolId,
            protocolName: protocolName,
            newReps: finalReps,
            newRest: finalRest,
            newTempo: finalTempo,
            newRPE: finalRPE
        )
    }

    // MARK: - Set Updates

    /// Update sets for an exercise instance
    /// Returns number of sets updated
    private static func updateSets(
        for instance: ExerciseInstance,
        targetReps: Int?,
        targetSets: Int?,
        restBetweenSets: Int?,
        tempo: String?,
        targetRPE: Double?
    ) -> Int {
        var updatedCount = 0

        // Get current sets for this instance
        var sets = instance.setIds.compactMap { setId in
            LocalDataStore.shared.exerciseSets[setId]
        }

        guard !sets.isEmpty else { return 0 }

        // Handle set count changes
        if let newSetCount = targetSets {
            let currentCount = sets.count

            if newSetCount > currentCount {
                // Add sets
                let lastSet = sets.last!
                for i in currentCount..<newSetCount {
                    let newSetId = "\(instance.id)_s\(i + 1)"
                    var newSet = ExerciseSet(
                        id: newSetId,
                        exerciseInstanceId: instance.id,
                        setNumber: i + 1,
                        targetWeight: lastSet.targetWeight,
                        targetReps: targetReps ?? lastSet.targetReps,
                        targetRPE: targetRPE.map { Int($0) } ?? lastSet.targetRPE,
                        actualWeight: nil,
                        actualReps: nil,
                        completion: .scheduled,
                        startTime: nil,
                        endTime: nil,
                        notes: nil,
                        recordedDate: nil
                    )
                    LocalDataStore.shared.exerciseSets[newSetId] = newSet
                    updatedCount += 1
                }

                // Update instance setIds
                var updatedInstance = instance
                var newSetIds = instance.setIds
                for i in currentCount..<newSetCount {
                    newSetIds.append("\(instance.id)_s\(i + 1)")
                }
                updatedInstance.setIds = newSetIds
                LocalDataStore.shared.exerciseInstances[instance.id] = updatedInstance

            } else if newSetCount < currentCount {
                // Remove sets (keep minimum 1)
                let keepCount = max(1, newSetCount)
                let removeCount = currentCount - keepCount

                for i in 0..<removeCount {
                    let removeIndex = currentCount - 1 - i
                    let setId = instance.setIds[removeIndex]
                    LocalDataStore.shared.exerciseSets.removeValue(forKey: setId)
                }

                // Update instance setIds
                var updatedInstance = instance
                updatedInstance.setIds = Array(instance.setIds.prefix(keepCount))
                LocalDataStore.shared.exerciseInstances[instance.id] = updatedInstance

                // Re-fetch sets
                sets = updatedInstance.setIds.compactMap { setId in
                    LocalDataStore.shared.exerciseSets[setId]
                }
            }
        }

        // Update existing sets
        for var set in sets {
            var changed = false

            if let reps = targetReps, set.targetReps != reps {
                set.targetReps = reps
                changed = true
            }

            if let rpe = targetRPE {
                let rpeInt = Int(rpe)
                if set.targetRPE != rpeInt {
                    set.targetRPE = rpeInt
                    changed = true
                }
            }

            if changed {
                LocalDataStore.shared.exerciseSets[set.id] = set
                updatedCount += 1
            }
        }

        return updatedCount
    }

    // MARK: - Persistence

    /// v206: Sync changes to Firestore
    private static func persistChanges(userId: String) {
        // v206: Removed legacy disk persistence - Firestore is source of truth
        // Sync affected workouts to Firestore
        Task {
            do {
                let plans = LocalDataStore.shared.plans.values.filter { $0.memberId == userId }
                let planIds = Set(plans.map { $0.id })

                let programs = LocalDataStore.shared.programs.values.filter { planIds.contains($0.planId) }
                let programIds = Set(programs.map { $0.id })

                let workouts = LocalDataStore.shared.workouts.values.filter { programIds.contains($0.programId) }

                for workout in workouts {
                    let instances = LocalDataStore.shared.exerciseInstances.values.filter { $0.workoutId == workout.id }
                    let instanceIds = Set(instances.map { $0.id })
                    let sets = LocalDataStore.shared.exerciseSets.values.filter { instanceIds.contains($0.exerciseInstanceId) }

                    try await FirestoreWorkoutRepository.shared.saveFullWorkout(
                        workout: workout,
                        instances: Array(instances),
                        sets: Array(sets),
                        memberId: userId
                    )
                }

                Logger.log(.info, component: "ProtocolChangeService",
                          message: "☁️ Synced protocol changes to Firestore")
            } catch {
                Logger.log(.warning, component: "ProtocolChangeService",
                          message: "⚠️ Firestore sync failed: \(error)")
            }
        }
    }
}
