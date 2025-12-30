//
// ProgramDetailView.swift
// Medina
//
// v46 Handler Refactor: Detail view pattern with collapsible sections, email-style cards
// v68.0: Added toolbar menu with "Activate Plan" action
// Created: November 2025
// Purpose: Program detail view showing metadata and workout cards
//

import SwiftUI

struct ProgramDetailView: View {
    let programId: String
    @EnvironmentObject private var navigationModel: NavigationModel

    @State private var showMetadata = true
    @State private var showWorkouts = true

    // v68.0: Plan activation state
    @State private var showActivationConfirmation = false
    @State private var activationOverlapPlan: Plan?
    @State private var activationSkippedCount: Int = 0
    @State private var errorMessage: String?
    @State private var showError = false

    private var coordinator: NavigationCoordinator {
        NavigationCoordinator(navigationModel: navigationModel)
    }

    // v68.0: Get the parent plan for this program
    private var parentPlan: Plan? {
        guard let program = LocalDataStore.shared.programs[programId] else {
            return nil
        }
        return LocalDataStore.shared.plans[program.planId]
    }

    // v68.0: Check if parent plan is draft
    private var isParentPlanDraft: Bool {
        parentPlan?.status == .draft
    }

    // MARK: - Main Content (extracted to help type checker)

    @ViewBuilder
    private var mainContent: some View {
        if let program = LocalDataStore.shared.programs[programId] {
            VStack(spacing: 0) {
                breadcrumbBar(for: program)
                heroSection(for: program)
                activatePlanBanner
                if parentPlan?.status == .active {
                    nextWorkoutChip(for: program)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
                programScrollContent(for: program)
            }
        } else {
            EmptyStateView(
                icon: "calendar",
                title: "Program Not Found",
                message: "The requested program could not be found."
            )
        }
    }

    @ViewBuilder
    private var activatePlanBanner: some View {
        if isParentPlanDraft {
            Button(action: { handleActivatePlan() }) {
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
    }

    @ViewBuilder
    private func programScrollContent(for program: Program) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DisclosureGroup("Program Details", isExpanded: $showMetadata) {
                    VStack(alignment: .leading, spacing: 12) {
                        programMetadataSection(for: program)
                    }
                    .padding(.top, 12)
                }
                .tint(Color("PrimaryText"))

                Divider().background(Color("BorderColor"))

                let workoutCount = LocalDataStore.shared.workouts.values
                    .filter { $0.programId == programId }
                    .count

                DisclosureGroup("Workouts in this Program (\(workoutCount))", isExpanded: $showWorkouts) {
                    VStack(alignment: .leading, spacing: 12) {
                        workoutsSection(for: program)
                    }
                    .padding(.top, 12)
                }
                .tint(Color("PrimaryText"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isParentPlanDraft {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        handleActivatePlan()
                    } label: {
                        Label("Activate Plan", systemImage: "play.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Color("PrimaryText"))
                }
            }
        }
    }

    var body: some View {
        mainContent
            .navigationTitle(LocalDataStore.shared.programs[programId]?.name ?? "Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .alert("Replace Active Plan?", isPresented: $showActivationConfirmation) {
                Button("Cancel", role: .cancel) {
                    activationOverlapPlan = nil
                    activationSkippedCount = 0
                }
                Button("Replace Plan", role: .destructive) {
                    Task { await performPlanActivation(planId: parentPlan?.id ?? "") }
                }
            } message: {
                if let overlapPlan = activationOverlapPlan {
                    Text("\"\(parentPlan?.name ?? "New Plan")\" will replace \"\(overlapPlan.name)\". \(overlapPlan.name) will be abandoned and \(activationSkippedCount) remaining \(activationSkippedCount == 1 ? "workout" : "workouts") will be marked as skipped.")
                }
            }
    }

    // MARK: - Section Builders

    @ViewBuilder
    private func breadcrumbBar(for program: Program) -> some View {
        var items: [BreadcrumbItem] = []

        // Add plan breadcrumb (tappable if exists)
        if let plan = LocalDataStore.shared.plans[program.planId] {
            items.append(BreadcrumbItem(label: "Plan") {
                coordinator.navigateToPlan(id: plan.id)
            })
        }

        // Add program breadcrumb (current, not tappable)
        items.append(BreadcrumbItem(label: "Program", action: nil))

        return BreadcrumbBar(items: items)
    }

    @ViewBuilder
    private func heroSection(for program: Program) -> some View {
        let (statusText, statusColor) = program.status.statusInfo()

        // Line 1: Date range + status badge
        let dateRange = "\(DateFormatters.shortMonthDayFormatter.string(from: program.startDate)) – \(DateFormatters.shortMonthDayFormatter.string(from: program.endDate))"

        // Line 2: Goal + Weekly sessions + duration (from parent plan)
        let line2: String = {
            if let plan = LocalDataStore.shared.plans[program.planId] {
                let totalSessions = plan.weightliftingDays + plan.cardioDays
                return "\(plan.goal.displayName) • \(totalSessions) days/week • \(plan.targetSessionDuration) min"
            }
            return ""
        }()

        HeroSection(
            line1Text: dateRange,
            statusText: statusText,
            statusColor: statusColor,
            line2Text: line2
        )
    }

    @ViewBuilder
    private func programMetadataSection(for program: Program) -> some View {
        // Get parent plan for inherited fields
        if let plan = LocalDataStore.shared.plans[program.planId] {
            // Split Type
            KeyValueRow(key: "Split Type", value: plan.splitType.displayName)

            // Compound
            let compoundPercent = Int(plan.compoundTimeAllocation * 100)
            KeyValueRow(key: "Compound", value: "\(compoundPercent)%")

            // Isolation
            KeyValueRow(key: "Isolation", value: plan.isolationApproach.displayName)
        }

        // Progression
        KeyValueRow(key: "Progression", value: program.progressionType.displayName)

        // Intensity
        let startPct = Int(program.startingIntensity * 100)
        let endPct = Int(program.endingIntensity * 100)
        KeyValueRow(key: "Intensity", value: "\(startPct)% → \(endPct)%")

        // Weekly Mix and Days (from parent plan)
        if let plan = LocalDataStore.shared.plans[program.planId] {
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
    }

    @ViewBuilder
    private func workoutsSection(for program: Program) -> some View {
        let workouts = LocalDataStore.shared.workouts.values
            .filter { $0.programId == programId }
            .sorted { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) }

        // v101.4: Build date suffix map for same-day workouts (A, B, C, etc.)
        let dateSuffixes = buildDateSuffixes(for: Array(workouts))

        ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
            workoutRow(for: workout, number: "\(index + 1)", dateSuffix: dateSuffixes[workout.id])
        }
    }

    /// v101.4: Build a map of workout ID → suffix (A, B, C) for same-day workouts
    private func buildDateSuffixes(for workouts: [Workout]) -> [String: String] {
        var suffixes: [String: String] = [:]

        // Group workouts by date (calendar day)
        let calendar = Calendar.current
        var dateGroups: [Date: [Workout]] = [:]

        for workout in workouts {
            if let date = workout.scheduledDate {
                let dayStart = calendar.startOfDay(for: date)
                dateGroups[dayStart, default: []].append(workout)
            }
        }

        // For dates with multiple workouts, assign suffixes A, B, C, etc.
        for (_, groupWorkouts) in dateGroups where groupWorkouts.count > 1 {
            // Sort by creation time (earlier workouts get earlier letters)
            let sorted = groupWorkouts.sorted { w1, w2 in
                // Use workout ID as proxy for creation order (UUIDs are time-based)
                w1.id < w2.id
            }

            for (index, workout) in sorted.enumerated() {
                let letter = String(UnicodeScalar("A".unicodeScalars.first!.value + UInt32(index))!)
                suffixes[workout.id] = letter
            }
        }

        return suffixes
    }

    /// v101.4: Added dateSuffix parameter for same-day workouts (A, B, C)
    /// v158: Check for active session to show blue regardless of original status
    @ViewBuilder
    private func workoutRow(for workout: Workout, number: String, dateSuffix: String? = nil) -> some View {
        // v158: Check for active session - if this workout has an active session, show blue
        let statusColor: Color = {
            let hasActiveSession = LocalDataStore.shared.sessions.values.contains { session in
                session.workoutId == workout.id && session.status == .active
            }
            if hasActiveSession {
                return .blue
            }
            return workout.status.statusInfo().1
        }()

        // Title: Day of week + Date ("Mon, Nov 3") + optional suffix for same-day workouts ("Wed, Dec 10 A")
        let title: String? = {
            if let date = workout.scheduledDate {
                let calendar = Calendar.current
                let dayOfWeekIndex = calendar.component(.weekday, from: date)
                let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let dayName = dayNames[dayOfWeekIndex - 1]
                let dateStr = DateFormatters.shortMonthDayFormatter.string(from: date)
                // v101.4: Add suffix (A, B, C) for same-day workouts
                if let suffix = dateSuffix {
                    return "\(dayName), \(dateStr) \(suffix)"
                }
                return "\(dayName), \(dateStr)"
            }
            return nil
        }()

        // v101.5: Subtitle - just type/split (no "0 exercises" - that's confusing)
        let subtitle: String = {
            if workout.type == .cardio {
                return "Cardio"
            } else {
                // Strength: show split day name, plus exercise count only if > 0
                var parts: [String] = []

                if let splitDay = workout.splitDay {
                    parts.append(splitDay.displayName)
                }

                // v101.5: Only show exercise count if exercises have been selected
                let exerciseCount = workout.exerciseIds.count
                if exerciseCount > 0 {
                    parts.append("\(exerciseCount) exercises")
                }

                return parts.joined(separator: " • ")
            }
        }()

        // v53.0 Phase 2: Removed calculateDuration (method doesn't exist on Workout model)
        // TODO: Implement workout duration estimation if needed
        let timeText: String? = nil

        StatusListRow(
            number: number,
            title: title,
            subtitle: subtitle,
            metadata: nil,
            statusText: nil,
            statusColor: statusColor,
            timeText: timeText,
            showChevron: true,
            action: {
                coordinator.navigateToWorkout(id: workout.id)
            }
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func nextWorkoutChip(for program: Program) -> some View {
        // Get all workouts in this program
        let workouts = LocalDataStore.shared.workouts.values
            .filter { $0.programId == programId }
            .sorted { ($0.scheduledDate ?? Date.distantPast) < ($1.scheduledDate ?? Date.distantPast) }

        // Find next scheduled or in-progress workout
        if let nextWorkout = workouts.first(where: {
            $0.status == .scheduled || $0.status == .inProgress
        }) {
            // v160: Check for active session to show "Continue" vs "Start"
            let hasActiveSession = LocalDataStore.shared.sessions.values.contains { session in
                session.workoutId == nextWorkout.id && session.status == .active
            }

            // v74.3: Format date like PlanDetailView ("Wed, Dec 3")
            let dateStr: String = {
                if let date = nextWorkout.scheduledDate {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEE, MMM d"
                    return formatter.string(from: date)
                }
                return nextWorkout.displayName
            }()

            let chipText = hasActiveSession
                ? "Continue Workout"
                : "Start Workout: \(dateStr)"

            let iconName = hasActiveSession ? "play.circle.fill" : "play.fill"

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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)

                    Text(chipText)
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

    // Status helpers moved to shared StatusHelpers.swift

    // MARK: - v68.0: Plan Activation (Firebase API)

    /// Handle plan activation button tap - uses Firebase API
    private func handleActivatePlan() {
        guard let plan = parentPlan else {
            errorMessage = "Unable to find plan for this program."
            showError = true
            return
        }

        Task {
            await performPlanActivation(planId: plan.id)
        }
    }

    /// Perform plan activation via Firebase
    private func performPlanActivation(planId: String) async {
        do {
            // Call Firebase API with confirmOverlap: true (auto-complete any overlapping plan)
            let response = try await FirebaseAPIClient.shared.activatePlan(planId: planId, confirmOverlap: true)

            if response.success {
                Logger.log(.info, component: "ProgramDetailView",
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
            Logger.log(.error, component: "ProgramDetailView",
                       message: "Plan activation failed: \(error)")
        }
    }
}

// MARK: - Previews

#Preview("Active Program") {
    NavigationStack {
        ProgramDetailView(programId: "prog_bobby_fall_2025_nov")
            .environmentObject(NavigationModel())
    }
}

#Preview("Completed Program") {
    NavigationStack {
        ProgramDetailView(programId: "prog_bobby_fall_2025_oct")
            .environmentObject(NavigationModel())
    }
}
