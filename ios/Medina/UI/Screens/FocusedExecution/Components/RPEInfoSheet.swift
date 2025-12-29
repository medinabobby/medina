//
// RPEInfoSheet.swift
// Medina
//
// v78.9: Simplified RPE info sheet matching app design patterns
// Created: December 2025
// Purpose: Quick educational tooltip explaining RPE concept
//

import SwiftUI

/// Compact sheet explaining RPE (Rate of Perceived Exertion)
struct RPEInfoSheet: View {
    let rpe: Double
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            VStack(spacing: 20) {
                // Header with value and intensity badge
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RPE \(Int(rpe))")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Color("PrimaryText"))

                        Text("Rate of Perceived Exertion")
                            .font(.system(size: 14))
                            .foregroundColor(Color("SecondaryText"))
                    }

                    Spacer()

                    // Intensity badge
                    Text(intensityLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(intensityColor)
                        .cornerRadius(16)
                }

                // Simple explanation
                VStack(alignment: .leading, spacing: 12) {
                    Text("RPE measures how hard a set feels based on reps you have \"left in the tank.\"")
                        .font(.system(size: 15))
                        .foregroundColor(Color("PrimaryText"))
                        .lineSpacing(4)

                    // What it means for this workout
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "target")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        Text("Finish each set feeling like you could do **\(repsInReserve) more rep\(repsInReserve == 1 ? "" : "s")** with good form.")
                            .font(.system(size: 15))
                            .foregroundColor(Color("PrimaryText"))
                            .lineSpacing(4)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(10)
                }

                // Done button
                Button(action: onDismiss) {
                    Text("Got it")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
            .padding(20)
        }
        .background(Color("Background"))
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private var repsInReserve: Int {
        max(0, 10 - Int(rpe))
    }

    private var intensityLabel: String {
        switch rpe {
        case 9...10: return "Max Effort"
        case 8..<9: return "Very Hard"
        case 7..<8: return "Hard"
        case 6..<7: return "Moderate"
        default: return "Light"
        }
    }

    private var intensityColor: Color {
        switch rpe {
        case 9...10: return .red
        case 8..<9: return .orange
        case 7..<8: return Color.orange.opacity(0.8)
        case 6..<7: return .green
        default: return .blue
        }
    }
}

// MARK: - Preview

#Preview("RPE 7") {
    RPEInfoSheet(rpe: 7, onDismiss: {})
}

#Preview("RPE 9") {
    RPEInfoSheet(rpe: 9, onDismiss: {})
}
