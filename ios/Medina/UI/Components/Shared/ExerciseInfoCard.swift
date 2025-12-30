//
// ExerciseInfoCard.swift
// Medina
//
// v78.1: Shared component for exercise details display
// Created: December 2025
// Purpose: Unified exercise information UI used by both ExerciseDetailView and ExerciseDetailsSheet
//

import SwiftUI

/// Shared exercise information component with configurable sections
/// Used by ExerciseDetailView (sidebar) and ExerciseDetailsSheet (workout)
struct ExerciseInfoCard: View {
    let exercise: Exercise

    /// Whether to show MuscleHeroView (workout sheet shows it, sidebar doesn't)
    var showMuscleHero: Bool = false

    /// Whether to show user stats (sidebar shows it, workout sheet doesn't)
    var showUserStats: Bool = false

    /// v79.3: Whether to show equipment section (false when ExerciseHeaderView handles it)
    var showEquipment: Bool = true

    /// Whether to show skip/substitute actions (workout sheet shows it, sidebar doesn't)
    var showActions: Bool = false

    /// v78.9: Whether substitution is allowed (disabled if sets already logged)
    var canSubstitute: Bool = true

    /// v78.9: Message to show when substitution is disabled
    var substituteDisabledMessage: String? = nil

    /// Optional userId for stats lookup
    var userId: String? = nil

    /// Callbacks for actions
    var onSkip: (() -> Void)? = nil
    var onSubstitute: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Muscle diagram (only for workout sheet)
            if showMuscleHero && !exercise.muscleGroups.isEmpty {
                MuscleHeroView(
                    muscles: exercise.muscleGroups,
                    primaryMuscle: exercise.muscleGroups.first
                )
                .frame(maxWidth: .infinity)
            }

            // Video tutorial (standardized blue)
            videoSection

            // Instructions
            if !exercise.instructions.isEmpty {
                instructionsSection
            }

            // Equipment (v79.3: optionally hide when ExerciseHeaderView shows it)
            if showEquipment {
                equipmentSection
            }

            // Difficulty/Level
            levelSection

            // v87.0: Movement Pattern (if available)
            if exercise.movementPattern != nil {
                movementPatternSection
            }

            // Muscles text (only for sidebar - sheet has MuscleHeroView)
            if !showMuscleHero {
                musclesTextSection
            }

            // Actions (only for workout sheet)
            if showActions {
                Divider()
                    .padding(.vertical, 8)
                actionsSection
            }
        }
    }

    // MARK: - Video Section (Standardized Blue)

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("LEARN THIS EXERCISE")

            Button(action: openVideoSearch) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color("AccentBlue").opacity(0.1))
                            .frame(width: 50, height: 50)

                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color("AccentBlue"))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch Tutorial")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color("PrimaryText"))

                        Text("Opens YouTube search")
                            .font(.system(size: 13))
                            .foregroundColor(Color("SecondaryText"))
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color("SecondaryText"))
                }
                .padding(12)
                .background(Color("BackgroundSecondary"))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("INSTRUCTIONS")

            Text(exercise.instructions)
                .font(.system(size: 15))
                .foregroundColor(Color("PrimaryText"))
                .lineSpacing(4)
        }
    }

    // MARK: - Equipment Section

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("EQUIPMENT")

            HStack(spacing: 12) {
                Image(systemName: equipmentIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 32)

                Text(exercise.equipment.displayName)
                    .font(.system(size: 15))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()
            }
            .padding(12)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)
        }
    }

    // MARK: - Level Section

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("DIFFICULTY")

            HStack(spacing: 12) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                    .frame(width: 32)

                Text(exercise.experienceLevel.displayName)
                    .font(.system(size: 15))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()
            }
            .padding(12)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)
        }
    }

    // MARK: - v87.0: Movement Pattern Section

    private var movementPatternSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("MOVEMENT PATTERN")

            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.functional")
                    .font(.system(size: 20))
                    .foregroundColor(.purple)
                    .frame(width: 32)

                Text(exercise.movementPattern?.displayName ?? "Unknown")
                    .font(.system(size: 15))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()
            }
            .padding(12)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)
        }
    }

    // MARK: - Muscles Text Section (for sidebar only)

    private var musclesTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("MUSCLES WORKED")

            VStack(alignment: .leading, spacing: 8) {
                if let primary = exercise.primaryMuscle {
                    HStack(spacing: 8) {
                        Text(primary.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color("PrimaryText"))

                        Text("Primary")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color("SecondaryText"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                if !exercise.secondaryMuscles.isEmpty {
                    Text(exercise.secondaryMuscles.map { $0.displayName }.joined(separator: ", "))
                        .font(.system(size: 14))
                        .foregroundColor(Color("SecondaryText"))
                }
            }
            .padding(12)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)
        }
    }

    // MARK: - Actions Section (for workout sheet only)

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Skip button
            Button(action: { onSkip?() }) {
                HStack {
                    Image(systemName: "forward.fill")
                    Text("Skip This Exercise")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }

            // v78.9: Substitute button - disabled if sets logged
            if canSubstitute {
                Button(action: { onSubstitute?() }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Substitute Exercise")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            } else {
                // v78.9: Show disabled state with message
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Substitute Exercise")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color("SecondaryText").opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)

                    if let message = substituteDisabledMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(Color("SecondaryText"))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color("SecondaryText"))
    }

    private var equipmentIcon: String {
        switch exercise.equipment {
        case .barbell:
            return "figure.strengthtraining.traditional"
        case .dumbbells:
            return "dumbbell"
        case .cableMachine, .machine:
            return "gearshape.2"
        case .bodyweight:
            return "figure.walk"
        case .kettlebell:
            return "scalemass"
        case .resistanceBand:
            return "arrow.left.arrow.right"
        default:
            return "figure.strengthtraining.traditional"
        }
    }

    private func openVideoSearch() {
        let searchQuery = "\(exercise.name) tutorial form"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let youtubeUrl = "https://www.youtube.com/results?search_query=\(searchQuery)"

        if let url = URL(string: youtubeUrl) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview("Exercise Info Card - Sheet Mode") {
    ScrollView {
        if let exercise = LocalDataStore.shared.exercises["bench_press"] {
            ExerciseInfoCard(
                exercise: exercise,
                showMuscleHero: true,
                showActions: true,
                onSkip: { print("Skip") },
                onSubstitute: { print("Substitute") }
            )
            .padding(20)
        }
    }
}

#Preview("Exercise Info Card - Sidebar Mode") {
    ScrollView {
        if let exercise = LocalDataStore.shared.exercises["bench_press"] {
            ExerciseInfoCard(
                exercise: exercise,
                showMuscleHero: false,
                showUserStats: true
            )
            .padding(20)
        }
    }
}
