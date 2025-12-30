//
// SidebarContentFolders.swift
// Medina
//
// v93.6: Entity-specific folder implementations for sidebar
// v117: Removed WorkoutsFolder and PlansFolder (replaced by SelectablePlansFolder)
// Exercises, Protocols, Classes, Messages
//

import SwiftUI

// MARK: - Exercises Folder

struct ExercisesFolder: View {
    let libraryExercises: [Exercise]
    let library: UserLibrary?
    let userId: String
    let sidebarItemLimit: Int
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    var body: some View {
        SidebarFolderView(
            icon: "dumbbell.fill",
            title: "Exercises",
            count: library?.exercises.count ?? 0,
            isExpanded: $isExpanded
        ) {
            if libraryExercises.isEmpty {
                SidebarEmptyState(
                    "No exercises in library",
                    browseAction: {
                        let allExercises = Array(LocalDataStore.shared.exercises.values)
                            .sorted { $0.name < $1.name }
                        onShowAll("Browse Exercises", .exercises(allExercises))
                    },
                    browseLabel: "Browse Exercises"
                )
            } else {
                // v100.2: Exercises don't have status - no dots
                ForEach(libraryExercises.prefix(sidebarItemLimit)) { exercise in
                    SidebarItemButton(
                        text: exercise.name,
                        statusDot: nil
                    ) {
                        onNavigate(exercise.id, .exercise)
                        onDismiss()
                    }
                }

                if let library = library {
                    SidebarShowAllButton(
                        title: "Show All Exercises",
                        totalCount: library.exercises.count,
                        visibleCount: sidebarItemLimit
                    ) {
                        let allExercises = library.exercises.compactMap { exerciseId in
                            LocalDataStore.shared.exercises[exerciseId]
                        }
                        onShowAll("All Exercises", .exercises(allExercises))
                    }
                }
            }
        }
    }
}

// MARK: - Protocols Folder

struct ProtocolsFolder: View {
    let library: UserLibrary?
    let sidebarItemLimit: Int
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    private var libraryProtocolIds: Set<String> {
        Set(library?.protocols.map(\.protocolConfigId) ?? [])
    }

    private var libraryFamilies: [ProtocolFamily] {
        let allFamilies = ProtocolGroupingService.getProtocolFamilies()

        return allFamilies.compactMap { family -> ProtocolFamily? in
            let libraryVariants = family.variants.filter { libraryProtocolIds.contains($0.id) }
            guard !libraryVariants.isEmpty else { return nil }
            return ProtocolFamily(
                id: family.id,
                displayName: family.displayName,
                variants: libraryVariants,
                defaultVariant: libraryVariants.first
            )
        }
    }

    var body: some View {
        SidebarFolderView(
            icon: "list.number",
            title: "Protocols",
            count: libraryProtocolIds.count,
            isExpanded: $isExpanded
        ) {
            if libraryFamilies.isEmpty {
                SidebarEmptyState(
                    "No protocols in library",
                    browseAction: {
                        let allProtocols = Array(LocalDataStore.shared.protocolConfigs.values)
                        onShowAll("Browse Protocols", .protocols(allProtocols))
                    },
                    browseLabel: "Browse Protocols"
                )
            } else {
                ForEach(libraryFamilies.prefix(sidebarItemLimit)) { family in
                    SidebarProtocolFamilyButton(family: family) {
                        onNavigate(family.id, .protocolFamily)
                        onDismiss()
                    }
                }

                if libraryFamilies.count > sidebarItemLimit {
                    SidebarShowAllButton(
                        title: "Show All Protocols",
                        totalCount: libraryProtocolIds.count,
                        visibleCount: sidebarItemLimit
                    ) {
                        let libraryProtocols = libraryProtocolIds.compactMap { id in
                            LocalDataStore.shared.protocolConfigs[id]
                        }
                        onShowAll("My Protocols", .protocols(libraryProtocols))
                    }
                }
            }
        }
    }
}

// v186: Removed ClassesFolder (class booking deferred for beta)

// MARK: - Messages Folder

struct MessagesFolder: View {
    let userId: String
    let filteredMemberId: String?  // v189: Filter threads to only those with this member
    let sidebarItemLimit: Int
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void  // v189: Modal for all messages
    let onDismiss: () -> Void

    /// v189: Threads filtered by selected member (if any)
    private var threads: [MessageThread] {
        let allThreads = LocalDataStore.shared.threads(for: userId)

        // If filtering by member, only show threads that include that member
        guard let memberId = filteredMemberId else {
            return allThreads
        }

        return allThreads.filter { thread in
            thread.participantIds.contains(memberId)
        }
    }

    private var unreadCount: Int {
        threads.filter { $0.unreadCount(for: userId) > 0 }.count
    }

    var body: some View {
        SidebarFolderView(
            icon: "bubble.left.and.bubble.right.fill",
            title: "Messages",
            count: threads.count,
            unreadCount: unreadCount,
            isExpanded: $isExpanded
        ) {
            if threads.isEmpty {
                SidebarEmptyState("No messages")
            } else {
                ForEach(threads.prefix(sidebarItemLimit)) { thread in
                    CompactThreadRow(
                        thread: thread,
                        currentUserId: userId,
                        onTap: {
                            onNavigate(thread.id, .thread)
                            onDismiss()
                        }
                    )
                }

                // v189: Show "+ X more" - opens modal with all messages
                if threads.count > sidebarItemLimit {
                    SidebarMoreButton(
                        remainingCount: threads.count - sidebarItemLimit,
                        onTap: {
                            onShowAll("Messages", .threads(threads, userId: userId))
                        }
                    )
                }
            }
        }
    }
}
