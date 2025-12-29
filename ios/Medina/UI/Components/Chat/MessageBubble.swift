//
// MessageBubble.swift
// Medina
//
// v60.0: Use StatusListRow for workout created (consistent with schedule UI)
// v53.0: Simplified to text-only messages (removed card support)
// v62.5: Removed calendar/schedule views - text-only for chat pattern
// v108.0: Added analysis card support for training progress visualizations
// v109.2: Added class schedule card support for calendar-style class listings
// v142: Removed inline chips - now rendered at bottom via ChatInputView (industry standard)
// Last reviewed: December 2025
//

import SwiftUI

struct MessageBubble: View {
    let message: Message
    let navigationCoordinator: NavigationCoordinator?

    init(
        message: Message,
        navigationCoordinator: NavigationCoordinator? = nil
    ) {
        self.message = message
        self.navigationCoordinator = navigationCoordinator
    }

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            // v62.5: Simplified to text + cards only (removed calendar/schedule views)
            // v59.6.4: Inject navigation for workout created links
            if let workoutData = message.workoutCreatedData, let coordinator = navigationCoordinator {
                // v60.0: Workout created using StatusListRow (matches schedule pattern)
                // v62.3: Use EntityListFormatters for consistent formatting with All Workouts list
                // v178: Show BOTH text AND card (text above, card below) - matches summaryCardData pattern
                let config: StatusListRowConfig = {
                    if let workout = TestDataManager.shared.workouts[workoutData.workoutId] {
                        return EntityListFormatters.formatWorkout(workout)
                    } else {
                        // Fallback if workout not found
                        return StatusListRowConfig(
                            title: workoutData.workoutName,
                            subtitle: "Tap to review",
                            statusColor: Color("SecondaryText")
                        )
                    }
                }()

                VStack(alignment: .leading, spacing: 12) {
                    // v178: Show AI intro text if present
                    if !message.content.isEmpty {
                        Text(message.content)
                            .foregroundColor(Color("PrimaryText"))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Workout card below
                    StatusListRow(
                        title: config.title,
                        subtitle: config.subtitle,
                        metadata: config.metadata,
                        statusText: config.statusText,
                        statusColor: config.statusColor,
                        showChevron: true,
                        mode: .compact,
                        action: {
                            coordinator.navigateToWorkout(id: workoutData.workoutId)
                        }
                    )
                }
                .frame(maxWidth: safeScreenWidth * 0.95, alignment: .leading)
            } else if let planData = message.planCreatedData, let coordinator = navigationCoordinator {
                // v63.0: Plan created using StatusListRow
                // v63.0.1: Use plan's actual status for badge (Draft, Active, etc.)
                let (statusText, statusColor): (String, Color) = {
                    if let plan = TestDataManager.shared.plans[planData.planId] {
                        return plan.status.statusInfo()
                    }
                    return ("Draft", Color("SecondaryText"))  // Default for new plans
                }()

                StatusListRow(
                    title: planData.planName,
                    subtitle: "\(planData.workoutCount) workouts • \(planData.durationWeeks) weeks",
                    statusText: statusText.uppercased(),
                    statusColor: statusColor,
                    showChevron: true,
                    mode: .compact,
                    action: {
                        coordinator.navigateToPlan(id: planData.planId)
                    }
                )
                .frame(maxWidth: safeScreenWidth * 0.95, alignment: .leading)
            } else if let summaryData = message.summaryCardData, let coordinator = navigationCoordinator {
                // v62.0: Summary card for workout/program/plan summaries
                // v62.1: Use StatusListRow (green bar pattern) instead of SummaryCardRow
                // v62.2: Show BOTH text content AND card (text above, card below)
                VStack(alignment: .leading, spacing: 12) {
                    // Show AI text if present
                    // v62.4: fixedSize ensures text wraps fully without truncation
                    if !message.content.isEmpty {
                        Text(message.content)
                            .foregroundColor(Color("PrimaryText"))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Summary card
                    StatusListRow(
                        title: summaryData.title,
                        subtitle: summaryData.subtitle,
                        statusText: summaryData.statusText,
                        statusColor: summaryData.statusColor,
                        showChevron: true,
                        mode: .compact,
                        action: {
                            switch summaryData.scope {
                            case .workout:
                                coordinator.navigateToWorkoutSummary(id: summaryData.id)
                            case .program:
                                coordinator.navigateToProgram(id: summaryData.id)
                            case .plan:
                                coordinator.navigateToPlan(id: summaryData.id)
                            }
                        }
                    )
                }
                .frame(maxWidth: safeScreenWidth * 0.95, alignment: .leading)
            } else if let draftData = message.draftMessageData {
                // v93.4: Draft message card for confirmation before sending
                DraftMessageCard(data: draftData)
                    .frame(maxWidth: safeScreenWidth * 0.95, alignment: .leading)
            } else if let analysisData = message.analysisCardData {
                // v108.0: Analysis card for training progress visualizations
                VStack(alignment: .leading, spacing: 12) {
                    // Show AI text if present
                    if !message.content.isEmpty {
                        Text(message.content)
                            .foregroundColor(Color("PrimaryText"))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Analysis visualization card
                    AnalysisCardView(data: analysisData)
                }
                .frame(maxWidth: safeScreenWidth * 0.95, alignment: .leading)
            } else if let view = message.view {
                // Rich content view without navigation
                view
                    .frame(maxWidth: safeScreenWidth * 0.95, alignment: .leading)
            } else if message.isUser {
                // User messages: Bubble style (right-aligned)
                Text(message.content)
                    .padding(12)
                    .background(Color("AccentBlue"))
                    .foregroundColor(Color("OnAccent"))
                    .cornerRadius(16)
                    .frame(
                        maxWidth: safeScreenWidth * 0.75,
                        alignment: .trailing
                    )
            } else {
                // AI messages: Plain text, no bubble (ChatGPT/Claude style)
                // v142: Chips now rendered at bottom via ChatInputView (industry standard)
                Text(message.content)
                    .foregroundColor(Color("PrimaryText"))
                    .frame(
                        maxWidth: safeScreenWidth * 0.85,
                        alignment: .leading
                    )
            }

            if !message.isUser { Spacer() }
        }
    }

    // MARK: - Helper

    /// Safe screen width calculation to prevent CoreGraphics NaN errors
    private var safeScreenWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width

        // Ensure screen width is valid and finite
        guard screenWidth.isFinite && screenWidth > 0 else {
            // Fallback to a reasonable default (iPhone standard width)
            return 375.0
        }

        return screenWidth
    }
}

