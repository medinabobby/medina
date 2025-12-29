//
// HeroSection.swift
// Medina
//
// v46 Handler Refactor: Shared hero section component
// Created: November 2025
// Purpose: Two-line hero display with primary stats and status badge
//

import SwiftUI

/// Hero section showing two lines of key stats with status badge
/// Line 1: Primary stat + status badge (right-aligned)
/// Line 2: Secondary key stats (optional)
struct HeroSection: View {
    let line1Text: String
    let statusText: String?
    let statusColor: Color
    let line2Text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Line 1: Primary stat + status badge
            HStack(spacing: 12) {
                Text(line1Text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()

                if let statusText = statusText {
                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor.opacity(0.15))
                        .cornerRadius(6)
                }
            }

            // Line 2: Secondary stats (optional)
            if let line2Text = line2Text {
                Text(line2Text)
                    .font(.system(size: 15))
                    .foregroundColor(Color("SecondaryText"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color("Background"))
    }
}

// MARK: - Previews

#Preview("Plan Hero") {
    VStack(spacing: 0) {
        HeroSection(
            line1Text: "Oct 1 – Dec 31",
            statusText: "Active",
            statusColor: .accentColor,
            line2Text: "5 days/week • Strength focus"
        )
        Spacer()
    }
}

#Preview("Program Hero") {
    VStack(spacing: 0) {
        HeroSection(
            line1Text: "Nov 1 – Nov 30",
            statusText: "Active",
            statusColor: .accentColor,
            line2Text: "Foundation • 60% → 70%"
        )
        Spacer()
    }
}

#Preview("Workout Hero") {
    VStack(spacing: 0) {
        HeroSection(
            line1Text: "Oct 27",
            statusText: "Completed",
            statusColor: .green,
            line2Text: "Upper Body • ~48 min"
        )
        Spacer()
    }
}

#Preview("Exercise Hero") {
    VStack(spacing: 0) {
        HeroSection(
            line1Text: "3 of 5 sets complete",
            statusText: nil,
            statusColor: .accentColor,
            line2Text: "Strength 5x5 • 8.0 RPE"
        )
        Spacer()
    }
}
