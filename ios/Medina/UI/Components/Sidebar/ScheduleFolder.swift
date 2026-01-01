//
// ScheduleFolder.swift
// Medina
//
// v250: Schedule folder showing this week's workouts in sidebar
// Matches web's ScheduleFolder.tsx pattern
//

import SwiftUI

/// Schedule folder showing this week's workouts
/// Displays upcoming/today workouts with status dots
struct ScheduleFolder: View {
    let userId: String
    let sidebarItemLimit: Int
    @Binding var isExpanded: Bool
    let onNavigate: (String, Entity) -> Void
    let onDismiss: () -> Void

    /// Get this week's workouts (all statuses)
    private var thisWeekWorkouts: [Workout] {
        WorkoutResolver.workouts(
            for: userId,
            temporal: .thisWeek,
            status: nil,  // All statuses
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: nil,
            program: nil,
            dateInterval: nil
        ).sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) }
    }

    /// Upcoming workouts (scheduled, today or future)
    private var upcomingWorkouts: [Workout] {
        let today = Calendar.current.startOfDay(for: Date())
        return thisWeekWorkouts.filter { workout in
            guard let date = workout.scheduledDate else { return false }
            let workoutDay = Calendar.current.startOfDay(for: date)
            return workoutDay >= today && workout.status == .scheduled
        }
    }

    /// Count of upcoming workouts
    private var upcomingCount: Int {
        upcomingWorkouts.count
    }

    var body: some View {
        SidebarFolderView(
            icon: "calendar",
            title: "Schedule",
            count: upcomingCount,
            isExpanded: $isExpanded
        ) {
            if thisWeekWorkouts.isEmpty {
                SidebarEmptyState("No workouts this week")
            } else if upcomingWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("All done for this week!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 44)
                        .padding(.trailing, 20)
                        .padding(.vertical, 10)
                }
            } else {
                ForEach(upcomingWorkouts.prefix(sidebarItemLimit)) { workout in
                    ScheduleWorkoutRow(
                        workout: workout,
                        onTap: {
                            onNavigate(workout.id, .workout)
                            onDismiss()
                        }
                    )
                }

                // Show "+ X more..." if there are more workouts
                if upcomingWorkouts.count > sidebarItemLimit {
                    SidebarMoreButton(
                        remainingCount: upcomingWorkouts.count - sidebarItemLimit,
                        label: "workouts",
                        onTap: {
                            // TODO: v251 - Navigate to schedule view
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Schedule Workout Row

/// Row showing workout with day label and status
private struct ScheduleWorkoutRow: View {
    let workout: Workout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Day label (Today, Tomorrow, Wed, etc.)
                Text(dayLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                // Workout name
                Text(workoutName)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Status dot
                StatusDot(executionStatus: workout.status)
            }
            .padding(.leading, 44)
            .padding(.trailing, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var workoutName: String {
        workout.splitDay?.displayName ?? workout.type.displayName
    }

    private var dayLabel: String {
        guard let date = workout.scheduledDate else { return "" }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let workoutDay = calendar.startOfDay(for: date)
        let daysDiff = calendar.dateComponents([.day], from: today, to: workoutDay).day ?? 0

        switch daysDiff {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"  // "Mon", "Tue", etc.
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ScheduleFolderPreview()
    }
    .frame(width: 280)
    .background(Color("BackgroundPrimary"))
}

private struct ScheduleFolderPreview: View {
    @State private var isExpanded = true

    var body: some View {
        ScheduleFolder(
            userId: "bobby_tulsiani",
            sidebarItemLimit: 3,
            isExpanded: $isExpanded,
            onNavigate: { _, _ in },
            onDismiss: {}
        )
    }
}
