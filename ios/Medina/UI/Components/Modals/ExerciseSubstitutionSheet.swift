//
// ExerciseSubstitutionSheet.swift
// Medina
//
// v61.1 - Exercise Substitution UI
// v79.1 - Simplified: removed redundant header, labels, and explanatory text
// Modal sheet for selecting alternative exercises
//

import SwiftUI

struct ExerciseSubstitutionSheet: View {
    let exerciseInstance: ExerciseInstance
    let workoutId: String
    let onSubstitute: (String) -> Void
    let onDismiss: () -> Void

    @State private var candidates: [SubstitutionCandidate] = []
    @State private var isLoading = true

    // Get current exercise for display (may have been substituted)
    private var currentExercise: Exercise? {
        // v79.2: Get fresh instance from LocalDataStore in case it was substituted
        if let freshInstance = LocalDataStore.shared.exerciseInstances[exerciseInstance.id] {
            return LocalDataStore.shared.exercises[freshInstance.exerciseId]
        }
        return LocalDataStore.shared.exercises[exerciseInstance.exerciseId]
    }

    var body: some View {
        // v79.1: Simplified sheet - drag indicator only, no header
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // Content area
            if isLoading {
                Spacer()
                ProgressView()
                    .foregroundColor(Color("SecondaryText"))
                Spacer()
            } else if candidates.isEmpty {
                noAlternativesView
            } else {
                alternativesListView
            }
        }
        .background(Color("Background"))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .task {
            Logger.log(.info, component: "ExerciseSubstitutionSheet",
                      message: "Sheet task started - loading alternatives")
            loadAlternatives()
        }
    }

    // MARK: - Subviews

    private var noAlternativesView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(Color("SecondaryText"))

            Text("No Alternatives")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color("PrimaryText"))
            Spacer()
        }
    }

    private var alternativesListView: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(candidates) { candidate in
                    SubstitutionRow(candidate: candidate) {
                        onSubstitute(candidate.exercise.id)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Data Loading

    private func loadAlternatives() {
        // Get user info
        let userId = LocalDataStore.shared.currentUserId ?? "bobby"
        guard let user = LocalDataStore.shared.users[userId] else {
            isLoading = false
            return
        }

        // v79.2: Get CURRENT exercise ID from LocalDataStore (may have been substituted)
        // The passed-in exerciseInstance could be stale after a substitution
        let currentExerciseId: String
        if let freshInstance = LocalDataStore.shared.exerciseInstances[exerciseInstance.id] {
            currentExerciseId = freshInstance.exerciseId
        } else {
            currentExerciseId = exerciseInstance.exerciseId
        }

        // Get available equipment based on workout location
        let availableEquipment: Set<Equipment> = {
            // Check workout location
            if let workout = LocalDataStore.shared.workouts[workoutId],
               let program = LocalDataStore.shared.programs[workout.programId],
               let plan = LocalDataStore.shared.plans[program.planId],
               let memberProfile = user.memberProfile {
                // Use location from workout context if available
                if memberProfile.trainingLocation == .home {
                    return memberProfile.availableEquipment ?? [.bodyweight]
                }
            }
            // Default: gym equipment (all)
            return Set(Equipment.allCases)
        }()

        // Get user library
        let userLibrary = LocalDataStore.shared.libraries[userId]

        // Get experience level
        let experienceLevel = user.memberProfile?.experienceLevel ?? .intermediate

        // Find alternatives
        candidates = ExerciseSubstitutionService.findAlternatives(
            for: currentExerciseId,
            availableEquipment: availableEquipment,
            userLibrary: userLibrary,
            userExperienceLevel: experienceLevel,
            limit: 6
        )

        isLoading = false

        Logger.log(.info, component: "ExerciseSubstitutionSheet",
                  message: "Loaded \(candidates.count) alternatives for \(currentExerciseId)")
    }
}

// MARK: - Substitution Row

/// v79.1: Simplified row - just name, equipment icon, and % badge
struct SubstitutionRow: View {
    let candidate: SubstitutionCandidate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Equipment icon
                Image(systemName: candidate.exercise.equipment.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(Color("SecondaryText"))
                    .frame(width: 24)

                // Exercise name
                Text(candidate.exercise.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color("PrimaryText"))
                    .lineLimit(1)

                Spacer()

                // Match percentage badge
                Text("\(candidate.scorePercentage)%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(matchColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(matchColor.opacity(0.15))
                    .cornerRadius(6)
            }
            .padding(12)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var matchColor: Color {
        switch candidate.scorePercentage {
        case 90...100: return .green
        case 70..<90: return Color(red: 0.3, green: 0.7, blue: 0.3) // Darker green
        case 50..<70: return .orange
        default: return .gray
        }
    }
}

// MARK: - Equipment Icon Extension

private extension Equipment {
    var iconName: String {
        switch self {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbells: return "dumbbell.fill"
        case .cableMachine: return "cable.connector"
        case .machine: return "gearshape.fill"
        case .kettlebell: return "scalemass.fill"
        case .resistanceBand: return "line.diagonal"
        case .bodyweight: return "figure.stand"
        case .pullupBar: return "rectangle.and.arrow.up.right.and.arrow.down.left"
        case .bench: return "rectangle.fill"
        case .smith: return "square.grid.3x3.fill"
        case .trx: return "arrow.up.arrow.down"
        case .squatRack: return "square.fill"
        case .dipStation: return "arrow.down.to.line"
        case .treadmill: return "figure.run"
        case .bike: return "bicycle"
        case .rower: return "arrow.left.arrow.right"
        case .elliptical: return "figure.elliptical.crosstrainer"
        case .skiErg: return "figure.skiing.crosscountry"
        case .none: return "xmark.circle"
        }
    }
}

// MARK: - Previews

#Preview("With Alternatives") {
    ExerciseSubstitutionSheet(
        exerciseInstance: ExerciseInstance(
            id: "test_instance",
            exerciseId: "barbell_bench_press",
            workoutId: "test_workout",
            protocolVariantId: "strength_3x5_heavy",
            setIds: ["set1", "set2", "set3"],
            status: .scheduled,
            trainerInstructions: nil,
            supersetLabel: nil
        ),
        workoutId: "test_workout",
        onSubstitute: { exerciseId in
            print("Selected: \(exerciseId)")
        },
        onDismiss: {
            print("Dismissed")
        }
    )
}
