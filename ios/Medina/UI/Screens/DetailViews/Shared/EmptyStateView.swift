//
// EmptyStateView.swift
// Medina
//
// v48 Navigation Refactor
// Created: November 2025
// Purpose: Reusable empty state component for detail views
//

import SwiftUI

/// Displays an empty state with icon, message, and optional action
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color("SecondaryText"))

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))

                Text(message)
                    .font(.system(size: 15))
                    .foregroundColor(Color("SecondaryText"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Previews

#Preview("No Workouts") {
    EmptyStateView(
        icon: "figure.strengthtraining.traditional",
        title: "No Workouts Yet",
        message: "This program doesn't have any workouts scheduled yet.",
        actionTitle: "Create Workout",
        action: { print("Create workout tapped") }
    )
}

#Preview("No Data") {
    EmptyStateView(
        icon: "chart.bar",
        title: "No Data Available",
        message: "Complete some workouts to see your progress here."
    )
}

#Preview("No Plans") {
    EmptyStateView(
        icon: "calendar",
        title: "No Active Plans",
        message: "Start by creating a training plan to track your fitness journey.",
        actionTitle: "Get Started",
        action: { print("Get started tapped") }
    )
}
