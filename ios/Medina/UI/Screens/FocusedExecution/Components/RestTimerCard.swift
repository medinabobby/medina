//
// RestTimerCard.swift
// Medina
//
// v78.4: Compact rest timer card for inline display
// Created: December 2025
// Purpose: Rest timer that replaces SetActionCard during rest periods
// Matches SetActionCard styling for consistent UX
//

import SwiftUI

/// Compact rest timer card that fits in SetActionCard's space
struct RestTimerCard: View {
    let endDate: Date
    let totalTime: TimeInterval
    let onAdjustRest: (Int) -> Void
    let onSkipRest: () -> Void
    let onTimerCompleted: () -> Void

    // v83.0: Optional next exercise preview for supersets
    var nextExerciseLabel: String? = nil
    var nextExerciseName: String? = nil

    @State private var hasAutoTransitioned = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = max(0, endDate.timeIntervalSince(context.date))
            let isExpired = remaining <= 0

            VStack(spacing: 16) {
                // Handle indicator (matches SetActionCard)
                handleIndicator

                // Rest label
                Text("Rest")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))

                // Large countdown time
                Text(formatTime(remaining))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(isExpired ? .green : Color("PrimaryText"))
                    .contentTransition(.numericText())

                // Horizontal progress bar
                progressBar(remaining: remaining)

                // v83.0: Next exercise preview for supersets
                if let label = nextExerciseLabel, let name = nextExerciseName {
                    HStack(spacing: 6) {
                        Text("Next:")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color("SecondaryText"))

                        Text(label)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.teal)

                        Text("- \(name)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color("SecondaryText"))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }

                // Adjustment buttons row
                adjustmentButtons

                // Skip button (matches LOG SET styling)
                skipButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color("CardBackground"))
                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: -5)
            )
            .onChange(of: isExpired) { expired in
                handleExpiration(expired: expired)
            }
        }
    }

    // MARK: - Subviews

    /// Drag handle indicator at top (matches SetActionCard)
    private var handleIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 36, height: 5)
    }

    /// Horizontal progress bar showing time remaining (drains as time passes)
    private func progressBar(remaining: TimeInterval) -> some View {
        // Progress represents time REMAINING (1.0 = full time, 0.0 = no time left)
        let progress = totalTime > 0 ? remaining / totalTime : 0

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                // Progress fill (drains as time runs out)
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressColor(remaining: remaining))
                    .frame(width: geo.size.width * CGFloat(min(1.0, max(0, progress))))
                    .animation(.linear(duration: 0.5), value: progress)
            }
        }
        .frame(height: 8)
        .padding(.horizontal, 20)
    }

    /// Color based on time remaining
    private func progressColor(remaining: TimeInterval) -> Color {
        if remaining <= 0 {
            return .green
        } else if remaining < 10 {
            return .orange
        } else {
            return .blue
        }
    }

    /// -10s and +10s adjustment buttons
    private var adjustmentButtons: some View {
        HStack(spacing: 12) {
            // -10s button
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                onAdjustRest(-10)
            }) {
                Text("-10s")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(12)
            }

            // +10s button
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                onAdjustRest(10)
            }) {
                Text("+10s")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(12)
            }
        }
    }

    /// Skip button (matches LOG SET button styling)
    private var skipButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onSkipRest()
        }) {
            Text("Skip")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(14)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func handleExpiration(expired: Bool) {
        guard expired && !hasAutoTransitioned else { return }
        hasAutoTransitioned = true

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Wait briefly to show completed state, then auto-transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            onTimerCompleted()
        }
    }
}

// MARK: - Preview

#Preview("Rest Timer Card") {
    ZStack {
        Color("Background")
            .ignoresSafeArea()

        VStack {
            Spacer()

            RestTimerCard(
                endDate: Date().addingTimeInterval(90),
                totalTime: 120,
                onAdjustRest: { seconds in print("Adjust by \(seconds)") },
                onSkipRest: { print("Skip rest") },
                onTimerCompleted: { print("Timer completed") }
            )
        }
    }
}

#Preview("Rest Timer Card - Low Time") {
    ZStack {
        Color("Background")
            .ignoresSafeArea()

        VStack {
            Spacer()

            RestTimerCard(
                endDate: Date().addingTimeInterval(8),
                totalTime: 60,
                onAdjustRest: { _ in },
                onSkipRest: { },
                onTimerCompleted: { }
            )
        }
    }
}
