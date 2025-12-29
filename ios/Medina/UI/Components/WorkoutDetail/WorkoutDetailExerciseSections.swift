//
// WorkoutDetailExerciseSections.swift
// Medina
//
// v93.7: Extracted exercise sections from WorkoutDetailView
// Exercises list, instance rows, planned exercise rows
//

import SwiftUI

// MARK: - Exercises List View

struct WorkoutExercisesListView: View {
    let workout: Workout
    @Binding var showExercises: Bool
    let exerciseRowBuilder: (Int, ExerciseInstance) -> AnyView
    let plannedExerciseRowBuilder: (Int, String) -> AnyView

    private var instances: [ExerciseInstance] {
        let allInstances = Array(TestDataManager.shared.exerciseInstances.values)
        let filtered = allInstances.filter { $0.workoutId == workout.id }
        let sorted = filtered.sorted { $0.id < $1.id }
        return sorted
    }

    private var exerciseCount: Int {
        if !instances.isEmpty {
            return instances.count
        } else {
            return workout.exerciseIds.count
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DisclosureGroup("Exercises in this Workout (\(exerciseCount))", isExpanded: $showExercises) {
                    VStack(alignment: .leading, spacing: 12) {
                        exercisesContent
                    }
                    .padding(.top, 12)
                }
                .tint(Color("PrimaryText"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private var exercisesContent: some View {
        if !instances.isEmpty {
            ForEach(Array(instances.enumerated()), id: \.element.id) { index, instance in
                exerciseRowBuilder(index, instance)
            }
        } else if !workout.exerciseIds.isEmpty {
            ForEach(Array(workout.exerciseIds.enumerated()), id: \.offset) { index, exerciseId in
                plannedExerciseRowBuilder(index, exerciseId)
            }
        } else {
            Text("No exercises found")
                .font(.body)
                .foregroundColor(Color("SecondaryText"))
        }
    }
}

// MARK: - Exercise Instance Row

struct WorkoutExerciseInstanceRow: View {
    let exercise: Exercise
    let instance: ExerciseInstance
    let index: Int
    let isExpanded: Bool
    let hasLoggedData: Bool
    let onToggleExpansion: () -> Void
    let onSetLog: (ExerciseSet, Double, Int) -> Void
    let onUnskipSet: (String) -> Void
    let onSkipExercise: () -> Void
    let onResetExercise: () -> Void
    let onSubstituteExercise: () -> Void

    private var displayNumber: String? {
        instance.supersetLabel ?? "\(index + 1)"
    }

    var body: some View {
        ExerciseCard(
            exercise: exercise,
            instance: instance,
            number: displayNumber,
            isExpanded: isExpanded,
            isActive: false,  // v78.6: Active state only in FocusedExecution
            hasLoggedData: hasLoggedData,
            isSetInteractive: { _ in true },  // v78.6: All sets editable in detail view
            onToggleExpansion: onToggleExpansion,
            onSetLog: onSetLog,
            onSkipSet: nil,
            onUnskipSet: onUnskipSet,
            onSkipExercise: onSkipExercise,
            onResetExercise: onResetExercise,
            onSubstituteExercise: onSubstituteExercise
        )
    }
}

// MARK: - Planned Exercise Row

struct WorkoutPlannedExerciseRow: View {
    let exercise: Exercise
    let position: Int
    let workout: Workout
    let coordinator: NavigationCoordinator

    private var instance: ExerciseInstance? {
        let instanceId = "\(workout.id)_ex\(position)"
        return TestDataManager.shared.exerciseInstances[instanceId]
    }

    private var displayNumber: String? {
        instance?.supersetLabel ?? "\(position + 1)"
    }

    private var subtitle: String {
        if position < workout.protocolVariantIds.count,
           let protocolId = workout.protocolVariantIds[position],
           let config = TestDataManager.shared.protocolConfigs[protocolId] {
            let setCount = instance?.setIds.count ?? config.reps.count
            return "\(config.variantName) • \(setCount) sets"
        }
        return "Protocol not assigned"
    }

    private var timeText: String? {
        if position < workout.protocolVariantIds.count,
           let protocolId = workout.protocolVariantIds[position],
           let protocolConfig = TestDataManager.shared.protocolConfigs[protocolId] {
            // v132: Include transition time to match DurationAwareWorkoutBuilder
            let minutes = ExerciseTimeCalculator.calculateWorkoutTime(
                protocolConfigs: [protocolConfig],
                workoutType: .strength,
                restBetweenExercises: 90
            )
            if minutes > 0 {
                return "~\(minutes) min"
            }
        }
        return nil
    }

    private var statusColor: Color {
        if let instance = instance {
            return instance.status.statusInfo().1
        }
        return Color("SecondaryText")
    }

    var body: some View {
        StatusListRow(
            number: displayNumber,
            title: exercise.name,
            subtitle: subtitle,
            metadata: nil,
            statusText: nil,
            statusColor: statusColor,
            timeText: timeText,
            showChevron: true,
            action: {
                coordinator.navigateToExercise(id: exercise.id)
            }
        )
    }
}

// MARK: - Workout Hero Section

struct WorkoutHeroSection: View {
    let workout: Workout
    let isSessionActive: Bool

    private var instances: [ExerciseInstance] {
        Array(TestDataManager.shared.exerciseInstances.values)
            .filter { $0.workoutId == workout.id }
    }

    private var protocolConfigs: [ProtocolConfig] {
        instances.compactMap { instance in
            TestDataManager.shared.protocolConfigs[instance.protocolVariantId]
        }
    }

    private var totalMinutes: Int {
        // v132: Include transition time to match DurationAwareWorkoutBuilder
        ExerciseTimeCalculator.calculateWorkoutTime(
            protocolConfigs: protocolConfigs,
            workoutType: .strength,
            restBetweenExercises: 90
        )
    }

    private var statusInfo: (String, Color) {
        if isSessionActive {
            return ("Active", .blue)
        }
        return workout.status.statusInfo()
    }

    private var dateTimeString: String {
        if let date = workout.scheduledDate {
            let calendar = Calendar.current
            let dayOfWeekIndex = calendar.component(.weekday, from: date)
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let dayName = dayNames[dayOfWeekIndex - 1]
            let dateStr = DateFormatters.shortMonthDayFormatter.string(from: date)

            if totalMinutes > 0 {
                return "\(dayName), \(dateStr) • ~\(totalMinutes) min"
            } else {
                return "\(dayName), \(dateStr)"
            }
        }
        return "No date"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(dateTimeString)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()

                Text(statusInfo.0)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(statusInfo.1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusInfo.1.opacity(0.15))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color("Background"))
    }
}

// MARK: - Workout Breadcrumb Bar

struct WorkoutBreadcrumbBar: View {
    let workout: Workout
    let coordinator: NavigationCoordinator

    var body: some View {
        var items: [BreadcrumbItem] = []

        if let program = TestDataManager.shared.programs[workout.programId],
           let plan = TestDataManager.shared.plans[program.planId] {

            items.append(BreadcrumbItem(label: "Plan") {
                coordinator.navigateToPlan(id: plan.id)
            })

            items.append(BreadcrumbItem(label: "Program") {
                coordinator.navigateToProgram(id: program.id)
            })
        }

        items.append(BreadcrumbItem(label: "Workout", action: nil))

        return BreadcrumbBar(items: items)
    }
}
