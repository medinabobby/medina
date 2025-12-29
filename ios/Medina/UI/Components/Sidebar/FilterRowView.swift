//
//  FilterRowView.swift
//  Medina
//
//  v105: Reusable filter row with highlighted background when active
//  v105.1: Added expandable support with chevron
//

import SwiftUI

/// Single filter row with highlighted background when active
/// Used in SidebarFilterSection for member/trainer selection
struct FilterRowView: View {
    let icon: String
    let title: String
    let isActive: Bool
    var indent: Bool = false
    var count: Int? = nil
    var isExpandable: Bool = false
    var isExpanded: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Chevron for expandable rows
                if isExpandable {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                }

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundColor(isActive ? .accentColor : .primary)

                Spacer()

                if let count = count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, isExpandable ? 12 : 20)
            .padding(.leading, indent ? 16 : 0)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 0) {
        FilterRowView(
            icon: "person.2.fill",
            title: "All Members",
            isActive: true,
            count: 5
        ) {}

        FilterRowView(
            icon: "person.fill",
            title: "Bobby Tulsiani",
            isActive: false
        ) {}

        FilterRowView(
            icon: "person.fill",
            title: "Sarah Smith",
            isActive: false,
            indent: true
        ) {}
    }
}
