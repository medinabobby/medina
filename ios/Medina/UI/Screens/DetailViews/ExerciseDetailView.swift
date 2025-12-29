//
// ExerciseDetailView.swift
// Medina
//
// General exercise overview showing instructions, equipment, and muscle groups
// Created: November 2025
// v70.0: Added library toggle (star icon) for adding/removing from user's library
// v72.1: Added "Your Stats" section showing 1RM, history, and working weight suggestions
// v72.4: Round working weights to 5 lbs, show experience level, add YouTube tutorial link
// v72.4: Added estimated 1RM from equivalent exercises (barbell → dumbbell conversion)
// v78.1: Refactored to use shared ExerciseInfoCard for unified UX
// v79.3: Added empty state for uncalibrated exercises + 1RM edit capability
// v79.4: Added ExerciseHeaderView with tappable equipment badge for variant navigation
//
// Purpose: Shows educational exercise information without workout context
//

import SwiftUI

struct ExerciseDetailView: View {
    let exerciseId: String
    let userId: String

    @State private var isInLibrary: Bool = false
    @State private var showOneRMEditSheet = false  // v79.3: 1RM edit sheet
    @State private var showEquipmentVariants = false  // v79.4: Equipment variants sheet
    @State private var refreshTrigger = UUID()      // v79.3: Force refresh after edit
    @EnvironmentObject private var navigationModel: NavigationModel  // v79.4: For variant navigation

    init(exerciseId: String, userId: String? = nil) {
        self.exerciseId = exerciseId
        self.userId = userId ?? TestDataManager.shared.currentUserId ?? "bobby"
    }

    // v72.1: Get user's ExerciseTarget for this exercise
    private var target: ExerciseTarget? {
        let targetId = "\(userId)-\(exerciseId)"
        return TestDataManager.shared.targets[targetId]
    }

    /// v79.4: Check if exercise has equipment variants for swapping
    private var hasEquipmentVariants: Bool {
        guard let exercise = TestDataManager.shared.exercises[exerciseId] else { return false }
        return ExerciseDataStore.alternateEquipmentVariants(for: exercise).count > 0
    }

    /// v91.1: Stats section label - "YOUR STATS" when viewing own data, "BOBBY'S STATS" when viewing member
    private var statsLabelText: String {
        if userId == TestDataManager.shared.currentUserId {
            return "YOUR STATS"
        }
        guard let user = TestDataManager.shared.users[userId] else {
            return "MEMBER STATS"
        }
        return "\(user.firstName.uppercased())'S STATS"
    }

    var body: some View {
        Group {
            if let exercise = TestDataManager.shared.exercises[exerciseId] {
                // Scrollable content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // v79.4: Exercise header with name + tappable equipment badge
                        ExerciseHeaderView(
                            exercise: exercise,
                            size: .large,
                            alignment: .center,
                            equipmentTappable: hasEquipmentVariants,
                            onEquipmentTap: hasEquipmentVariants ? { showEquipmentVariants = true } : nil
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        // v72.1: Show user's stats first if available
                        yourStatsSection

                        // v79.1: Use shared ExerciseInfoCard with muscle diagram
                        // showMuscleHero: true (matches workout sheet with muscle diagram)
                        // showUserStats: false (handled separately above with history)
                        // v79.4: showEquipment: false (equipment now shown in header)
                        // showActions: false (no skip/substitute in sidebar)
                        ExerciseInfoCard(
                            exercise: exercise,
                            showMuscleHero: true,
                            showUserStats: false,
                            showEquipment: false,
                            showActions: false,
                            userId: userId
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            } else {
                EmptyStateView(
                    icon: "figure.strengthtraining.traditional",
                    title: "Exercise Not Found",
                    message: "The requested exercise could not be found."
                )
            }
        }
        .navigationTitle(TestDataManager.shared.exercises[exerciseId]?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                libraryToggleButton
            }
        }
        .onAppear {
            isInLibrary = LibraryPersistenceService.isExerciseInLibrary(exerciseId, userId: userId)
        }
        .sheet(isPresented: $showOneRMEditSheet) {
            // v79.3: 1RM edit sheet
            if let exercise = TestDataManager.shared.exercises[exerciseId] {
                OneRMEditSheet(
                    exercise: exercise,
                    userId: userId,
                    existingTarget: target,
                    onSave: { _ in
                        showOneRMEditSheet = false
                        refreshTrigger = UUID()  // Force refresh
                    },
                    onDismiss: {
                        showOneRMEditSheet = false
                    }
                )
            }
        }
        .sheet(isPresented: $showEquipmentVariants) {
            // v79.4: Equipment variants sheet for library navigation
            if let exercise = TestDataManager.shared.exercises[exerciseId] {
                LibraryEquipmentSheet(
                    currentExercise: exercise,
                    onSelect: { variantId in
                        showEquipmentVariants = false
                        // Navigate to the variant's detail view
                        navigationModel.navigateToExercise(variantId)
                    }
                )
            }
        }
        .id(refreshTrigger)  // v79.3: Force view refresh when target changes
    }

    // MARK: - Your Stats Section (v72.1, v72.4 estimated support)

    /// v72.4: Get estimated 1RM from equivalent exercises if no direct target
    private var estimatedTarget: EquivalentExerciseEstimator.EstimatedTarget? {
        // Only estimate if no direct target exists
        guard target?.currentTarget == nil else { return nil }
        return EquivalentExerciseEstimator.estimate1RM(for: exerciseId, userId: userId)
    }

    @ViewBuilder
    private var yourStatsSection: some View {
        if let target = target, let max = target.currentTarget {
            // Direct 1RM exists
            directStatsSection(max: max, target: target)
        } else if let estimate = estimatedTarget {
            // v72.4: Show estimated 1RM from equivalent exercise
            estimatedStatsSection(estimate: estimate)
        } else {
            // v79.3: Empty state - no 1RM data
            emptyStatsSection
        }
    }

    // MARK: - Empty Stats Section (v79.3)

    /// v79.3: Empty state when no 1RM data exists - shows "Add 1RM" and "Ask Medina" buttons
    @ViewBuilder
    private var emptyStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header (v91.1: Show member name when viewing member's stats)
            Text(statsLabelText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("SecondaryText"))

            // Empty state card
            VStack(spacing: 16) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 36))
                    .foregroundColor(Color("SecondaryText").opacity(0.5))

                Text("No 1RM Data Yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))

                Text("Add your one-rep max to get personalized weight suggestions")
                    .font(.system(size: 14))
                    .foregroundColor(Color("SecondaryText"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                // Action buttons
                HStack(spacing: 12) {
                    // Add 1RM button
                    Button(action: { showOneRMEditSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("Add 1RM")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }

                    // Ask Medina button
                    Button(action: navigateToChat) {
                        HStack(spacing: 6) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 14))
                            Text("Ask Medina")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)
        }
    }

    /// Navigate to chat for AI-guided calibration
    private func navigateToChat() {
        // Post notification to navigate to chat tab
        NotificationCenter.default.post(
            name: NSNotification.Name("NavigateToChat"),
            object: nil
        )
    }

    /// Stats section when user has direct 1RM for this exercise
    @ViewBuilder
    private func directStatsSection(max: Double, target: ExerciseTarget) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header with edit button (v91.1: Show member name when viewing member's stats)
            HStack {
                Text(statsLabelText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color("SecondaryText"))

                Spacer()

                // v79.3: Edit button
                Button(action: { showOneRMEditSheet = true }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color("SecondaryText"))
                }
            }

            // 1RM Card
            VStack(alignment: .leading, spacing: 12) {
                // 1RM row
                HStack {
                    Text("1RM (One Rep Max)")
                        .font(.system(size: 15))
                        .foregroundColor(Color("PrimaryText"))
                    Spacer()
                    Text("\(Int(max)) lbs")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color("AccentBlue"))
                }

                // Last updated
                if let date = target.lastCalibrated {
                    HStack {
                        Text("Last Updated")
                            .font(.system(size: 14))
                            .foregroundColor(Color("SecondaryText"))
                        Spacer()
                        Text(date, style: .date)
                            .font(.system(size: 14))
                            .foregroundColor(Color("SecondaryText"))
                    }
                }

                // Source (if from history)
                if let lastEntry = target.targetHistory.last {
                    HStack {
                        Text("Source")
                            .font(.system(size: 14))
                            .foregroundColor(Color("SecondaryText"))
                        Spacer()
                        Text(formatCalibrationSource(lastEntry.calibrationSource))
                            .font(.system(size: 14))
                            .foregroundColor(Color("SecondaryText"))
                    }
                }
            }
            .padding(16)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)

            // Working weight suggestions
            workingWeightSuggestions(max: max, isEstimate: false)

            // History (if more than 1 entry)
            if target.targetHistory.count > 1 {
                historySection(entries: target.targetHistory)
            }
        }
    }

    /// v72.4: Stats section when showing estimated 1RM from equivalent exercise
    @ViewBuilder
    private func estimatedStatsSection(estimate: EquivalentExerciseEstimator.EstimatedTarget) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text("ESTIMATED STATS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("SecondaryText"))

            // Estimated 1RM Card
            VStack(alignment: .leading, spacing: 12) {
                // Estimated 1RM row
                HStack {
                    Text("Est. 1RM")
                        .font(.system(size: 15))
                        .foregroundColor(Color("PrimaryText"))
                    Spacer()
                    HStack(spacing: 4) {
                        Text("~\(Int(estimate.estimated1RM)) lbs")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color.orange)
                    }
                }

                // Source explanation
                HStack {
                    Text("Source")
                        .font(.system(size: 14))
                        .foregroundColor(Color("SecondaryText"))
                    Spacer()
                    Text("Estimated")
                        .font(.system(size: 14))
                        .foregroundColor(Color("SecondaryText"))
                }

                // Based on which exercise
                HStack {
                    Text("Based on")
                        .font(.system(size: 14))
                        .foregroundColor(Color("SecondaryText"))
                    Spacer()
                    Text("\(estimate.sourceExerciseName) (\(Int(estimate.source1RM)) lbs)")
                        .font(.system(size: 14))
                        .foregroundColor(Color("SecondaryText"))
                        .lineLimit(1)
                }
            }
            .padding(16)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)

            // Working weight suggestions (with estimate flag)
            workingWeightSuggestions(max: estimate.estimated1RM, isEstimate: true)

            // Confidence note
            Text("Weights are estimated based on your \(estimate.sourceExerciseName) 1RM. Adjust as needed.")
                .font(.system(size: 12))
                .foregroundColor(Color("SecondaryText").opacity(0.7))
        }
    }

    // MARK: - Working Weight Suggestions

    @ViewBuilder
    private func workingWeightSuggestions(max: Double, isEstimate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUGGESTED WORKING WEIGHTS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("SecondaryText"))

            HStack(spacing: 12) {
                workingWeightPill(percentage: 0.65, max: max, label: "Light", isEstimate: isEstimate)
                workingWeightPill(percentage: 0.75, max: max, label: "Moderate", isEstimate: isEstimate)
                workingWeightPill(percentage: 0.85, max: max, label: "Heavy", isEstimate: isEstimate)
            }

            let baseText = isEstimate ? "Based on estimated 1RM of ~\(Int(max)) lbs" : "Based on your 1RM of \(Int(max)) lbs"
            Text(baseText)
                .font(.system(size: 12))
                .foregroundColor(Color("SecondaryText").opacity(0.7))
        }
    }

    /// Round weight to nearest 5 lbs (standard plate increments)
    private func roundToPlate(_ weight: Double) -> Int {
        return Int((weight / 5.0).rounded() * 5)
    }

    private func workingWeightPill(percentage: Double, max: Double, label: String, isEstimate: Bool = false) -> some View {
        let rawWeight = max * percentage
        let weight = roundToPlate(rawWeight)
        return VStack(spacing: 4) {
            Text(isEstimate ? "~\(weight)" : "\(weight)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isEstimate ? Color.orange : Color("PrimaryText"))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color("SecondaryText"))
            Text("\(Int(percentage * 100))%")
                .font(.system(size: 10))
                .foregroundColor(Color("SecondaryText").opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color("BackgroundSecondary"))
        .cornerRadius(10)
    }

    // MARK: - History Section

    @ViewBuilder
    private func historySection(entries: [ExerciseTarget.TargetEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HISTORY")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("SecondaryText"))

            VStack(spacing: 8) {
                // Show last 5 entries (most recent first)
                ForEach(entries.suffix(5).reversed(), id: \.date) { entry in
                    HStack {
                        Text(entry.date, style: .date)
                            .font(.system(size: 14))
                            .foregroundColor(Color("SecondaryText"))
                        Spacer()
                        Text("\(Int(entry.target)) lbs")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color("PrimaryText"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color("BackgroundSecondary"))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatCalibrationSource(_ source: String) -> String {
        switch source {
        case "manual_import": return "Manual Entry"
        case "chat_input": return "Chat"
        case "workout": return "Workout"
        default: return source.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Library Toggle (v70.0, v71.0 styling)

    private var libraryToggleButton: some View {
        Button(action: toggleLibrary) {
            Image(systemName: isInLibrary ? "star.fill" : "star")
                .foregroundColor(isInLibrary ? Color("AccentBlue") : Color("SecondaryText"))
                .font(.system(size: 18))
        }
        .accessibilityLabel(isInLibrary ? "Remove from library" : "Add to library")
    }

    private func toggleLibrary() {
        do {
            if isInLibrary {
                try LibraryPersistenceService.removeExercise(exerciseId, userId: userId)
                isInLibrary = false
                Logger.log(.info, component: "ExerciseDetailView",
                           message: "Removed \(exerciseId) from library")
            } else {
                try LibraryPersistenceService.addExercise(exerciseId, userId: userId)
                isInLibrary = true
                Logger.log(.info, component: "ExerciseDetailView",
                           message: "Added \(exerciseId) to library")
            }
        } catch {
            Logger.log(.error, component: "ExerciseDetailView",
                       message: "Failed to toggle library: \(error)")
        }
    }

    // v78.1: Removed exerciseInfoSection and videoSearchSection
    // These are now handled by ExerciseInfoCard shared component
}

// MARK: - Previews

#Preview("Exercise Overview") {
    NavigationStack {
        ExerciseDetailView(exerciseId: "barbell_back_squat")
        .environmentObject(NavigationModel())
    }
}
