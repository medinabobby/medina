//
// WorkoutDetailView.swift
// Medina
//
// v93.7: Refactored from 952 lines to ~400 lines
// Extracted components:
//   - WorkoutDetailViewModel.swift (state management + business logic)
//   - WorkoutDetailExerciseSections.swift (exercises list, rows, hero, breadcrumb)
//
// v46 Handler Refactor: Detail view pattern with collapsible sections, email-style cards
// v68.0: Added draft plan UX with activation flow and overlap handling
// v78.6: Removed dead active-workout code (rest timer, progressive disclosure)
// v78.8: Removed redirect to FocusedExecution - let users see WorkoutDetailView with Continue
// v175: Prevent starting workout when another is in progress (active session conflict alert)
//

import SwiftUI

struct WorkoutDetailView: View {
    let workoutId: String
    @EnvironmentObject private var navigationModel: NavigationModel
    @StateObject private var actionCoordinator = EntityActionCoordinator()
    @StateObject private var viewModel: WorkoutDetailViewModel

    // Session coordinator for workout execution
    @StateObject private var sessionCoordinator: WorkoutSessionCoordinator = {
        let userId = TestDataManager.shared.currentUserId ?? "bobby"
        let voiceService = VoiceService(apiKey: Config.openAIKey)
        return WorkoutSessionCoordinator(memberId: userId, voiceService: voiceService)
    }()

    // v175: Active session conflict state
    @State private var showActiveSessionAlert = false
    @State private var activeSessionConflict: Session?
    @State private var pendingWorkoutId: String?

    init(workoutId: String) {
        self.workoutId = workoutId
        self._viewModel = StateObject(wrappedValue: WorkoutDetailViewModel(workoutId: workoutId))
    }

    private var coordinator: NavigationCoordinator {
        NavigationCoordinator(navigationModel: navigationModel)
    }

    var body: some View {
        Group {
            let _ = viewModel.applyDeltas()
            if let workout = TestDataManager.shared.workouts[workoutId] {
                VStack(spacing: 0) {
                    WorkoutBreadcrumbBar(workout: workout, coordinator: coordinator)
                    WorkoutHeroSection(workout: workout, isSessionActive: sessionCoordinator.isWorkoutActive)
                    workoutStatusBox(for: workout)
                    exercisesListView(for: workout)
                }
                .onAppear {
                    // v162: Restore active session if exists - enables "End Workout Early" from detail view
                    sessionCoordinator.restoreSession(for: workoutId)

                    // v208: Lazy load instances/sets from Firestore on demand
                    Task {
                        await viewModel.loadDetailsIfNeeded()
                    }

                    if workout.exerciseIds.isEmpty {
                        viewModel.isLoadingExercises = true
                        Task {
                            await viewModel.ensureExercisesSelectedAsync(for: workout)
                            await MainActor.run {
                                viewModel.isLoadingExercises = false
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(
                    icon: "figure.strengthtraining.traditional",
                    title: "Workout Not Found",
                    message: "The requested workout could not be found."
                )
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let workout = TestDataManager.shared.workouts[workoutId] {
                ToolbarItem(placement: .navigationBarTrailing) {
                    workoutActionsMenu(for: workout)
                }
            }
        }
        .alert(actionCoordinator.alertTitle, isPresented: $actionCoordinator.showAlert) {
            Button("Cancel", role: .cancel) { actionCoordinator.cancelAction() }
            Button("Confirm", role: .destructive) {
                Task { await actionCoordinator.confirmAction() }
            }
        } message: {
            Text(actionCoordinator.alertMessage)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Replace Active Plan?", isPresented: $viewModel.showActivationConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.activationOverlapPlan = nil
                viewModel.activationSkippedCount = 0
            }
            Button("Replace Plan", role: .destructive) {
                Task { await viewModel.performPlanActivation() }
            }
        } message: {
            if let overlapPlan = viewModel.activationOverlapPlan {
                Text("\"\(viewModel.parentPlan?.name ?? "New Plan")\" will replace \"\(overlapPlan.name)\". \(overlapPlan.name) will be abandoned and \(viewModel.activationSkippedCount) remaining \(viewModel.activationSkippedCount == 1 ? "workout" : "workouts") will be marked as skipped.")
            }
        }
        // v175: Active session conflict alert
        .alert("Workout In Progress", isPresented: $showActiveSessionAlert) {
            Button("Continue Current") { continueCurrentWorkout() }
            Button("End & Start New", role: .destructive) { endAndStartNewWorkout() }
            Button("Cancel", role: .cancel) { clearConflictState() }
        } message: {
            Text(activeSessionConflictMessage)
        }
        .sheet(isPresented: $viewModel.showSummarySheet) {
            let userId = TestDataManager.shared.currentUserId ?? "bobby"
            WorkoutSummaryView(workoutId: workoutId, memberId: userId)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowWorkoutSummary"))) { notification in
            if let notificationWorkoutId = notification.userInfo?["workoutId"] as? String,
               notificationWorkoutId == workoutId {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    viewModel.showSummarySheet = true
                }
            }
        }
        .sheet(item: $viewModel.substitutionContext) { context in
            ExerciseSubstitutionSheet(
                exerciseInstance: context.instance,
                workoutId: workoutId,
                onSubstitute: { newExerciseId in
                    viewModel.performSubstitution(instanceId: context.id, newExerciseId: newExerciseId)
                    viewModel.substitutionContext = nil
                },
                onDismiss: {
                    viewModel.substitutionContext = nil
                }
            )
        }
    }

    // MARK: - Navigation Title

    private var navigationTitle: String {
        if let workout = TestDataManager.shared.workouts[workoutId],
           let date = workout.scheduledDate {
            let calendar = Calendar.current
            let dayOfWeekIndex = calendar.component(.weekday, from: date)
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayName = dayNames[dayOfWeekIndex - 1]
            let dateStr = DateFormatters.shortMonthDayFormatter.string(from: date)
            return "\(dayName), \(dateStr)"
        }
        return "Workout"
    }

    // MARK: - Exercises List

    @ViewBuilder
    private func exercisesListView(for workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let instances = viewModel.getInstances(for: workout)
                let exerciseCount = !instances.isEmpty ? instances.count : workout.exerciseIds.count

                DisclosureGroup("Exercises in this Workout (\(exerciseCount))", isExpanded: $viewModel.showExercises) {
                    VStack(alignment: .leading, spacing: 12) {
                        // v208: Show loading indicator while fetching instances/sets
                        if viewModel.isLoadingDetails {
                            HStack {
                                Spacer()
                                ProgressView("Loading exercises...")
                                    .padding(.vertical, 20)
                                Spacer()
                            }
                        } else if !instances.isEmpty {
                            ForEach(Array(instances.enumerated()), id: \.element.id) { index, instance in
                                if let exercise = TestDataManager.shared.exercises[instance.exerciseId] {
                                    exerciseRow(exercise: exercise, instance: instance, index: index)
                                }
                            }
                        } else if !workout.exerciseIds.isEmpty {
                            ForEach(Array(workout.exerciseIds.enumerated()), id: \.offset) { index, exerciseId in
                                if let exercise = TestDataManager.shared.exercises[exerciseId] {
                                    WorkoutPlannedExerciseRow(
                                        exercise: exercise,
                                        position: index,
                                        workout: workout,
                                        coordinator: coordinator
                                    )
                                }
                            }
                        } else {
                            Text("No exercises found")
                                .font(.body)
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }
                    .padding(.top, 12)
                }
                .tint(Color("PrimaryText"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func exerciseRow(exercise: Exercise, instance: ExerciseInstance, index: Int) -> some View {
        WorkoutExerciseInstanceRow(
            exercise: exercise,
            instance: instance,
            index: index,
            isExpanded: viewModel.expandedExercises.contains(instance.id),
            hasLoggedData: viewModel.hasLoggedData(instance: instance),
            onToggleExpansion: { viewModel.toggleExpansion(instanceId: instance.id) },
            onSetLog: { set, weight, reps in viewModel.handleSetLog(set: set, weight: weight, reps: reps) },
            onUnskipSet: { setId in viewModel.handleUnskipSet(setId: setId, sessionCoordinator: sessionCoordinator) },
            onSkipExercise: { viewModel.handleSkipExercise(sessionCoordinator: sessionCoordinator) },
            onResetExercise: { viewModel.handleResetExercise(instanceId: instance.id, sessionCoordinator: sessionCoordinator) },
            onSubstituteExercise: {
                viewModel.substitutionContext = WorkoutSubstitutionContext(id: instance.id, instance: instance)
            }
        )
    }

    // MARK: - Workout Status Box

    @ViewBuilder
    private func workoutStatusBox(for workout: Workout) -> some View {
        WorkoutStatusBar(
            workout: workout,
            coordinator: sessionCoordinator,
            onFinishWorkout: { sessionCoordinator.completeWorkout() },
            onStartWorkout: { handleStartWorkout(workoutId: workout.id) },
            onContinueWorkout: { handleStartWorkout(workoutId: workout.id) },
            onReviewWorkout: { viewModel.showSummarySheet = true },
            isInDraftPlan: viewModel.isWorkoutInDraftPlan,
            onActivatePlan: { viewModel.handleActivatePlan() }
        )
    }

    // MARK: - v175: Active Session Conflict Handling

    /// Check for active session on a DIFFERENT workout before starting
    private func handleStartWorkout(workoutId: String) {
        let userId = TestDataManager.shared.currentUserId ?? "bobby"

        // Check for active session on a DIFFERENT workout
        if let existingSession = TestDataManager.shared.activeSession(for: userId),
           existingSession.workoutId != workoutId {
            // Store the workout we want to start and show conflict alert
            pendingWorkoutId = workoutId
            activeSessionConflict = existingSession
            showActiveSessionAlert = true
            Logger.log(.warning, component: "WorkoutDetailView",
                       message: "⚠️ Active session conflict: trying to start \(workoutId) but \(existingSession.workoutId) is active")
            return
        }

        // No conflict - proceed with navigation
        coordinator.enterFocusedExecution(workoutId: workoutId)
    }

    /// Message for active session conflict alert
    private var activeSessionConflictMessage: String {
        guard let session = activeSessionConflict,
              let activeWorkout = TestDataManager.shared.workouts[session.workoutId] else {
            return "Another workout is in progress."
        }
        return "'\(activeWorkout.displayName)' is still in progress. End it first or continue that workout."
    }

    private func continueCurrentWorkout() {
        if let session = activeSessionConflict {
            coordinator.enterFocusedExecution(workoutId: session.workoutId)
        }
    }

    private func endAndStartNewWorkout() {
        if let newWorkoutId = pendingWorkoutId {
            // Complete current workout (marks remaining as skipped)
            sessionCoordinator.completeWorkout()
            // Then start the new workout
            coordinator.enterFocusedExecution(workoutId: newWorkoutId)
        }
    }

    private func clearConflictState() {
        pendingWorkoutId = nil
        activeSessionConflict = nil
    }

    // MARK: - Actions Menu

    @ViewBuilder
    private func workoutActionsMenu(for workout: Workout) -> some View {
        let (statusText, _) = workout.status.statusInfo()

        let parentContext: ParentContext? = {
            if let program = TestDataManager.shared.programs[workout.programId] {
                return ParentContext(planId: program.planId, programId: program.id, workoutId: workout.id)
            }
            return nil
        }()

        let descriptor = EntityDescriptor(
            entityType: .workout,
            entityId: workout.id,
            status: statusText,
            userRole: .member,
            parentContext: parentContext
        )

        let actions = EntityActionProvider.actions(for: descriptor)

        if !actions.isEmpty {
            Menu {
                ForEach(actions) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        Task {
                            await handleAction(action, for: workout, descriptor: descriptor)
                        }
                    } label: {
                        Label(action.title, systemImage: action.icon)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundColor(Color("PrimaryText"))
            }
        }
    }

    private func handleAction(_ action: EntityAction, for workout: Workout, descriptor: EntityDescriptor) async {
        switch action.type {
        // v162: Added .continueWorkout - was falling through to default which kicked to chat
        // v175: Route through handleStartWorkout to check for active session conflicts
        case .startWorkout, .startGuidedWorkout, .continueWorkout:
            handleStartWorkout(workoutId: workout.id)

        case .completeWorkout:
            await sessionCoordinator.completeWorkout()
            viewModel.applyDeltas()

        case .resetWorkout:
            await sessionCoordinator.resetWorkout(workoutId: workout.id)
            viewModel.applyDeltas()

        // v166: Skip workout - save delta and refresh view
        case .skipWorkout:
            let delta = DeltaStore.WorkoutDelta(workoutId: workout.id, scheduledDate: nil, completion: .skipped)
            DeltaStore.shared.saveWorkoutDelta(delta)
            viewModel.applyDeltas()
            // v206: Sync to Firestore
            if let program = TestDataManager.shared.programs[workout.programId],
               let plan = TestDataManager.shared.plans[program.planId] {
                var skippedWorkout = workout
                skippedWorkout.status = .skipped
                TestDataManager.shared.workouts[workout.id] = skippedWorkout
                Task {
                    do {
                        try await FirestoreWorkoutRepository.shared.saveWorkout(skippedWorkout, memberId: plan.memberId)
                    } catch {
                        Logger.log(.warning, component: "WorkoutDetailView", message: "⚠️ Firestore sync failed: \(error)")
                    }
                }
            }
            Logger.log(.info, component: "WorkoutDetailView", message: "Skipped workout: \(workout.id)")

        // v162: Removed .refreshExercises - feature was never scoped

        default:
            let result = await actionCoordinator.execute(
                actionType: action.type,
                descriptor: descriptor,
                context: .detailView,
                navigationModel: navigationModel,
                chatViewModel: nil
            )

            switch result {
            case .success:
                break
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            case .cancelled:
                break
            }
        }
    }
}

// MARK: - Previews

#Preview("Completed Workout") {
    NavigationStack {
        WorkoutDetailView(workoutId: "bobby_onplan_20251027")
            .environmentObject(NavigationModel())
    }
}

#Preview("Scheduled Workout") {
    NavigationStack {
        WorkoutDetailView(workoutId: "bobby_onplan_20251104")
            .environmentObject(NavigationModel())
    }
}
