//
//  SupersetPairingService.swift
//  Medina
//
//  v83.0: Superset pairing logic for workout creation
//  v93.5: Fix duplicate exercise positions causing "6 exercises, 3 rows" bug
//  Created: December 2025
//
//  Purpose: Creates SupersetGroup objects for workouts based on either:
//  - Auto-pair mode: System pairs exercises based on style (antagonist, agonist, etc.)
//  - Explicit mode: User specifies exact pairings with custom rest times
//

import Foundation

// MARK: - SupersetGroupIntent

/// Intent for explicit superset groupings from AI tool call
struct SupersetGroupIntent: Codable {
    let positions: [Int]      // Exercise positions (0-indexed) to pair
    let restBetween: Int      // Rest in seconds between exercises in this group (1a→1b)
    let restAfter: Int        // Rest in seconds after completing full rotation
}

// MARK: - SupersetPairingService

/// Service for creating SupersetGroup objects during workout creation
/// Supports both auto-pair (system determines pairs) and explicit (user-specified) modes
enum SupersetPairingService {

    // MARK: - Main Entry Point

    /// Create superset groups from exercise list based on style
    /// - Parameters:
    ///   - exerciseIds: Array of exercise IDs in workout order
    ///   - style: SupersetStyle (antagonist, agonist, circuit, explicit, none)
    ///   - explicitGroups: User-specified groupings (only for explicit mode)
    ///   - userLevel: Experience level (affects safety validations)
    /// - Returns: Array of SupersetGroup objects, or nil if style is "none"
    static func createGroups(
        exerciseIds: [String],
        style: SupersetStyle,
        explicitGroups: [SupersetGroupIntent]? = nil,
        userLevel: ExperienceLevel = .intermediate
    ) -> [SupersetGroup]? {

        switch style {
        case .none:
            return nil

        case .explicit:
            // v83.1: For explicit mode, honor user's request regardless of exercise count
            // User specified exact pairings, so trust their configuration
            return createExplicitGroups(from: explicitGroups, exerciseCount: exerciseIds.count)

        case .circuit:
            return createCircuitGroup(exerciseCount: exerciseIds.count, style: style)

        case .antagonist, .agonist, .compoundIsolation:
            // Auto-pair modes need minimum 4 exercises for 2 pairs
            guard exerciseIds.count >= 4 else {
                return nil
            }
            return createAutoPairedGroups(
                exerciseIds: exerciseIds,
                style: style,
                userLevel: userLevel
            )
        }
    }

    // MARK: - Explicit Mode

    /// Convert user-specified groupings to SupersetGroup objects
    /// - Parameters:
    ///   - intents: Array of SupersetGroupIntent from AI tool call
    ///   - exerciseCount: Total number of exercises in workout
    /// - Returns: Array of SupersetGroup objects
    static func createExplicitGroups(
        from intents: [SupersetGroupIntent]?,
        exerciseCount: Int
    ) -> [SupersetGroup]? {

        guard let intents = intents, !intents.isEmpty else {
            return nil
        }

        var groups: [SupersetGroup] = []
        var usedPositions: Set<Int> = []  // v93.5: Track used positions across ALL groups

        for (index, intent) in intents.enumerated() {
            // Validate positions are within bounds
            guard intent.positions.allSatisfy({ $0 >= 0 && $0 < exerciseCount }) else {
                Logger.log(.warning, component: "SupersetPairingService",
                    message: "v93.5: Skipping group \(index+1) - positions out of bounds (exerciseCount=\(exerciseCount))")
                continue
            }

            // v93.5: Filter out positions already used by previous groups
            let availablePositions = intent.positions.filter { !usedPositions.contains($0) }
            guard availablePositions.count >= 2 else {
                // A superset group needs at least 2 exercises
                Logger.log(.warning, component: "SupersetPairingService",
                    message: "v93.5: Skipping group \(index+1) - insufficient unique positions (need 2+, have \(availablePositions.count))")
                continue
            }

            // Mark these positions as used
            availablePositions.forEach { usedPositions.insert($0) }

            // v93.5: Use availablePositions (deduplicated) instead of intent.positions
            // Create rest array - restBetween for all except last, restAfter for last
            var restDurations = Array(repeating: intent.restBetween, count: availablePositions.count)
            if !restDurations.isEmpty {
                restDurations[restDurations.count - 1] = intent.restAfter
            }

            let group = SupersetGroup(
                id: "explicit_superset_\(index + 1)",
                groupNumber: index + 1,
                exercisePositions: availablePositions,  // v93.5: Use deduplicated positions
                restBetweenExercises: restDurations
            )

            groups.append(group)
        }

        return groups.isEmpty ? nil : groups
    }

    // MARK: - Circuit Mode

    /// Create a single circuit group containing all exercises
    /// - Parameters:
    ///   - exerciseCount: Number of exercises
    ///   - style: SupersetStyle for rest duration defaults
    /// - Returns: Array with one SupersetGroup containing all positions
    private static func createCircuitGroup(
        exerciseCount: Int,
        style: SupersetStyle
    ) -> [SupersetGroup]? {

        guard exerciseCount >= 2 else { return nil }

        let positions = Array(0..<exerciseCount)

        // All exercises get short rest, last one gets longer rest
        var restDurations = Array(repeating: style.defaultRestBetween, count: exerciseCount)
        restDurations[exerciseCount - 1] = style.defaultRestAfter

        let group = SupersetGroup(
            id: "circuit_group_1",
            groupNumber: 1,
            exercisePositions: positions,
            restBetweenExercises: restDurations
        )

        return [group]
    }

    // MARK: - Auto-Pair Mode

    /// Create superset groups using system-determined pairings
    /// - Parameters:
    ///   - exerciseIds: Array of exercise IDs
    ///   - style: Pairing style (antagonist, agonist, compound_isolation)
    ///   - userLevel: User experience level
    /// - Returns: Array of SupersetGroup objects
    private static func createAutoPairedGroups(
        exerciseIds: [String],
        style: SupersetStyle,
        userLevel: ExperienceLevel
    ) -> [SupersetGroup]? {

        // Get exercise objects
        let exercises: [(position: Int, exercise: Exercise)] = exerciseIds.enumerated().compactMap { index, id in
            guard let exercise = TestDataManager.shared.exercises[id] else { return nil }
            return (index, exercise)
        }

        guard exercises.count >= 4 else {
            Logger.log(.warning, component: "SupersetPairingService",
                message: "⚠️ Only \(exercises.count) exercises (need 4+ for auto-pairing)")
            return nil
        }

        // v83.4: Debug log exercise info for pairing analysis
        let muscleList = exercises.map { "\($0.exercise.name): \($0.exercise.muscleGroups.first?.rawValue ?? "?")" }.joined(separator: ", ")
        Logger.log(.info, component: "SupersetPairingService",
            message: "Auto-pairing \(exercises.count) exercises (\(style.rawValue)): \(muscleList)")

        // Find pairs based on style
        let pairs: [(pos1: Int, pos2: Int, score: Double)]

        switch style {
        case .antagonist:
            pairs = findAntagonistPairs(exercises: exercises)
        case .agonist:
            pairs = findAgonistPairs(exercises: exercises, userLevel: userLevel)
        case .compoundIsolation:
            pairs = findCompoundIsolationPairs(exercises: exercises)
        default:
            return nil
        }

        // v83.4: Debug log pair candidates
        if pairs.isEmpty {
            Logger.log(.warning, component: "SupersetPairingService",
                message: "⚠️ No valid pairs found for \(style.rawValue) - need opposing muscle groups (e.g., quads↔hamstrings, chest↔back)")
        } else {
            let pairInfo = pairs.prefix(3).map { "(\($0.pos1)-\($0.pos2): \(String(format: "%.2f", $0.score)))" }.joined(separator: ", ")
            Logger.log(.info, component: "SupersetPairingService",
                message: "Found \(pairs.count) candidate pair(s): \(pairInfo)")
        }

        // Convert pairs to SupersetGroups
        return createGroupsFromPairs(
            pairs: pairs,
            style: style,
            maxGroups: 2  // Limit to 2 superset pairs per workout
        )
    }

    // MARK: - Pairing Algorithms

    /// Find antagonist pairs (push-pull, opposing muscles)
    private static func findAntagonistPairs(
        exercises: [(position: Int, exercise: Exercise)]
    ) -> [(pos1: Int, pos2: Int, score: Double)] {

        var candidates: [(pos1: Int, pos2: Int, score: Double)] = []

        for i in 0..<exercises.count {
            for j in (i + 1)..<exercises.count {
                let (pos1, ex1) = exercises[i]
                let (pos2, ex2) = exercises[j]

                // Check for avoidance rules
                if shouldAvoidPairing(ex1, ex2) { continue }

                // Calculate antagonist score
                var score = 0.0

                // Movement pattern matching (highest weight: 0.5)
                if let pattern1 = ex1.movementPattern, let pattern2 = ex2.movementPattern {
                    if isMovementAntagonist(pattern1, pattern2) {
                        score += 0.5
                    }
                }

                // Muscle group opposition (weight: 0.35)
                if let primary1 = ex1.muscleGroups.first, let primary2 = ex2.muscleGroups.first {
                    score += antagonistMuscleScore(primary1, primary2) * 0.35
                }

                // Equipment compatibility bonus (weight: 0.15)
                if ex1.equipment == ex2.equipment && ex1.equipment != .bodyweight {
                    score += 0.15
                }

                // Only include if score is meaningful
                if score >= 0.4 {
                    candidates.append((pos1, pos2, score))
                }
            }
        }

        return candidates.sorted { $0.score > $1.score }
    }

    /// Find agonist pairs (same muscle group - compound + isolation)
    /// v83.4: Removed beginner block - AI can advise on safety, user decides
    private static func findAgonistPairs(
        exercises: [(position: Int, exercise: Exercise)],
        userLevel: ExperienceLevel
    ) -> [(pos1: Int, pos2: Int, score: Double)] {

        // v83.4: REMOVED hard block for beginners
        // Philosophy: Code enables, AI guides, User decides
        // AI can warn beginners about agonist superset intensity if appropriate

        var candidates: [(pos1: Int, pos2: Int, score: Double)] = []

        for i in 0..<exercises.count {
            for j in (i + 1)..<exercises.count {
                let (pos1, ex1) = exercises[i]
                let (pos2, ex2) = exercises[j]

                // Must have at least one isolation for safety
                guard ex1.type == .isolation || ex2.type == .isolation else { continue }

                // Must target same primary muscle
                guard let primary1 = ex1.muscleGroups.first,
                      let primary2 = ex2.muscleGroups.first,
                      primary1 == primary2 else { continue }

                // Different base exercise
                guard ex1.baseExercise != ex2.baseExercise else { continue }

                var score = 0.6  // Base score for valid agonist pair

                // Compound + isolation is ideal
                if ex1.type != ex2.type {
                    score += 0.25
                }

                // Equipment compatibility bonus
                if ex1.equipment == ex2.equipment {
                    score += 0.1
                }

                candidates.append((pos1, pos2, score))
            }
        }

        return candidates.sorted { $0.score > $1.score }
    }

    /// Find compound-isolation pairs (any compound with any isolation)
    private static func findCompoundIsolationPairs(
        exercises: [(position: Int, exercise: Exercise)]
    ) -> [(pos1: Int, pos2: Int, score: Double)] {

        var candidates: [(pos1: Int, pos2: Int, score: Double)] = []

        let compounds = exercises.filter { $0.exercise.type == .compound }
        let isolations = exercises.filter { $0.exercise.type == .isolation }

        for compound in compounds {
            for isolation in isolations {
                let (pos1, ex1) = compound
                let (pos2, ex2) = isolation

                var score = 0.5  // Base score

                // Same primary muscle is ideal (post-exhaust)
                if let primary1 = ex1.muscleGroups.first,
                   let primary2 = ex2.muscleGroups.first,
                   primary1 == primary2 {
                    score += 0.3
                } else {
                    score += 0.15  // Different muscles still useful (active recovery)
                }

                // Equipment compatibility
                if ex1.equipment == ex2.equipment {
                    score += 0.1
                }

                candidates.append((pos1, pos2, score))
            }
        }

        return candidates.sorted { $0.score > $1.score }
    }

    // MARK: - Helper Methods

    /// Check if two movement patterns are antagonists or complementary
    /// v83.5: Added squat↔pull pairs for full-body supersets (different body regions allow rest)
    private static func isMovementAntagonist(_ p1: MovementPattern, _ p2: MovementPattern) -> Bool {
        let pairs: Set<Set<MovementPattern>> = [
            // Traditional antagonist pairs
            [.horizontalPress, .horizontalPull],
            [.verticalPress, .verticalPull],
            [.push, .pull],
            [.squat, .hinge],
            // v83.5: Complementary pairs (lower body + upper body allows rest)
            [.squat, .verticalPull],     // Squat + Pull-up/Lat pulldown
            [.squat, .horizontalPull],   // Squat + Row
            [.hinge, .verticalPull],     // Deadlift + Pull-up
            [.hinge, .horizontalPull],   // Deadlift + Row
            [.squat, .pull],             // Generic squat + pull
            [.hinge, .pull]              // Generic hinge + pull
        ]
        return pairs.contains([p1, p2])
    }

    /// Calculate antagonist score between two muscle groups
    /// v83.5: Added lower body↔upper back pairs for full-body supersets
    private static func antagonistMuscleScore(_ m1: MuscleGroup, _ m2: MuscleGroup) -> Double {
        // Perfect pairs (1.0) - traditional antagonists
        let perfectPairs: Set<Set<MuscleGroup>> = [
            [.chest, .back], [.chest, .lats],
            [.biceps, .triceps],
            [.quadriceps, .hamstrings],
            [.shoulders, .back]
        ]
        if perfectPairs.contains([m1, m2]) { return 1.0 }

        // Good pairs (0.7) - includes complementary pairs
        // v83.5: Added quads/glutes↔lats/back for squat-pull supersets
        let goodPairs: Set<Set<MuscleGroup>> = [
            [.chest, .traps],
            [.shoulders, .lats],
            [.abs, .back],
            [.glutes, .quadriceps],
            // v83.5: Lower body ↔ Upper back (squat-pull supersets)
            [.quadriceps, .lats],
            [.quadriceps, .back],
            [.glutes, .lats],
            [.glutes, .back],
            [.hamstrings, .lats],
            [.hamstrings, .back]
        ]
        if goodPairs.contains([m1, m2]) { return 0.7 }

        // Same muscle = avoid for antagonist
        if m1 == m2 { return 0.0 }

        // Neutral
        return 0.3
    }

    /// Check if two exercises should NOT be paired
    /// v83.4: Removed hard safety blocks - AI can advise, user decides
    /// Only blocks truly invalid pairings (same exercise twice)
    private static func shouldAvoidPairing(_ ex1: Exercise, _ ex2: Exercise) -> Bool {
        // Only block: Same base exercise (no benefit to supersetting identical movements)
        if ex1.baseExercise == ex2.baseExercise {
            return true
        }

        // v83.4: REMOVED hard blocks for:
        // - Two heavy barbell compounds (user preference, AI can advise)
        // - Olympic lifts (user preference, AI can advise)
        // Philosophy: Code enables, AI guides, User decides

        return false
    }

    /// Convert scored pairs into SupersetGroup objects
    private static func createGroupsFromPairs(
        pairs: [(pos1: Int, pos2: Int, score: Double)],
        style: SupersetStyle,
        maxGroups: Int
    ) -> [SupersetGroup]? {

        var usedPositions: Set<Int> = []
        var groups: [SupersetGroup] = []
        var groupNumber = 1

        for pair in pairs where groups.count < maxGroups {
            // Skip if either position already used
            guard !usedPositions.contains(pair.pos1),
                  !usedPositions.contains(pair.pos2) else {
                continue
            }

            let group = SupersetGroup.pair(
                groupNumber: groupNumber,
                position1: pair.pos1,
                position2: pair.pos2,
                restAfterFirst: style.defaultRestBetween,
                restAfterSecond: style.defaultRestAfter
            )

            groups.append(group)
            usedPositions.insert(pair.pos1)
            usedPositions.insert(pair.pos2)
            groupNumber += 1
        }

        return groups.isEmpty ? nil : groups
    }

    // MARK: - v83.0: Reorder for Adjacent Pairs

    /// Reorder exercises so superset pairs are adjacent, then update group positions
    /// - Parameters:
    ///   - exerciseIds: Original exercise IDs in workout order
    ///   - groups: Superset groups with original positions
    /// - Returns: Tuple of (reordered exercise IDs, updated superset groups)
    static func reorderForAdjacentPairs(
        exerciseIds: [String],
        groups: [SupersetGroup]
    ) -> (exerciseIds: [String], groups: [SupersetGroup]) {

        guard !groups.isEmpty else {
            return (exerciseIds, groups)
        }

        var reorderedIds: [String] = []
        var newGroups: [SupersetGroup] = []
        var usedOriginalPositions: Set<Int> = []

        // First, add superset pairs in order (group 1 pair, group 2 pair, etc.)
        for group in groups.sorted(by: { $0.groupNumber < $1.groupNumber }) {
            let newStartPosition = reorderedIds.count
            var newPositions: [Int] = []

            for originalPos in group.exercisePositions {
                guard originalPos < exerciseIds.count else { continue }
                // v93.5: Skip positions already used (prevents duplicates when AI reuses positions across groups)
                guard !usedOriginalPositions.contains(originalPos) else {
                    Logger.log(.warning, component: "SupersetPairingService",
                        message: "v93.5: Skipping duplicate position \(originalPos) (already used)")
                    continue
                }
                reorderedIds.append(exerciseIds[originalPos])
                newPositions.append(reorderedIds.count - 1)
                usedOriginalPositions.insert(originalPos)
            }

            // Create updated group with new positions
            let updatedGroup = SupersetGroup(
                id: group.id,
                groupNumber: group.groupNumber,
                exercisePositions: newPositions,
                restBetweenExercises: group.restBetweenExercises
            )
            newGroups.append(updatedGroup)
        }

        // Then add unpaired exercises at the end
        for (originalPos, exerciseId) in exerciseIds.enumerated() {
            if !usedOriginalPositions.contains(originalPos) {
                reorderedIds.append(exerciseId)
            }
        }

        return (reorderedIds, newGroups)
    }
}
