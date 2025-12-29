//
// TempoInfoSheet.swift
// Medina
//
// v78.9: Simplified Tempo info sheet matching app design patterns
// Created: December 2025
// Purpose: Quick educational tooltip explaining Tempo concept
//

import SwiftUI

/// Compact sheet explaining Tempo notation
struct TempoInfoSheet: View {
    let tempo: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tempo \(tempo)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color("PrimaryText"))

                    Text("Movement Speed Control")
                        .font(.system(size: 14))
                        .foregroundColor(Color("SecondaryText"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Visual tempo breakdown - horizontal
                HStack(spacing: 0) {
                    tempoPhase(value: parts.eccentric, label: "Down", color: .blue)
                    tempoPhase(value: parts.bottomPause, label: "Pause", color: .purple)
                    tempoPhase(value: parts.concentric, label: "Up", color: .green)
                    tempoPhase(value: parts.topPause, label: "Hold", color: .orange)
                }
                .padding(4)
                .background(Color("BackgroundSecondary"))
                .cornerRadius(12)

                // X explanation if present
                if tempo.uppercased().contains("X") {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                        Text("\"X\" = explosive (fast as possible with control)")
                            .font(.system(size: 14))
                            .foregroundColor(Color("SecondaryText"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Simple tip
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "metronome")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                        .frame(width: 24)

                    Text("Count seconds in your head for each phase. Controlled tempo builds muscle and prevents injury.")
                        .font(.system(size: 15))
                        .foregroundColor(Color("PrimaryText"))
                        .lineSpacing(4)
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(10)

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
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Components

    private func tempoPhase(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(value.uppercased() == "X" ? .orange : color)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color("SecondaryText"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var parts: (eccentric: String, bottomPause: String, concentric: String, topPause: String) {
        let cleaned = tempo.replacingOccurrences(of: "-", with: "")
        let chars = Array(cleaned)

        return (
            eccentric: chars.count > 0 ? String(chars[0]) : "0",
            bottomPause: chars.count > 1 ? String(chars[1]) : "0",
            concentric: chars.count > 2 ? String(chars[2]) : "0",
            topPause: chars.count > 3 ? String(chars[3]) : "0"
        )
    }
}

// MARK: - Preview

#Preview("Tempo 2010") {
    TempoInfoSheet(tempo: "2010", onDismiss: {})
}

#Preview("Tempo 3110") {
    TempoInfoSheet(tempo: "3110", onDismiss: {})
}

#Preview("Tempo 30X0") {
    TempoInfoSheet(tempo: "30X0", onDismiss: {})
}
