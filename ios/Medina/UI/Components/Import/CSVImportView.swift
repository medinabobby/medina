//
// CSVImportView.swift
// Medina
//
// v74.4: CSV import preview and confirmation UI
// Shows parsed workout data and allows user to import
// Created: December 2, 2025
//

import SwiftUI

struct CSVImportView: View {
    @Environment(\.dismiss) var dismiss
    let fileURL: URL
    let user: UnifiedUser

    @State private var importResult: CSVImportResult?
    @State private var error: Error?
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var importSuccess = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = error {
                    errorView(error)
                } else if let result = importResult {
                    resultView(result)
                }
            }
            .navigationTitle("Import Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if importResult != nil && !importSuccess {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            performImport()
                        }
                        .disabled(isImporting)
                    }
                }
            }
        }
        .onAppear {
            parseFile()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Parsing workout data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Import Error")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                parseFile()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Result View

    private func resultView(_ result: CSVImportResult) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success state
                if importSuccess {
                    successView(result)
                } else {
                    // Preview
                    previewHeader(result)
                    exerciseList(result)
                    unmatchedSection(result)
                }
            }
            .padding()
        }
    }

    // MARK: - Preview Header

    private func previewHeader(_ result: CSVImportResult) -> some View {
        VStack(spacing: 16) {
            // Summary stats
            HStack(spacing: 32) {
                StatBox(
                    value: "\(result.workouts.count)",
                    label: "Workouts"
                )

                StatBox(
                    value: "\(result.uniqueExercises.count)",
                    label: "Exercises"
                )

                StatBox(
                    value: "\(result.totalSets)",
                    label: "Sets"
                )
            }

            // Date range
            if let firstDate = result.workouts.first?.date,
               let lastDate = result.workouts.last?.date {
                Text(formatDateRange(firstDate, lastDate))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Exercise List

    private func exerciseList(_ result: CSVImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises Found")
                .font(.headline)

            let matchedCount = result.uniqueExercises.count - result.unmatchedExercises.count

            Text("\(matchedCount) matched to library")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ForEach(Array(result.uniqueExercises.keys.sorted()), id: \.self) { name in
                if let rm = result.uniqueExercises[name] {
                    ExerciseRow(name: name, estimated1RM: rm, isMatched: !result.unmatchedExercises.contains(name))
                }
            }
        }
    }

    // MARK: - Unmatched Section

    @ViewBuilder
    private func unmatchedSection(_ result: CSVImportResult) -> some View {
        if !result.unmatchedExercises.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Not Matched")
                    .font(.headline)
                    .foregroundColor(.orange)

                Text("These exercises weren't found in the library and won't be imported:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(result.unmatchedExercises, id: \.self) { name in
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.orange)
                        Text(name)
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        }
    }

    // MARK: - Success View

    private func successView(_ result: CSVImportResult) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Import Complete!")
                .font(.title2)
                .fontWeight(.semibold)

            let matchedCount = result.uniqueExercises.count - result.unmatchedExercises.count
            Text("\(matchedCount) exercises imported with 1RM estimates")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Your weight recommendations will now be more accurate.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func parseFile() {
        isLoading = true
        error = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: fileURL)
                let result = try CSVImportService.parseCSV(data: data)

                DispatchQueue.main.async {
                    self.importResult = result
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }

    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private func performImport() {
        guard let result = importResult else { return }

        isImporting = true

        let targets = CSVImportService.createExerciseTargets(
            from: result,
            userId: user.id
        )

        // Save to LocalDataStore
        for target in targets {
            LocalDataStore.shared.targets[target.id] = target
        }

        // Add matched exercises to user's library (for sidebar + 1.2x scoring boost)
        let matchedExerciseIds = targets.map { $0.exerciseId }
        do {
            try LibraryPersistenceService.addExercises(matchedExerciseIds, userId: user.id)
        } catch {
            Logger.log(.error, component: "CSVImportView",
                       message: "Failed to add exercises to library: \(error)")
        }

        Logger.log(.info, component: "CSVImportView",
                   message: "Imported \(targets.count) exercise targets from CSV")

        isImporting = false
        importSuccess = true
    }
}

// MARK: - Supporting Views

private struct StatBox: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct ExerciseRow: View {
    let name: String
    let estimated1RM: Double
    let isMatched: Bool

    var body: some View {
        HStack {
            Image(systemName: isMatched ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMatched ? .green : .gray)

            Text(name)
                .font(.subheadline)

            Spacer()

            Text("\(Int(estimated1RM)) lb")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    CSVImportView(
        fileURL: URL(fileURLWithPath: "/tmp/test.csv"),
        user: UnifiedUser(
            id: "bobby",
            firebaseUID: "test",
            authProvider: .email,
            email: "bobby@test.com",
            name: "Bobby",
            birthdate: Date(),
            gender: .male,
            roles: [.member],
            memberProfile: nil
        )
    )
}
