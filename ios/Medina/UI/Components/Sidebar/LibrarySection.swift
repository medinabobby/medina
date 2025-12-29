//
//  LibrarySection.swift
//  Medina
//
//  v114: Library/Favorites section (Exercises + Protocols)
//  Profile-level favorites, NOT filtered by Plan/Program
//

import SwiftUI

/// Collapsible library section containing Exercises and Protocols
/// These are profile-level favorites, not tied to any specific plan
/// v190: Added title parameter for dynamic labeling
struct LibrarySection: View {
    let userId: String
    let library: UserLibrary?
    let libraryExercises: [Exercise]
    let sidebarItemLimit: Int
    let title: String  // v190: Dynamic title ("Library", "Bobby's Library", etc.)
    @Binding var isExpanded: Bool
    @Binding var showExercises: Bool
    @Binding var showProtocols: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Library header (collapsible parent)
            LibrarySectionHeader(
                isExpanded: $isExpanded,
                title: title
            )

            if isExpanded {
                // Exercises subfolder (indented)
                ExercisesFolder(
                    libraryExercises: libraryExercises,
                    library: library,
                    userId: userId,
                    sidebarItemLimit: sidebarItemLimit,
                    isExpanded: $showExercises,
                    onNavigate: onNavigate,
                    onShowAll: onShowAll,
                    onDismiss: onDismiss
                )
                .padding(.leading, 16)

                // Protocols subfolder (indented)
                ProtocolsFolder(
                    library: library,
                    sidebarItemLimit: sidebarItemLimit,
                    isExpanded: $showProtocols,
                    onNavigate: onNavigate,
                    onShowAll: onShowAll,
                    onDismiss: onDismiss
                )
                .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Library Section Header

/// Collapsible header for the Library section
/// v190: Takes title parameter for dynamic labeling ("Library", "Bobby's Library", "All Libraries")
/// Count badge removed - sub-folders (Exercises, Protocols) show their own counts
struct LibrarySectionHeader: View {
    @Binding var isExpanded: Bool
    let title: String

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 12) {
                // Chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color("SecondaryText"))
                    .frame(width: 12)

                // Icon
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))
                    .frame(width: 20)

                // Title (v190: dynamic)
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(Color("PrimaryText"))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct LibrarySection_Previews: PreviewProvider {
    static var previews: some View {
        LibrarySectionPreview()
            .frame(width: 300)
            .background(Color("Background"))
    }
}

private struct LibrarySectionPreview: View {
    @State private var isExpanded = true
    @State private var showExercises = false
    @State private var showProtocols = false

    var body: some View {
        LibrarySection(
            userId: "bobby",
            library: nil,
            libraryExercises: [],
            sidebarItemLimit: 3,
            title: "Library",
            isExpanded: $isExpanded,
            showExercises: $showExercises,
            showProtocols: $showProtocols,
            onNavigate: { _, _ in },
            onShowAll: { _, _ in },
            onDismiss: { }
        )
    }
}
