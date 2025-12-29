//
// EntityListModal.swift
// Medina
//
// v54.7: Generic entity list modal for "Show All" functionality
// Created: November 2025
// Purpose: Reusable modal for displaying scrollable, searchable entity lists
//

import SwiftUI

/// Generic modal for displaying lists of entities
/// Uses StatusListRow for consistent UI across all entity types
/// Supports search filtering with built-in iOS .searchable()
struct EntityListModal<Item: Identifiable>: View where Item.ID == String {
    let title: String
    let items: [Item]
    let searchPlaceholder: String
    let formatRow: (Item) -> StatusListRowConfig
    let onItemTap: (String) -> Void  // Pass item.id

    @State private var searchText = ""
    @Environment(\.dismiss) var dismiss

    /// Filtered items based on search text
    var filteredItems: [Item] {
        if searchText.isEmpty {
            return items
        }

        // Filter based on formatted row data (title, subtitle, metadata)
        return items.filter { item in
            let config = formatRow(item)
            let searchLower = searchText.lowercased()

            // Search across title, subtitle, and metadata
            if let title = config.title, title.lowercased().contains(searchLower) {
                return true
            }
            if let subtitle = config.subtitle, subtitle.lowercased().contains(searchLower) {
                return true
            }
            if let metadata = config.metadata, metadata.lowercased().contains(searchLower) {
                return true
            }

            return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background")
                    .ignoresSafeArea()

                if filteredItems.isEmpty {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(Color("SecondaryText"))

                        Text(searchText.isEmpty ? "No items" : "No results for \"\(searchText)\"")
                            .font(.headline)
                            .foregroundColor(Color("PrimaryText"))

                        if !searchText.isEmpty {
                            Text("Try a different search term")
                                .font(.subheadline)
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredItems) { item in
                                let config = formatRow(item)

                                StatusListRow(
                                    number: config.number,
                                    title: config.title,
                                    subtitle: config.subtitle,
                                    metadata: config.metadata,
                                    statusText: config.statusText,
                                    statusColor: config.statusColor,
                                    timeText: config.timeText,
                                    showChevron: true,
                                    action: {
                                        onItemTap(item.id)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: searchPlaceholder
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Configuration for StatusListRow display
/// Separates data formatting from UI rendering
struct StatusListRowConfig {
    let number: String?
    let title: String?
    let subtitle: String?
    let metadata: String?
    let statusText: String?
    let statusColor: Color
    let timeText: String?

    init(
        number: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        metadata: String? = nil,
        statusText: String? = nil,
        statusColor: Color = Color("SecondaryText"),
        timeText: String? = nil
    ) {
        self.number = number
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.statusText = statusText
        self.statusColor = statusColor
        self.timeText = timeText
    }
}
