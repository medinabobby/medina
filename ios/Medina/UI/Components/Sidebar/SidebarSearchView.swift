//
// SidebarSearchView.swift
// Medina
//
// v93.6: Extracted search bar from SidebarView
//

import SwiftUI

/// Search bar component for sidebar navigation
struct SidebarSearchView: View {
    @Binding var searchText: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Color("SecondaryText"))

            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(Color("PrimaryText"))

            if !searchText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color("SecondaryText"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color("BackgroundSecondary"))
    }
}

/// Header view for sidebar with title and dismiss button
struct SidebarHeaderView: View {
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Divider()
        }
        .padding(20)
    }
}

/// User profile section at bottom of sidebar
struct SidebarProfileSection: View {
    let user: UnifiedUser
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with initials
            Circle()
                .fill(.blue)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(initials(from: user.name))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
                .accessibilityHidden(true)

            // Name and role
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let primaryRole = user.roles.first {
                    Text(primaryRole.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Settings button
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens settings and profile information")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(user.name), \(user.roles.first?.displayName ?? ""), tap to open settings")
    }

    private func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
}

// MARK: - Preview

#Preview("Search Bar") {
    VStack {
        SidebarSearchView(
            searchText: .constant("bench"),
            onClear: {}
        )

        SidebarSearchView(
            searchText: .constant(""),
            onClear: {}
        )
    }
    .frame(width: 280)
}

#Preview("Header") {
    SidebarHeaderView(title: "Medina", onDismiss: {})
        .frame(width: 280)
}
