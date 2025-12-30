//
// PlanDetailView.swift
// Medina
//
// v46 Handler Refactor: Detail view pattern with collapsible sections, email-style cards
// Created: November 2025
// Purpose: Plan detail view showing schedule, strategy, and program cards
//

import SwiftUI

struct PlanDetailView: View {
    let planId: String
    @EnvironmentObject private var navigationModel: NavigationModel
    @StateObject private var actionCoordinator = EntityActionCoordinator()

    @State private var showPlanDetails = true
    @State private var showPrograms = true

    // v74.0: Plan activation state
    @State private var showActivationConfirmation = false
    @State private var activationOverlapPlan: Plan?
    @State private var activationSkippedCount: Int = 0
    @State private var errorMessage: String?
    @State private var showError = false

    private var coordinator: NavigationCoordinator {
        NavigationCoordinator(navigationModel: navigationModel)
    }

    var body: some View {
        Group {
            if let plan = LocalDataStore.shared.plans[planId] {
                VStack(spacing: 0) {
                    // Breadcrumb navigation
                    BreadcrumbBar(items: [
                        BreadcrumbItem(label: "Plan", action: nil)
                    ])

                    // Hero section
                    heroSection(for: plan)

                    // v74.0: Activate Plan banner for draft plans
                    if plan.status == .draft {
                        Button(action: { handleActivatePlan(plan: plan) }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.orange)

                                Text("Activate Plan to Start")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color("PrimaryText"))

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color("SecondaryText"))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    // Next Workout Preview (if plan is active)
                    if plan.status == .active {
                        nextWorkoutChip(for: plan)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    // Scrollable content sections
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            DisclosureGroup("Plan Details", isExpanded: $showPlanDetails) {
                                VStack(alignment: .leading, spacing: 12) {
                                    planDetailsSection(for: plan)
                                }
                                .padding(.top, 12)
                            }
                            .tint(Color("PrimaryText"))

                            Divider().background(Color("BorderColor"))

                            // Count programs for header
                            let programCount = LocalDataStore.shared.programs.values
                                .filter { $0.planId == planId }
                                .count

                            DisclosureGroup("Programs in this Plan (\(programCount))", isExpanded: $showPrograms) {
                                VStack(alignment: .leading, spacing: 12) {
                                    programsSection(for: plan)
                                }
                                .padding(.top, 12)
                            }
                            .tint(Color("PrimaryText"))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                }
            } else {
                EmptyStateView(
                    icon: "calendar",
                    title: "Plan Not Found",
                    message: "The requested plan could not be found."
                )
            }
        }
        .navigationTitle(LocalDataStore.shared.plans[planId]?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let plan = LocalDataStore.shared.plans[planId] {
                ToolbarItem(placement: .navigationBarTrailing) {
                    planActionsMenu(for: plan)
                }
            }
        }
        .alert(actionCoordinator.alertTitle, isPresented: $actionCoordinator.showAlert) {
            Button("Cancel", role: .cancel) {
                actionCoordinator.cancelAction()
            }
            Button("Confirm", role: .destructive) {
                Task {
                    await actionCoordinator.confirmAction()
                }
            }
        } message: {
            Text(actionCoordinator.alertMessage)
        }
        // v74.0: Plan activation confirmation alert (for overlap)
        .alert("Replace Active Plan?", isPresented: $showActivationConfirmation) {
            Button("Cancel", role: .cancel) {
                activationOverlapPlan = nil
                activationSkippedCount = 0
            }
            Button("Replace Plan", role: .destructive) {
                Task {
                    await performPlanActivation()
                }
            }
        } message: {
            if let overlapPlan = activationOverlapPlan,
               let plan = LocalDataStore.shared.plans[planId] {
                Text("\"\(plan.name)\" will replace \"\(overlapPlan.name)\". \(overlapPlan.name) will be abandoned and \(activationSkippedCount) remaining \(activationSkippedCount == 1 ? "workout" : "workouts") will be marked as skipped.")
            }
        }
        // v74.0: Error alert
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Section Builders

    @ViewBuilder
    private func heroSection(for plan: Plan) -> some View {
        let (statusText, statusColor) = plan.status.statusInfo()

        // Line 1: Date range + status badge
        let dateRange = "\(DateFormatters.shortMonthDayFormatter.string(from: plan.startDate)) – \(DateFormatters.shortMonthDayFormatter.string(from: plan.endDate))"

        // Line 2: Goal + Weekly sessions + duration
        let totalSessions = plan.weightliftingDays + plan.cardioDays
        let line2 = "\(plan.goal.displayName) • \(totalSessions) days/week • \(plan.targetSessionDuration) min"

        HeroSection(
            line1Text: dateRange,
            statusText: statusText,
            statusColor: statusColor,
            line2Text: line2
        )
    }

    @ViewBuilder
    private func planDetailsSection(for plan: Plan) -> some View {
        // Emphasized Muscle Groups
        if let emphasized = plan.emphasizedMuscleGroups, !emphasized.isEmpty {
            let muscles = emphasized
                .sorted { $0.displayName < $1.displayName }
                .map { $0.displayName }
                .joined(separator: ", ")
            KeyValueRow(key: "Emphasis", value: muscles)
        }

        // v81.2: Training Location
        KeyValueRow(key: "Location", value: plan.trainingLocation.displayName)

        // Split Type (read-only)
        KeyValueRow(key: "Split Type", value: plan.splitType.displayName)

        // v66: Compound/Isolation hidden - confusing jargon for users
        // These values still exist in Plan model for internal use

        // Intensity (calculated from child programs)
        let programs = LocalDataStore.shared.programs.values
            .filter { $0.planId == planId }
        if !programs.isEmpty {
            if let minIntensity = programs.map({ $0.startingIntensity }).min(),
               let maxIntensity = programs.map({ $0.endingIntensity }).max() {
                let minPct = Int(minIntensity * 100)
                let maxPct = Int(maxIntensity * 100)
                KeyValueRow(key: "Intensity", value: "\(minPct)% → \(maxPct)%")
            }
        }

        // Weekly Mix
        let totalSessions = plan.weightliftingDays + plan.cardioDays
        KeyValueRow(
            key: "Weekly Mix",
            value: "\(plan.weightliftingDays) strength • \(plan.cardioDays) cardio"
        )

        // Days
        let preferredDays = DayOfWeek.allCases.filter { plan.preferredDays.contains($0) }
        if !preferredDays.isEmpty {
            KeyValueRow(
                key: "Days",
                value: preferredDays.map { $0.shortName }.joined(separator: ", ")
            )
        }
    }


    @ViewBuilder
    private func programsSection(for plan: Plan) -> some View {
        let programs = LocalDataStore.shared.programs.values
            .filter { $0.planId == planId }
            .sorted { $0.startDate < $1.startDate }

        ForEach(Array(programs.enumerated()), id: \.element.id) { index, program in
            programRow(for: program, number: "\(index + 1)")
        }
    }

    @ViewBuilder
    private func programRow(for program: Program, number: String) -> some View {
        let (statusText, statusColor) = program.status.statusInfo()

        let subtitle: String = {
            let dateRange = "\(DateFormatters.shortMonthDayFormatter.string(from: program.startDate)) – \(DateFormatters.shortMonthDayFormatter.string(from: program.endDate))"

            // Count workouts in this program
            let workoutCount = LocalDataStore.shared.workouts.values
                .filter { $0.programId == program.id }
                .count

            return "\(dateRange) • \(workoutCount) workouts"
        }()

        StatusListRow(
            number: number,
            title: program.name,
            subtitle: subtitle,
            metadata: nil,
            statusText: statusText,
            statusColor: statusColor,
            action: {
                coordinator.navigateToProgram(id: program.id)
            }
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func nextWorkoutChip(for plan: Plan) -> some View {
        // Get all workouts from all programs in this plan
        let programs = LocalDataStore.shared.programs.values
            .filter { $0.planId == planId }

        let programIds = Set(programs.map { $0.id })

        let allWorkouts = LocalDataStore.shared.workouts.values
            .filter { programIds.contains($0.programId) }
            .sorted { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) }

        // Find next scheduled or in-progress workout
        if let nextWorkout = allWorkouts.first(where: {
            $0.status == .scheduled || $0.status == .inProgress
        }) {
            // v160: Check for active session to show "Continue" vs "Next"
            let hasActiveSession = LocalDataStore.shared.sessions.values.contains { session in
                session.workoutId == nextWorkout.id && session.status == .active
            }

            let message = hasActiveSession
                ? "Continue workout: \(nextWorkout.displayName)"
                : "Next workout: \(nextWorkout.displayName)"

            let iconName = hasActiveSession ? "play.circle.fill" : "calendar.circle.fill"

            Button(action: {
                // v163: Go directly to FocusedExecution for active sessions
                if hasActiveSession {
                    coordinator.enterFocusedExecution(workoutId: nextWorkout.id)
                } else {
                    coordinator.navigateToWorkout(id: nextWorkout.id)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)

                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color("PrimaryText"))

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color("SecondaryText"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - v49: Action Menu

    /// Build actions menu for plan toolbar
    @ViewBuilder
    private func planActionsMenu(for plan: Plan) -> some View {
        // Build entity descriptor
        let (statusText, _) = plan.status.statusInfo()
        let descriptor = EntityDescriptor(
            entityType: .plan,
            entityId: plan.id,
            status: statusText,
            userRole: .member,  // TODO: Get from UserContext when available
            parentContext: nil
        )

        // Get available actions
        let actions = EntityActionProvider.actions(for: descriptor)

        if !actions.isEmpty {
            Menu {
                ForEach(actions) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        Task {
                            let result = await actionCoordinator.execute(
                                actionType: action.type,
                                descriptor: descriptor,
                                context: .detailView,
                                navigationModel: navigationModel,
                                chatViewModel: nil
                            )

                            // Handle result
                            // Note: Success messages are now injected via notification in EntityActionCoordinator
                            // Navigation is also handled by EntityActionCoordinator
                            _ = result
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

    // Status helpers moved to shared StatusHelpers.swift

    // MARK: - v74.0: Plan Activation (Firebase API)

    /// Handle plan activation button tap - uses Firebase API
    private func handleActivatePlan(plan: Plan) {
        Task {
            await performPlanActivation()
        }
    }

    /// Perform plan activation via Firebase
    private func performPlanActivation() async {
        do {
            // Call Firebase API with confirmOverlap: true (auto-complete any overlapping plan)
            let response = try await FirebaseAPIClient.shared.activatePlan(planId: planId, confirmOverlap: true)

            if response.success {
                Logger.log(.info, component: "PlanDetailView",
                           message: "Plan activated via Firebase: \(planId)")

                // Refresh data from Firestore
                NotificationCenter.default.post(name: .planStatusDidChange, object: nil)
            } else {
                errorMessage = response.error ?? response.message ?? "Activation failed"
                showError = true
            }

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            Logger.log(.error, component: "PlanDetailView",
                       message: "Plan activation failed: \(error)")
        }
    }
}

// MARK: - Previews

#Preview("Fall 2025 Plan") {
    NavigationStack {
        PlanDetailView(planId: "plan_bobby_fall_2025")
            .environmentObject(NavigationModel())
    }
}
