//
// WorkoutSessionCoordinator.swift
// Medina
//
// v52.1 - In-place workout execution coordinator
// v53.0 Phase 2 - Inlined session business logic (no handler dependencies)
// v55.0 - Comprehensive superset skip logic with helper functions
// v69.0 - Auto-cascade to next program when current program is completed
// v95.1 - Template-based voice for fast, confirmatory announcements
// v98 - Screen-free voice: set targets, rest countdown, superset rotation
// v163 - Removed statusText (in-place execution UI removed, FocusedExecution only)
// Last reviewed: December 2025
//
// Purpose: Observable wrapper for workout session execution on WorkoutDetailView
// Touch-first architecture - no MessageCard dependencies
//
// v56.0: Refactored to use SessionProgressionService
// - Slim coordinator (~250 lines): UI, orchestration, voice
// - Service (~580 lines): All business logic (progression, skip, reset)
// - Direct delegation pattern (no test infrastructure needed yet)
//
// v95.1: Voice Overhaul
// - Template-based for most triggers (fast, no GPT latency)
// - Hybrid: GPT for workout intro/complete (personality), templates for rest
// - Verbosity level (1-5) controls announcement detail
// - Confirmatory: Echo back what was logged + preview next set
//
// v97: Voice UX Overhaul
// - GPT-powered intro/outro with training style personas
// - Voice-synchronized intro screen (waits for voice completion)
// - Exercise transition announcements when advancing exercises
//

import Foundation
import Combine

/// Coordinates workout session execution with observable state for UI binding
/// v56.0: Delegates business logic to SessionProgressionService
@MainActor
class WorkoutSessionCoordinator: ObservableObject {

    // MARK: - Published State

    /// Current active session (nil if no workout active)
    @Published private(set) var activeSession: Session?

    /// Current workout being executed
    @Published private(set) var workout: Workout?

    // v163: Removed statusText - in-place execution UI removed, FocusedExecution is only mode

    /// Rest timer countdown (seconds remaining, nil if no active rest)
    @Published private(set) var restTimeRemaining: Int?

    /// Whether workout has started (determines button visibility)
    @Published var isWorkoutActive: Bool = false

    // MARK: - Dependencies

    private let memberId: String
    private let voiceService: VoiceService?
    private let announcementService: VoiceAnnouncementService  // v86.0: AI-generated announcements
    private var restTimerTask: Task<Void, Never>?
    private let progressionService: SessionProgressionService

    // MARK: - Initialization

    init(memberId: String, voiceService: VoiceService? = nil) {
        self.memberId = memberId
        self.voiceService = voiceService
        self.announcementService = VoiceAnnouncementService()  // v86.0
        self.progressionService = SessionProgressionService()

        // v57.6: Don't auto-restore sessions in init - let WorkoutDetailView explicitly call restoreSession(for:)
        // This prevents restoring wrong workout's session when viewing a different workout
    }

    deinit {
        restTimerTask?.cancel()
    }

    // MARK: - Session Management

    /// Check if there's an active session and restore state
    func checkForActiveSession() {
        if let session = TestDataManager.shared.activeSession(for: memberId),
           let workout = TestDataManager.shared.workouts[session.workoutId] {
            self.activeSession = session
            self.workout = workout
            self.isWorkoutActive = true

            // Resume rest timer if active
            if let restTimer = session.activeRestTimer {
                startRestTimerCountdown(duration: restTimer.remainingTime)
            }
        }
    }

    /// Check if a specific workout has an active session
    func hasActiveSession(for workoutId: String) -> Bool {
        if let session = TestDataManager.shared.activeSession(for: memberId) {
            return session.workoutId == workoutId
        }
        return false
    }

    /// Restore active session for a specific workout
    /// v57.7: Made synchronous to prevent race conditions in view rendering
    func restoreSession(for workoutId: String) {
        if let session = TestDataManager.shared.activeSession(for: memberId),
           session.workoutId == workoutId,
           let workout = TestDataManager.shared.workouts[session.workoutId] {
            self.activeSession = session
            self.workout = workout
            self.isWorkoutActive = true

            // Resume rest timer if active
            if let restTimer = session.activeRestTimer {
                startRestTimerCountdown(duration: restTimer.remainingTime)
            }

            Logger.log(.info, component: "WorkoutSessionCoordinator",
                       message: "Restored active session for workout: \(workoutId)")
        }
    }

    /// v61.1: Reload workout data from TestDataManager after exercise substitution
    /// This updates the stored workout reference to reflect changes made directly to TestDataManager
    func reloadWorkout() {
        guard let currentWorkout = workout else { return }

        if let updatedWorkout = TestDataManager.shared.workouts[currentWorkout.id] {
            self.workout = updatedWorkout

            Logger.log(.info, component: "WorkoutSessionCoordinator",
                       message: "Reloaded workout data for: \(currentWorkout.id)")
        }
    }

    /// Start a new workout session (v53.0: Inlined from SessionStartHandler)
    /// v55.0: Guided-only mode (removed mode parameter)
    /// v68.0: Added explicit single-workout enforcement
    func startWorkout(workoutId: String) async {
        guard let workout = TestDataManager.shared.workouts[workoutId] else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot start workout: Workout not found")
            return
        }

        // v68.0: Explicit single-workout enforcement
        // Prevent starting a second workout while one is already active
        if let existingSession = TestDataManager.shared.activeSession(for: memberId) {
            Logger.log(.warning, component: "WorkoutSessionCoordinator",
                       message: "Cannot start workout '\(workout.displayName)': Active session already exists for workout '\(existingSession.workoutId)'")
            return
        }

        // v55.0: Create new session (guided-only, no executionMode)
        let session = Session(
            id: UUID().uuidString,
            workoutId: workoutId,
            memberId: memberId,
            startTime: Date(),
            endTime: nil,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            status: .active,
            pausedAt: nil,
            totalPauseTime: 0,
            activeRestTimer: nil,
            currentSupersetCycleSet: nil
        )

        // Save session
        TestDataManager.shared.sessions[session.id] = session

        // v96.1: Update workout status to inProgress
        // This makes the sidebar dot turn blue (active) instead of grey (scheduled)
        let workoutDelta = DeltaStore.WorkoutDelta(
            workoutId: workout.id,
            scheduledDate: nil,
            completion: .inProgress
        )
        DeltaStore.shared.saveWorkoutDelta(workoutDelta)

        var updatedWorkout = workout
        updatedWorkout.status = .inProgress
        TestDataManager.shared.workouts[workout.id] = updatedWorkout

        // Update state
        self.activeSession = session
        self.workout = updatedWorkout
        self.isWorkoutActive = true

        // v97: Voice announcement is now handled by startWorkoutWithVoice()
        // for synchronized screen transitions

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "Started workout in guided mode: \(workout.displayName)")
    }

    /// v97: Start workout with GPT-powered intro and return completion signal
    /// - Parameter workoutId: Workout to start
    /// - Returns: True when voice intro has completed (or skipped if voice disabled)
    func startWorkoutWithVoice(workoutId: String) async -> Bool {
        // Start the workout (sets up session, updates state)
        await startWorkout(workoutId: workoutId)

        // Get workout reference after startWorkout() updates it
        guard let workout = self.workout else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "startWorkoutWithVoice: No workout after start")
            return true
        }

        // If voice is disabled, return immediately
        guard isVoiceEnabled() else {
            return true
        }

        // Get user for training style
        guard let user = TestDataManager.shared.users[memberId] else {
            // Fall back to template if no user
            if let voiceService = voiceService {
                let intro = VoiceTemplateService.workoutIntro(
                    workoutName: workout.displayName,
                    exerciseCount: workout.exerciseIds.count
                )
                try? await voiceService.speak(intro, userId: memberId)
            }
            return true
        }

        // v182: Removed trainingStyle - using default Medina personality
        let voiceGender = user.memberProfile?.voiceSettings?.voiceGender ?? .female
        let voiceSettings = user.memberProfile?.voiceSettings ?? .default

        // v97: Build context for GPT-powered intro
        let context = VoiceAnnouncementService.WorkoutVoiceContext(
            voiceSettings: voiceSettings,
            workoutName: workout.displayName,
            splitDay: workout.splitDay,
            totalExercises: workout.exerciseIds.count,
            currentExerciseNumber: nil,
            exerciseName: nil,
            setNumber: nil,
            totalSets: nil,
            targetWeight: nil,
            actualWeight: nil,
            targetReps: nil,
            actualReps: nil,
            targetRPE: nil,
            actualRPE: nil,
            oneRMPercentage: nil,
            volumeProgress: nil,
            tempo: nil,
            restDuration: nil,
            workoutDuration: nil
        )

        // Use VoiceSequencer for GPT-powered intro
        let success = await VoiceSequencer.shared.announceAndWait(
            trigger: .workoutStart,
            context: context,
            userId: memberId,
            voiceGender: voiceGender
        )

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "v97: GPT intro completed, success=\(success)")

        return success
    }

    /// Log a set with weight and reps (v53.0: Inlined from InstanceUpdateHandler)
    /// v55.0: Guided-only mode (removed setId parameter)
    /// - Parameters:
    ///   - weight: Weight lifted (must be >= 0, where 0 indicates bodyweight)
    ///   - reps: Reps completed (must be > 0)
    func logSet(weight: Double, reps: Int) async {
        // Validate weight (allow 0 for bodyweight exercises)
        guard weight >= 0 else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot log set: Weight must be 0 or greater (got \(weight))")
            return
        }

        // Validate reps
        guard reps > 0 else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot log set: Reps must be greater than 0 (got \(reps))")
            return
        }

        guard let session = activeSession else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot log set: No active session")
            return
        }

        guard let workout = workout else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot log set: No workout")
            return
        }

        // v56.0: Use service for progression logic
        guard let (set, instance) = progressionService.getCurrentSet(session: session, workout: workout) else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot find current set/instance")
            return
        }

        // Capture indices BEFORE advancing (for setJustCompleted tracking)
        let currentSetIndex = session.currentSetIndex
        let isLastSet = currentSetIndex == instance.setIds.count - 1

        // Save set delta AND update in-memory state (critical for skip logic)
        let setDelta = DeltaStore.SetDelta(
            setId: set.id,
            actualWeight: weight,
            actualReps: reps,
            completion: .completed
        )
        DeltaStore.shared.saveSetDelta(setDelta)

        // Update in-memory set immediately (needed for findNextPendingExercise to work correctly)
        var updatedSet = set
        updatedSet.actualWeight = weight
        updatedSet.actualReps = reps
        updatedSet.completion = .completed
        TestDataManager.shared.exerciseSets[set.id] = updatedSet

        // v202: Sync set to Firestore in real-time (fire-and-forget)
        let setToSync = updatedSet
        let workoutIdForSync = workout.id
        let memberIdForSync = memberId
        Task {
            do {
                try await FirestoreWorkoutRepository.shared.saveSet(
                    setToSync,
                    workoutId: workoutIdForSync,
                    memberId: memberIdForSync
                )
                Logger.log(.debug, component: "WorkoutSync",
                    message: "Synced set \(setToSync.id) to Firestore")
            } catch {
                Logger.log(.error, component: "WorkoutSync",
                    message: "Failed to sync set \(setToSync.id): \(error)")
            }
        }

        // Advance session using service
        let (updatedSession, restDuration, setJustCompleted) = progressionService.advanceSession(
            session: session,
            workout: workout,
            currentInstance: instance,
            setJustCompleted: currentSetIndex,
            didCompleteExercise: isLastSet
        )

        // Update session and rest timer
        updateSession(updatedSession)
        if let duration = restDuration {
            var sessionWithRest = updatedSession
            sessionWithRest.activeRestTimer = RestTimer(
                startTime: Date(),
                duration: duration,
                setJustCompleted: setJustCompleted
            )
            updateSession(sessionWithRest)
            startRestTimerCountdown(duration: duration)
        }

        // Check if workout is complete (use updated session)
        if updatedSession.currentExerciseIndex >= workout.exerciseIds.count {
            completeWorkout()
        }

        // v95.1: Template-based confirmatory voice (fast, no GPT latency)
        // v97: Added exercise transition announcements
        // v98: Added superset rotation announcements
        if let voiceService = voiceService, isVoiceEnabled() {
            let nextSetInfo = progressionService.getNextSetWithTargets(session: updatedSession, workout: workout)
            let restDur = restDuration  // Capture for task
            let verbosity = getUserVerbosity()
            let previousExerciseIndex = session.currentExerciseIndex
            let nextExerciseIndex = updatedSession.currentExerciseIndex
            let exerciseChanged = nextExerciseIndex != previousExerciseIndex

            // v98: Detect superset rotation vs full exercise transition
            // Superset rotation: exercise changed but we're staying in same superset group
            let didRotateInSuperset: Bool = {
                guard exerciseChanged,
                      let groups = workout.supersetGroups else {
                    return false
                }
                // Check if both exercises are in the same superset group
                let previousInGroup = groups.first { $0.exercisePositions.contains(previousExerciseIndex) }
                let nextInGroup = groups.first { $0.exercisePositions.contains(nextExerciseIndex) }
                return previousInGroup != nil && previousInGroup?.id == nextInGroup?.id
            }()

            // Full exercise transition = moved to new exercise not in same superset
            let didAdvanceExercise = exerciseChanged && !didRotateInSuperset && nextExerciseIndex < workout.exerciseIds.count

            Task {
                // Use template for instant confirmation (no GPT delay)
                let loggedAnnouncement = VoiceTemplateService.setLogged(
                    actualReps: reps,
                    actualWeight: weight,
                    restDuration: restDur != nil ? Int(restDur!) : nil,
                    nextSetNumber: nextSetInfo?.setNumber,
                    nextTargetReps: nextSetInfo?.reps,
                    nextTargetWeight: nextSetInfo?.weight,
                    verbosity: verbosity
                )
                try? await voiceService.speak(loggedAnnouncement, userId: self.memberId)

                // v98: Announce superset rotation (different exercise in same group)
                if didRotateInSuperset {
                    let nextExerciseId = workout.exerciseIds[nextExerciseIndex]
                    if let nextExercise = TestDataManager.shared.exercises[nextExerciseId] {
                        let rotationAnnouncement = VoiceTemplateService.supersetRotation(
                            exerciseName: nextExercise.name,
                            setNumber: updatedSession.currentSetIndex + 1,
                            verbosity: verbosity
                        )

                        // Brief pause before rotation announcement
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        try? await voiceService.speak(rotationAnnouncement, userId: self.memberId)

                        Logger.log(.info, component: "WorkoutSessionCoordinator",
                                   message: "v98: Announced superset rotation to \(nextExercise.name)")
                    }
                }

                // v97: Announce next exercise if we advanced to a new one (not in same superset)
                if didAdvanceExercise {
                    let nextExerciseId = workout.exerciseIds[nextExerciseIndex]
                    if let nextExercise = TestDataManager.shared.exercises[nextExerciseId] {
                        // Get set count for next exercise
                        let instanceId = "\(workout.id)_ex\(nextExerciseIndex)"
                        let setCount = TestDataManager.shared.exerciseInstances[instanceId]?.setIds.count ?? 3

                        let transitionAnnouncement = VoiceTemplateService.exerciseTransition(
                            exerciseName: nextExercise.name,
                            setCount: setCount,
                            verbosity: verbosity
                        )

                        // Brief pause before transition announcement
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        try? await voiceService.speak(transitionAnnouncement, userId: self.memberId)

                        Logger.log(.info, component: "WorkoutSessionCoordinator",
                                   message: "v97: Announced exercise transition to \(nextExercise.name)")
                    }
                }
            }
        }

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "Logged set (guided mode): \(Int(weight)) lbs × \(reps) reps | Session state: exerciseIndex=\(updatedSession.currentExerciseIndex), setIndex=\(updatedSession.currentSetIndex), instance has \(instance.setIds.count) sets, restTimer=\(updatedSession.activeRestTimer != nil ? "active" : "none")")
    }

    /// v101.2: Log a cardio set with duration and optional distance
    /// - Parameters:
    ///   - durationSeconds: Duration performed in seconds
    ///   - distance: Distance covered in miles (optional)
    func logCardioSet(durationSeconds: Int, distance: Double?) async {
        // Validate duration
        guard durationSeconds > 0 else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot log cardio set: Duration must be greater than 0 (got \(durationSeconds))")
            return
        }

        guard let session = activeSession else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot log cardio set: No active session")
            return
        }

        guard let workout = workout else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot log cardio set: No workout")
            return
        }

        // Get current set/instance
        guard let (set, instance) = progressionService.getCurrentSet(session: session, workout: workout) else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "Cannot find current set/instance for cardio")
            return
        }

        // Capture indices BEFORE advancing
        let currentSetIndex = session.currentSetIndex
        let isLastSet = currentSetIndex == instance.setIds.count - 1

        // Save cardio set delta with duration/distance
        let setDelta = DeltaStore.SetDelta(
            setId: set.id,
            completion: .completed,
            actualDuration: durationSeconds,
            actualDistance: distance
        )
        DeltaStore.shared.saveSetDelta(setDelta)

        // Update in-memory set immediately
        var updatedSet = set
        updatedSet.actualDuration = durationSeconds
        updatedSet.actualDistance = distance
        updatedSet.completion = .completed
        TestDataManager.shared.exerciseSets[set.id] = updatedSet

        // v202: Sync cardio set to Firestore in real-time (fire-and-forget)
        let setToSync = updatedSet
        let workoutIdForSync = workout.id
        let memberIdForSync = memberId
        Task {
            do {
                try await FirestoreWorkoutRepository.shared.saveSet(
                    setToSync,
                    workoutId: workoutIdForSync,
                    memberId: memberIdForSync
                )
                Logger.log(.debug, component: "WorkoutSync",
                    message: "Synced cardio set \(setToSync.id) to Firestore")
            } catch {
                Logger.log(.error, component: "WorkoutSync",
                    message: "Failed to sync cardio set \(setToSync.id): \(error)")
            }
        }

        // Advance session (cardio typically has just 1 "set" per exercise)
        let (updatedSession, restDuration, setJustCompleted) = progressionService.advanceSession(
            session: session,
            workout: workout,
            currentInstance: instance,
            setJustCompleted: currentSetIndex,
            didCompleteExercise: isLastSet
        )

        // Update session and rest timer
        updateSession(updatedSession)
        if let duration = restDuration {
            var sessionWithRest = updatedSession
            sessionWithRest.activeRestTimer = RestTimer(
                startTime: Date(),
                duration: duration,
                setJustCompleted: setJustCompleted
            )
            updateSession(sessionWithRest)
            startRestTimerCountdown(duration: duration)
        }

        // Check if workout is complete
        if updatedSession.currentExerciseIndex >= workout.exerciseIds.count {
            completeWorkout()
        }

        // Format duration for logging
        let mins = durationSeconds / 60
        let secs = durationSeconds % 60
        let distanceStr = distance.map { String(format: "%.1f mi", $0) } ?? "no distance"
        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "v101.2: Logged cardio set: \(mins):\(String(format: "%02d", secs)) • \(distanceStr)")
    }

    /// v52.4.2: Adjust rest timer by adding/subtracting seconds
    /// v82.6: Fixed - now updates session.activeRestTimer.endTime for UI sync
    func adjustRestTimer(by seconds: Int) {
        guard var session = activeSession,
              var restTimer = session.activeRestTimer else {
            return
        }

        // Calculate new end time (minimum: now)
        let adjustment = TimeInterval(seconds)
        let newEndTime = max(Date(), restTimer.endTime.addingTimeInterval(adjustment))
        restTimer.endTime = newEndTime

        // Update session with new rest timer
        session.activeRestTimer = restTimer
        TestDataManager.shared.sessions[session.id] = session
        self.activeSession = session

        // Update local countdown state
        let remaining = max(0, Int(newEndTime.timeIntervalSinceNow))
        restTimeRemaining = remaining

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "v82.6: Adjusted rest timer by \(seconds)s → endTime=\(newEndTime), remaining=\(remaining)s")
    }

    /// Skip current rest timer
    /// v98: Added parameter to control whether to announce next set (avoid double-announce)
    /// - Parameter announceNext: If true, announces next set target after clearing rest
    func skipRest(announceNext: Bool = false) {
        guard let session = activeSession,
              session.activeRestTimer != nil else {
            return
        }

        // Clear rest timer
        var updatedSession = session
        updatedSession.activeRestTimer = nil
        TestDataManager.shared.sessions[session.id] = updatedSession

        self.activeSession = updatedSession
        self.restTimeRemaining = nil
        restTimerTask?.cancel()

        // v98: Announce next set target if requested (manual skip)
        if announceNext {
            announceNextSetTarget()
        }

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "Skipped rest timer | Session state: exerciseIndex=\(updatedSession.currentExerciseIndex), setIndex=\(updatedSession.currentSetIndex), restTimeRemaining=\(self.restTimeRemaining?.description ?? "nil")")
    }

    // MARK: - Skip Functionality (v56.0)

    /// Skip the current exercise (all remaining sets) and advance to the next exercise
    /// v56.0: Delegates to service
    func skipCurrentExercise() async {
        guard let session = activeSession else {
            Logger.log(.warning, component: "WorkoutSessionCoordinator", message: "No active session to skip exercise")
            return
        }
        guard let workout = workout else {
            Logger.log(.warning, component: "WorkoutSessionCoordinator", message: "No workout found for skip")
            return
        }

        // Use service to skip exercise
        guard let result = progressionService.skipExercise(session: session, workout: workout) else {
            return
        }

        // Update session and rest timer
        updateSession(result.session)
        if let duration = result.restDuration {
            var sessionWithRest = result.session
            sessionWithRest.activeRestTimer = RestTimer(
                startTime: Date(),
                duration: duration,
                setJustCompleted: result.setJustCompletedIndex
            )
            updateSession(sessionWithRest)
            startRestTimerCountdown(duration: duration)
        }

        // v57.0: Check if workout is complete after skipping
        if result.session.currentExerciseIndex >= workout.exerciseIds.count {
            completeWorkout()
        }

        // Voice announcement
        speakIfEnabled("Skipped \(result.exerciseName)")
    }

    /// Reset workout - clear all data, delete session
    /// v56.0: Delegates to service
    func resetWorkout(workoutId: String) async {
        // Use service to reset workout
        let deletedSessionId = progressionService.resetWorkout(
            workoutId: workoutId,
            activeSessionId: activeSession?.id
        )

        // Clear coordinator state if this was our active session
        if let deletedId = deletedSessionId, activeSession?.id == deletedId {
            self.activeSession = nil
            self.isWorkoutActive = false
            self.restTimeRemaining = nil
            restTimerTask?.cancel()
        }
    }

    /// Reset exercise - clear data, back to Set 1 if active
    /// v56.0: Delegates to service
    func resetExercise(instanceId: String) async {
        guard let instance = TestDataManager.shared.exerciseInstances[instanceId] else { return }

        // Use service to reset exercise
        _ = progressionService.resetExercise(instanceId: instanceId)

        // Reset to Set 1 if this is active exercise
        if let session = activeSession,
           let workout = workout,
           workout.exerciseIds[session.currentExerciseIndex] == instance.exerciseId {
            var updatedSession = session
            updatedSession.currentSetIndex = 0
            updateSession(updatedSession)
        }
    }

    /// Unskip a previously skipped set
    /// v56.0: Delegates to service
    func unskipSet(setId: String) async {
        // Use service to unskip set
        guard progressionService.unskipSet(setId: setId) else {
            return
        }

        // Voice announcement
        speakIfEnabled("Set restored")
    }

    /// Complete the workout
    /// v52.3: Made public for manual completion in simple mode
    /// v79.4: Added auto-calibration of 1RM from workout performance
    /// v165: Mark as skipped (not completed) if all sets were skipped
    func completeWorkout() {
        guard let session = activeSession,
              let workout = workout else {
            return
        }

        // v165: Check if ANY set was actually completed (not all skipped)
        // If all sets are skipped/unlogged, mark workout as skipped instead of completed
        let allWorkoutSets = workout.exerciseIds.enumerated().flatMap { (index, _) -> [ExerciseSet] in
            let instanceId = "\(workout.id)_ex\(index)"
            guard let instance = TestDataManager.shared.exerciseInstances[instanceId] else { return [] }
            return instance.setIds.compactMap { TestDataManager.shared.exerciseSets[$0] }
        }
        let hasAnyCompletedSet = allWorkoutSets.contains { $0.completion == .completed }
        let finalStatus: ExecutionStatus = hasAnyCompletedSet ? .completed : .skipped

        // v79.4: Auto-calibrate 1RM from workout performance (only if completed)
        // Progressive overload: only updates if new estimate > existing
        if finalStatus == .completed {
            WorkoutCalibrationService.calibrateFromWorkout(workoutId: workout.id, memberId: memberId)
        }

        // Mark workout with appropriate status
        let workoutDelta = DeltaStore.WorkoutDelta(
            workoutId: workout.id,
            scheduledDate: nil,
            completion: finalStatus
        )
        DeltaStore.shared.saveWorkoutDelta(workoutDelta)

        // v54.7: Update in-memory state immediately (triggers reactive UI updates)
        var updatedWorkout = workout
        updatedWorkout.status = finalStatus == .completed ? .completed : .skipped
        updatedWorkout.completedDate = finalStatus == .completed ? Date() : nil
        TestDataManager.shared.workouts[workout.id] = updatedWorkout

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "v165: Workout final status: \(finalStatus.rawValue) (hasAnyCompletedSet=\(hasAnyCompletedSet))")

        // v52.3: Mark instances completed/skipped based on execution mode
        // Process ALL instances (not just remaining) to handle both modes correctly
        for (exerciseIndex, exerciseId) in workout.exerciseIds.enumerated() {
            if let instance = TestDataManager.shared.exerciseInstances.values.first(where: {
                $0.workoutId == workout.id && $0.exerciseId == exerciseId
            }) {
                // v57.0: Check actual set completion status, not just progression
                let instanceStatus: ExecutionStatus
                if exerciseIndex < session.currentExerciseIndex {
                    // Progressed past this exercise - check if ANY set was completed
                    let allSets = TestDataManager.shared.exerciseSets.values.filter {
                        $0.exerciseInstanceId == instance.id
                    }
                    let hasCompletedSet = allSets.contains { $0.completion == .completed }
                    instanceStatus = hasCompletedSet ? .completed : .skipped
                } else {
                    // Haven't reached this exercise yet
                    instanceStatus = .skipped
                }

                // Save instance delta
                let instanceDelta = DeltaStore.InstanceDelta(
                    instanceId: instance.id,
                    completion: instanceStatus
                )
                DeltaStore.shared.saveInstanceDelta(instanceDelta)

                // Mark unlogged sets as skipped (leave completed sets alone)
                for setId in instance.setIds {
                    if let set = TestDataManager.shared.exerciseSets[setId],
                       set.actualWeight == nil && set.actualReps == nil {
                        let setDelta = DeltaStore.SetDelta(
                            setId: setId,
                            completion: .skipped
                        )
                        DeltaStore.shared.saveSetDelta(setDelta)
                    }
                }

                // v82.3: Record exercise usage for AI learning
                let allSetsForUsage = TestDataManager.shared.exerciseSets.values.filter {
                    $0.exerciseInstanceId == instance.id
                }
                let completedSetsCount = allSetsForUsage.filter { $0.completion == .completed }.count
                let totalSetsCount = allSetsForUsage.count

                var prefs = TestDataManager.shared.userExercisePreferences(for: memberId)
                prefs.recordUsage(
                    exerciseId: exerciseId,
                    completedSets: completedSetsCount,
                    totalSets: totalSetsCount
                )
                TestDataManager.shared.exercisePreferences[memberId] = prefs
            }
        }

        // v82.3: Exercise preferences recorded in-memory
        // v206: Removed legacy disk persistence - preferences synced via profile
        Logger.log(.info, component: "WorkoutSessionCoordinator",
                  message: "v82.3: Recorded exercise usage for \(workout.exerciseIds.count) exercises")

        // End session
        var updatedSession = session
        updatedSession.status = .completed
        updatedSession.endTime = Date()
        TestDataManager.shared.sessions[session.id] = updatedSession

        // v206: Sync completed workout to Firestore
        if let program = TestDataManager.shared.programs[updatedWorkout.programId],
           let plan = TestDataManager.shared.plans[program.planId] {

            // Sync to Firestore (fire-and-forget)
            let completedWorkout = updatedWorkout
            Task {
                do {
                    let instances = TestDataManager.shared.exerciseInstances.values.filter { $0.workoutId == completedWorkout.id }
                    let instanceIds = Set(instances.map { $0.id })
                    let sets = TestDataManager.shared.exerciseSets.values.filter { instanceIds.contains($0.exerciseInstanceId) }

                    try await FirestoreWorkoutRepository.shared.saveFullWorkout(
                        workout: completedWorkout,
                        instances: Array(instances),
                        sets: Array(sets),
                        memberId: plan.memberId
                    )
                    Logger.log(.info, component: "WorkoutSessionCoordinator",
                              message: "☁️ Synced completed workout to Firestore")
                } catch {
                    Logger.log(.warning, component: "WorkoutSessionCoordinator",
                              message: "⚠️ Firestore sync failed: \(error)")
                }
            }

            // v69.0: Check for program completion and auto-cascade to next program
            checkProgramCompletionAndCascade(program: program, plan: plan)
        } else {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                      message: "Could not find program/plan for workout \(updatedWorkout.id)")
        }

        // Update state
        self.activeSession = nil
        self.isWorkoutActive = false
        self.restTimeRemaining = nil
        restTimerTask?.cancel()

        // v97: GPT-powered workout outro with personality
        // v165: Only play celebratory outro if workout was actually completed (not skipped)
        if isVoiceEnabled() && finalStatus == .completed {
            let durationMinutes = Int(Date().timeIntervalSince(session.startTime) / 60)
            let workoutName = workout.displayName

            Task {
                // Get user for voice settings
                // v182: Removed trainingStyle - using default Medina personality
                if let user = TestDataManager.shared.users[memberId] {
                    let voiceGender = user.memberProfile?.voiceSettings?.voiceGender ?? .female
                    let voiceSettings = user.memberProfile?.voiceSettings ?? .default

                    // Build context for GPT-powered outro
                    let context = VoiceAnnouncementService.WorkoutVoiceContext(
                        voiceSettings: voiceSettings,
                        workoutName: workoutName,
                        splitDay: workout.splitDay,
                        totalExercises: workout.exerciseIds.count,
                        currentExerciseNumber: nil,
                        exerciseName: nil,
                        setNumber: nil,
                        totalSets: nil,
                        targetWeight: nil,
                        actualWeight: nil,
                        targetReps: nil,
                        actualReps: nil,
                        targetRPE: nil,
                        actualRPE: nil,
                        oneRMPercentage: nil,
                        volumeProgress: nil,
                        tempo: nil,
                        restDuration: nil,
                        workoutDuration: TimeInterval(durationMinutes * 60)
                    )

                    // Use VoiceSequencer for GPT-powered, celebratory outro
                    let _ = await VoiceSequencer.shared.announceAndWait(
                        trigger: .workoutComplete,
                        context: context,
                        userId: memberId,
                        voiceGender: voiceGender
                    )

                    Logger.log(.info, component: "WorkoutSessionCoordinator",
                               message: "v97: GPT outro completed for \(workoutName)")
                } else {
                    // Fallback to template if no user
                    if let voiceService = voiceService {
                        let complete = VoiceTemplateService.workoutComplete(duration: durationMinutes)
                        try? await voiceService.speak(complete, userId: self.memberId)
                    }
                }
            }
        }

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "Workout \(finalStatus.rawValue) in guided mode: \(workout.displayName)")
    }

    // MARK: - Helper Methods

    // v163: Removed updateStatusText() and getCurrentExerciseInfo() - in-place execution UI removed

    /// Start rest timer countdown with UI updates
    /// v98: Added countdown warnings at 10, 5, 3, 2, 1 seconds
    private func startRestTimerCountdown(duration: TimeInterval) {
        restTimerTask?.cancel()

        restTimeRemaining = Int(duration)

        restTimerTask = Task { @MainActor in
            while let remaining = restTimeRemaining, remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                guard !Task.isCancelled else { break }

                restTimeRemaining = remaining - 1

                // v98: Countdown warnings at milestones
                if isVoiceEnabled(), let voiceService = voiceService {
                    let warningTimes = [10, 5, 3, 2, 1]
                    if let newRemaining = restTimeRemaining, warningTimes.contains(newRemaining) {
                        let warning = VoiceTemplateService.restWarning(secondsRemaining: newRemaining)
                        Task {
                            try? await voiceService.speak(warning, userId: self.memberId)
                        }
                    }
                }
            }

            // Rest complete - announce next set target
            if !Task.isCancelled {
                restTimeRemaining = nil
                skipRest() // Auto-clear rest timer
                announceNextSetTarget()  // v98: Tell user what's next
            }
        }
    }

    // MARK: - Helper Methods (v56.0)

    /// Persist updated session to TestDataManager and update activeSession
    /// - Parameter session: Session to persist
    private func updateSession(_ session: Session) {
        TestDataManager.shared.sessions[session.id] = session
        activeSession = session
    }

    /// Speak a voice message if voice service is enabled
    /// v56.0: Centralized voice helper
    private func speakIfEnabled(_ message: String) {
        guard let voiceService = voiceService else { return }
        Task {
            try? await voiceService.speak(message, userId: self.memberId)
        }
    }

    /// v95.1: Get user's verbosity level for template-based announcements
    private func getUserVerbosity() -> Int {
        guard let user = TestDataManager.shared.users[memberId],
              let profile = user.memberProfile else {
            return 3 // Default moderate verbosity
        }
        return profile.voiceSettings?.verbosityLevel ?? 3
    }

    /// v95.1: Check if voice is enabled for this user
    private func isVoiceEnabled() -> Bool {
        guard let user = TestDataManager.shared.users[memberId],
              let profile = user.memberProfile else {
            return true // Default to enabled
        }
        return profile.voiceSettings?.isEnabled ?? true
    }

    // MARK: - v98: Screen-Free Voice Helpers

    /// v98: Announce next set target (weight to rack, reps to hit)
    /// Called after rest completes (natural or skipped) to prepare user for next set
    private func announceNextSetTarget() {
        guard let session = activeSession,
              let workout = workout,
              let voiceService = voiceService,
              isVoiceEnabled() else { return }

        // Get current set info from progression service
        guard let (set, instance) = progressionService.getCurrentSet(session: session, workout: workout) else {
            Logger.log(.warning, component: "WorkoutSessionCoordinator",
                       message: "v98: Cannot announce set target - no current set")
            return
        }

        // Get exercise name
        let exerciseId = workout.exerciseIds[session.currentExerciseIndex]
        let exercise = TestDataManager.shared.exercises[exerciseId]

        let announcement = VoiceTemplateService.setTarget(
            setNumber: session.currentSetIndex + 1,
            totalSets: instance.setIds.count,
            targetReps: set.targetReps ?? 8,
            targetWeight: set.targetWeight ?? 0,
            exerciseName: exercise?.name,
            verbosity: getUserVerbosity()
        )

        Task {
            try? await voiceService.speak(announcement, userId: memberId)
            Logger.log(.info, component: "WorkoutSessionCoordinator",
                       message: "v98: Announced set target - \(announcement)")
        }
    }

    // MARK: - v69.0: Program Completion Cascade

    /// Check if program is complete and auto-activate the next program
    /// Called after each workout completion
    private func checkProgramCompletionAndCascade(program: Program, plan: Plan) {
        // Get all workouts in this program
        let programWorkouts = TestDataManager.shared.workouts.values.filter {
            $0.programId == program.id
        }

        // Check if all workouts are completed or skipped
        let allCompleted = programWorkouts.allSatisfy {
            $0.status == .completed || $0.status == .skipped
        }

        guard allCompleted else {
            // Program not complete yet
            return
        }

        // Mark current program as completed
        var updatedProgram = program
        updatedProgram.status = .completed
        TestDataManager.shared.programs[program.id] = updatedProgram

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "Program completed: \(program.name)")

        // Find next program in the plan (sorted by start date)
        let allPlanPrograms = TestDataManager.shared.programs.values
            .filter { $0.planId == plan.id }
            .sorted { $0.startDate < $1.startDate }

        guard let currentIndex = allPlanPrograms.firstIndex(where: { $0.id == program.id }),
              currentIndex + 1 < allPlanPrograms.count else {
            // No next program - this was the last one
            // Mark the plan as completed
            var updatedPlan = plan
            updatedPlan.status = .completed
            TestDataManager.shared.plans[plan.id] = updatedPlan

            Logger.log(.info, component: "WorkoutSessionCoordinator",
                       message: "Plan completed: \(plan.name) - all programs finished!")

            // v206: Sync to Firestore (fire-and-forget)
            Task {
                do {
                    try await FirestorePlanRepository.shared.savePlan(updatedPlan)
                } catch {
                    Logger.log(.warning, component: "WorkoutSessionCoordinator",
                              message: "⚠️ Firestore sync failed: \(error)")
                }
            }
            return
        }

        // Activate the next program
        let nextProgram = allPlanPrograms[currentIndex + 1]
        var activatedProgram = nextProgram
        activatedProgram.status = .active
        TestDataManager.shared.programs[nextProgram.id] = activatedProgram

        Logger.log(.info, component: "WorkoutSessionCoordinator",
                   message: "Auto-activated next phase: \(nextProgram.name) (focus: \(nextProgram.focus.displayName))")

        // v206: Removed legacy disk persistence - Firestore syncs program status via plan

        // Voice announcement for phase transition
        speakIfEnabled("Great work! You've completed the \(program.focus.displayName) phase. Next up: \(nextProgram.focus.displayName) phase!")
    }

    // MARK: - v86.0: AI-Generated Voice Announcements

    /// Generate an AI-powered voice announcement using user's training style and voice settings
    /// Falls back to simple announcement if AI fails or user has no settings
    private func generateAnnouncement(
        trigger: VoiceAnnouncementService.VoiceTrigger,
        workout: Workout,
        exerciseName: String?,
        setNumber: Int?,
        totalSets: Int?,
        targetWeight: Double?,
        targetReps: Int?,
        actualWeight: Double?,
        actualReps: Int?,
        restDuration: TimeInterval?
    ) async -> String {
        // Get user settings
        guard let user = TestDataManager.shared.users[memberId] else {
            return getFallbackAnnouncement(trigger: trigger, workout: workout)
        }

        // v182: Removed trainingStyle - using default Medina personality
        let voiceSettings = user.memberProfile?.voiceSettings ?? .default

        // Check if voice is enabled
        guard voiceSettings.isEnabled else {
            return ""
        }

        // Build context
        let context = VoiceAnnouncementService.WorkoutVoiceContext(
            voiceSettings: voiceSettings,
            workoutName: workout.displayName,
            splitDay: workout.splitDay,
            totalExercises: workout.exerciseIds.count,
            currentExerciseNumber: nil,  // Could compute from session if needed
            exerciseName: exerciseName,
            setNumber: setNumber,
            totalSets: totalSets,
            targetWeight: targetWeight,
            actualWeight: actualWeight,
            targetReps: targetReps,
            actualReps: actualReps,
            targetRPE: nil,  // Could get from set if needed
            actualRPE: nil,
            oneRMPercentage: nil,  // Could compute if 1RM is known
            volumeProgress: nil,  // Could compute cumulative volume
            tempo: nil,  // v95.0: Could get from protocol config if needed
            restDuration: restDuration != nil ? Int(restDuration!) : nil,
            workoutDuration: nil  // Could track elapsed time
        )

        // Try AI generation, fall back to simple announcement on error
        do {
            return try await announcementService.generateAnnouncement(trigger: trigger, context: context)
        } catch {
            Logger.log(.error, component: "WorkoutSessionCoordinator",
                       message: "AI announcement failed, using fallback: \(error.localizedDescription)")
            return getFallbackAnnouncement(trigger: trigger, workout: workout)
        }
    }

    /// v95.1: Template-based fallback announcements (fast, no GPT)
    /// Uses VoiceTemplateService for consistency with verbosity levels
    private func getFallbackAnnouncement(trigger: VoiceAnnouncementService.VoiceTrigger, workout: Workout) -> String {
        switch trigger {
        case .workoutStart:
            return VoiceTemplateService.workoutIntro(
                workoutName: workout.displayName,
                exerciseCount: workout.exerciseIds.count
            )
        case .exerciseStart:
            return "Next exercise."
        case .setComplete:
            return "Logged."
        case .restStart:
            return VoiceTemplateService.restStart(duration: 60, verbosity: getUserVerbosity())
        case .exerciseComplete:
            return "Exercise complete."
        case .workoutComplete:
            // Calculate workout duration
            if let session = activeSession {
                let duration = Int(Date().timeIntervalSince(session.startTime) / 60)
                return VoiceTemplateService.workoutComplete(duration: duration)
            }
            return VoiceTemplateService.workoutComplete(duration: 0)
        }
    }
}
