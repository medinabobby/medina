//
// StatusListRow.swift
// Medina
//
// v60.0: Added compact mode for chat context
// v46 Handler Refactor: Shared list row with colored stripe, email-style layout
// Created: November 2025
// Purpose: Reusable list row with 3px colored left stripe for status indication
//

import SwiftUI

/// Display mode for StatusListRow
enum StatusListRowMode {
    case standard  // Full padding, used in schedule/detail views
    case compact   // Reduced padding, used in chat context
}

/// Reusable list row component with colored left status stripe
/// Used across all detail views for consistent visual design
/// Supports time display in right corner OR status badge (not both)
/// Title and status/time appear on same row (email app pattern), title truncates
struct StatusListRow: View {
    let number: String?
    let title: String?
    let subtitle: String?
    let metadata: String?
    let statusText: String?
    let statusColor: Color
    let timeText: String?
    let showChevron: Bool
    let mode: StatusListRowMode
    let action: () -> Void

    init(
        number: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        metadata: String? = nil,
        statusText: String? = nil,
        statusColor: Color,
        timeText: String? = nil,
        showChevron: Bool = true,
        mode: StatusListRowMode = .standard,
        action: @escaping () -> Void
    ) {
        self.number = number
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.statusText = statusText
        self.statusColor = statusColor
        self.timeText = timeText
        self.showChevron = showChevron
        self.mode = mode
        self.action = action
    }

    // MARK: - Computed Properties for Mode-Based Styling

    private var verticalPadding: CGFloat {
        mode == .compact ? 10 : 12
    }

    private var leadingPadding: CGFloat {
        mode == .compact ? 16 : 19
    }

    private var trailingPadding: CGFloat {
        mode == .compact ? 12 : 16
    }

    private var titleFontSize: CGFloat {
        mode == .compact ? 15 : 16
    }

    private var subtitleFontSize: CGFloat {
        mode == .compact ? 13 : 14
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // Main content
                HStack(spacing: 12) {
                    // Number badge (optional) - supports both numeric ("1", "2") and alphanumeric ("1a", "1b")
                    if let number = number {
                        Text(number)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color("SecondaryText"))
                            .frame(width: 30)
                    }

                    // Title + Subtitle + Metadata
                    VStack(alignment: .leading, spacing: 4) {
                        // Title row - title, status/time, and chevron on same line
                        if let title = title {
                            HStack(spacing: 8) {
                                Text(title)
                                    .font(.system(size: titleFontSize, weight: .medium))
                                    .foregroundColor(Color("PrimaryText"))
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                // Right corner: Time OR Status badge (not both)
                                if let timeText = timeText {
                                    // Time display (right-aligned, no badge styling)
                                    Text(timeText)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(Color("SecondaryText"))
                                        .fixedSize()
                                } else if let statusText = statusText {
                                    // Status badge
                                    Text(statusText)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(statusColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(statusColor.opacity(0.1))
                                        .cornerRadius(4)
                                        .fixedSize()
                                }

                                // Chevron on title row
                                if showChevron {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color("SecondaryText"))
                                }
                            }
                        }

                        // Subtitle (with status badge if no title)
                        if let subtitle = subtitle {
                            HStack(spacing: 8) {
                                Text(subtitle)
                                    .font(.system(size: subtitleFontSize))
                                    .foregroundColor(Color("SecondaryText"))

                                // If no title, show status/time/chevron on subtitle row
                                if title == nil {
                                    Spacer(minLength: 0)

                                    // Right corner: Time OR Status badge (not both)
                                    if let timeText = timeText {
                                        Text(timeText)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(Color("SecondaryText"))
                                            .fixedSize()
                                    } else if let statusText = statusText {
                                        Text(statusText)
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(statusColor)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(statusColor.opacity(0.1))
                                            .cornerRadius(4)
                                            .fixedSize()
                                    }

                                    if showChevron {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Color("SecondaryText"))
                                    }
                                }
                            }
                        }

                        // Metadata
                        if let metadata = metadata {
                            Text(metadata)
                                .font(.system(size: 13))
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }
                }
                .padding(.leading, leadingPadding)
                .padding(.trailing, trailingPadding)
                .padding(.vertical, verticalPadding)
                .background(Color("BackgroundSecondary"))
                .cornerRadius(10)

                // Colored left stripe (status indicator)
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusColor)
                    .frame(width: 3)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("With Number") {
    VStack(spacing: 12) {
        StatusListRow(
            number: "1",
            title: "Barbell Bench Press",
            subtitle: "Strength 5x5 Straight Sets",
            metadata: "~14 min • Compound",
            statusText: "Completed",
            statusColor: .green,
            action: {}
        )

        StatusListRow(
            number: "2",
            title: "Barbell Overhead Press",
            subtitle: "Strength 5x5 Straight Sets",
            metadata: "~14 min • Compound",
            statusText: "In Progress",
            statusColor: .accentColor,
            action: {}
        )

        StatusListRow(
            number: "3",
            title: "Lat Pulldown",
            subtitle: "Strength 5x5 Straight Sets",
            metadata: "~14 min • Compound",
            statusText: "Scheduled",
            statusColor: Color("SecondaryText"),
            action: {}
        )
    }
    .padding()
}

#Preview("Set Rows") {
    VStack(spacing: 12) {
        StatusListRow(
            number: "1",
            title: "Set 1",
            subtitle: "Target: 127 lbs × 5",
            metadata: "Actual: 63 lbs × 4",
            statusText: "Done",
            statusColor: .green,
            showChevron: false,
            action: {}
        )

        StatusListRow(
            number: "2",
            title: "Set 2",
            subtitle: "Target: 127 lbs × 5",
            metadata: nil,
            statusText: "Planned",
            statusColor: Color("SecondaryText"),
            showChevron: false,
            action: {}
        )

        StatusListRow(
            number: "3",
            title: "Set 3",
            subtitle: "Target: 127 lbs × 5",
            metadata: "Skipped",
            statusText: "Skipped",
            statusColor: .orange,
            showChevron: false,
            action: {}
        )
    }
    .padding()
}

#Preview("Without Number") {
    VStack(spacing: 12) {
        StatusListRow(
            title: "Development • Linear",
            subtitle: "Nov 1 - Nov 30 • 20 workouts",
            metadata: "Part of Fall Strength Build",
            statusText: "Active",
            statusColor: .accentColor,
            action: {}
        )

        StatusListRow(
            title: "Foundation • Linear",
            subtitle: "Oct 1 - Oct 31 • 20 workouts",
            metadata: "Part of Fall Strength Build",
            statusText: "Completed",
            statusColor: .green,
            action: {}
        )
    }
    .padding()
}

#Preview("With Time") {
    VStack(spacing: 12) {
        StatusListRow(
            number: "1",
            title: "Oct 1",
            subtitle: "Upper Body • Strength",
            metadata: nil,
            statusText: nil,
            statusColor: .green,
            timeText: "~53 min",
            action: {}
        )

        StatusListRow(
            number: "2",
            title: "Oct 2",
            subtitle: "Cardio Session",
            metadata: nil,
            statusText: nil,
            statusColor: .accentColor,
            timeText: "~30 min",
            action: {}
        )

        StatusListRow(
            number: "3",
            title: "Oct 3",
            subtitle: "Lower Body • Strength",
            metadata: nil,
            statusText: nil,
            statusColor: Color("SecondaryText"),
            timeText: "~53 min",
            action: {}
        )
    }
    .padding()
}
