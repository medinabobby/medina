//
// ChatNavigationDestinations.swift
// Medina
//
// v93.8: Extracted navigation destination routing from ChatView
// Maps NavigationRoute to destination views
//

import SwiftUI

/// Builds destination views for NavigationStack routing
@MainActor
enum ChatNavigationDestinations {

    /// Map NavigationRoute to destination views
    @ViewBuilder
    static func view(
        for route: NavigationRoute,
        navigationModel: NavigationModel,
        selectedMemberId: String?,
        currentUserId: String
    ) -> some View {
        switch route {
        case .plan(let id):
            PlanDetailView(planId: id)
                .environmentObject(navigationModel)

        case .program(let id):
            ProgramDetailView(programId: id)
                .environmentObject(navigationModel)

        case .workout(let id):
            WorkoutDetailView(workoutId: id)
                .environmentObject(navigationModel)

        case .exercise(let id):
            // v91.1: Pass selected member ID for trainer mode
            ExerciseDetailView(exerciseId: id, userId: selectedMemberId ?? currentUserId)

        case .protocol(let id):
            ProtocolDetailView(userId: currentUserId, protocolConfigId: id, onDismiss: {
                NavigationCoordinator(navigationModel: navigationModel).popCurrent()
            })

        case .protocolFamily(let id):
            if let family = ProtocolGroupingService.getFamily(id: id) {
                ProtocolFamilyDetailView(family: family, userId: currentUserId)
            } else {
                Text("Protocol family not found")
            }

        // v186: Removed .class case (class booking deferred for beta)

        case .member(let id):
            // v92.0: Unified user profile view
            UserProfileView(userId: id, mode: .view)
                .environmentObject(navigationModel)

        // v164: Removed deprecated .message() and .messages cases (superseded by .thread)

        case .thread(let id):
            ThreadDetailView(threadId: id)
                .environmentObject(navigationModel)

        case .focusedExecution(let workoutId):
            FocusedExecutionView(workoutId: workoutId)
                .environmentObject(navigationModel)
        }
    }
}
