//
// URLImportView.swift
// Medina
//
// v106: URL import preview and analysis view
// Created: December 10, 2025
//
// Shows URL input, preview, triggers AI analysis,
// displays extraction results before import confirmation.
//

import SwiftUI

struct URLImportView: View {
    let user: UnifiedUser
    var onImportComplete: ((ImportProcessingResult) -> Void)?
    @Environment(\.dismiss) var dismiss

    @State private var urlString = ""
    @State private var isAnalyzing = false
    @State private var extractionResult: URLExtractionResult?
    @State private var error: Error?
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // URL Input
                    urlInputSection

                    if isAnalyzing {
                        analyzingView
                    } else if let result = extractionResult {
                        extractionResultsView(result)
                    } else if let error = error {
                        errorView(error)
                    } else if !urlString.isEmpty && isValidURL {
                        analyzeButton
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Check clipboard for URL
                if let clipboardString = UIPasteboard.general.string,
                   clipboardString.hasPrefix("http"),
                   URL(string: clipboardString) != nil {
                    urlString = clipboardString
                }
                isURLFieldFocused = true
            }
        }
    }

    // MARK: - URL Input Section

    private var urlInputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)

                TextField("Paste workout program URL", text: $urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        if isValidURL {
                            analyzeURL()
                        }
                    }

                if !urlString.isEmpty {
                    Button {
                        urlString = ""
                        extractionResult = nil
                        error = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // Paste from clipboard hint
            if urlString.isEmpty {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                    Text("Paste a URL from T-Nation, Reddit, or any fitness article")
                        .font(.system(size: 14))
                }
                .foregroundColor(.secondary)
            }

            // URL validation feedback
            if !urlString.isEmpty && !isValidURL {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                    Text("Please enter a valid URL")
                        .font(.system(size: 14))
                }
                .foregroundColor(.orange)
            }
        }
    }

    private var isValidURL: Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    // MARK: - Analyze Button

    private var analyzeButton: some View {
        Button(action: analyzeURL) {
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

            Text("Analyzing webpage...")
                .font(.system(size: 17, weight: .medium))

            Text("Extracting workout program with GPT-4")
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
    private func extractionResultsView(_ result: URLExtractionResult) -> some View {
        VStack(spacing: 16) {
            // Header with source info
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.programName ?? "Program Found")
                        .font(.system(size: 17, weight: .semibold))
                    Text(result.sourceType.displayName)
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

            // Program description
            if let description = result.description {
                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
            }

            // Weekly schedule
            if let schedule = result.weeklySchedule, !schedule.isEmpty {
                scheduleView(schedule)
            }

            // Summary stats
            summaryStats(result)

            // Exercise list
            exerciseList(result)

            // Import button
            importButton(result)
        }
    }

    private func scheduleView(_ schedule: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Schedule")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(schedule.enumerated()), id: \.offset) { index, day in
                        VStack(spacing: 4) {
                            Text("Day \(index + 1)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(day)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(day.lowercased() == "rest" ? Color.gray.opacity(0.1) : Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func summaryStats(_ result: URLExtractionResult) -> some View {
        HStack(spacing: 0) {
            statItem(value: "\(result.exercises.count)", label: "Exercises")
            Divider().frame(height: 40)
            statItem(value: "\(uniqueDays(result))", label: "Days")
            if let duration = result.duration {
                Divider().frame(height: 40)
                statItem(value: "\(duration)", label: "Weeks")
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

    private func exerciseList(_ result: URLExtractionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercises Found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(result.exercises.prefix(10).enumerated()), id: \.offset) { index, exercise in
                    exerciseRow(exercise)

                    if index < min(result.exercises.count - 1, 9) {
                        Divider()
                            .padding(.leading, 16)
                    }
                }

                if result.exercises.count > 10 {
                    HStack {
                        Text("+ \(result.exercises.count - 10) more exercises")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
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

                if let notes = exercise.notes {
                    Text(notes)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(16)
    }

    private func importButton(_ result: URLExtractionResult) -> some View {
        Button(action: { processImport(result) }) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 18))
                Text("Import Program")
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
                analyzeURL()
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

    private func analyzeURL() {
        guard isValidURL else { return }

        isAnalyzing = true
        error = nil
        extractionResult = nil

        Task {
            do {
                let result = try await URLExtractionService.extractProgramData(from: urlString)
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

    private func processImport(_ result: URLExtractionResult) {
        // Convert URL extraction result to ImportedWorkoutData
        let importData = URLToImportConverter.convert(result, userId: user.id)

        do {
            // Process through existing pipeline
            let processingResult = try ImportProcessingService.process(importData, userId: user.id)

            Logger.log(.info, component: "URLImportView",
                       message: "URL import complete: \(processingResult.targets.count) targets")

            onImportComplete?(processingResult)
            dismiss()
        } catch {
            Logger.log(.error, component: "URLImportView",
                       message: "URL import failed: \(error)")
            self.error = error
        }
    }

    // MARK: - Helpers

    private func uniqueDays(_ result: URLExtractionResult) -> Int {
        if let schedule = result.weeklySchedule {
            return Set(schedule.filter { $0.lowercased() != "rest" }).count
        }
        // Count unique days from exercise notes
        let days = result.exercises.compactMap { exercise -> String? in
            guard let notes = exercise.notes else { return nil }
            // Extract day info from notes like "Push: 3x8-12"
            let components = notes.split(separator: ":")
            return components.first.map(String.init)
        }
        return max(Set(days).count, 1)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - URL to Import Converter

enum URLToImportConverter {
    /// Convert URL extraction result to ImportedWorkoutData for processing pipeline
    static func convert(_ result: URLExtractionResult, userId: String) -> ImportedWorkoutData {
        var exercises: [ImportedExerciseData] = []
        var sessionExercises: [ImportedSessionExercise] = []

        for exercise in result.exercises {
            // Create aggregated exercise data
            var exerciseData = ImportedExerciseData(exerciseName: exercise.name)

            // Create sets for session history
            var importedSets: [ImportedSet] = []

            if !exercise.sets.isEmpty {
                for set in exercise.sets {
                    // Use actual weight/reps if provided
                    let weight = set.weight ?? 0
                    let reps = set.reps ?? 10  // Default to 10 reps if not specified

                    importedSets.append(ImportedSet(
                        reps: reps,
                        weight: weight
                    ))

                    // Track for aggregated data
                    if exerciseData.recentWeight == nil || weight > (exerciseData.recentWeight ?? 0) {
                        exerciseData.recentWeight = weight
                        exerciseData.recentReps = reps
                    }
                }
            }

            exercises.append(exerciseData)
            sessionExercises.append(ImportedSessionExercise(
                exerciseName: exercise.name,
                sets: importedSets
            ))
        }

        // Create a single session representing the program template
        let session = ImportedSession(
            sessionNumber: 1,
            date: Date(),
            exercises: sessionExercises
        )

        return ImportedWorkoutData(
            userId: userId,
            exercises: exercises,
            sessions: [session],
            source: .url
        )
    }
}

// MARK: - Preview

#Preview {
    URLImportView(
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
