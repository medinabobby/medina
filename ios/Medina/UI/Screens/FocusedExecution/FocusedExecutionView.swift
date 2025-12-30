//
// FocusedExecutionView.swift
// Medina
//
// v76.0: Main container for focused workout execution mode
// v79.3: Added protocol chip + ProtocolInfoSheet for special protocols
// v97: Voice-synchronized intro screen (waits for GPT voice to finish)
// v101.2: Cardio branching - uses CardioSetActionCard for cardio exercises
// Created: December 2025
// Purpose: One exercise, one set at a time - Zing-style workout execution
//

import SwiftUI

/// Focused workout execution view showing one exercise and one set at a time
struct FocusedExecutionView: View {
    let workoutId: String
    @EnvironmentObject private var navigationModel: NavigationModel
    @StateObject private var viewModel: FocusedExecutionViewModel

    @State private var showDetailsSheet = false
    @State private var showMenu = false
    @State private var showEndWorkoutConfirmation = false
    @State private var showCompletionSummary = false
    @State private var showRPEInfo = false   // v78.7: Separate RPE info sheet
    @State private var showTempoInfo = false // v78.7: Separate Tempo info sheet
    @State private var showProtocolInfo = false // v79.3: Protocol info sheet
    @State private var substitutionContext: SubstitutionContext? // v78.8: Substitution sheet
    @State private var showEquipmentSwap = false // v79.0: Equipment swap sheet

    // Initializer to set up the view model
    init(workoutId: String) {
        self.workoutId = workoutId

        // Create session coordinator with voice service
        let userId = TestDataManager.shared.currentUserId ?? "bobby"
        let voiceService = VoiceService()
        let coordinator = WorkoutSessionCoordinator(memberId: userId, voiceService: voiceService)

        _viewModel = StateObject(wrappedValue: FocusedExecutionViewModel(
            workoutId: workoutId,
            coordinator: coordinator
        ))
    }

    var body: some View {
        ZStack {
            // Background
            Color("Background")
                .ignoresSafeArea()

            // v97: Show intro screen first, waits for voice completion
            if viewModel.isShowingIntro {
                FocusedExecutionIntroView(
                    workoutName: viewModel.workoutName,
                    splitDay: viewModel.splitDay,
                    totalExercises: viewModel.totalExercises,
                    onComplete: {
                        viewModel.completeIntro()
                    },
                    isVoiceComplete: $viewModel.isVoiceIntroComplete
                )
            } else if viewModel.isWorkoutComplete {
                workoutCompleteView
            } else {
                executionView
            }

            // v78.4: Rest timer is now inline (replaces SetActionCard), not overlay
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isResting)
        .animation(.easeInOut(duration: 0.4), value: viewModel.isShowingIntro)
        .navigationBarHidden(true)
        .onAppear {
            Task {
                await viewModel.startWorkoutIfNeeded()
            }
        }
        .sheet(isPresented: $showDetailsSheet) {
            if let exercise = viewModel.currentExercise {
                ExerciseDetailsSheet(
                    exercise: exercise,
                    instance: viewModel.currentInstance,
                    onSkip: {
                        Task {
                            await viewModel.skipExercise()
                        }
                    },
                    onSubstitute: {
                        // v78.8: Wire up substitution sheet
                        showDetailsSheet = false
                        if let instance = viewModel.currentInstance {
                            substitutionContext = SubstitutionContext(
                                id: instance.id,
                                instance: instance
                            )
                        }
                    },
                    canSubstitute: !viewModel.hasLoggedSets,
                    loggedSetCount: viewModel.loggedSetCount
                )
            }
        }
        .sheet(item: $substitutionContext) { context in
            // v78.8: Substitution sheet
            ExerciseSubstitutionSheet(
                exerciseInstance: context.instance,
                workoutId: workoutId,
                onSubstitute: { newExerciseId in
                    viewModel.substituteExercise(newExerciseId: newExerciseId)
                    substitutionContext = nil
                },
                onDismiss: {
                    substitutionContext = nil
                }
            )
        }
        .sheet(isPresented: $showCompletionSummary) {
            let userId = TestDataManager.shared.currentUserId ?? "bobby"
            WorkoutSummaryView(workoutId: workoutId, memberId: userId)
        }
        .sheet(isPresented: $showRPEInfo) {
            // v78.7: Separate RPE info sheet
            if let rpe = viewModel.currentProtocolRPE {
                RPEInfoSheet(rpe: rpe, onDismiss: { showRPEInfo = false })
            }
        }
        .sheet(isPresented: $showTempoInfo) {
            // v78.7: Separate Tempo info sheet
            if let tempo = viewModel.currentProtocolTempo {
                TempoInfoSheet(tempo: tempo, onDismiss: { showTempoInfo = false })
            }
        }
        .sheet(isPresented: $showEquipmentSwap) {
            // v79.0: Equipment swap sheet
            if let exercise = viewModel.currentExercise,
               let instance = viewModel.currentInstance {
                EquipmentSwapSheet(
                    currentExercise: exercise,
                    workoutId: workoutId,
                    instanceId: instance.id,
                    onSwap: { newExerciseId in
                        viewModel.substituteExercise(newExerciseId: newExerciseId)
                        showEquipmentSwap = false
                    },
                    onDismiss: {
                        showEquipmentSwap = false
                    }
                )
            }
        }
        .sheet(isPresented: $showProtocolInfo) {
            // v79.3: Protocol info sheet
            if let protocolConfig = viewModel.currentProtocolConfig {
                ProtocolInfoSheet(
                    protocolConfig: protocolConfig,
                    onDismiss: { showProtocolInfo = false }
                )
            }
        }
        .confirmationDialog("End Workout", isPresented: $showEndWorkoutConfirmation) {
            Button("End Workout Early", role: .destructive) {
                viewModel.completeWorkoutEarly()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mark remaining exercises as skipped and end the workout?")
        }
    }

    // MARK: - Main Execution View

    private var executionView: some View {
        VStack(spacing: 0) {
            // Progress header
            ExerciseProgressHeader(
                exerciseNumber: viewModel.exerciseNumber,
                totalExercises: viewModel.totalExercises,
                workoutName: viewModel.workoutName,
                onBack: {
                    // v78.8: Exit to WorkoutDetailView (not pop)
                    // This lets user see their progress in the expanded set view
                    navigationModel.popToRoot()
                    navigationModel.push(.workout(id: workoutId))
                },
                onMenu: {
                    showMenu = true
                },
                // v83.0: Pass superset label for "Exercise 1a of 4" display
                supersetLabel: viewModel.supersetLabel
            )
            .confirmationDialog("Options", isPresented: $showMenu) {
                // v78.9: Only show Substitute if no sets logged yet
                if !viewModel.hasLoggedSets {
                    Button("Substitute Exercise") {
                        if let instance = viewModel.currentInstance {
                            substitutionContext = SubstitutionContext(
                                id: instance.id,
                                instance: instance
                            )
                        }
                    }
                }
                Button("Skip Exercise", role: .destructive) {
                    Task {
                        await viewModel.skipExercise()
                    }
                }
                Button("End Workout Early", role: .destructive) {
                    showEndWorkoutConfirmation = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                // v78.9: Show message if substitution is disabled
                if viewModel.hasLoggedSets {
                    Text("Substitution unavailable - \(viewModel.loggedSetCount) set\(viewModel.loggedSetCount == 1 ? "" : "s") already logged")
                }
            }

            // v78.0: Status box with exercise name and protocol info (replaces MuscleHeroView)
            statusBox
                .padding(.horizontal, 20)
                .padding(.top, 24)

            Spacer()

            // v78.4: Bottom content - conditionally shows SetActionCard or RestTimerCard
            bottomContent
        }
    }

    // MARK: - Bottom Content (SetActionCard or RestTimerCard)

    /// v78.4: Conditional bottom content - shows rest timer during rest, set card otherwise
    /// v101.2: Branches between SetActionCard (strength) and CardioSetActionCard (cardio)
    @ViewBuilder
    private var bottomContent: some View {
        if viewModel.isResting, let endDate = viewModel.restEndDate {
            RestTimerCard(
                endDate: endDate,
                totalTime: viewModel.restTotalTime,
                onAdjustRest: { seconds in
                    viewModel.adjustRest(by: seconds)
                },
                onSkipRest: {
                    viewModel.skipRest()
                },
                onTimerCompleted: {
                    viewModel.skipRest()
                },
                // v83.0: Pass next exercise in superset for preview
                nextExerciseLabel: viewModel.nextExerciseInSuperset?.label,
                nextExerciseName: viewModel.nextExerciseInSuperset?.name
            )
            .transition(.opacity)
        } else if viewModel.isCardioExercise {
            // v101.2: Cardio exercise - show duration/distance inputs
            CardioSetActionCard(
                exerciseName: viewModel.exerciseName,
                setNumber: viewModel.setNumber,
                totalSets: viewModel.totalSets,
                durationSeconds: $viewModel.displayDuration,
                distance: $viewModel.displayDistance,
                showDistance: viewModel.showDistanceInput,
                onLog: {
                    Task {
                        await viewModel.logCardioSet()
                    }
                },
                onDetailsSheet: {
                    showDetailsSheet = true
                }
            )
            .transition(.opacity)
        } else {
            // Strength exercise - show weight/reps inputs
            SetActionCard(
                exerciseName: viewModel.exerciseName,
                setNumber: viewModel.setNumber,
                totalSets: viewModel.totalSets,
                weight: $viewModel.displayWeight,
                reps: $viewModel.displayReps,
                onLog: {
                    Task {
                        await viewModel.logSet()
                    }
                },
                onDetailsSheet: {
                    showDetailsSheet = true
                }
            )
            .transition(.opacity)
        }
    }

    // MARK: - Status Box

    /// v78.0: Status box showing current exercise and protocol guidance
    /// v79.3: Uses ExerciseHeaderView for consistent display + adds protocol chip
    private var statusBox: some View {
        VStack(spacing: 16) {
            // v79.3: Use ExerciseHeaderView for consistent name + equipment display
            if let exercise = viewModel.currentExercise {
                ExerciseHeaderView(
                    exercise: exercise,
                    size: .large,
                    alignment: .center,
                    equipmentTappable: true,
                    onEquipmentTap: { showEquipmentSwap = true }
                )
            }

            // v172.1: Protocol + training params in vertical layout
            // v172.2: Always show protocol chip for consistency (removed isSpecialProtocol filter)
            VStack(spacing: 8) {
                // Row 1: Protocol chip (centered, blue to match RPE/Tempo)
                if let protocolName = viewModel.currentProtocolName {
                    Button(action: { showProtocolInfo = true }) {
                        HStack(spacing: 6) {
                            Text(protocolName)
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                // Row 2: Training params (superset, RPE, tempo)
                HStack(spacing: 12) {
                    // v83.0: Superset badge (e.g., "1a", "1b")
                    if let supersetLabel = viewModel.supersetLabel {
                        Text(supersetLabel)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.teal.opacity(0.15))
                            .cornerRadius(8)
                    }

                    // RPE chip
                    if let rpe = viewModel.currentProtocolRPE {
                        Button(action: { showRPEInfo = true }) {
                            HStack(spacing: 6) {
                                Text("RPE \(Int(rpe))")
                                    .font(.system(size: 14, weight: .medium))
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }

                    // Tempo chip
                    if let tempo = viewModel.currentProtocolTempo {
                        Button(action: { showTempoInfo = true }) {
                            HStack(spacing: 6) {
                                Text("Tempo \(tempo)")
                                    .font(.system(size: 14, weight: .medium))
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Workout Complete View

    private var workoutCompleteView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
            }

            // Title
            Text("Workout Complete!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color("PrimaryText"))

            // Subtitle
            Text("Great work on \(viewModel.workoutName)")
                .font(.system(size: 17))
                .foregroundColor(Color("SecondaryText"))
                .multilineTextAlignment(.center)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button(action: {
                    showCompletionSummary = true
                }) {
                    Text("View Summary")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(14)
                }

                Button(action: {
                    navigationModel.pop()
                }) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Substitution Context

/// v78.8: Context for substitution sheet (same pattern as WorkoutDetailView)
private struct SubstitutionContext: Identifiable {
    let id: String
    let instance: ExerciseInstance
}

// MARK: - Preview

#Preview("Focused Execution") {
    NavigationStack {
        FocusedExecutionView(workoutId: "workout_w1_d1")
            .environmentObject(NavigationModel())
    }
}
