//
// ManualPREntryView.swift
// Medina
//
// v72.0: Manual PR entry for users to input their maxes directly
// Created: December 1, 2025
//

import SwiftUI

struct ManualPREntryView: View {
    let user: UnifiedUser
    @Environment(\.dismiss) var dismiss

    // Entry state
    @State private var entries: [PREntry] = []
    @State private var showAddExercise = false
    @State private var isSaving = false
    @State private var showSuccessMessage = false

    // Common compound exercises for quick selection
    private let commonExercises: [(id: String, name: String)] = [
        ("barbell_back_squat", "Barbell Back Squat"),
        ("conventional_deadlift", "Conventional Deadlift"),
        ("barbell_bench_press", "Barbell Bench Press"),
        ("overhead_press", "Overhead Press"),
        ("barbell_row", "Barbell Row"),
        ("pull_up", "Pull-up"),
        ("romanian_deadlift", "Romanian Deadlift"),
        ("incline_barbell_bench_press", "Incline Bench Press")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter your personal records")
                        .font(.system(size: 17, weight: .semibold))

                    Text("Add your 1RM (one rep max) or recent working weights. This helps Medina give you accurate weight recommendations.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

                // Existing entries
                if !entries.isEmpty {
                    VStack(spacing: 12) {
                        ForEach($entries) { $entry in
                            PREntryRow(entry: $entry, onDelete: {
                                withAnimation {
                                    entries.removeAll { $0.id == entry.id }
                                }
                            })
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Quick add common exercises
                if entries.isEmpty {
                    quickAddSection
                }

                // Add exercise button
                Button {
                    showAddExercise = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                        Text(entries.isEmpty ? "Add Exercise" : "Add Another Exercise")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 16)

                // Success message
                if showSuccessMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("PRs saved successfully!")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                }

                Spacer(minLength: 100)
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Manual Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveEntries()
                }
                .disabled(entries.isEmpty || !hasValidEntries || isSaving)
            }
        }
        .sheet(isPresented: $showAddExercise) {
            ExerciseSearchSheet(
                onSelect: { exerciseId, exerciseName in
                    addEntry(exerciseId: exerciseId, exerciseName: exerciseName)
                }
            )
        }
    }

    // MARK: - Quick Add Section

    private var quickAddSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMMON EXERCISES")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(commonExercises, id: \.id) { exercise in
                        Button {
                            addEntry(exerciseId: exercise.id, exerciseName: exercise.name)
                        } label: {
                            Text(exercise.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(.systemBackground))
                                .cornerRadius(20)
                                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                        }
                        .disabled(entries.contains { $0.exerciseId == exercise.id })
                        .opacity(entries.contains { $0.exerciseId == exercise.id } ? 0.5 : 1)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Helpers

    private var hasValidEntries: Bool {
        entries.allSatisfy { $0.isValid }
    }

    private func addEntry(exerciseId: String, exerciseName: String) {
        // Don't add duplicates
        guard !entries.contains(where: { $0.exerciseId == exerciseId }) else { return }

        let entry = PREntry(exerciseId: exerciseId, exerciseName: exerciseName)
        withAnimation {
            entries.append(entry)
        }
    }

    private func saveEntries() {
        guard !entries.isEmpty else { return }

        isSaving = true

        // Create ExerciseTargets for each valid entry
        for entry in entries where entry.isValid {
            let targetId = "\(user.id)-\(entry.exerciseId)"

            var target = LocalDataStore.shared.targets[targetId] ?? ExerciseTarget(
                id: targetId,
                exerciseId: entry.exerciseId,
                memberId: user.id,
                targetType: .max,
                currentTarget: nil,
                lastCalibrated: nil,
                targetHistory: []
            )

            // Update with imported value
            let effectiveMax = entry.effectiveMax
            target.currentTarget = effectiveMax
            target.lastCalibrated = Date()

            // Add to history
            let historyEntry = ExerciseTarget.TargetEntry(
                date: Date(),
                target: effectiveMax ?? 0,
                calibrationSource: "manual_import"
            )
            target.targetHistory.append(historyEntry)

            // Save to LocalDataStore
            LocalDataStore.shared.targets[targetId] = target

            Logger.log(.info, component: "ManualPREntryView",
                      message: "Saved PR for \(entry.exerciseName): \(effectiveMax ?? 0) lbs")
        }

        // v206: Removed legacy disk persistence - Firestore is source of truth
        // TODO: Add Firestore target sync when ready

        // Also add exercises to library if not already there
        let exerciseIds = entries.map { $0.exerciseId }
        do {
            try LibraryPersistenceService.addExercises(exerciseIds, userId: user.id)
        } catch {
            Logger.log(.error, component: "ManualPREntryView", message: "Failed to add to library: \(error)")
        }

        isSaving = false

        // Show success and dismiss
        withAnimation {
            showSuccessMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}

// MARK: - PR Entry Model

struct PREntry: Identifiable {
    let id = UUID()
    let exerciseId: String
    let exerciseName: String
    var oneRepMax: String = ""
    var workingWeight: String = ""
    var workingReps: String = ""
    var entryMode: EntryMode = .oneRepMax

    enum EntryMode: String, CaseIterable {
        case oneRepMax = "1RM"
        case workingWeight = "Working"

        var description: String {
            switch self {
            case .oneRepMax: return "Enter your 1 rep max"
            case .workingWeight: return "Enter recent weight & reps"
            }
        }
    }

    var isValid: Bool {
        switch entryMode {
        case .oneRepMax:
            return Double(oneRepMax) != nil && (Double(oneRepMax) ?? 0) > 0
        case .workingWeight:
            let weight = Double(workingWeight) ?? 0
            let reps = Int(workingReps) ?? 0
            return weight > 0 && reps > 0 && reps <= 20
        }
    }

    var effectiveMax: Double? {
        switch entryMode {
        case .oneRepMax:
            return Double(oneRepMax)
        case .workingWeight:
            guard let weight = Double(workingWeight),
                  let reps = Int(workingReps),
                  reps > 0, reps <= 12 else { return nil }
            // Brzycki formula
            return weight * (36.0 / (37.0 - Double(reps)))
        }
    }
}

// MARK: - PR Entry Row

private struct PREntryRow: View {
    @Binding var entry: PREntry
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with exercise name and delete
            HStack {
                Text(entry.exerciseName)
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }

            // Entry mode picker
            Picker("Entry Mode", selection: $entry.entryMode) {
                ForEach(PREntry.EntryMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Input fields based on mode
            if entry.entryMode == .oneRepMax {
                HStack {
                    Text("1RM")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)

                    TextField("225", text: $entry.oneRepMax)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    Text("lbs")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("Weight")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)

                        TextField("185", text: $entry.workingWeight)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)

                        Text("lbs")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Reps")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)

                        TextField("5", text: $entry.workingReps)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)

                        Text("reps")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }

                    // Estimated 1RM display
                    if let estimated = entry.effectiveMax {
                        Text("Estimated 1RM: \(Int(estimated)) lbs")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Exercise Search Sheet

private struct ExerciseSearchSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSelect: (String, String) -> Void

    @State private var searchText = ""

    private var allExercises: [(id: String, name: String)] {
        LocalDataStore.shared.exercises.values
            .map { ($0.id, $0.name) }
            .sorted { $0.1 < $1.1 }
    }

    private var filteredExercises: [(id: String, name: String)] {
        if searchText.isEmpty {
            return allExercises
        }
        return allExercises.filter {
            $0.1.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredExercises, id: \.id) { exercise in
                    Button {
                        onSelect(exercise.id, exercise.name)
                        dismiss()
                    } label: {
                        Text(exercise.name)
                            .foregroundColor(.primary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ManualPREntryView(
            user: UnifiedUser(
                id: "bobby",
                firebaseUID: "test",
                authProvider: .email,
                email: "bobby@medina.com",
                name: "Bobby Tulsiani",
                birthdate: Date(),
                gender: .male,
                roles: [.member],
                memberProfile: MemberProfile(
                    fitnessGoal: .strength,
                    experienceLevel: .intermediate,
                    preferredSessionDuration: 60,
                    membershipStatus: .active,
                    memberSince: Date()
                )
            )
        )
    }
}
