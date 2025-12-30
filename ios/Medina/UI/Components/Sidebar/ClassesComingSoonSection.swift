//
// ClassesComingSoonSection.swift
// Medina
//
// v194: District Demo Prep - Classes placeholder section
// Shows "Coming Soon" badge for class booking feature
//

import SwiftUI

/// Sidebar section showing Classes feature is coming soon
/// Demo-only: No backend functionality
struct ClassesComingSoonSection: View {
    @Binding var isExpanded: Bool

    var body: some View {
        SidebarFolderView(
            icon: "calendar",
            title: "Classes",
            subtitle: "Coming Soon",
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "calendar.badge.plus", text: "Book group classes")
                featureRow(icon: "clock", text: "View your schedule")
                featureRow(icon: "bell", text: "Get class reminders")

                ComingSoonDateBadge(date: "January 2026")
            }
            .padding(.leading, 44)
            .padding(.trailing, 20)
            .padding(.vertical, 8)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Badge with specific date for upcoming features
struct ComingSoonDateBadge: View {
    let date: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10))

            Text("Coming \(date)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(6)
        .padding(.top, 4)
    }
}

// MARK: - Preview

#Preview("Classes Coming Soon") {
    VStack(alignment: .leading) {
        ClassesComingSoonSection(isExpanded: .constant(true))
    }
    .frame(width: 280)
    .background(Color("BackgroundPrimary"))
}
