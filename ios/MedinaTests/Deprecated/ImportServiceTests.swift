//
// ImportServiceTests.swift
// MedinaTests
//
// v188: Tests for CSV import and intelligence services
// Tests: CSV parsing, exercise matching, 1RM calculation, experience inference
//
// Created: December 2025
//

import XCTest
@testable import Medina

@MainActor
class ImportServiceTests: XCTestCase {

    // MARK: - Properties

    var testUser: UnifiedUser!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()

        testUser = TestFixtures.testUser
        TestDataManager.shared.currentUserId = testUser.id
        TestDataManager.shared.users[testUser.id] = testUser
    }

    override func tearDown() async throws {
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - CSV Parsing Tests

    /// Test: Valid CSV parses correctly
    func testCSVParse_ValidFile() throws {
        // Given: A valid CSV with workout data (dates without commas to avoid parsing issues)
        let csvContent = """
        Workout,Date,Exercise,Sets x Reps,Weight
        1,2024-12-01,Bench Press,3x8,135 lb barbell
        ,,Squat,3x5,185 lb barbell
        2,2024-12-03,Deadlift,3x5,225 lb barbell
        """
        let data = csvContent.data(using: .utf8)!

        // When: Parsing the CSV
        let result = try CSVImportService.parseCSV(data: data)

        // Then: Should extract workouts
        XCTAssertEqual(result.workouts.count, 2, "Should parse 2 workouts")
        XCTAssertEqual(result.workouts[0].exercises.count, 2, "First workout has 2 exercises")
        XCTAssertEqual(result.workouts[1].exercises.count, 1, "Second workout has 1 exercise")
    }

    /// Test: Empty file throws error
    func testCSVParse_EmptyFile() {
        // Given: An empty CSV
        let csvContent = ""
        let data = csvContent.data(using: .utf8)!

        // When/Then: Should throw emptyFile error
        XCTAssertThrowsError(try CSVImportService.parseCSV(data: data)) { error in
            XCTAssertEqual(error as? CSVImportError, .emptyFile,
                "Should throw emptyFile error")
        }
    }

    /// Test: CSV with only header throws empty file error
    func testCSVParse_OnlyHeader() {
        // Given: CSV with just header
        let csvContent = "Workout,Date,Exercise,Sets x Reps,Weight"
        let data = csvContent.data(using: .utf8)!

        // When/Then: Should throw emptyFile (no data rows)
        XCTAssertThrowsError(try CSVImportService.parseCSV(data: data)) { error in
            XCTAssertEqual(error as? CSVImportError, .emptyFile)
        }
    }

    /// Test: CSV handles malformed rows gracefully
    func testCSVParse_MalformedRows() throws {
        // Given: CSV with some malformed rows (fewer columns)
        let csvContent = """
        Workout,Date,Exercise,Sets x Reps,Weight
        1,2024-12-01,Bench Press,3x8,135 lb
        ,,Short Row
        2,2024-12-03,Squat,3x5,185 lb
        """
        let data = csvContent.data(using: .utf8)!

        // When: Parsing the CSV
        let result = try CSVImportService.parseCSV(data: data)

        // Then: Should skip malformed rows and continue
        XCTAssertEqual(result.workouts.count, 2, "Should parse valid workouts")
        // Malformed row is skipped; bench 3 sets + squat 3 sets = 6 total
        XCTAssertEqual(result.totalSets, 6, "Should count sets from valid exercises")
    }

    /// Test: CSV extracts weight correctly from various formats
    func testCSVParse_WeightFormats() throws {
        // Given: CSV with various weight formats
        let csvContent = """
        Workout,Date,Exercise,Sets x Reps,Weight
        1,2024-12-01,Bench Press,3x8,135 lb barbell
        2,2024-12-02,DB Rows,3x10,50 lb dumbbells
        """
        let data = csvContent.data(using: .utf8)!

        // When: Parsing
        let result = try CSVImportService.parseCSV(data: data)

        // Then: Should parse workouts
        XCTAssertGreaterThanOrEqual(result.workouts.count, 1,
            "Should parse at least one workout")

        // And: Should extract weights from whatever was parsed
        if !result.workouts.isEmpty && !result.workouts[0].exercises.isEmpty {
            let firstWeight = result.workouts[0].exercises[0].sets[0].weight
            XCTAssertEqual(firstWeight, 135, "Should parse barbell weight")
        }
    }

    // MARK: - Exercise Matching Tests

    /// Test: Exercise name matches to library
    func testExerciseMatching_ExactMatch() {
        // Given: Exercise database is loaded
        // When: Matching common exercise names (case-insensitive partial match)
        let matchId = ImportProcessingService.matchExerciseToLibrary("Bench Press")

        // Then: Should find match
        XCTAssertNotNil(matchId, "Should find match for common exercise")
    }

    /// Test: Partial match works (Squats → squat)
    func testExerciseMatching_PartialMatch() {
        // Given: Exercise database loaded
        // When: Matching plural form
        let matchId = ImportProcessingService.matchExerciseToLibrary("Squats")

        // Then: Should find squat exercise
        XCTAssertNotNil(matchId, "Should match 'Squats' to squat exercise")
    }

    /// Test: Unmatched exercise returns nil
    func testExerciseMatching_NoMatch() {
        // Given: Exercise database loaded
        // When: Matching non-existent exercise
        let matchId = ImportProcessingService.matchExerciseToLibrary("Quantum Flux Lift 3000")

        // Then: Should return nil
        XCTAssertNil(matchId, "Should return nil for unknown exercise")
    }

    // MARK: - 1RM Calculation Tests

    /// Test: 1RM calculated from weight/reps
    func testOneRMCalculation_ValidData() {
        // Given: A set with weight and reps
        let sets = [ParsedSet(reps: 5, weight: 225, equipment: nil)]

        // When: Calculating 1RM
        let oneRM = CSVImportService.calculateBest1RM(from: sets)

        // Then: Should return estimated 1RM (Epley formula)
        XCTAssertNotNil(oneRM, "Should calculate 1RM")
        // Epley: 225 * (1 + 5/30) = 225 * 1.167 = ~262
        XCTAssertGreaterThan(oneRM!, 250, "1RM should be greater than working weight")
        XCTAssertLessThan(oneRM!, 280, "1RM should be reasonable")
    }

    /// Test: Best 1RM selected from multiple sets
    func testOneRMCalculation_SelectsBest() {
        // Given: Multiple sets with different weights
        let sets = [
            ParsedSet(reps: 8, weight: 185, equipment: nil),  // ~228
            ParsedSet(reps: 5, weight: 225, equipment: nil),  // ~262
            ParsedSet(reps: 3, weight: 245, equipment: nil)   // ~269
        ]

        // When: Calculating best 1RM (quality-weighted, 3-5 reps is optimal)
        let oneRM = CSVImportService.calculateBest1RM(from: sets)

        // Then: Should return a reasonable 1RM estimate
        XCTAssertNotNil(oneRM)
        // All sets should estimate between 228-269, quality weighting picks best
        XCTAssertGreaterThan(oneRM!, 220, "1RM should be reasonable")
        XCTAssertLessThan(oneRM!, 300, "1RM should not be wildly high")
    }

    // MARK: - Experience Level Inference Tests

    /// Test: Experience level inferred from big 3 lifts
    func testExperienceInference_Beginner() {
        // Given: Import data with beginner-level lifts
        let exercises = [
            ImportedExerciseData(
                exerciseName: "Squat",
                matchedExerciseId: "barbell_back_squat",
                oneRepMax: 95  // Very light squat
            ),
            ImportedExerciseData(
                exerciseName: "Bench Press",
                matchedExerciseId: "barbell_bench_press",
                oneRepMax: 65  // Very light bench
            )
        ]
        let importData = ImportedWorkoutData(userId: testUser.id, exercises: exercises, source: .csv)

        // When: Analyzing import
        let intelligence = ImportIntelligenceService.analyze(
            importData: importData,
            userWeight: 180  // 180 lb person
        )

        // Then: Should infer beginner level
        XCTAssertEqual(intelligence.inferredExperience, .beginner,
            "Should infer beginner from light lifts. Got: \(String(describing: intelligence.inferredExperience))")
    }

    /// Test: Experience level inferred - advanced
    func testExperienceInference_Advanced() {
        // Given: Import data with advanced-level lifts
        let exercises = [
            ImportedExerciseData(
                exerciseName: "Squat",
                matchedExerciseId: "barbell_back_squat",
                oneRepMax: 365  // 2x bodyweight squat
            ),
            ImportedExerciseData(
                exerciseName: "Bench Press",
                matchedExerciseId: "barbell_bench_press",
                oneRepMax: 275  // 1.5x bodyweight bench
            ),
            ImportedExerciseData(
                exerciseName: "Deadlift",
                matchedExerciseId: "conventional_deadlift",
                oneRepMax: 455  // 2.5x bodyweight deadlift
            )
        ]
        let importData = ImportedWorkoutData(userId: testUser.id, exercises: exercises, source: .csv)

        // When: Analyzing import
        let intelligence = ImportIntelligenceService.analyze(
            importData: importData,
            userWeight: 180  // 180 lb person
        )

        // Then: Should infer advanced or expert level
        XCTAssertTrue(
            intelligence.inferredExperience == .advanced || intelligence.inferredExperience == .expert,
            "Should infer advanced/expert from strong lifts. Got: \(String(describing: intelligence.inferredExperience))"
        )
    }

    // MARK: - Training Style Inference Tests

    /// Test: Powerlifting style detected
    func testTrainingStyleInference_Powerlifting() {
        // Given: Import data with powerlifting-style training (lots of big 3)
        let exercises = [
            ImportedExerciseData(exerciseName: "Back Squat", oneRepMax: 315),
            ImportedExerciseData(exerciseName: "Front Squat", oneRepMax: 225),
            ImportedExerciseData(exerciseName: "Bench Press", oneRepMax: 275),
            ImportedExerciseData(exerciseName: "Close Grip Bench", oneRepMax: 225),
            ImportedExerciseData(exerciseName: "Deadlift", oneRepMax: 405),
            ImportedExerciseData(exerciseName: "Sumo Deadlift", oneRepMax: 385)
        ]

        // Sessions with low reps
        let sessions = [
            ImportedSession(sessionNumber: 1, date: Date(), exercises: [
                ImportedSessionExercise(exerciseName: "Back Squat", sets: [
                    ImportedSet(reps: 3, weight: 285),
                    ImportedSet(reps: 3, weight: 285),
                    ImportedSet(reps: 3, weight: 285)
                ])
            ])
        ]

        let importData = ImportedWorkoutData(
            userId: testUser.id,
            exercises: exercises,
            sessions: sessions,
            source: .csv
        )

        // When: Analyzing
        let intelligence = ImportIntelligenceService.analyze(
            importData: importData,
            userWeight: nil
        )

        // Then: Should detect powerlifting style
        XCTAssertEqual(intelligence.trainingStyle, .powerlifting,
            "Should detect powerlifting style. Got: \(String(describing: intelligence.trainingStyle))")
    }

    // MARK: - Full Import Processing Tests

    /// Test: Full import creates targets and updates profile
    func testImportProcessing_CreatesTargets() throws {
        // Given: CSV with matched exercises
        let csvContent = """
        Workout,Date,Exercise,Sets x Reps,Weight
        1,2024-12-01,Bench Press,3x5,185 lb
        ,,Squat,3x5,225 lb
        """
        let data = csvContent.data(using: .utf8)!
        let csvResult = try CSVImportService.parseCSV(data: data)
        let importData = CSVImportService.toImportedWorkoutData(from: csvResult, userId: testUser.id)

        // When: Processing import
        let result = try ImportProcessingService.process(importData, userId: testUser.id)

        // Then: Should create exercise targets
        XCTAssertFalse(result.targets.isEmpty, "Should create targets from import")
        XCTAssertNotNil(result.intelligence, "Should extract intelligence")
    }

    /// Test: Conversion to ImportedWorkoutData preserves sessions
    func testCSVToImportedWorkoutData_PreservesSessions() throws {
        // Given: CSV with multiple workouts
        let csvContent = """
        Workout,Date,Exercise,Sets x Reps,Weight
        1,2024-12-01,Bench Press,3x8,135 lb
        2,2024-12-03,Squat,3x5,185 lb
        3,2024-12-05,Deadlift,3x5,225 lb
        """
        let data = csvContent.data(using: .utf8)!
        let csvResult = try CSVImportService.parseCSV(data: data)

        // When: Converting to ImportedWorkoutData
        let importData = CSVImportService.toImportedWorkoutData(from: csvResult, userId: testUser.id)

        // Then: Should preserve all sessions
        XCTAssertEqual(importData.sessionCount, 3, "Should have 3 sessions")
        XCTAssertEqual(importData.sessions[0].sessionNumber, 1)
        XCTAssertEqual(importData.sessions[1].sessionNumber, 2)
        XCTAssertEqual(importData.sessions[2].sessionNumber, 3)
    }
}
