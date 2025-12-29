//
// Message.swift
// Medina
//
// v53.0: Simplified to text-only messages (removed card support)
// v54.0: Added optional SwiftUI view support for rich content
// v62.5: Removed calendar/schedule data - text-only for chat pattern
// v108.0: Added analysisCardData for training progress visualizations
// v141: Added suggestionChipsData for response suggestion chips
// v186: Removed classScheduleCardData (class booking deferred for beta)
// Last reviewed: December 2025
//

import Foundation
import SwiftUI

struct Message: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
    let view: AnyView?  // v54.0: Optional SwiftUI view for rich content
    let workoutCreatedData: WorkoutCreatedData?  // v60.0: Workout creation data for StatusListRow
    let planCreatedData: PlanCreatedData?  // v63.0: Plan creation data for StatusListRow
    let summaryCardData: SummaryCardData?  // v62.0: Summary card data for workout/program/plan summaries
    let draftMessageData: DraftMessageData?  // v93.4: Draft message for confirmation before sending
    let analysisCardData: AnalysisCardData?  // v108.0: Analysis visualizations for training progress
    let suggestionChipsData: [SuggestionChip]?  // v141: Quick-action chips below AI responses

    init(
        content: String,
        isUser: Bool,
        view: AnyView? = nil,
        workoutCreatedData: WorkoutCreatedData? = nil,
        planCreatedData: PlanCreatedData? = nil,
        summaryCardData: SummaryCardData? = nil,
        draftMessageData: DraftMessageData? = nil,
        analysisCardData: AnalysisCardData? = nil,
        suggestionChipsData: [SuggestionChip]? = nil
    ) {
        self.content = content
        self.isUser = isUser
        self.view = view
        self.workoutCreatedData = workoutCreatedData
        self.planCreatedData = planCreatedData
        self.summaryCardData = summaryCardData
        self.draftMessageData = draftMessageData
        self.analysisCardData = analysisCardData
        self.suggestionChipsData = suggestionChipsData
    }
}

// v60.0: Workout creation data for StatusListRow reconstruction
struct WorkoutCreatedData {
    let workoutId: String
    let workoutName: String
}

// v63.0: Plan creation data for StatusListRow
struct PlanCreatedData {
    let planId: String
    let planName: String
    let workoutCount: Int
    let durationWeeks: Int
}

// v62.0: Summary scope enum for workout/program/plan summaries
enum SummaryScope {
    case workout
    case program
    case plan
}

// v93.4: Draft message data for confirmation before sending
struct DraftMessageData {
    let recipientId: String
    let recipientName: String
    let content: String
    let subject: String?
    let messageType: TrainerMessage.MessageType
    let onSend: (String) -> Void  // Callback with final content (user may edit)
    let onCancel: () -> Void
}

// v62.0: Summary card data for summary link in chat
// v62.1: Added workoutStatus and computed properties for StatusListRow compatibility
struct SummaryCardData {
    let scope: SummaryScope
    let id: String
    let title: String      // e.g., "Monday, Nov 10"
    let subtitle: String   // e.g., "4 of 6 exercises • 29 min"
    let workoutStatus: ExecutionStatus?  // v62.1: For workouts - nil for program/plan

    init(scope: SummaryScope, id: String, title: String, subtitle: String, workoutStatus: ExecutionStatus? = nil) {
        self.scope = scope
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.workoutStatus = workoutStatus
    }

    // v62.1: Status color for StatusListRow's left bar
    var statusColor: Color {
        switch scope {
        case .workout:
            guard let status = workoutStatus else { return .green }
            switch status {
            case .completed: return .green
            case .inProgress: return Color.accentColor
            case .skipped: return .orange
            case .scheduled: return Color("SecondaryText")
            }
        case .program: return Color("AccentBlue")
        case .plan: return .purple
        }
    }

    // v62.1: Status text for StatusListRow badge
    var statusText: String {
        switch scope {
        case .workout:
            guard let status = workoutStatus else { return "COMPLETED" }
            return status.displayName.uppercased()
        case .program: return "PROGRESS"
        case .plan: return "OVERVIEW"
        }
    }
}
