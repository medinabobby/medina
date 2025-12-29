//
// SearchResultsView.swift
// Medina
//
// Created: November 13, 2025
// Purpose: Display grouped search results in sidebar
//

import SwiftUI

struct SearchResultsView: View {
    let results: SearchResults
    let onNavigate: (String, Entity) -> Void
    let onDismiss: () -> Void

    private let maxResultsPerSection = 5

    var body: some View {
        if results.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Plans section
                    if !results.plans.isEmpty {
                        SearchResultSection(
                            title: "PLANS",
                            count: results.plans.count
                        ) {
                            ForEach(Array(results.plans.prefix(maxResultsPerSection))) { plan in
                                SearchResultRow(
                                    title: plan.name,
                                    subtitle: formatPlanSubtitle(plan),
                                    onTap: {
                                        onNavigate(plan.id, .plan)
                                        onDismiss()
                                    }
                                )
                            }

                            if results.plans.count > maxResultsPerSection {
                                ShowAllButton(
                                    count: results.plans.count,
                                    label: "plans"
                                )
                            }
                        }
                    }

                    // Programs section
                    if !results.programs.isEmpty {
                        SearchResultSection(
                            title: "PROGRAMS",
                            count: results.programs.count
                        ) {
                            ForEach(Array(results.programs.prefix(maxResultsPerSection))) { program in
                                SearchResultRow(
                                    title: program.name,
                                    subtitle: formatProgramSubtitle(program),
                                    onTap: {
                                        onNavigate(program.id, .program)
                                        onDismiss()
                                    }
                                )
                            }

                            if results.programs.count > maxResultsPerSection {
                                ShowAllButton(
                                    count: results.programs.count,
                                    label: "programs"
                                )
                            }
                        }
                    }

                    // Workouts section
                    if !results.workouts.isEmpty {
                        SearchResultSection(
                            title: "WORKOUTS",
                            count: results.workouts.count
                        ) {
                            ForEach(Array(results.workouts.prefix(maxResultsPerSection))) { workout in
                                SearchResultRow(
                                    title: formatWorkoutTitle(workout),
                                    subtitle: formatWorkoutSubtitle(workout),
                                    onTap: {
                                        onNavigate(workout.id, .workout)
                                        onDismiss()
                                    }
                                )
                            }

                            if results.workouts.count > maxResultsPerSection {
                                ShowAllButton(
                                    count: results.workouts.count,
                                    label: "workouts"
                                )
                            }
                        }
                    }

                    // Exercises section
                    if !results.exercises.isEmpty {
                        SearchResultSection(
                            title: "EXERCISES",
                            count: results.exercises.count
                        ) {
                            ForEach(Array(results.exercises.prefix(maxResultsPerSection))) { exercise in
                                SearchResultRow(
                                    title: exercise.name,
                                    subtitle: formatExerciseSubtitle(exercise),
                                    onTap: {
                                        onNavigate(exercise.id, .exercise)
                                        onDismiss()
                                    }
                                )
                            }

                            if results.exercises.count > maxResultsPerSection {
                                ShowAllButton(
                                    count: results.exercises.count,
                                    label: "exercises"
                                )
                            }
                        }
                    }

                    // v88.0: Protocol families section (grouped)
                    if !results.protocolFamilies.isEmpty {
                        SearchResultSection(
                            title: "PROTOCOLS",
                            count: results.protocolFamilies.count
                        ) {
                            ForEach(Array(results.protocolFamilies.prefix(maxResultsPerSection))) { family in
                                SearchResultRow(
                                    title: family.displayName,
                                    subtitle: family.hasMultipleVariants ? "\(family.variantCount) variants" : nil,
                                    onTap: {
                                        onNavigate(family.id, .protocolFamily)
                                        onDismiss()
                                    }
                                )
                            }

                            if results.protocolFamilies.count > maxResultsPerSection {
                                ShowAllButton(
                                    count: results.protocolFamilies.count,
                                    label: "protocols"
                                )
                            }
                        }
                    }

                    // v186: Removed classes section (class booking deferred for beta)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(Color("SecondaryText").opacity(0.5))

            Text("No results found")
                .font(.system(size: 15))
                .foregroundColor(Color("SecondaryText"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Formatters

    private func formatPlanSubtitle(_ plan: Plan) -> String {
        var parts: [String] = []

        // Status badge
        // v172: Removed abandoned - plans are now draft/active/completed only
        switch plan.status {
        case .active:
            parts.append("Active")
        case .draft:
            parts.append("Draft")
        case .completed:
            parts.append("Completed")
        }

        // Date range
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        parts.append("\(formatter.string(from: plan.startDate)) - \(formatter.string(from: plan.endDate))")

        return parts.joined(separator: " • ")
    }

    private func formatProgramSubtitle(_ program: Program) -> String {
        var parts: [String] = []

        // Training focus (enum to string)
        parts.append(program.focus.rawValue.capitalized)

        // Date range
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        parts.append("\(formatter.string(from: program.startDate)) - \(formatter.string(from: program.endDate))")

        return parts.joined(separator: " • ")
    }

    private func formatWorkoutTitle(_ workout: Workout) -> String {
        guard let date = workout.scheduledDate else {
            return workout.name
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: date)) - \(workout.name)"
    }

    private func formatWorkoutSubtitle(_ workout: Workout) -> String {
        var parts: [String] = []

        // Type
        parts.append(workout.type.rawValue.capitalized)

        // Status
        switch workout.status {
        case .completed:
            parts.append("Completed")
        case .inProgress:
            parts.append("In Progress")
        case .scheduled:
            parts.append("Scheduled")
        case .skipped:
            parts.append("Skipped")
        }

        return parts.joined(separator: " • ")
    }

    private func formatExerciseSubtitle(_ exercise: Exercise) -> String {
        var parts: [String] = []

        // Type
        parts.append(exercise.type.rawValue.capitalized)

        // Equipment if not bodyweight
        if exercise.equipment != .bodyweight {
            parts.append(exercise.equipment.rawValue.capitalized)
        }

        return parts.joined(separator: " • ")
    }

    // v186: Removed formatClassSubtitle (class booking deferred for beta)
}

// MARK: - Search Result Section

struct SearchResultSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color("SecondaryText"))

                Text("(\(count))")
                    .font(.system(size: 13))
                    .foregroundColor(Color("SecondaryText").opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Section content
            content()
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let title: String
    let subtitle: String?
    let onTap: () -> Void

    init(title: String, subtitle: String? = nil, onTap: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(Color("PrimaryText"))
                    .lineLimit(1)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(Color("SecondaryText"))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Show All Button

struct ShowAllButton: View {
    let count: Int
    let label: String

    var body: some View {
        Button(action: {
            // TODO: Implement "show all" functionality
            // Could either expand inline or send chat command
        }) {
            Text("Show all \(count) \(label)")
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
