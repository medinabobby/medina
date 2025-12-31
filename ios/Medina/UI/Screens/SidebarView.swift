//
// SidebarView.swift
// Medina
//
// v93.6: Refactored from 1,375 lines to ~350 lines
// v99.1: Added admin/gymOwner sidebar sections
// v105: SidebarContext integration - unified filter pattern
// v105.1: Messages moved above filter (YOUR inbox, not member-scoped)
// v114: Reorganized sections - Booked Classes (top), Plan/Program filters, Library section
// v115: Highlight-selection pattern replaces dropdown filters
// v116: UX redesign - collapsed by default, Messages at bottom for all roles,
//       "Classes" not "Booked Classes", max 1 plan in sidebar with "+N more" link
// v117: Removed Workouts folder - click plan/program = navigate to detail (not filter)
// v118: Reordered sections - Messages at TOP (universal), Classes at BOTTOM (not all use)
// v140: Listen for workoutStatusDidChange notification to refresh after skip
// v194: Added ClassesComingSoonSection + GymAccessSection for District demo
// v214: Removed District demo sections (Classes, GymAccess) for B2C launch
// Extracted components:
//   - SidebarFolderView.swift (reusable folder + item components)
//   - SidebarSearchView.swift (search bar + header + profile section)
//   - SidebarContentFolders.swift (Plans, Workouts, Exercises, Protocols, Classes, Messages)
//   - SidebarMemberScopedFolders.swift (trainer viewing member's data)
//   - AdminSidebarSections.swift (v187: removed for beta)
//   - SidebarViewModel.swift (state management + data loading)
//   - SidebarContext.swift (v105: unified filter state for sidebar + AI)
//   - SidebarFilterSection.swift (v105: filter UI at top of sidebar)
//   - SelectablePlansFolder.swift (v115: plans with nested selectable programs)
//   - MyClassesSection.swift (v115: classes trainer is teaching)
//   - ClassesSection.swift (v116: renamed from BookedClassesSection)
//   - LibrarySection.swift (v114: exercises + protocols grouped)
//

import SwiftUI

struct SidebarView: View {
    // v105: SidebarContext replaces user + selectedMemberId
    @ObservedObject var context: SidebarContext
    let onDismiss: () -> Void
    let onNavigate: (String, Entity) -> Void
    let onShowAll: (String, EntityListData) -> Void
    let onChatCommand: (String) -> Void
    let onLogout: () -> Void
    let onOpenSettings: () -> Void

    @StateObject private var viewModel: SidebarViewModel

    // v105: Convenience accessor for user from context
    private var user: UnifiedUser { context.currentUser }

    init(
        context: SidebarContext,
        onDismiss: @escaping () -> Void,
        onNavigate: @escaping (String, Entity) -> Void,
        onShowAll: @escaping (String, EntityListData) -> Void,
        onChatCommand: @escaping (String) -> Void,
        onLogout: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.context = context
        self.onDismiss = onDismiss
        self.onNavigate = onNavigate
        self.onShowAll = onShowAll
        self.onChatCommand = onChatCommand
        self.onLogout = onLogout
        self.onOpenSettings = onOpenSettings
        self._viewModel = StateObject(wrappedValue: SidebarViewModel(
            userId: context.currentUser.id
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarHeaderView(title: "Medina", onDismiss: onDismiss)

            SidebarSearchView(
                searchText: $viewModel.searchText,
                onClear: viewModel.clearSearch
            )

            Divider()

            // Toggle between search results and folder structure
            if !viewModel.debouncedSearchText.isEmpty, let results = viewModel.searchResults {
                SearchResultsView(
                    results: results,
                    onNavigate: onNavigate,
                    onDismiss: onDismiss
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // v189: Trainer sidebar - member filter at TOP, scopes everything below
                        if user.hasRole(.trainer) {
                            // Member filter section first
                            SidebarFilterSection(
                                context: context,
                                onShowAll: onShowAll  // v190: For member modal
                            )

                            Divider()
                                .padding(.vertical, 8)

                            // Messages filtered by selected member
                            MessagesFolder(
                                userId: user.id,
                                filteredMemberId: context.selectedMemberId,  // v189: Filter by member
                                sidebarItemLimit: viewModel.sidebarItemLimit,
                                isExpanded: $viewModel.showMessages,
                                onNavigate: onNavigate,
                                onShowAll: onShowAll,
                                onDismiss: onDismiss
                            )

                            Divider()
                                .padding(.vertical, 8)

                            trainerContent
                        } else {
                            // Member sidebar - Messages at top (no filter needed)
                            MessagesFolder(
                                userId: user.id,
                                filteredMemberId: nil,
                                sidebarItemLimit: viewModel.sidebarItemLimit,
                                isExpanded: $viewModel.showMessages,
                                onNavigate: onNavigate,
                                onShowAll: onShowAll,
                                onDismiss: onDismiss
                            )

                            Divider()
                                .padding(.vertical, 8)

                            memberContent
                        }
                    }
                }
            }

            Spacer()

            SidebarProfileSection(user: user, onOpenSettings: onOpenSettings)
        }
        .frame(width: 280)
        .background(Color("BackgroundPrimary"))
        .onAppear {
            viewModel.loadData()
        }
        .onChange(of: viewModel.searchText) { newValue in
            viewModel.handleSearchChange(newValue)
        }
        // v140: Refresh sidebar when workout status changes (skip, complete, etc.)
        .onReceive(NotificationCenter.default.publisher(for: .workoutStatusDidChange)) { _ in
            viewModel.loadData()
        }
        // v238: Refresh sidebar when plan status changes (delete, activate, etc.)
        // Refetches from Firestore to sync cross-device changes
        .onReceive(NotificationCenter.default.publisher(for: .planStatusDidChange)) { _ in
            Task {
                await LocalDataLoader.loadPlansFromFirestore(userId: user.id)
                viewModel.loadData()
            }
        }
    }

    // MARK: - Trainer Content (v118: Plans → Library → Classes)

    @ViewBuilder
    private var trainerContent: some View {
        // v105: Use context.selectedMemberId instead of local selectedMemberId
        if let memberId = context.selectedMemberId {
            // v118: Member-scoped view - Plans → Library → Classes

            // SECTION 1: Member's Plans (v117: click = navigate)
            // v190: Always show plans section (even if empty)
            SelectablePlansFolder(
                context: context,
                contextLabel: context.plansLabel(),
                isExpanded: $viewModel.showPlans,
                onNavigate: onNavigate,
                onShowAll: onShowAll,
                onDismiss: onDismiss
            )

            Divider()
                .padding(.vertical, 8)

            // SECTION 2: Member's Library
            MemberScopedLibrarySection(
                memberId: memberId,
                sidebarItemLimit: viewModel.sidebarItemLimit,
                title: context.libraryLabel(),  // v190: Dynamic label
                isExpanded: $viewModel.showLibrary,
                showExercises: $viewModel.showExercises,
                showProtocols: $viewModel.showProtocols,
                onNavigate: onNavigate,
                onShowAll: onShowAll,
                onDismiss: onDismiss
            )

            // v186: Removed member's ClassesSection (class booking deferred for beta)
        } else {
            // v116: Trainer aggregate view (no member selected)
            // v189: Shows "All Plans" with all members' plans
            // v190: Always show plans section (even if empty)
            SelectablePlansFolder(
                context: context,
                contextLabel: context.plansLabel(),  // v189: "All Plans"
                isExpanded: $viewModel.showMyPlans,
                onNavigate: onNavigate,
                onShowAll: onShowAll,
                onDismiss: onDismiss
            )

            Divider()
                .padding(.vertical, 8)

            // v189: All members' libraries combined
            AllMembersLibrarySection(
                trainerId: user.id,
                sidebarItemLimit: viewModel.sidebarItemLimit,
                title: context.libraryLabel(),  // v190: Dynamic label
                isExpanded: $viewModel.showLibrary,
                showExercises: $viewModel.showExercises,
                showProtocols: $viewModel.showProtocols,
                onNavigate: onNavigate,
                onShowAll: onShowAll,
                onDismiss: onDismiss
            )
        }
    }

    // MARK: - Member Content (v118: Plans → Library → Classes)

    @ViewBuilder
    private var memberContent: some View {
        // SECTION 1: Plans (v116: max 1 with "+N more" link)
        if !context.availablePlans.isEmpty {
            SelectablePlansFolder(
                context: context,
                contextLabel: "Plans",
                isExpanded: $viewModel.showPlans,
                onNavigate: onNavigate,
                onShowAll: onShowAll,
                onDismiss: onDismiss
            )

            Divider()
                .padding(.vertical, 8)
        }

        // SECTION 2: Library (Exercises + Protocols)
        LibrarySection(
            userId: user.id,
            library: viewModel.library,
            libraryExercises: viewModel.libraryExercises,
            sidebarItemLimit: viewModel.sidebarItemLimit,
            title: "Library",  // v190: Static for member's own view
            isExpanded: $viewModel.showLibrary,
            showExercises: $viewModel.showExercises,
            showProtocols: $viewModel.showProtocols,
            onNavigate: onNavigate,
            onShowAll: onShowAll,
            onDismiss: onDismiss
        )
    }

    // v117: Removed filteredWorkouts - no longer needed since Workouts folder removed
    // v187: Removed adminContent - admin/gymOwner UI deferred for beta
}
