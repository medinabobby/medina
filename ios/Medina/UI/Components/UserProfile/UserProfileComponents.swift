//
// UserProfileComponents.swift
// Medina
//
// v93.7: Reusable UI components for UserProfileView
// ProfileSection, ProfileCard, edit row components, FlowLayout
//

import SwiftUI

// MARK: - Profile Section Container

struct ProfileSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Profile Card Container

struct ProfileCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Profile Divider

struct ProfileDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

// MARK: - Profile Value Row (Read-Only)

struct ProfileValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .font(.system(size: 17))
                .foregroundColor(Color("SecondaryText"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Profile Edit Row (Text Field)

struct ProfileEditRow: View {
    let label: String
    @Binding var value: String
    var suffix: String? = nil
    var keyboardType: UIKeyboardType = .default
    var placeholder: String = ""

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 4) {
                TextField(placeholder, text: $value)
                    .font(.system(size: 17))
                    .foregroundColor(Color("SecondaryText"))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboardType)

                if let suffix = suffix {
                    Text(suffix)
                        .font(.system(size: 17))
                        .foregroundColor(Color("SecondaryText"))
                }
            }
            .frame(maxWidth: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Profile Picker Row (DatePicker, etc.)

struct ProfilePickerRow<Picker: View>: View {
    let label: String
    let value: String
    let picker: Picker

    init(label: String, value: String, @ViewBuilder picker: () -> Picker) {
        self.label = label
        self.value = value
        self.picker = picker()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 17))
                    .foregroundColor(Color("SecondaryText"))

                picker
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Profile Menu Row (Dropdown)

struct ProfileMenuRow<MenuContent: View>: View {
    let label: String
    let selection: String
    let menuContent: MenuContent

    init(label: String, selection: String, @ViewBuilder menuContent: () -> MenuContent) {
        self.label = label
        self.selection = selection
        self.menuContent = menuContent()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 17))
                .foregroundColor(.primary)

            Spacer()

            Menu {
                menuContent
            } label: {
                HStack(spacing: 4) {
                    Text(selection)
                        .font(.system(size: 17))
                        .foregroundColor(Color("SecondaryText"))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Color("SecondaryText").opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Specialty Chip

struct SpecialtyChip: View {
    let specialty: TrainerSpecialty

    var body: some View {
        Text(specialty.displayName)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let positions = layout(sizes: sizes, containerWidth: bounds.width).positions

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX - spacing)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Preference Row (View Mode)

struct ProfilePreferenceRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Stat Card

struct ProfileStatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
