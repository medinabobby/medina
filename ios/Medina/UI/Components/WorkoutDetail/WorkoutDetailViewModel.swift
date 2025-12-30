//
// WorkoutDetailViewModel.swift
// Medina
//
// v93.7: Extracted state management and business logic from WorkoutDetailView
// Handles set logging, skip/reset, substitution, exercise selection, plan activation
//

import SwiftUI

/// ViewModel managing workout detail state and operations
@MainActor
final class WorkoutDetailViewModel: ObservableObject {

    // MARK: - Published State

    @Published var showExercises = true
    @Published var expandedExercises: Set<String> = []
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSummarySheet = false
    @Published var substitutionContext: WorkoutSubstitutionContext?
    @Published var isLoadingExercises = false

    // v208: Lazy loading state
    @Published var isLoadingDetails = false
    @Published var hasLoadedDetails = false

    // Plan activation state
    @Published var showActivationConfirmation = false
    @Published var activationOverlapPlan: Plan?
    @Published var activationSkippedCount: Int = 0

    // MARK: - Context

    let workoutId: String

    init(workoutId: String) {
        self.workoutId = workoutId
    }

    // MARK: - Computed Properties

    var workout: Workout? {
        LocalDataStore.shared.workouts[workoutId]
    }

    var isWorkoutInDraftPlan: Bool {
        guard let workout = workout,
              let program = LocalDataStore.shared.programs[workout.programId],
              let plan = LocalDataStore.shared.plans[program.planId] else {
            return false
        }
        return plan.status == .draft
    }

    var parentPlan: Plan? {
        guard let workout = workout,
              let program = LocalDataStore.shared.programs[workout.programId],
              let plan = LocalDataStore.shared.plans[program.planId] else {
            return nil
        }
        return plan
    }

    // MARK: - Instance Helpers

    func getInstances(for workout: Workout) -> [ExerciseInstance] {
        let allInstances = Array(LocalDataStore.shared.exerciseInstances.values)
        let filtered = allInstances.filter { $0.workoutId == workout.id }
        let sorted = filtered.sorted { $0.id < $1.id }
        return sorted
    }

    func hasLoggedData(instance: ExerciseInstance) -> Bool {
        let sets = instance.setIds.compactMap { LocalDataStore.shared.exerciseSets[$0] }
        let dict = Dictionary(uniqueKeysWithValues: sets.map { ($0.id, $0) })
        let updated = DeltaStore.shared.applySetDeltas(to: dict)
        return updated.values.contains { $0.completion != nil }
    }

    // MARK: - Expansion

    func toggleExpansion(instanceId: String) {
        if expandedExercises.contains(instanceId) {
            expandedExercises.remove(instanceId)
        } else {
            expandedExercises.insert(instanceId)
        }
    }

    func expandAllExercises() {
        guard let workout = workout else { return }

        for exerciseId in workout.exerciseIds {
            if let instance = LocalDataStore.shared.exerciseInstances.values.first(where: {
                $0.workoutId == workout.id && $0.exerciseId == exerciseId
            }) {
                expandedExercises.insert(instance.id)
            }
        }
    }

    // MARK: - Set Logging

    func handleSetLog(set: ExerciseSet, weight: Double, reps: Int) {
        let delta = DeltaStore.SetDelta(
            id: UUID(),
            setId: set.id,
            actualWeight: weight,
            actualReps: reps,
            completion: .completed,
            recordedDate: Date(),
            notes: String?.none,
            timestamp: Date()
        )

        DeltaStore.shared.saveSetDelta(delta)

        Logger.log(.info, component: "WorkoutDetailView",
                   message: "Logged set \(set.setNumber): \(Int(weight)) lbs × \(reps) reps")

        applyDeltas()
    }

    // MARK: - Skip & Reset

    func handleSkipExercise(sessionCoordinator: WorkoutSessionCoordinator) {
        guard sessionCoordinator.isWorkoutActive else {
            Logger.log(.warning, component: "WorkoutDetailView", message: "Cannot skip exercise - no active session")
            return
        }

        Task {
            await sessionCoordinator.skipCurrentExercise()
            applyDeltas()
        }
    }

    func handleUnskipSet(setId: String, sessionCoordinator: WorkoutSessionCoordinator) {
        Task {
            guard let instance = LocalDataStore.shared.exerciseInstances.values.first(where: {
                $0.setIds.contains(setId)
            }) else {
                Logger.log(.warning, component: "WorkoutDetailView", message: "No instance found for set \(setId)")
                return
            }

            guard let clickedSetIndex = instance.setIds.firstIndex(of: setId) else {
                Logger.log(.warning, component: "WorkoutDetailView", message: "Set \(setId) not found in instance")
                return
            }

            let remainingSetIds = Array(instance.setIds.dropFirst(clickedSetIndex))
            for remainingSetId in remainingSetIds {
                await sessionCoordinator.unskipSet(setId: remainingSetId)
            }

            Logger.log(.info, component: "WorkoutDetailView",
                       message: "Unskipped \(remainingSetIds.count) sets starting from index \(clickedSetIndex)")

            applyDeltas()
        }
    }

    func handleResetExercise(instanceId: String, sessionCoordinator: WorkoutSessionCoordinator) {
        Task {
            await sessionCoordinator.resetExercise(instanceId: instanceId)
            applyDeltas()
        }
    }

    // MARK: - Exercise Substitution

    func performSubstitution(instanceId: String, newExerciseId: String) {
        do {
            let userId = LocalDataStore.shared.currentUserId ?? "bobby"
            try ExerciseSubstitutionService.performSubstitution(
                instanceId: instanceId,
                newExerciseId: newExerciseId,
                workoutId: workoutId,
                userId: userId
            )

            Logger.log(.info, component: "WorkoutDetailView",
                       message: "Successfully substituted exercise in instance \(instanceId) with \(newExerciseId)")

            applyDeltas()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            Logger.log(.error, component: "WorkoutDetailView",
                       message: "Exercise substitution failed: \(error)")
        }
    }

    // MARK: - Exercise Selection

    func ensureExercisesSelectedAsync(for workout: Workout) async {
        guard workout.exerciseIds.isEmpty else { return }

        guard let program = LocalDataStore.shared.programs[workout.programId],
              let plan = LocalDataStore.shared.plans[program.planId] else {
            Logger.log(.warning, component: "WorkoutDetailView",
                      message: "Cannot select exercises - missing program or plan for workout \(workout.id)")
            return
        }

        let userId = LocalDataStore.shared.currentUserId ?? "bobby"

        await Task.yield()

        let updatedWorkout = RuntimeExerciseSelector.ensureExercisesSelected(
            for: workout,
            plan: plan,
            userId: userId
        )

        if updatedWorkout.exerciseIds != workout.exerciseIds {
            Logger.log(.info, component: "WorkoutDetailView",
                      message: "v74.0: Async exercises selected for workout \(workout.id) - \(updatedWorkout.exerciseIds.count) exercises")
        }
    }

    // v162: Removed handleRefreshExercises - feature was never scoped/requested

    // MARK: - Plan Activation

    func handleActivatePlan() {
        guard let plan = parentPlan else {
            errorMessage = "Unable to find plan for this workout."
            showError = true
            return
        }

        let overlappingPlans = PlanActivationService.checkForOverlap(plan: plan)

        if let overlapping = overlappingPlans.first {
            activationOverlapPlan = overlapping
            activationSkippedCount = PlanActivationService.countRemainingWorkouts(for: overlapping)
            showActivationConfirmation = true
        } else {
            Task {
                await performPlanActivation()
            }
        }
    }

    func performPlanActivation() async {
        guard let plan = parentPlan else {
            errorMessage = "Unable to find plan for this workout."
            showError = true
            return
        }

        do {
            let result = try await PlanActivationService.activateWithAutoDeactivate(plan: plan)

            Logger.log(.info, component: "WorkoutDetailView",
                       message: "Activated plan '\(result.activatedPlan.name)' (deactivated: \(result.deactivatedPlan?.name ?? "none"), skipped: \(result.skippedWorkoutCount))")

            activationOverlapPlan = nil
            activationSkippedCount = 0
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            Logger.log(.error, component: "WorkoutDetailView",
                       message: "Plan activation failed: \(error)")
        }
    }

    // MARK: - Delta Application

    func applyDeltas() {
        let manager = LocalDataStore.shared
        manager.workouts = DeltaStore.shared.applyWorkoutDeltas(to: manager.workouts)
        manager.exerciseInstances = DeltaStore.shared.applyInstanceDeltas(to: manager.exerciseInstances)
        manager.exerciseSets = DeltaStore.shared.applySetDeltas(to: manager.exerciseSets)
    }

    // MARK: - v208 Lazy Loading

    /// Load instances and sets from Firestore on demand
    /// Called when WorkoutDetailView appears - avoids loading all data at login
    func loadDetailsIfNeeded() async {
        // Skip if already loaded or currently loading
        guard !hasLoadedDetails, !isLoadingDetails else { return }

        // Check if instances already exist in memory (from previous load or local cache)
        let existingInstances = LocalDataStore.shared.exerciseInstances.values.filter { $0.workoutId == workoutId }
        if !existingInstances.isEmpty {
            hasLoadedDetails = true
            return
        }

        isLoadingDetails = true
        defer { isLoadingDetails = false }

        let userId = LocalDataStore.shared.currentUserId ?? "bobby"
        await LocalDataLoader.loadWorkoutDetails(workoutId: workoutId, userId: userId)

        hasLoadedDetails = true
        Logger.log(.info, component: "WorkoutDetailViewModel",
                  message: "v208: Lazy loaded details for workout \(workoutId)")
    }
}

// MARK: - Supporting Types

/// Context for exercise substitution sheet in WorkoutDetailView (used with .sheet(item:) pattern)
/// Note: FocusedExecutionView has its own SubstitutionContext defined locally
struct WorkoutSubstitutionContext: Identifiable {
    let id: String  // instance ID
    let instance: ExerciseInstance
}
