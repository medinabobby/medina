//
// BreadcrumbBar.swift
// Medina
//
// v46 Handler Refactor: Shared breadcrumb navigation component
// Created: November 2025
// Purpose: Shows hierarchical navigation path with tappable segments
//

import SwiftUI

/// Represents a single breadcrumb item in the navigation hierarchy
struct BreadcrumbItem: Identifiable {
    let id = UUID()
    let label: String
    let action: (() -> Void)?

    init(label: String, action: (() -> Void)? = nil) {
        self.label = label
        self.action = action
    }
}

/// Breadcrumb navigation bar showing hierarchical path
/// Pattern: Plan > Program > Workout > Exercise (current level highlighted)
struct BreadcrumbBar: View {
    let items: [BreadcrumbItem]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                // Breadcrumb segment
                if let action = item.action {
                    // Tappable segment (not current)
                    Button(action: action) {
                        Text(item.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color("SecondaryText"))
                    }
                } else {
                    // Current segment (not tappable)
                    Text(item.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color("PrimaryText"))
                }

                // Separator (not after last item)
                if index < items.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color("SecondaryText").opacity(0.5))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color("BackgroundSecondary"))
    }
}

// MARK: - Previews

#Preview("Plan Level") {
    VStack(spacing: 0) {
        BreadcrumbBar(items: [
            BreadcrumbItem(label: "Plan", action: nil)
        ])
        Spacer()
    }
}

#Preview("Program Level") {
    VStack(spacing: 0) {
        BreadcrumbBar(items: [
            BreadcrumbItem(label: "Plan", action: { print("Navigate to Plan") }),
            BreadcrumbItem(label: "Program", action: nil)
        ])
        Spacer()
    }
}

#Preview("Workout Level") {
    VStack(spacing: 0) {
        BreadcrumbBar(items: [
            BreadcrumbItem(label: "Plan", action: { print("Navigate to Plan") }),
            BreadcrumbItem(label: "Program", action: { print("Navigate to Program") }),
            BreadcrumbItem(label: "Workout", action: nil)
        ])
        Spacer()
    }
}

#Preview("Exercise Level") {
    VStack(spacing: 0) {
        BreadcrumbBar(items: [
            BreadcrumbItem(label: "Plan", action: { print("Navigate to Plan") }),
            BreadcrumbItem(label: "Program", action: { print("Navigate to Program") }),
            BreadcrumbItem(label: "Workout", action: { print("Navigate to Workout") }),
            BreadcrumbItem(label: "Exercise", action: nil)
        ])
        Spacer()
    }
}
