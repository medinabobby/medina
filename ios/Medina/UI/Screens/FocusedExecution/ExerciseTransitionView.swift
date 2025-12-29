//
// ExerciseTransitionView.swift
// Medina
//
// v95.0: Transition screen shown between exercises
// Provides natural timing for exercise announcements
//

import SwiftUI

/// Transition screen shown between exercises
///
/// **Purpose:**
/// Shows "Up Next" preview before loading exercise details.
/// Allows voice announcement to complete before showing exercise.
///
/// **Display:**
/// - "Up Next" label
/// - Exercise name
/// - Equipment badge
/// - Target sets/reps
/// - Brief countdown/progress indicator
struct ExerciseTransitionView: View {
    let exerciseName: String
    let exerciseNumber: Int
    let totalExercises: Int
    let equipment: Equipment?
    let targetSets: Int
    let targetReps: Int?
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var progress: Double = 0
    @State private var isAnimating = false

    /// Duration before auto-advancing (matches voice exercise intro)
    private let transitionDuration: Double = 2.5

    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            HStack {
                Text("Exercise \(exerciseNumber) of \(totalExercises)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))

                Spacer()

                // Skip button
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer()

            // "Up Next" label with animation
            VStack(spacing: 8) {
                Text("UP NEXT")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color("SecondaryText"))
                    .tracking(2)

                // Arrow animation
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.blue)
                    .offset(y: isAnimating ? 4 : 0)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }

            // Exercise name
            Text(exerciseName)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(Color("PrimaryText"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Equipment badge (if not bodyweight)
            if let equipment = equipment, equipment != .bodyweight {
                Text(equipment.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
            }

            // Target sets/reps
            HStack(spacing: 16) {
                // Sets
                VStack(spacing: 4) {
                    Text("\(targetSets)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color("PrimaryText"))
                    Text("sets")
                        .font(.system(size: 14))
                        .foregroundColor(Color("SecondaryText"))
                }

                // Divider
                Rectangle()
                    .fill(Color("CardBackground"))
                    .frame(width: 1, height: 40)

                // Reps
                if let reps = targetReps {
                    VStack(spacing: 4) {
                        Text("\(reps)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color("PrimaryText"))
                        Text("reps")
                            .font(.system(size: 14))
                            .foregroundColor(Color("SecondaryText"))
                    }
                }
            }
            .padding(.top, 12)

            Spacer()

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color("CardBackground"))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Background").ignoresSafeArea())
        .onAppear {
            startTransition()
        }
    }

    private func startTransition() {
        isAnimating = true

        // Animate progress bar
        withAnimation(.linear(duration: transitionDuration)) {
            progress = 1.0
        }

        // Auto-advance after transition duration
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
            onComplete()
        }
    }
}

// MARK: - Preview

#Preview("Exercise Transition") {
    ExerciseTransitionView(
        exerciseName: "Barbell Bench Press",
        exerciseNumber: 2,
        totalExercises: 6,
        equipment: .barbell,
        targetSets: 4,
        targetReps: 8,
        onComplete: { print("Transition complete") },
        onSkip: { print("Skipped") }
    )
}
