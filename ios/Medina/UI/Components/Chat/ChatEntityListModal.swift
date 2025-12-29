//
// ChatEntityListModal.swift
// Medina
//
// v93.8: Extracted entity list modal builder from ChatView
// v99.1: Added users case for admin sidebar
// v186: Removed class-related cases (class booking deferred for beta)
// v190: Added memberFilter case for sidebar selection (not navigation)
// Constructs EntityListModal based on typed EntityListData enum
//

import SwiftUI

/// Builds entity list modals for "Show All" functionality from sidebar
@MainActor
enum ChatEntityListModalBuilder {

    /// Construct EntityListModal based on typed enum
    /// - Parameters:
    ///   - data: Typed entity data
    ///   - title: Modal title
    ///   - coordinator: Navigation coordinator for entity navigation
    ///   - sidebarContext: Optional context for member filter selection (v190)
    ///   - onDismiss: Optional dismiss callback for member filter selection (v190)
    @ViewBuilder
    static func view(
        for data: EntityListData?,
        title: String,
        coordinator: NavigationCoordinator,
        sidebarContext: SidebarContext? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        if let data = data {
            switch data {
            case .workouts(let workouts):
                EntityListModal(
                    title: title,
                    items: workouts,
                    searchPlaceholder: "Search workouts...",
                    formatRow: EntityListFormatters.formatWorkout,
                    onItemTap: { workoutId in
                        coordinator.navigateToWorkout(id: workoutId)
                    }
                )
            case .exercises(let exercises):
                EntityListModal(
                    title: title,
                    items: exercises,
                    searchPlaceholder: "Search exercises...",
                    formatRow: EntityListFormatters.formatExercise,
                    onItemTap: { exerciseId in
                        coordinator.navigateToExercise(id: exerciseId)
                    }
                )
            case .protocols(let protocols):
                EntityListModal(
                    title: title,
                    items: protocols,
                    searchPlaceholder: "Search protocols...",
                    formatRow: EntityListFormatters.formatProtocol,
                    onItemTap: { protocolId in
                        coordinator.navigateToProtocol(id: protocolId)
                    }
                )
            case .plans(let plans):
                EntityListModal(
                    title: title,
                    items: plans,
                    searchPlaceholder: "Search plans...",
                    formatRow: EntityListFormatters.formatPlan,
                    onItemTap: { planId in
                        coordinator.navigateToPlan(id: planId)
                    }
                )
            case .programs(let programs):
                EntityListModal(
                    title: title,
                    items: programs,
                    searchPlaceholder: "Search programs...",
                    formatRow: EntityListFormatters.formatProgram,
                    onItemTap: { programId in
                        coordinator.navigateToProgram(id: programId)
                    }
                )

            // v99.1: Admin sidebar types
            case .users(let users):
                EntityListModal(
                    title: title,
                    items: users,
                    searchPlaceholder: "Search members...",
                    formatRow: EntityListFormatters.formatUser,
                    onItemTap: { userId in
                        coordinator.navigateToMember(id: userId)
                    }
                )

            // v189: Messages list modal
            case .threads(let threads, let userId):
                EntityListModal(
                    title: title,
                    items: threads,
                    searchPlaceholder: "Search messages...",
                    formatRow: { thread in
                        EntityListFormatters.formatThread(thread, userId: userId)
                    },
                    onItemTap: { threadId in
                        coordinator.navigateToThread(id: threadId)
                    }
                )

            // v190: Member filter selection (selects member in sidebar, doesn't navigate)
            case .memberFilter(let users):
                EntityListModal(
                    title: title,
                    items: users,
                    searchPlaceholder: "Search members...",
                    formatRow: EntityListFormatters.formatUser,
                    onItemTap: { userId in
                        // Select member in sidebar context instead of navigating
                        sidebarContext?.selectMember(userId)
                        onDismiss?()
                    }
                )
            }
        }
    }
}
