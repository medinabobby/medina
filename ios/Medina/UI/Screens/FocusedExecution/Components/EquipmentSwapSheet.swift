//
// EquipmentSwapSheet.swift
// Medina
//
// v79.0: Quick equipment swap without full exercise substitution
// v79.2: UX audit - visible drag indicator, swipe-only dismiss (no Cancel button)
// Created: December 2025
// Purpose: Allow user to change equipment variant (e.g., barbell → dumbbell) for same base exercise
//

import SwiftUI

/// Sheet for swapping equipment variant of current exercise
/// Shows exercises with same baseExercise but different equipment
struct EquipmentSwapSheet: View {
    let currentExercise: Exercise
    let workoutId: String
    let instanceId: String
    let onSwap: (String) -> Void  // Returns new exercise ID
    let onDismiss: () -> Void

    @State private var availableVariants: [Exercise] = []

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Change Equipment")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color("PrimaryText"))

                Text("Same exercise, different equipment")
                    .font(.system(size: 14))
                    .foregroundColor(Color("SecondaryText"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Current equipment indicator
            HStack(spacing: 12) {
                Image(systemName: equipmentIcon(for: currentExercise.equipment))
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current")
                        .font(.system(size: 12))
                        .foregroundColor(Color("SecondaryText"))
                    Text(currentExercise.equipment.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color("PrimaryText"))
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)

            // Available variants
            if availableVariants.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(Color("SecondaryText"))
                    Text("No other equipment variants available")
                        .font(.system(size: 15))
                        .foregroundColor(Color("SecondaryText"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(availableVariants) { variant in
                        equipmentRow(for: variant)
                    }
                }
            }
        }
        .padding(20)
        .background(Color("Background"))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadVariants()
        }
    }

    // MARK: - Components

    private func equipmentRow(for variant: Exercise) -> some View {
        Button(action: {
            onSwap(variant.id)
        }) {
            HStack(spacing: 12) {
                Image(systemName: equipmentIcon(for: variant.equipment))
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.equipment.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color("PrimaryText"))

                    if variant.name != currentExercise.name {
                        Text(variant.name)
                            .font(.system(size: 13))
                            .foregroundColor(Color("SecondaryText"))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))
            }
            .padding(12)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadVariants() {
        // Find all exercises with same baseExercise but different equipment
        let allExercises = TestDataManager.shared.exercises.values

        availableVariants = allExercises.filter { exercise in
            exercise.baseExercise == currentExercise.baseExercise &&
            exercise.equipment != currentExercise.equipment &&
            exercise.id != currentExercise.id
        }
        .sorted { $0.equipment.displayName < $1.equipment.displayName }
    }

    private func equipmentIcon(for equipment: Equipment) -> String {
        switch equipment {
        case .barbell:
            return "figure.strengthtraining.traditional"
        case .dumbbells:
            return "dumbbell"
        case .cableMachine, .machine:
            return "gearshape.2"
        case .bodyweight:
            return "figure.walk"
        case .kettlebell:
            return "scalemass"
        case .resistanceBand:
            return "arrow.left.arrow.right"
        case .smith:
            return "square.grid.3x3"
        default:
            return "figure.strengthtraining.traditional"
        }
    }
}

// MARK: - Preview

#Preview("Equipment Swap Sheet") {
    if let exercise = TestDataManager.shared.exercises["bench_press"] {
        EquipmentSwapSheet(
            currentExercise: exercise,
            workoutId: "test_workout",
            instanceId: "test_instance",
            onSwap: { newId in print("Swap to: \(newId)") },
            onDismiss: { print("Dismiss") }
        )
    } else {
        Text("Exercise not found")
    }
}
