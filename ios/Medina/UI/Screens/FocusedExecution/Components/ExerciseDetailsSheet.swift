//
// ExerciseDetailsSheet.swift
// Medina
//
// v76.0: Swipe-up sheet showing exercise details during focused execution
// v78.0: Added MuscleHeroView at top (moved from main execution view)
// v78.1: Refactored to use shared ExerciseInfoCard component
// Created: December 2025
// Purpose: Instructions, video link, muscles, and skip/substitute actions
//

import SwiftUI

/// Sheet showing exercise details with skip/substitute options
/// v78.1: Now uses ExerciseInfoCard for unified UX with ExerciseDetailView
/// v78.9: Added canSubstitute to disable substitution after sets logged
struct ExerciseDetailsSheet: View {
    let exercise: Exercise
    let instance: ExerciseInstance?
    let onSkip: () -> Void
    let onSubstitute: () -> Void

    /// v78.9: Whether substitution is allowed (disabled if sets already logged)
    var canSubstitute: Bool = true

    /// v78.9: Number of sets logged (for disabled message)
    var loggedSetCount: Int = 0

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                // v78.1: Use shared ExerciseInfoCard with workout-mode configuration
                // showMuscleHero: true (diagram at top with horizontal pills)
                // showActions: true (skip/substitute buttons)
                // No redundant musclesSection - MuscleHeroView pills handle this
                ExerciseInfoCard(
                    exercise: exercise,
                    showMuscleHero: true,
                    showUserStats: false,
                    showActions: true,
                    canSubstitute: canSubstitute,
                    substituteDisabledMessage: canSubstitute ? nil : "\(loggedSetCount) set\(loggedSetCount == 1 ? "" : "s") already logged",
                    onSkip: {
                        dismiss()
                        onSkip()
                    },
                    onSubstitute: {
                        dismiss()
                        onSubstitute()
                    }
                )
                .padding(20)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview("Exercise Details Sheet") {
    // Uses existing exercise from TestDataManager
    if let exercise = TestDataManager.shared.exercises["bench_press"] {
        ExerciseDetailsSheet(
            exercise: exercise,
            instance: nil,
            onSkip: { print("Skip") },
            onSubstitute: { print("Substitute") }
        )
    } else {
        Text("Exercise not found")
    }
}
