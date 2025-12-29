//
// SidebarFolderView.swift
// Medina
//
// v93.6: Extracted reusable folder component from SidebarView
// v118: Added subtitle parameter for credit usage display ("2/3 this month")
// Reduces SidebarView from 1,375 lines to ~400 lines
//

import SwiftUI

/// Reusable expandable folder component for sidebar navigation
struct SidebarFolderView<Content: View>: View {
    let icon: String
    let title: String
    let count: Int?         // v118: Made optional (nil when using subtitle)
    let subtitle: String?   // v118: For credit usage "2/3 this month"
    let unreadCount: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(
        icon: String,
        title: String,
        count: Int,
        unreadCount: Int = 0,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.count = count
        self.subtitle = nil
        self.unreadCount = unreadCount
        self._isExpanded = isExpanded
        self.content = content
    }

    /// v118: Init with subtitle instead of count (for class credits display)
    init(
        icon: String,
        title: String,
        subtitle: String?,
        unreadCount: Int = 0,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.count = nil
        self.subtitle = subtitle
        self.unreadCount = unreadCount
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            folderHeader

            if isExpanded {
                content()
            }
        }
    }

    private var folderHeader: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20)
                    .foregroundColor(.secondary)

                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                // Unread badge (for messages folder)
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }

                Spacer()

                // v118: Show subtitle (credit usage) or count
                if let subtitle = subtitle {
                    Text("• \(subtitle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else if let count = count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Sidebar Item Components

/// Empty state for folders with no items
struct SidebarEmptyState: View {
    let message: String
    let browseAction: (() -> Void)?
    let browseLabel: String?

    init(
        _ message: String,
        browseAction: (() -> Void)? = nil,
        browseLabel: String? = nil
    ) {
        self.message = message
        self.browseAction = browseAction
        self.browseLabel = browseLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)

            if let action = browseAction, let label = browseLabel {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                        Text(label)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
    }
}

/// Item row button for sidebar navigation
struct SidebarItemButton: View {
    let text: String
    let statusDot: StatusDot?
    let action: () -> Void

    init(
        text: String,
        statusDot: StatusDot? = nil,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.statusDot = statusDot
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if let dot = statusDot {
                    dot
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.01))
        .contentShape(Rectangle())
    }
}

/// "Show All" button for folder expansion
struct SidebarShowAllButton: View {
    let title: String
    let totalCount: Int
    let visibleCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)

                Spacer()

                if totalCount > visibleCount {
                    Text("(\(totalCount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .padding(.top, 4)
        .background(Color.white.opacity(0.01))
        .contentShape(Rectangle())
    }
}

/// v189: "+ X more..." link for Messages folder and other lists
/// v190: Made generic with label parameter
struct SidebarMoreButton: View {
    let remainingCount: Int
    let label: String  // v190: "messages", "members", etc.
    let onTap: () -> Void

    init(remainingCount: Int, label: String = "messages", onTap: @escaping () -> Void) {
        self.remainingCount = remainingCount
        self.label = label
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text("+ \(remainingCount) more \(label)...")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .fontWeight(.medium)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .padding(.leading, 44)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Workout item row with date and status
struct SidebarWorkoutButton: View {
    let workout: Workout
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(formatWorkoutName(workout))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                StatusDot(executionStatus: workout.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.01))
        .contentShape(Rectangle())
    }

    private func formatWorkoutName(_ workout: Workout) -> String {
        if let date = workout.scheduledDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        } else {
            return "No Date"
        }
    }
}

// v186: Removed SidebarClassButton (class booking deferred for beta)

/// Protocol family button with variant count badge
struct SidebarProtocolFamilyButton: View {
    let family: ProtocolFamily
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(family.displayName)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // v99.9: Show variant count if multiple variants (no status dots - protocols don't have meaningful states)
                if family.hasMultipleVariants {
                    Text("\(family.variantCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color("BackgroundSecondary"))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.01))
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview("Folder - Plans") {
    VStack {
        SidebarFolderView(
            icon: "list.clipboard",
            title: "Plans",
            count: 3,
            isExpanded: .constant(true)
        ) {
            SidebarItemButton(
                text: "Fall Strength",
                statusDot: StatusDot(status: .active)
            ) {}

            SidebarItemButton(
                text: "Summer Cut",
                statusDot: StatusDot(status: .completed)
            ) {}
        }
    }
    .frame(width: 280)
    .background(Color("BackgroundPrimary"))
}

#Preview("Empty State") {
    SidebarEmptyState(
        "No exercises in library",
        browseAction: {},
        browseLabel: "Browse Exercises"
    )
    .frame(width: 280)
    .background(Color("BackgroundPrimary"))
}
