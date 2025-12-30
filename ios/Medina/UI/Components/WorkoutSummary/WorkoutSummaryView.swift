//
// WorkoutSummaryView.swift
// Medina
//
// Created: November 13, 2025
// Purpose: Full-screen workout summary sheet with percentage funnel metrics
//

import SwiftUI

struct WorkoutSummaryView: View {
    let workoutId: String
    let memberId: String
    @Environment(\.dismiss) var dismiss
    @State private var showShareSheet = false
    @State private var expandedExercises: Set<Int> = []  // Track which exercises are expanded

    private var summary: CompletedWorkoutSummary? {
        WorkoutSummaryService.generateSummary(for: workoutId, memberId: memberId)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                if let summary = summary {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        headerSection(summary: summary)

                        // Percentage funnel metrics
                        metricsSection(summary: summary)

                        // Exercises list
                        exercisesSection(summary: summary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                } else {
                    Text("Unable to load workout summary")
                        .foregroundColor(Color("SecondaryText"))
                        .padding()
                }
            }
            .background(Color("Background"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color("PrimaryText"))
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Workout Summary")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color("PrimaryText"))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if summary != nil {
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let summary = summary {
                    let shareText = WorkoutSummaryFormatter.formatForSharing(summary: summary)
                    ShareSheet(items: [shareText])
                }
            }
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private func headerSection(summary: CompletedWorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title: Date + Completed badge (right-justified)
            HStack(spacing: 12) {
                Text(formatDateFull(summary.scheduledDate))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color("PrimaryText"))
                    .lineLimit(1)

                Spacer()

                Text("Completed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
            }

            // Subtitle: Protocol names
            if !protocolNamesText(for: summary).isEmpty {
                Text(protocolNamesText(for: summary))
                    .font(.system(size: 14))
                    .foregroundColor(Color("SecondaryText"))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Metrics Section (Percentage Funnel)

    @ViewBuilder
    private func metricsSection(summary: CompletedWorkoutSummary) -> some View {
        VStack(spacing: 8) {
            // Duration percentage (actual vs estimated)
            metricRow(
                label: "Duration",
                percentage: summary.duration.percentage
            )

            // Exercises percentage
            metricRow(
                label: "Exercises",
                percentage: summary.exercises.percentage
            )

            // Sets percentage
            metricRow(
                label: "Sets",
                percentage: summary.sets.percentage
            )

            // Reps percentage
            metricRow(
                label: "Reps",
                percentage: summary.reps.percentage
            )

            // v62.0: Volume - show percentage if targets exist, otherwise just actual
            if summary.volume.hasTarget {
                metricRow(
                    label: "Volume",
                    percentage: summary.volume.percentage
                )
            } else {
                // No target weights available - show absolute volume
                volumeAbsoluteRow(actual: summary.volume.actual)
            }
        }
    }

    @ViewBuilder
    private func metricRow(label: String, percentage: Double?) -> some View {
        let pct = percentage ?? 0
        let barColor = semanticColor(for: pct)

        HStack(spacing: 12) {
            // Label
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color("PrimaryText"))
                .frame(width: 90, alignment: .leading)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color("SecondaryText").opacity(0.1))
                        .frame(height: 6)

                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geometry.size.width * min(pct, 1.0), height: 6)
                }
            }
            .frame(height: 6)

            // Percentage text
            Text(String(format: "%.0f%%", pct * 100))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color("PrimaryText"))
                .frame(width: 45, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color("BackgroundSecondary"))
        .cornerRadius(8)
    }

    // v62.0: Volume row showing absolute value when no targets exist
    @ViewBuilder
    private func volumeAbsoluteRow(actual: Double) -> some View {
        HStack(spacing: 12) {
            // Label
            Text("Volume")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color("PrimaryText"))
                .frame(width: 90, alignment: .leading)

            Spacer()

            // Absolute value (no percentage bar)
            Text("\(Int(actual)) lbs lifted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color("SecondaryText"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color("BackgroundSecondary"))
        .cornerRadius(8)
    }

    // Semantic color based on performance
    private func semanticColor(for percentage: Double) -> Color {
        if percentage >= 1.0 {
            return Color.green  // Excellent (100%+)
        } else if percentage >= 0.5 {
            return Color.accentColor  // Good (50-99%)
        } else {
            return Color.orange  // Needs improvement (<50%)
        }
    }

    // MARK: - Exercises Section

    @ViewBuilder
    private func exercisesSection(summary: CompletedWorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color("PrimaryText"))

            VStack(spacing: 8) {
                ForEach(Array(summary.exerciseDetails.enumerated()), id: \.offset) { index, exercise in
                    exerciseRow(exercise: exercise)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(exercise: ExerciseSummary) -> some View {
        let index = summary?.exerciseDetails.firstIndex(where: { $0.exerciseName == exercise.exerciseName }) ?? 0
        let isExpanded = expandedExercises.contains(index)
        let statusColor = exercise.status == .completed ? Color.green : Color.orange

        Button(action: {
            if expandedExercises.contains(index) {
                expandedExercises.remove(index)
            } else {
                expandedExercises.insert(index)
            }
        }) {
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 0) {
                    // Exercise header
                    HStack(spacing: 12) {
                        // Number badge (if superset label exists)
                        if let label = exercise.supersetLabel {
                            Text(label)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color("SecondaryText"))
                                .frame(width: 30)
                        }

                        // Exercise name and stats
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.exerciseName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color("PrimaryText"))

                            if exercise.status == .completed {
                                Text("\(exercise.formattedSetsPercentage) sets • \(exercise.formattedRepsPercentage) reps • \(exercise.formattedVolumePercentage) volume")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color("SecondaryText"))
                            } else {
                                Text("Skipped")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color("SecondaryText"))
                            }
                        }

                        Spacer()

                        // Expand/collapse chevron
                        if exercise.status == .completed && !exercise.sets.isEmpty {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }
                    .padding(.vertical, 12)

                    // Expanded set details
                    if isExpanded && exercise.status == .completed {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(exercise.sets.indices, id: \.self) { setIndex in
                                setRow(set: exercise.sets[setIndex])
                            }
                        }
                        .padding(.top, 6)
                        .padding(.leading, exercise.supersetLabel != nil ? 42 : 11)
                    }
                }
                .padding(.leading, 19)
                .padding(.trailing, 16)
                .background(Color("BackgroundSecondary"))
                .cornerRadius(10)

                // Status stripe (3px left border)
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusColor)
                    .frame(width: 3)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func setRow(set: SetSummary) -> some View {
        HStack(spacing: 12) {
            // Set number
            Text("\(set.setNumber)")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color("PrimaryText"))
                .frame(width: 20, alignment: .leading)

            // Weight and reps
            if let weight = set.actualWeight, let reps = set.actualReps {
                Text("\(Int(weight)) lbs × \(reps) reps")
                    .font(.system(size: 14))
                    .foregroundColor(Color("PrimaryText"))
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(Color("SecondaryText"))
            }

            Spacer()

            // Volume percentage
            if set.completion == ExecutionStatus.completed {
                Text(set.formattedVolumePercentage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color("CardBackground").opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func formatDateFull(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func protocolNamesText(for summary: CompletedWorkoutSummary) -> String {
        guard let workout = LocalDataStore.shared.workouts[summary.workoutId] else {
            return ""
        }

        let protocolIds = Set(workout.protocolVariantIds.values)
        let protocolNames = protocolIds.compactMap { id in
            LocalDataStore.shared.protocolConfigs[id]?.variantName
        }.sorted()

        return protocolNames.joined(separator: " • ")
    }
}

// MARK: - Preview

#Preview {
    WorkoutSummaryView(
        workoutId: "test_workout",
        memberId: "bobby"
    )
}
