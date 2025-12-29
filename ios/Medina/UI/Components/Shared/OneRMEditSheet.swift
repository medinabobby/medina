//
// OneRMEditSheet.swift
// Medina
//
// v79.3: Focused 1RM editor for single exercise
// Created: December 2025
// Purpose: Edit or add 1RM from ExerciseDetailView
//

import SwiftUI

/// Sheet for editing or adding a 1RM for a single exercise
/// Simpler than ManualPREntryView (which handles multiple exercises)
struct OneRMEditSheet: View {
    let exercise: Exercise
    let userId: String
    let existingTarget: ExerciseTarget?
    let onSave: (Double) -> Void
    let onDismiss: () -> Void

    @State private var entryMode: EntryMode = .oneRepMax
    @State private var oneRepMaxText = ""
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var isSaving = false

    enum EntryMode: String, CaseIterable {
        case oneRepMax = "1RM"
        case workingWeight = "Working"

        var description: String {
            switch self {
            case .oneRepMax: return "Enter your 1 rep max directly"
            case .workingWeight: return "Calculate from weight & reps"
            }
        }
    }

    init(
        exercise: Exercise,
        userId: String,
        existingTarget: ExerciseTarget? = nil,
        onSave: @escaping (Double) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.exercise = exercise
        self.userId = userId
        self.existingTarget = existingTarget
        self.onSave = onSave
        self.onDismiss = onDismiss

        // Pre-fill with existing value if editing
        if let current = existingTarget?.currentTarget {
            _oneRepMaxText = State(initialValue: String(Int(current)))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Exercise header
                    ExerciseHeaderView(
                        exercise: exercise,
                        size: .large,
                        alignment: .center,
                        equipmentTappable: false
                    )
                    .padding(.top, 8)

                    // Entry mode picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW DO YOU WANT TO ENTER?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color("SecondaryText"))

                        Picker("Entry Mode", selection: $entryMode) {
                            ForEach(EntryMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(entryMode.description)
                            .font(.system(size: 13))
                            .foregroundColor(Color("SecondaryText"))
                    }
                    .padding(.horizontal, 20)

                    // Input fields
                    VStack(spacing: 16) {
                        if entryMode == .oneRepMax {
                            oneRepMaxInput
                        } else {
                            workingWeightInput
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .background(Color("Background"))
            .navigationTitle(existingTarget != nil ? "Edit 1RM" : "Add 1RM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid || isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Input Views

    private var oneRepMaxInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1RM (ONE REP MAX)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("SecondaryText"))

            HStack(spacing: 12) {
                TextField("225", text: $oneRepMaxText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
                    .background(Color("BackgroundSecondary"))
                    .cornerRadius(12)

                Text("lbs")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))
            }
        }
    }

    private var workingWeightInput: some View {
        VStack(spacing: 16) {
            // Weight input
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT WEIGHT")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color("SecondaryText"))

                HStack(spacing: 12) {
                    TextField("185", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 24, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 14)
                        .background(Color("BackgroundSecondary"))
                        .cornerRadius(12)

                    Text("lbs")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color("SecondaryText"))
                }
            }

            // Reps input
            VStack(alignment: .leading, spacing: 8) {
                Text("REPS COMPLETED")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color("SecondaryText"))

                HStack(spacing: 12) {
                    TextField("5", text: $repsText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 24, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 14)
                        .background(Color("BackgroundSecondary"))
                        .cornerRadius(12)

                    Text("reps")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color("SecondaryText"))
                }
            }

            // Estimated 1RM display
            if let estimated = calculatedMax {
                HStack(spacing: 8) {
                    Image(systemName: "function")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)

                    Text("Estimated 1RM: \(Int(estimated)) lbs")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Validation & Calculation

    private var isValid: Bool {
        switch entryMode {
        case .oneRepMax:
            guard let value = Double(oneRepMaxText) else { return false }
            return value > 0 && value <= 1500
        case .workingWeight:
            guard let weight = Double(weightText),
                  let reps = Int(repsText) else { return false }
            return weight > 0 && weight <= 1500 && reps > 0 && reps <= 20
        }
    }

    private var calculatedMax: Double? {
        switch entryMode {
        case .oneRepMax:
            return Double(oneRepMaxText)
        case .workingWeight:
            guard let weight = Double(weightText),
                  let reps = Int(repsText),
                  reps > 0, reps <= 20 else { return nil }
            // Brzycki formula
            return weight * (36.0 / (37.0 - Double(reps)))
        }
    }

    // MARK: - Save

    private func save() {
        guard let effectiveMax = calculatedMax else { return }

        isSaving = true

        let targetId = "\(userId)-\(exercise.id)"

        // Create or update target
        var target = TestDataManager.shared.targets[targetId] ?? ExerciseTarget(
            id: targetId,
            exerciseId: exercise.id,
            memberId: userId,
            targetType: .max,
            currentTarget: nil,
            lastCalibrated: nil,
            targetHistory: []
        )

        target.currentTarget = effectiveMax
        target.lastCalibrated = Date()

        // Add to history
        let historyEntry = ExerciseTarget.TargetEntry(
            date: Date(),
            target: effectiveMax,
            calibrationSource: "manual_edit"
        )
        target.targetHistory.append(historyEntry)

        // Save to TestDataManager
        TestDataManager.shared.targets[targetId] = target

        // v206: Removed legacy disk persistence - Firestore is source of truth
        // TODO: Add Firestore target sync when ready

        Logger.log(.info, component: "OneRMEditSheet",
                  message: "Saved 1RM for \(exercise.name): \(Int(effectiveMax)) lbs")

        isSaving = false
        onSave(effectiveMax)
    }
}

// MARK: - Preview

#Preview("Add New 1RM") {
    // Use TestDataManager exercise for preview
    if let exercise = TestDataManager.shared.exercises["barbell_bench_press"] {
        OneRMEditSheet(
            exercise: exercise,
            userId: "bobby",
            existingTarget: nil,
            onSave: { max in print("Saved: \(max)") },
            onDismiss: { print("Dismissed") }
        )
    }
}

#Preview("Edit Existing 1RM") {
    // Use TestDataManager exercise for preview
    if let exercise = TestDataManager.shared.exercises["barbell_bench_press"] {
        OneRMEditSheet(
            exercise: exercise,
            userId: "bobby",
            existingTarget: ExerciseTarget(
                id: "bobby-barbell_bench_press",
                exerciseId: "barbell_bench_press",
                memberId: "bobby",
                targetType: .max,
                currentTarget: 225,
                lastCalibrated: Date().addingTimeInterval(-86400 * 14),
                targetHistory: []
            ),
            onSave: { max in print("Saved: \(max)") },
            onDismiss: { print("Dismissed") }
        )
    }
}
