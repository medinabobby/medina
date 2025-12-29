//
// SidebarMemberScopedFolders.swift
// Medina
//
// v93.6: Member-scoped folder implementations for trainer view
// v118: Removed unused MemberScopedPlansFolder, MemberScopedWorkoutsFolder, MemberScopedClassesFolder
// When a trainer selects a specific member, these folders show that member's data
//

import SwiftUI

// MARK: - Member-Scoped Exercises Folder

struct MemberScopedExercisesFolder: View {
    let memberId: String
    let sidebarItemLimit: Int
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    private var memberLibrary: UserLibrary? {
        TestDataManager.shared.libraries[memberId]
    }

    private var memberExercises: [Exercise] {
        memberLibrary?.exercises.compactMap { exerciseId in
            TestDataManager.shared.exercises[exerciseId]
        } ?? []
    }

    var body: some View {
        SidebarFolderView(
            icon: "dumbbell.fill",
            title: "Exercises",
            count: memberExercises.count,
            isExpanded: $isExpanded
        ) {
            if memberExercises.isEmpty {
                SidebarEmptyState("No exercises in library")
            } else {
                // v99.9: Removed status dots - exercises don't have meaningful state
                ForEach(memberExercises.prefix(sidebarItemLimit)) { exercise in
                    SidebarItemButton(
                        text: exercise.name,
                        statusDot: nil  // No status dots for exercises
                    ) {
                        onNavigate(exercise.id, .exercise)
                        onDismiss()
                    }
                }

                if memberExercises.count > sidebarItemLimit {
                    SidebarShowAllButton(
                        title: "Show All Exercises",
                        totalCount: memberExercises.count,
                        visibleCount: sidebarItemLimit
                    ) {
                        onShowAll("All Exercises", .exercises(memberExercises))
                    }
                }
            }
        }
    }
}

// MARK: - Member-Scoped Protocols Folder

struct MemberScopedProtocolsFolder: View {
    let memberId: String
    let sidebarItemLimit: Int
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    private var memberLibrary: UserLibrary? {
        TestDataManager.shared.libraries[memberId]
    }

    private var libraryProtocolIds: Set<String> {
        Set(memberLibrary?.protocols.map(\.protocolConfigId) ?? [])
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
                SidebarEmptyState("No protocols in library")
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
                            TestDataManager.shared.protocolConfigs[id]
                        }
                        onShowAll("All Protocols", .protocols(libraryProtocols))
                    }
                }
            }
        }
    }
}

// MARK: - Member-Scoped Library Section (v114)

/// Collapsible library section for trainer viewing member's data
/// Contains Exercises and Protocols sub-folders (profile-level, not filtered by plan)
/// v190: Added title parameter for dynamic labeling ("Bobby's Library")
struct MemberScopedLibrarySection: View {
    let memberId: String
    let sidebarItemLimit: Int
    let title: String  // v190: Dynamic title from context.libraryLabel()
    @Binding var isExpanded: Bool
    @Binding var showExercises: Bool
    @Binding var showProtocols: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    private var memberLibrary: UserLibrary? {
        TestDataManager.shared.libraries[memberId]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Library header (collapsible parent)
            LibrarySectionHeader(
                isExpanded: $isExpanded,
                title: title
            )

            if isExpanded {
                // Exercises subfolder (indented)
                MemberScopedExercisesFolder(
                    memberId: memberId,
                    sidebarItemLimit: sidebarItemLimit,
                    isExpanded: $showExercises,
                    onNavigate: onNavigate,
                    onShowAll: onShowAll,
                    onDismiss: onDismiss
                )
                .padding(.leading, 16)

                // Protocols subfolder (indented)
                MemberScopedProtocolsFolder(
                    memberId: memberId,
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

// MARK: - All Members Library Section (v189)

/// Aggregate library section showing all assigned members' exercises and protocols
/// Used when trainer selects "All Members" in sidebar filter
/// v190: Added title parameter, reuses LibrarySectionHeader
struct AllMembersLibrarySection: View {
    let trainerId: String
    let sidebarItemLimit: Int
    let title: String  // v190: Dynamic title ("All Libraries")
    @Binding var isExpanded: Bool
    @Binding var showExercises: Bool
    @Binding var showProtocols: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    /// All assigned members
    private var assignedMembers: [UnifiedUser] {
        UserDataStore.members(assignedToTrainer: trainerId)
    }

    /// Combined exercise IDs from all members' libraries
    private var allExerciseIds: Set<String> {
        var ids = Set<String>()
        for member in assignedMembers {
            if let library = TestDataManager.shared.libraries[member.id] {
                ids.formUnion(library.exercises)
            }
        }
        return ids
    }

    /// Combined protocol IDs from all members' libraries
    private var allProtocolIds: Set<String> {
        var ids = Set<String>()
        for member in assignedMembers {
            if let library = TestDataManager.shared.libraries[member.id] {
                ids.formUnion(library.protocols.map { $0.protocolConfigId })
            }
        }
        return ids
    }

    /// Exercise objects for display
    private var allExercises: [Exercise] {
        allExerciseIds.compactMap { TestDataManager.shared.exercises[$0] }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // v190: Reuse shared header component
            LibrarySectionHeader(
                isExpanded: $isExpanded,
                title: title
            )

            if isExpanded {
                // Exercises
                AllMembersExercisesFolder(
                    exercises: allExercises,
                    sidebarItemLimit: sidebarItemLimit,
                    isExpanded: $showExercises,
                    onNavigate: onNavigate,
                    onShowAll: onShowAll,
                    onDismiss: onDismiss
                )
                .padding(.leading, 16)

                // Protocols
                AllMembersProtocolsFolder(
                    protocolIds: allProtocolIds,
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

// MARK: - All Members Exercises Folder (v189)

struct AllMembersExercisesFolder: View {
    let exercises: [Exercise]
    let sidebarItemLimit: Int
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    var body: some View {
        SidebarFolderView(
            icon: "dumbbell.fill",
            title: "Exercises",
            count: exercises.count,
            isExpanded: $isExpanded
        ) {
            if exercises.isEmpty {
                SidebarEmptyState("No exercises in members' libraries")
            } else {
                ForEach(exercises.prefix(sidebarItemLimit)) { exercise in
                    SidebarItemButton(
                        text: exercise.name,
                        statusDot: nil
                    ) {
                        onNavigate(exercise.id, .exercise)
                        onDismiss()
                    }
                }

                if exercises.count > sidebarItemLimit {
                    SidebarShowAllButton(
                        title: "Show All Exercises",
                        totalCount: exercises.count,
                        visibleCount: sidebarItemLimit
                    ) {
                        onShowAll("All Members' Exercises", .exercises(exercises))
                    }
                }
            }
        }
    }
}

// MARK: - All Members Protocols Folder (v189)

struct AllMembersProtocolsFolder: View {
    let protocolIds: Set<String>
    let sidebarItemLimit: Int
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onDismiss: () -> Void

    private var libraryFamilies: [ProtocolFamily] {
        let allFamilies = ProtocolGroupingService.getProtocolFamilies()

        return allFamilies.compactMap { family -> ProtocolFamily? in
            let libraryVariants = family.variants.filter { protocolIds.contains($0.id) }
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
            count: protocolIds.count,
            isExpanded: $isExpanded
        ) {
            if libraryFamilies.isEmpty {
                SidebarEmptyState("No protocols in members' libraries")
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
                        totalCount: protocolIds.count,
                        visibleCount: sidebarItemLimit
                    ) {
                        let libraryProtocols = protocolIds.compactMap { id in
                            TestDataManager.shared.protocolConfigs[id]
                        }
                        onShowAll("All Members' Protocols", .protocols(libraryProtocols))
                    }
                }
            }
        }
    }
}
