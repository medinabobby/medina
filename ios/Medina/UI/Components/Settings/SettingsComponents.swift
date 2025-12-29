//
// SettingsComponents.swift
// Medina
//
// v74.1: Extracted from SettingsModal.swift for reuse across settings screens
// Created: December 1, 2025
//

import SwiftUI

// MARK: - Section Container

/// Container for grouped settings with optional header
struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - Toggle Row

/// iOS-style toggle row with title and optional subtitle
struct SettingsToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundColor(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Navigation Row

/// Navigation row for NavigationLink destinations
struct SettingsNavigationRow: View {
    let icon: String?
    let title: String
    let value: String?

    init(icon: String? = nil, title: String, value: String? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)
            }

            Text(title)
                .font(.system(size: 17))
                .foregroundColor(.primary)

            Spacer()

            if let value = value {
                Text(value)
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Disclosure Row

/// Chevron navigation row for drilling into sub-screens (button version)
struct SettingsDisclosureRow: View {
    let icon: String?
    let title: String
    let value: String?
    let action: () -> Void

    init(icon: String? = nil, title: String, value: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.value = value
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                        .frame(width: 28, height: 28)
                }

                Text(title)
                    .font(.system(size: 17))
                    .foregroundColor(.primary)

                Spacer()

                if let value = value {
                    Text(value)
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Value Row

/// Read-only row displaying label and value (used in profile)
struct SettingsValueRow: View {
    let icon: String?
    let label: String
    let value: String

    init(icon: String? = nil, label: String, value: String) {
        self.icon = icon
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)
            }

            Text(label)
                .font(.system(size: 17))
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.system(size: 17))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Divider

/// Divider for separating rows within a section
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}

// MARK: - Menu Row

/// Menu-based picker row (inline dropdown)
struct SettingsMenuRow<MenuContent: View>: View {
    let title: String
    let selection: String
    let menuContent: MenuContent

    init(title: String, selection: String, @ViewBuilder menuContent: () -> MenuContent) {
        self.title = title
        self.selection = selection
        self.menuContent = menuContent()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17))
                .foregroundColor(.primary)

            Spacer()

            Menu {
                menuContent
            } label: {
                HStack(spacing: 4) {
                    Text(selection)
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Coming Soon Badge

/// v80.2: Small pill badge for features not yet fully implemented
struct ComingSoonBadge: View {
    var body: some View {
        Text("Coming Soon")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(.systemGray5))
            )
    }
}
