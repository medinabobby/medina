//
// ExerciseProgressHeader.swift
// Medina
//
// v76.0: Progress header showing exercise position in workout
// Created: December 2025
// Purpose: "Exercise 2 of 5" header with back button integration
//

import SwiftUI

/// Header showing current exercise position in workout
struct ExerciseProgressHeader: View {
    let exerciseNumber: Int
    let totalExercises: Int
    let workoutName: String
    let onBack: () -> Void
    let onMenu: () -> Void

    // v83.0: Optional superset label (e.g., "1a", "1b")
    var supersetLabel: String? = nil

    /// Display text for exercise position (uses superset label if available)
    private var exercisePositionText: String {
        if let label = supersetLabel {
            return "Exercise \(label) of \(totalExercises)"
        } else {
            return "Exercise \(exerciseNumber) of \(totalExercises)"
        }
    }

    var body: some View {
        HStack {
            // v78.8: Exit button (X instead of Back)
            Button(action: onBack) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))
            }

            Spacer()

            // Exercise counter
            VStack(spacing: 2) {
                Text(exercisePositionText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))

                // Progress dots
                progressDots
            }

            Spacer()

            // Menu button
            Button(action: onMenu) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color("Background"))
    }

    /// Visual progress dots
    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(1...totalExercises, id: \.self) { index in
                Circle()
                    .fill(index <= exerciseNumber ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Preview

#Preview("Exercise Progress Header") {
    VStack {
        ExerciseProgressHeader(
            exerciseNumber: 2,
            totalExercises: 5,
            workoutName: "Push Day",
            onBack: { print("Back") },
            onMenu: { print("Menu") }
        )

        Spacer()
    }
    .background(Color("Background"))
}

#Preview("Last Exercise") {
    VStack {
        ExerciseProgressHeader(
            exerciseNumber: 5,
            totalExercises: 5,
            workoutName: "Push Day",
            onBack: { print("Back") },
            onMenu: { print("Menu") }
        )

        Spacer()
    }
    .background(Color("Background"))
}
