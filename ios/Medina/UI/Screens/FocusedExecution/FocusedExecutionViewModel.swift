//
// FocusedExecutionViewModel.swift
// Medina
//
// v76.0: ViewModel for focused workout execution mode
// v79.3: Added protocol config and isSpecialProtocol for protocol chip
// v95.0: Added intro state for voice sequencing
// v97: Voice-synchronized intro screen (waits for GPT voice to finish)
// v101.2: Added cardio support - displayDuration/displayDistance, isCardioExercise, logCardioSet()
// Created: December 2025
// Purpose: Bridge between FocusedExecutionView and WorkoutSessionCoordinator
//

import Foundation
import Combine

/// ViewModel for focused workout execution - one exercise, one set at a time
@MainActor
class FocusedExecutionViewModel: ObservableObject {

    // MARK: - Published State

    /// v95.0: Whether showing workout intro screen (before first exercise)
    @Published private(set) var isShowingIntro: Bool = true

    /// v97: Whether voice intro has completed (signals intro screen to transition)
    @Published var isVoiceIntroComplete: Bool = false

    /// Current exercise being performed
    @Published private(set) var currentExercise: Exercise?

    /// Current exercise instance (contains set IDs)
    @Published private(set) var currentInstance: ExerciseInstance?

    /// Current set to log
    @Published private(set) var currentSet: ExerciseSet?

    /// Set number within current exercise (1-indexed)
    @Published private(set) var setNumber: Int = 1

    /// Total sets for current exercise
    @Published private(set) var totalSets: Int = 1

    /// Exercise number within workout (1-indexed)
    @Published private(set) var exerciseNumber: Int = 1

    /// Total exercises in workout
    @Published private(set) var totalExercises: Int = 1

    /// Weight to display/log (editable)
    @Published var displayWeight: Double = 0

    /// Reps to display/log (editable)
    @Published var displayReps: Int = 0

    // v101.2: Cardio properties
    /// Duration to display/log for cardio exercises (in seconds)
    @Published var displayDuration: Int = 0

    /// Distance to display/log for cardio exercises (in miles)
    @Published var displayDistance: Double = 0.0

    /// Whether currently in rest period
    @Published private(set) var isResting: Bool = false

    /// Rest timer remaining seconds
    @Published private(set) var restTimeRemaining: Int?

    /// Rest timer end date (for RestTimerCardView)
    @Published private(set) var restEndDate: Date?

    /// Total rest duration for current timer
    @Published private(set) var restTotalTime: TimeInterval = 0

    /// Whether workout is complete
    @Published private(set) var isWorkoutComplete: Bool = false

    /// Workout name for display
    @Published private(set) var workoutName: String = ""

    // MARK: - Dependencies

    private let coordinator: WorkoutSessionCoordinator
    private let workoutId: String
    private var cancellables = Set<AnyCancellable>()

    // v78.2: Track last logged values per exercise for defaults
    private var lastLoggedWeightByExercise: [String: Double] = [:]
    private var lastLoggedRepsByExercise: [String: Int] = [:]

    // MARK: - Computed Properties

    /// Primary muscles for current exercise (for muscle diagram)
    var primaryMuscles: [MuscleGroup] {
        currentExercise?.muscleGroups ?? []
    }

    /// Primary muscle (first in list) for highlighting
    var primaryMuscle: MuscleGroup? {
        currentExercise?.muscleGroups.first
    }

    /// Exercise name for display
    var exerciseName: String {
        currentExercise?.name ?? "Exercise"
    }

    /// Set progress string (e.g., "Set 2 of 4")
    var setProgressText: String {
        "Set \(setNumber) of \(totalSets)"
    }

    /// Exercise progress string (e.g., "Exercise 2 of 5")
    var exerciseProgressText: String {
        "Exercise \(exerciseNumber) of \(totalExercises)"
    }

    /// v78.0: Protocol info for display (e.g., "RPE 8 • Tempo 3-1-1")
    /// v83.3: Updated to use effective protocol config (applies customizations)
    var protocolInfoText: String? {
        guard let workout = TestDataManager.shared.workouts[workoutId],
              let instance = currentInstance,
              let config = InstanceInitializationService.effectiveProtocolConfig(for: instance, in: workout) else {
            return nil
        }

        var parts: [String] = []

        // RPE (property is `rpe`, not `targetRPE`)
        if let rpeArray = config.rpe, let rpe = rpeArray.first {
            parts.append("RPE \(Int(rpe))")
        }

        // Tempo
        if let tempo = config.tempo, tempo != "X" && tempo != "0" {
            parts.append("Tempo \(tempo)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    /// v78.0: Equipment for current exercise
    var equipmentText: String? {
        guard let exercise = currentExercise else { return nil }
        if exercise.equipment == .bodyweight { return nil }
        return exercise.equipment.displayName
    }

    // MARK: - v101.2: Cardio Properties

    /// Whether current exercise is a cardio exercise
    var isCardioExercise: Bool {
        currentExercise?.exerciseType == .cardio
    }

    /// Whether to show distance input for this cardio exercise
    /// (Treadmill, bike yes; stretching, jump rope no)
    var showDistanceInput: Bool {
        guard let exercise = currentExercise else { return false }
        // Show distance for equipment that tracks it
        let distanceEquipment: Set<Equipment> = [.treadmill, .bike, .rower, .elliptical]
        return distanceEquipment.contains(exercise.equipment) ||
               exercise.id.contains("run") || exercise.id.contains("bike") || exercise.id.contains("row")
    }

    /// v78.2: Current protocol RPE (for info sheet)
    /// v83.3: Updated to use effective protocol config (applies customizations)
    var currentProtocolRPE: Double? {
        guard let workout = TestDataManager.shared.workouts[workoutId],
              let instance = currentInstance,
              let config = InstanceInitializationService.effectiveProtocolConfig(for: instance, in: workout),
              let rpeArray = config.rpe,
              let rpe = rpeArray.first else {
            return nil
        }
        return rpe
    }

    /// v78.2: Current protocol tempo (for info sheet)
    /// v83.3: Updated to use effective protocol config (applies customizations)
    var currentProtocolTempo: String? {
        guard let workout = TestDataManager.shared.workouts[workoutId],
              let instance = currentInstance,
              let config = InstanceInitializationService.effectiveProtocolConfig(for: instance, in: workout),
              let tempo = config.tempo,
              tempo != "X" && tempo != "0" else {
            return nil
        }
        return tempo
    }

    /// v78.9: Check if current exercise has any logged sets (disables substitution)
    var hasLoggedSets: Bool {
        guard let instance = currentInstance else { return false }

        // Check if any set in this instance has actual data logged
        for setId in instance.setIds {
            if let set = TestDataManager.shared.exerciseSets[setId],
               set.actualReps != nil || set.actualWeight != nil {
                return true
            }
        }
        return false
    }

    /// v78.9: Number of logged sets for current exercise
    var loggedSetCount: Int {
        guard let instance = currentInstance else { return 0 }

        return instance.setIds.reduce(0) { count, setId in
            if let set = TestDataManager.shared.exerciseSets[setId],
               set.actualReps != nil || set.actualWeight != nil {
                return count + 1
            }
            return count
        }
    }

    /// v79.3: Current protocol config (for ProtocolInfoSheet)
    var currentProtocolConfig: ProtocolConfig? {
        guard let workout = TestDataManager.shared.workouts[workoutId],
              exerciseNumber <= workout.protocolVariantIds.count,
              let protocolId = workout.protocolVariantIds[exerciseNumber - 1] else {
            return nil
        }
        return TestDataManager.shared.protocolConfigs[protocolId]
    }

    /// v79.3: Current protocol variant name (for protocol chip display)
    var currentProtocolName: String? {
        currentProtocolConfig?.variantName
    }

    /// v79.3: Whether current protocol is a "special" protocol (Myo, Waves, Drop Sets, etc.)
    /// Special protocols show a protocol chip in the UI
    var isSpecialProtocol: Bool {
        guard let config = currentProtocolConfig,
              let family = config.protocolFamily else {
            return false
        }

        // Special protocol families that warrant a protocol chip
        let specialFamilies: Set<String> = [
            "myo_protocol",
            "waves_protocol",
            "pyramid_ascending",
            "pyramid_descending",
            "advanced_ratchet",
            "drop_set",
            "emom",
            "rest_pause",
            "calibration_protocol"
        ]

        return specialFamilies.contains(family)
    }

    // MARK: - v95.0: Intro Properties

    /// Split day for the workout (for intro screen display)
    var splitDay: SplitDay? {
        guard let workout = TestDataManager.shared.workouts[workoutId] else { return nil }
        return workout.splitDay
    }

    /// Complete intro and transition to first exercise
    func completeIntro() {
        isShowingIntro = false
        Logger.log(.info, component: "FocusedExecutionVM", message: "Intro complete, showing first exercise")
    }

    // MARK: - v83.0: Superset Properties

    /// Current superset label (e.g., "1a", "1b", "2a") from instance
    var supersetLabel: String? {
        currentInstance?.supersetLabel
    }

    /// Whether current exercise is part of a superset
    var isInSuperset: Bool {
        currentInstance?.supersetLabel != nil
    }

    /// Next exercise info in same superset (for RestTimerCard preview)
    /// Returns (label, exerciseName) or nil if not in superset
    /// Wraps around: after last exercise in group, shows first exercise (for next set)
    var nextExerciseInSuperset: (label: String, name: String)? {
        guard let workout = TestDataManager.shared.workouts[workoutId],
              let groups = workout.supersetGroups,
              let currentInstance = currentInstance,
              let _ = currentInstance.supersetLabel else {
            return nil
        }

        // Find which superset group we're in
        let currentPosition = exerciseNumber - 1  // 0-indexed
        guard let group = groups.first(where: { $0.exercisePositions.contains(currentPosition) }) else {
            return nil
        }

        // Find next position in the rotation
        guard let currentIdxInGroup = group.exercisePositions.firstIndex(of: currentPosition) else {
            return nil
        }

        // Calculate next index with wraparound
        let nextIdxInGroup = (currentIdxInGroup + 1) % group.exercisePositions.count
        let nextPosition = group.exercisePositions[nextIdxInGroup]

        guard nextPosition < workout.exerciseIds.count else { return nil }

        let nextExerciseId = workout.exerciseIds[nextPosition]
        if let nextExercise = TestDataManager.shared.exercises[nextExerciseId],
           let nextLabel = group.label(for: nextPosition) {
            return (nextLabel, nextExercise.name)
        }

        return nil
    }

    // MARK: - Initialization

    init(workoutId: String, coordinator: WorkoutSessionCoordinator) {
        self.workoutId = workoutId
        self.coordinator = coordinator

        // Get workout name
        if let workout = TestDataManager.shared.workouts[workoutId] {
            self.workoutName = workout.displayName
            self.totalExercises = workout.exerciseIds.count
        }

        // Observe coordinator state changes
        setupBindings()
    }

    // MARK: - Setup

    /// Track if workout has been started at least once (to avoid false completion on init)
    private var hasStartedWorkout = false

    private func setupBindings() {
        // Observe active session changes
        coordinator.$activeSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                self?.updateFromSession(session)
            }
            .store(in: &cancellables)

        // Observe rest timer
        coordinator.$restTimeRemaining
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in
                self?.restTimeRemaining = remaining
                self?.isResting = remaining != nil
            }
            .store(in: &cancellables)

        // Observe workout active state
        // NOTE: Only mark complete if we've actually started the workout first
        coordinator.$isWorkoutActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self = self else { return }

                if isActive {
                    // Workout started
                    self.hasStartedWorkout = true
                } else if self.hasStartedWorkout && self.coordinator.activeSession == nil {
                    // Workout ended (only if we started it)
                    self.isWorkoutComplete = true
                }
            }
            .store(in: &cancellables)
    }

    /// Update view state from session
    private func updateFromSession(_ session: Session?) {
        guard let session = session,
              let workout = TestDataManager.shared.workouts[workoutId] else {
            Logger.log(.warning, component: "FocusedExecutionVM",
                      message: "⚠️ updateFromSession: session=\(session != nil), workout=\(TestDataManager.shared.workouts[workoutId] != nil)")
            return
        }

        // Update exercise number (1-indexed)
        exerciseNumber = session.currentExerciseIndex + 1
        totalExercises = workout.exerciseIds.count

        // Check if workout is complete
        if session.currentExerciseIndex >= workout.exerciseIds.count {
            isWorkoutComplete = true
            return
        }

        // Get current exercise
        let currentExerciseId = workout.exerciseIds[session.currentExerciseIndex]
        currentExercise = TestDataManager.shared.exercises[currentExerciseId]

        // v78.0: Debug logging for exercise lookup failures
        if currentExercise == nil {
            Logger.log(.warning, component: "FocusedExecutionVM",
                      message: "⚠️ Exercise not found: '\(currentExerciseId)'. Available exercises: \(TestDataManager.shared.exercises.count)")
        }

        // Get current instance - v78.0: Use position-based ID format
        // Instance IDs are formatted as "{workoutId}_ex{position}"
        let instanceId = "\(workoutId)_ex\(session.currentExerciseIndex)"
        currentInstance = TestDataManager.shared.exerciseInstances[instanceId]

        // Fallback: Try filter-based lookup if direct lookup fails
        if currentInstance == nil {
            let instances = TestDataManager.shared.exerciseInstances.values.filter {
                $0.workoutId == workoutId && $0.exerciseId == currentExerciseId
            }
            currentInstance = instances.first

            if currentInstance == nil {
                Logger.log(.warning, component: "FocusedExecutionVM",
                          message: "⚠️ Instance not found for workout=\(workoutId), exercise=\(currentExerciseId)")
            }
        }

        // Get current set
        if let instance = currentInstance {
            totalSets = instance.setIds.count
            setNumber = session.currentSetIndex + 1

            if session.currentSetIndex < instance.setIds.count {
                let setId = instance.setIds[session.currentSetIndex]
                currentSet = TestDataManager.shared.exerciseSets[setId]

                // v78.2: Initialize display values with fallback chain:
                // 1. Target weight/reps from calibration (if available)
                // 2. Last logged values for this exercise (for uncalibrated users)
                // 3. Default (0 for weight, 8 for reps)
                // v101.2: Also initialize cardio values if it's a cardio set
                if let set = currentSet {
                    let lastWeight = lastLoggedWeightByExercise[currentExerciseId]
                    let lastReps = lastLoggedRepsByExercise[currentExerciseId]

                    displayWeight = set.targetWeight ?? lastWeight ?? 0
                    displayReps = set.targetReps ?? lastReps ?? 8

                    // v101.2: Initialize cardio values
                    displayDuration = set.targetDuration ?? 1800  // Default 30 min
                    displayDistance = set.targetDistance ?? 0.0
                }
            }
        } else {
            // v78.0: Fallback to protocol default sets if no instance
            // v78.2: Include last logged values in fallback chain
            if let protocolId = workout.protocolVariantIds[session.currentExerciseIndex],
               let config = TestDataManager.shared.protocolConfigs[protocolId] {
                totalSets = config.reps.count
                setNumber = min(session.currentSetIndex + 1, totalSets)

                let lastWeight = lastLoggedWeightByExercise[currentExerciseId]
                let lastReps = lastLoggedRepsByExercise[currentExerciseId]

                displayWeight = lastWeight ?? 0
                displayReps = lastReps ?? config.reps.first ?? 8
            }
        }

        // Update rest state
        if let restTimer = session.activeRestTimer {
            isResting = true
            restTotalTime = restTimer.originalDuration
            restEndDate = restTimer.endTime
        } else {
            isResting = false
            restEndDate = nil
        }
    }

    // MARK: - Actions

    /// Start the workout (called on view appear if not already started)
    /// v97: Uses voice-synchronized start that waits for GPT intro
    /// v208: Ensures instances/sets are lazy-loaded before starting
    func startWorkoutIfNeeded() async {
        // v208: Lazy load instances/sets if not already loaded
        // This handles navigation directly to FocusedExecution (e.g., from chat chips)
        let existingInstances = TestDataManager.shared.exerciseInstances.values.filter { $0.workoutId == workoutId }
        if existingInstances.isEmpty {
            let userId = TestDataManager.shared.currentUserId ?? "bobby"
            Logger.log(.info, component: "FocusedExecutionVM",
                      message: "v208: Lazy loading instances/sets for workout \(workoutId)")
            await LocalDataLoader.loadWorkoutDetails(workoutId: workoutId, userId: userId)
        }

        // Check if already has an active session for this workout
        if coordinator.hasActiveSession(for: workoutId) {
            coordinator.restoreSession(for: workoutId)
            // Already has session, skip intro voice
            isVoiceIntroComplete = true
        } else if !coordinator.isWorkoutActive {
            // v97: Start workout with GPT-powered voice intro
            // This awaits until voice completes, then signals intro screen
            let voiceComplete = await coordinator.startWorkoutWithVoice(workoutId: workoutId)
            isVoiceIntroComplete = voiceComplete
        }
    }

    /// Log the current set with displayed weight and reps
    func logSet() async {
        guard displayReps > 0 else { return }

        // v78.2: Store logged values for this exercise to use as defaults for next set
        if let exerciseId = currentExercise?.id {
            lastLoggedWeightByExercise[exerciseId] = displayWeight
            lastLoggedRepsByExercise[exerciseId] = displayReps
        }

        await coordinator.logSet(weight: displayWeight, reps: displayReps)
    }

    /// v101.2: Log the current cardio set with duration and optional distance
    func logCardioSet() async {
        guard displayDuration > 0 else { return }

        await coordinator.logCardioSet(
            durationSeconds: displayDuration,
            distance: showDistanceInput ? displayDistance : nil
        )
    }

    /// Skip the current exercise
    func skipExercise() async {
        await coordinator.skipCurrentExercise()
    }

    /// Adjust weight by increment
    func adjustWeight(by amount: Double) {
        displayWeight = max(0, displayWeight + amount)
    }

    /// Adjust reps by increment
    func adjustReps(by amount: Int) {
        displayReps = max(1, displayReps + amount)
    }

    /// Skip rest timer
    /// v98: Manual skip announces next set target for screen-free use
    func skipRest() {
        coordinator.skipRest(announceNext: true)
    }

    /// Adjust rest timer
    func adjustRest(by seconds: Int) {
        coordinator.adjustRestTimer(by: seconds)
    }

    /// Complete workout early
    func completeWorkoutEarly() {
        coordinator.completeWorkout()
    }

    /// v78.8: Substitute the current exercise with a different one
    func substituteExercise(newExerciseId: String) {
        guard let instance = currentInstance else {
            Logger.log(.warning, component: "FocusedExecutionVM",
                      message: "Cannot substitute: no current instance")
            return
        }

        let userId = TestDataManager.shared.currentUserId ?? "bobby"

        do {
            try ExerciseSubstitutionService.performSubstitution(
                instanceId: instance.id,
                newExerciseId: newExerciseId,
                workoutId: workoutId,
                userId: userId
            )

            // Reload coordinator's workout reference to pick up the new exercise
            coordinator.reloadWorkout()

            Logger.log(.info, component: "FocusedExecutionVM",
                      message: "Substituted exercise in instance \(instance.id) with \(newExerciseId)")
        } catch {
            Logger.log(.error, component: "FocusedExecutionVM",
                      message: "Substitution failed: \(error)")
        }
    }

    /// v78.8: Reload workout data (for substitution updates)
    func reloadWorkout() {
        coordinator.reloadWorkout()
    }
}
