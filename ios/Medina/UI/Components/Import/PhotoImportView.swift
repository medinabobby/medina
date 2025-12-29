//
// PhotoImportView.swift
// Medina
//
// v79.5: Photo import preview and analysis view
// Created: December 3, 2025
//
// Shows selected image preview, triggers Vision API analysis,
// displays extraction results before import confirmation.
//

import SwiftUI

struct PhotoImportView: View {
    let image: UIImage
    let user: UnifiedUser
    var onImportComplete: ((ImportProcessingResult) -> Void)?
    @Environment(\.dismiss) var dismiss

    @State private var isAnalyzing = false
    @State private var extractionResult: VisionExtractionResult?
    @State private var importResult: ImportProcessingResult?
    @State private var error: Error?
    @State private var showingConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image Preview
                    imagePreview

                    if isAnalyzing {
                        analyzingView
                    } else if let result = extractionResult {
                        extractionResultsView(result)
                    } else if let error = error {
                        errorView(error)
                    } else {
                        analyzeButton
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import from Photo")
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

    // MARK: - Image Preview

    private var imagePreview: some View {
        VStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)

            Text("Photo ready for analysis")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Analyze Button

    private var analyzeButton: some View {
        Button(action: analyzeImage) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                Text("Analyze with AI")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.blue)
            .cornerRadius(12)
        }
    }

    // MARK: - Analyzing View

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Analyzing image...")
                .font(.system(size: 17, weight: .medium))

            Text("Using GPT-4o Vision to extract workout data")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Extraction Results View

    @ViewBuilder
    private func extractionResultsView(_ result: VisionExtractionResult) -> some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Data Extracted")
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(result.sourceType.displayName) detected")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Confidence badge
                Text("\(Int(result.confidence * 100))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(confidenceColor(result.confidence))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(confidenceColor(result.confidence).opacity(0.15))
                    .cornerRadius(8)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // Summary stats
            summaryStats(result)

            // Exercise list
            exerciseList(result)

            // Import button
            importButton(result)
        }
    }

    private func summaryStats(_ result: VisionExtractionResult) -> some View {
        HStack(spacing: 0) {
            statItem(value: "\(result.exercises.count)", label: "Exercises")
            Divider().frame(height: 40)
            statItem(value: "\(totalSets(result))", label: "Sets")
            if let dates = result.dates, !dates.isEmpty {
                Divider().frame(height: 40)
                statItem(value: "\(dates.count)", label: "Dates")
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func exerciseList(_ result: VisionExtractionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercises Found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(result.exercises.enumerated()), id: \.offset) { index, exercise in
                    exerciseRow(exercise)

                    if index < result.exercises.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    private func exerciseRow(_ exercise: ExtractedExercise) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 16, weight: .medium))

                Text(setsSummary(exercise.sets))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let date = exercise.date {
                Text(formatDate(date))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    private func importButton(_ result: VisionExtractionResult) -> some View {
        Button(action: { processImport(result) }) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 18))
                Text("Import \(result.exercises.count) Exercises")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.green)
            .cornerRadius(12)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Extraction Failed")
                .font(.system(size: 17, weight: .semibold))

            Text(error.localizedDescription)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                self.error = nil
                analyzeImage()
            }
            .foregroundColor(.blue)
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func analyzeImage() {
        isAnalyzing = true
        error = nil

        Task {
            do {
                let result = try await VisionExtractionService.extractWorkoutData(from: image)
                await MainActor.run {
                    extractionResult = result
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isAnalyzing = false
                }
            }
        }
    }

    private func processImport(_ result: VisionExtractionResult) {
        // Convert extraction result to ImportedWorkoutData
        let importData = VisionToImportConverter.convert(result, userId: user.id)

        do {
            // Process through existing pipeline
            let processingResult = try ImportProcessingService.process(importData, userId: user.id)

            Logger.log(.info, component: "PhotoImportView",
                       message: "Photo import complete: \(processingResult.targets.count) targets")

            onImportComplete?(processingResult)
            dismiss()
        } catch {
            Logger.log(.error, component: "PhotoImportView",
                       message: "Photo import failed: \(error)")
            self.error = error
        }
    }

    // MARK: - Helpers

    private func totalSets(_ result: VisionExtractionResult) -> Int {
        result.exercises.reduce(0) { $0 + $1.sets.count }
    }

    private func setsSummary(_ sets: [ExtractedSet]) -> String {
        guard !sets.isEmpty else { return "No sets" }

        let validSets = sets.filter { $0.weight != nil || $0.reps != nil }
        guard !validSets.isEmpty else { return "\(sets.count) sets" }

        // Get max weight and typical reps
        if let maxWeight = validSets.compactMap({ $0.weight }).max(),
           let reps = validSets.compactMap({ $0.reps }).first {
            return "\(validSets.count) sets × \(reps) @ \(Int(maxWeight)) lbs"
        } else if let maxWeight = validSets.compactMap({ $0.weight }).max() {
            return "\(validSets.count) sets @ \(Int(maxWeight)) lbs"
        } else {
            return "\(validSets.count) sets"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Preview

#Preview {
    PhotoImportView(
        image: UIImage(systemName: "photo")!,
        user: UnifiedUser(
            id: "test",
            firebaseUID: "test",
            authProvider: .email,
            email: "test@test.com",
            name: "Test User",
            birthdate: Date(),
            gender: .male,
            roles: [.member],
            memberProfile: nil
        )
    )
}
