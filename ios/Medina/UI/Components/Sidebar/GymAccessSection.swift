//
// GymAccessSection.swift
// Medina
//
// v194: District Demo Prep - Kisi door unlock preview
// Shows compact card grid matching Kisi app style
// Demo-only: Tap shows "Coming Soon" alert
//

import SwiftUI

/// Sidebar section for Kisi door unlock preview
/// Reference: Optix + Zap Fitness integrations use "Tap in-app" buttons
struct GymAccessSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "lock.open")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Text("DISTRICT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)

                Spacer()
            }
            .padding(.horizontal, 20)

            // Door cards (compact grid)
            HStack(spacing: 10) {
                DoorUnlockCard(name: "Main Gym")
                DoorUnlockCard(name: "Studio")
            }
            .padding(.horizontal, 20)

            // Kisi attribution
            HStack {
                Spacer()
                Text("Powered by Kisi")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
    }
}

/// Individual door unlock card (matches Kisi app style)
struct DoorUnlockCard: View {
    let name: String
    @State private var showComingSoon = false

    var body: some View {
        Button(action: { showComingSoon = true }) {
            VStack(spacing: 6) {
                // Lock icon in circle
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    )

                // Status
                Text("LOCKED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.blue)
                    .tracking(0.5)

                // Door name
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Kisi door unlock integration coming January 2026.\n\nUnlock gym doors right from this app.")
        }
    }
}

// MARK: - Preview

#Preview("Gym Access Section") {
    VStack {
        Spacer()
        GymAccessSection()
        Spacer()
    }
    .frame(width: 280, height: 200)
    .background(Color("BackgroundPrimary"))
}

#Preview("Door Card") {
    HStack(spacing: 10) {
        DoorUnlockCard(name: "Main Gym")
        DoorUnlockCard(name: "Studio")
    }
    .padding()
    .frame(width: 280)
    .background(Color("BackgroundPrimary"))
}
