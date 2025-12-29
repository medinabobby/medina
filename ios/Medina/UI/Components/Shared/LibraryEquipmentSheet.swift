//
// LibraryEquipmentSheet.swift
// Medina
//
// v79.4: Equipment variant selector for library/sidebar context
// Created: December 2025
// Purpose: Browse exercise equipment variants without workout context
//
// Different from EquipmentSwapSheet (FocusedExecution):
// - EquipmentSwapSheet: Swaps exercise during workout execution
// - LibraryEquipmentSheet: Navigates to variant's detail view in sidebar
//

import SwiftUI

/// Sheet for browsing equipment variants in library context
/// Selecting a variant navigates to that exercise's detail view
struct LibraryEquipmentSheet: View {
    let currentExercise: Exercise
    let onSelect: (String) -> Void  // Returns selected exercise ID

    @State private var variants: [Exercise] = []

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Equipment Variants")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color("PrimaryText"))

                Text("Same exercise, different equipment")
                    .font(.system(size: 14))
                    .foregroundColor(Color("SecondaryText"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Current equipment (highlighted)
            currentEquipmentRow

            // Divider
            if !variants.isEmpty {
                HStack {
                    Text("Other Options")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color("SecondaryText"))
                    Spacer()
                }
            }

            // Available variants
            if variants.isEmpty {
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
                    ForEach(variants) { variant in
                        variantRow(for: variant)
                    }
                }
            }

            Spacer()
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

    private var currentEquipmentRow: some View {
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
    }

    private func variantRow(for variant: Exercise) -> some View {
        Button(action: {
            onSelect(variant.id)
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

                    // Show variant name if different (e.g., "Sumo Deadlift")
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
        // Use ExerciseDataStore method for consistent results
        variants = ExerciseDataStore.alternateEquipmentVariants(for: currentExercise)
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

#Preview("Library Equipment Sheet") {
    if let exercise = TestDataManager.shared.exercises["bench_press"] ?? TestDataManager.shared.exercises.values.first {
        LibraryEquipmentSheet(
            currentExercise: exercise,
            onSelect: { id in print("Selected: \(id)") }
        )
    } else {
        Text("No exercises available")
    }
}
