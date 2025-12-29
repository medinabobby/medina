//
// RestTimerCardView.swift
// Medina
//
// v19.0: Rest timer countdown card with circular progress
// v28.3: Moved to Cards layer for better organization
// v54.0: Simplified to minimal full-screen overlay design
// v54.4: Updated colors for light background visibility (blue progress, dark text)
// Last reviewed: November 2025
//
// Minimal full-screen rest timer for solid background
//

import SwiftUI

struct RestTimerCardView: View {
    let sessionId: String
    let endDate: Date  // v19.0.1: Captured at creation time, immutable - no Session dependency
    let totalTime: TimeInterval
    let onAdjustRest: (Int) -> Void
    let onSkipRest: () -> Void
    let onTimerCompleted: () -> Void

    @State private var hasAutoTransitioned = false
    @State private var impactOccurred = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let currentRemaining = max(0, endDate.timeIntervalSince(context.date))
            let currentProgress = calculateProgress(remaining: currentRemaining)
            let currentIsExpired = currentRemaining <= 0

            VStack(spacing: 24) {
                Spacer()

                // Circular Timer Progress (no card background)
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                        .frame(width: 240, height: 240)

                    // Progress circle
                    Circle()
                        .trim(from: 0, to: currentProgress)
                        .stroke(timerColor(remaining: currentRemaining, expired: currentIsExpired),
                               style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 240, height: 240)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: timerColor(remaining: currentRemaining, expired: currentIsExpired).opacity(0.3),
                               radius: currentIsExpired ? 8 : 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentProgress)

                    // Time display
                    VStack(spacing: 6) {
                        Text(formatTime(currentRemaining))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(Color("PrimaryText"))
                            .contentTransition(.numericText())

                        if currentIsExpired {
                            Text("Time's up!")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.orange)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Text("remaining")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }
                }

                Spacer()
                    .frame(height: 40)

                // Action buttons (minimal style)
                HStack(spacing: 16) {
                    // -10s button
                    Button(action: {
                        onAdjustRest(-10)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "minus.circle")
                            Text("10s")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color("PrimaryText"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)
                    }

                    // +10s button
                    Button(action: {
                        onAdjustRest(10)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("10s")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color("PrimaryText"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)
                    }

                    // Skip button
                    Button(action: {
                        onSkipRest()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "forward.fill")
                            Text("Skip")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .onChange(of: currentIsExpired) { expired in
                guard expired && !hasAutoTransitioned else { return }

                // v19.0.1: Break re-entrancy - schedule state mutation after current render
                hasAutoTransitioned = true

                // Haptic feedback
                if !impactOccurred {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    impactOccurred = true
                }

                // Wait 1 second to show "Time's up!" message, then dispatch to next runloop
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    DispatchQueue.main.async {
                        onTimerCompleted()
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties & Helpers

    /// Calculate progress (0.0 to 1.0)
    private func calculateProgress(remaining: TimeInterval) -> CGFloat {
        guard totalTime > 0 else { return 0 }
        let elapsed = totalTime - remaining
        return min(1.0, max(0, CGFloat(elapsed / totalTime)))
    }

    /// Format time as M:SS
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Timer color based on remaining time
    private func timerColor(remaining: TimeInterval, expired: Bool) -> Color {
        if expired {
            return .green
        } else if remaining < 30 {
            return .orange
        } else {
            return .blue  // Match "Active" badge color
        }
    }
}
