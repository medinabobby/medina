//
// ExerciseHeaderView.swift
// Medina
//
// v79.3: Unified exercise header component for consistent display
// Created: December 2025
// Purpose: Standardized Name + Equipment Badge pattern across all views
//

import SwiftUI

/// Unified exercise header showing name and equipment badge
/// Used across FocusedExecutionView, ExerciseDetailView, ExerciseCard, ExerciseDetailsSheet
struct ExerciseHeaderView: View {
    let exercise: Exercise

    /// Header size determines font sizing and spacing
    var size: HeaderSize = .large

    /// Alignment for the header content
    var alignment: HorizontalAlignment = .center

    /// Whether equipment badge is tappable (e.g., for equipment swap)
    var equipmentTappable: Bool = false

    /// Action when equipment badge is tapped
    var onEquipmentTap: (() -> Void)? = nil

    enum HeaderSize {
        case large   // 28pt name, used in FocusedExecutionView, ExerciseDetailView
        case medium  // 16pt name, used in ExerciseCard, sheets
        case compact // 14pt name, used in compact list rows

        var nameFont: Font {
            switch self {
            case .large: return .system(size: 28, weight: .bold)
            case .medium: return .system(size: 16, weight: .medium)
            case .compact: return .system(size: 14, weight: .medium)
            }
        }

        var equipmentFont: Font {
            switch self {
            case .large: return .system(size: 15, weight: .medium)
            case .medium: return .system(size: 13)
            case .compact: return .system(size: 12)
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .large: return 13
            case .medium: return 11
            case .compact: return 10
            }
        }

        var chevronSize: CGFloat {
            switch self {
            case .large: return 11
            case .medium: return 9
            case .compact: return 8
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .large: return 12
            case .medium: return 8
            case .compact: return 6
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .large: return 6
            case .medium: return 4
            case .compact: return 3
            }
        }

        var spacing: CGFloat {
            switch self {
            case .large: return 8
            case .medium: return 4
            case .compact: return 3
            }
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: size.spacing) {
            // Exercise name
            Text(exercise.name)
                .font(size.nameFont)
                .foregroundColor(Color("PrimaryText"))
                .multilineTextAlignment(alignment == .center ? .center : .leading)

            // Equipment badge (skip for bodyweight since it's implicit)
            if exercise.equipment != .bodyweight && exercise.equipment != .none {
                equipmentBadge
            }
        }
    }

    @ViewBuilder
    private var equipmentBadge: some View {
        let badgeContent = HStack(spacing: 6) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: size.iconSize))
            Text(exercise.equipment.displayName)
                .font(size.equipmentFont)
            if equipmentTappable {
                Image(systemName: "chevron.down")
                    .font(.system(size: size.chevronSize, weight: .semibold))
            }
        }
        .foregroundColor(Color("SecondaryText"))
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Color("BackgroundSecondary"))
        .cornerRadius(8)

        if equipmentTappable, let onTap = onEquipmentTap {
            Button(action: onTap) {
                badgeContent
            }
        } else {
            badgeContent
        }
    }
}

// MARK: - Preview

#Preview("Large - FocusedExecution Style") {
    VStack(spacing: 32) {
        if let exercise = LocalDataStore.shared.exercises["barbell_bench_press"] {
            ExerciseHeaderView(
                exercise: exercise,
                size: .large,
                equipmentTappable: true,
                onEquipmentTap: { print("Swap equipment") }
            )
        }

        if let exercise = LocalDataStore.shared.exercises["bodyweight_pushups"] ?? LocalDataStore.shared.exercises.values.first(where: { $0.equipment == .bodyweight }) {
            ExerciseHeaderView(
                exercise: exercise,
                size: .large
            )
        }
    }
    .padding()
    .background(Color("Background"))
}

#Preview("Medium - ExerciseCard Style") {
    VStack(alignment: .leading, spacing: 16) {
        if let exercise = LocalDataStore.shared.exercises["barbell_bench_press"] {
            ExerciseHeaderView(
                exercise: exercise,
                size: .medium,
                alignment: .leading
            )
        }

        if let exercise = LocalDataStore.shared.exercises["dumbbell_row"] ?? LocalDataStore.shared.exercises.values.first(where: { $0.equipment == .dumbbells }) {
            ExerciseHeaderView(
                exercise: exercise,
                size: .medium,
                alignment: .leading
            )
        }
    }
    .padding()
    .background(Color("BackgroundSecondary"))
}

#Preview("Compact - List Row Style") {
    VStack(alignment: .leading, spacing: 12) {
        if let exercise = LocalDataStore.shared.exercises["barbell_bench_press"] {
            ExerciseHeaderView(
                exercise: exercise,
                size: .compact,
                alignment: .leading
            )
        }
    }
    .padding()
}
