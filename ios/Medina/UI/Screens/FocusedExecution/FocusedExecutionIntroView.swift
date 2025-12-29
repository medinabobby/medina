//
// FocusedExecutionIntroView.swift
// Medina
//
// v95.0: Workout intro screen shown before first exercise
// v95.1: Optimized for template-based voice (fast, ~200ms TTS)
// v97: Voice-synchronized intro - waits for GPT voice to complete
//
// Now uses voice completion signal instead of fixed timer.
// Shows spinner until GPT-powered intro finishes speaking.
//

import SwiftUI

/// v97: Workout intro screen that waits for voice completion
///
/// **Purpose:**
/// Shows workout info while GPT-powered voice intro plays.
/// Transitions to first exercise ONLY after voice completes.
///
/// **v97 Voice-Synchronized Flow:**
/// 1. Screen appears with spinner and "Starting workout..."
/// 2. GPT generates personalized intro (~1-2s)
/// 3. Voice speaks the intro (~2-3s)
/// 4. isVoiceComplete becomes true
/// 5. Brief delay (0.5s), then onComplete() fires
///
/// **Fallback:**
/// If voice doesn't complete in 8s, transitions anyway to prevent hang.
///
/// **Display:**
/// - Workout name
/// - Split day type (Push, Pull, Legs, etc.)
/// - Total exercise count
/// - Spinner with "Starting workout..." text
struct FocusedExecutionIntroView: View {
    let workoutName: String
    let splitDay: SplitDay?
    let totalExercises: Int
    let onComplete: () -> Void

    /// v97: Voice completion signal from ViewModel
    @Binding var isVoiceComplete: Bool

    @State private var isAnimating = false
    @State private var hasTransitioned = false

    /// v97: Fallback timeout if voice doesn't complete
    private let fallbackTimeout: Double = 8.0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Workout icon with pulse animation
            ZStack {
                // Pulsing background
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )

                // Icon
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundColor(.blue)
            }

            // Workout info
            VStack(spacing: 12) {
                // Workout name
                Text(workoutName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color("PrimaryText"))
                    .multilineTextAlignment(.center)

                // Split day badge
                if let splitDay = splitDay {
                    Text(splitDay.displayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(splitDay.color)
                        .cornerRadius(12)
                }

                // Exercise count
                Text("\(totalExercises) exercises")
                    .font(.system(size: 17))
                    .foregroundColor(Color("SecondaryText"))
            }

            Spacer()

            // v97: Spinner instead of progress bar
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(1.2)

                Text("Starting workout...")
                    .font(.system(size: 15))
                    .foregroundColor(Color("SecondaryText"))
            }
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Background").ignoresSafeArea())
        .onAppear {
            startIntro()
        }
        .onChange(of: isVoiceComplete) { complete in
            if complete {
                transitionToExercise()
            }
        }
    }

    private func startIntro() {
        isAnimating = true

        // v97: Fallback timeout - if voice doesn't complete in 8s, transition anyway
        DispatchQueue.main.asyncAfter(deadline: .now() + fallbackTimeout) {
            if !hasTransitioned {
                Logger.log(.warning, component: "FocusedExecutionIntroView",
                          message: "v97: Fallback timeout triggered after \(fallbackTimeout)s")
                transitionToExercise()
            }
        }
    }

    /// v97: Transition to first exercise with brief delay
    private func transitionToExercise() {
        guard !hasTransitioned else { return }
        hasTransitioned = true

        // Brief delay after voice completes for natural pacing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onComplete()
        }
    }
}

// MARK: - Split Day Color Extension

private extension SplitDay {
    var color: Color {
        switch self {
        case .push: return .orange
        case .pull: return .blue
        case .legs: return .green
        case .chest: return .red
        case .back: return .indigo
        case .shoulders: return .purple
        case .arms: return .cyan
        case .fullBody: return .teal
        case .upper: return .orange
        case .lower: return .green
        case .notApplicable: return .gray
        }
    }
}

// MARK: - Preview

#Preview("Workout Intro") {
    FocusedExecutionIntroView(
        workoutName: "Push Day A",
        splitDay: .push,
        totalExercises: 6,
        onComplete: { print("Intro complete") },
        isVoiceComplete: .constant(false)
    )
}
