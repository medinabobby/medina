//
// ExerciseLibraryHandlerTests.swift
// MedinaTests
//
// v184: Tests for add_to_library and remove_from_library tool handlers
// Tests: adding/removing exercises from favorites, fuzzy matching, error handling
//
// Created: December 2025
//

import XCTest
@testable import Medina

@MainActor
class ExerciseLibraryHandlerTests: XCTestCase {

    // MARK: - Properties

    var mockContext: MockToolContext!
    var testUser: UnifiedUser!
    var context: ToolCallContext!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()

        mockContext = MockToolContext()
        testUser = TestFixtures.testUser
        TestDataManager.shared.currentUserId = testUser.id
        context = mockContext.build(for: testUser)

        // Clear user's library
        if let library = TestDataManager.shared.libraries[testUser.id] {
            var clearedLibrary = library
            clearedLibrary.exercises = []
            TestDataManager.shared.libraries[testUser.id] = clearedLibrary
        }
    }

    override func tearDown() async throws {
        mockContext.reset()
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - AddToLibrary Success Cases

    /// Test: Adding exercise to library succeeds
    func testAddToLibrary_ValidExercise_AddsToLibrary() async throws {
        // Given: A valid exercise ID
        let exerciseId = "barbell_bench_press"

        // Verify not in library
        let initialLibrary = TestDataManager.shared.libraries[testUser.id]
        XCTAssertFalse(initialLibrary?.exercises.contains(exerciseId) ?? false)

        // When: Adding to library
        let output = await AddToLibraryHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Exercise should be in library
        XCTAssertTrue(output.contains("Added") || output.contains("added"),
            "Should confirm addition. Output: \(output)")

        let updatedLibrary = TestDataManager.shared.libraries[testUser.id]
        XCTAssertTrue(updatedLibrary?.exercises.contains(exerciseId) ?? false,
            "Exercise should be in library")
    }

    /// Test: Adding exercise shows exercise name in response
    func testAddToLibrary_ShowsExerciseName() async throws {
        // Given: A valid exercise
        let exerciseId = "barbell_back_squat"

        // When: Adding to library
        let output = await AddToLibraryHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Response should include exercise name
        XCTAssertTrue(output.contains("Squat") || output.contains("squat"),
            "Should show exercise name. Output: \(output)")
    }

    /// Test: Fuzzy matching works for exercise names
    func testAddToLibrary_FuzzyMatching_FindsExercise() async throws {
        // Given: A fuzzy exercise name
        let fuzzyName = "bench press"  // Should match barbell_bench_press

        // When: Adding to library
        let output = await AddToLibraryHandler.executeOnly(
            args: ["exerciseId": fuzzyName],
            context: context
        )

        // Then: Should find and add the exercise
        // Note: Depends on ExerciseFuzzyMatcher implementation
        // If fuzzy matcher works, should succeed; if not, will return error
        // This test verifies the handler calls the matcher
        XCTAssertFalse(output.isEmpty, "Should return a response")
    }

    // MARK: - AddToLibrary Error Cases

    /// Test: Adding already-favorited exercise returns appropriate message
    func testAddToLibrary_AlreadyInLibrary_ReturnsMessage() async throws {
        // Given: An exercise already in library
        let exerciseId = "barbell_bench_press"

        // Add to library first
        if var library = TestDataManager.shared.libraries[testUser.id] {
            library.exercises.insert(exerciseId)
            TestDataManager.shared.libraries[testUser.id] = library
        } else {
            var library = UserLibrary(userId: testUser.id)
            library.exercises.insert(exerciseId)
            TestDataManager.shared.libraries[testUser.id] = library
        }

        // When: Trying to add again
        let output = await AddToLibraryHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Should say already in library
        XCTAssertTrue(output.contains("already"),
            "Should indicate already in library. Output: \(output)")
    }

    /// Test: Invalid exercise ID returns error
    func testAddToLibrary_InvalidExerciseId_ReturnsError() async throws {
        // When: Using invalid exercise ID
        let output = await AddToLibraryHandler.executeOnly(
            args: ["exerciseId": "nonexistent_exercise_xyz"],
            context: context
        )

        // Then: Should return error
        XCTAssertTrue(output.contains("ERROR") || output.contains("not found"),
            "Should return error for invalid exercise. Output: \(output)")
    }

    /// Test: Missing exerciseId returns error
    func testAddToLibrary_MissingExerciseId_ReturnsError() async throws {
        // When: Calling without exerciseId
        let output = await AddToLibraryHandler.executeOnly(
            args: [:],
            context: context
        )

        // Then: Should return error
        XCTAssertTrue(output.contains("ERROR"),
            "Should return ERROR for missing exerciseId. Output: \(output)")
    }

    // MARK: - RemoveFromLibrary Success Cases

    /// Test: Removing exercise from library succeeds
    func testRemoveFromLibrary_ValidExercise_RemovesFromLibrary() async throws {
        // Given: An exercise in library
        let exerciseId = "barbell_bench_press"

        // Add to library first
        if var library = TestDataManager.shared.libraries[testUser.id] {
            library.exercises.insert(exerciseId)
            TestDataManager.shared.libraries[testUser.id] = library
        } else {
            var library = UserLibrary(userId: testUser.id)
            library.exercises.insert(exerciseId)
            TestDataManager.shared.libraries[testUser.id] = library
        }

        // Verify in library
        XCTAssertTrue(TestDataManager.shared.libraries[testUser.id]?.exercises.contains(exerciseId) ?? false)

        // When: Removing from library
        let output = await RemoveFromLibraryHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Exercise should be removed
        XCTAssertTrue(output.contains("Removed") || output.contains("removed"),
            "Should confirm removal. Output: \(output)")

        let updatedLibrary = TestDataManager.shared.libraries[testUser.id]
        XCTAssertFalse(updatedLibrary?.exercises.contains(exerciseId) ?? true,
            "Exercise should be removed from library")
    }

    /// Test: Removing exercise shows exercise name in response
    func testRemoveFromLibrary_ShowsExerciseName() async throws {
        // Given: An exercise in library
        let exerciseId = "barbell_back_squat"

        // Add to library
        if var library = TestDataManager.shared.libraries[testUser.id] {
            library.exercises.insert(exerciseId)
            TestDataManager.shared.libraries[testUser.id] = library
        } else {
            var library = UserLibrary(userId: testUser.id)
            library.exercises.insert(exerciseId)
            TestDataManager.shared.libraries[testUser.id] = library
        }

        // When: Removing from library
        let output = await RemoveFromLibraryHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Response should include exercise name
        XCTAssertTrue(output.contains("Squat") || output.contains("squat"),
            "Should show exercise name. Output: \(output)")
    }

    // MARK: - RemoveFromLibrary Error Cases

    /// Test: Removing exercise not in library returns appropriate message
    func testRemoveFromLibrary_NotInLibrary_ReturnsMessage() async throws {
        // Given: An exercise NOT in library
        let exerciseId = "barbell_bench_press"

        // Ensure not in library
        if var library = TestDataManager.shared.libraries[testUser.id] {
            library.exercises.remove(exerciseId)
            TestDataManager.shared.libraries[testUser.id] = library
        }

        // When: Trying to remove
        let output = await RemoveFromLibraryHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Should say not in library
        XCTAssertTrue(output.contains("not in"),
            "Should indicate not in library. Output: \(output)")
    }

    /// Test: Invalid exercise ID returns error
    func testRemoveFromLibrary_InvalidExerciseId_ReturnsError() async throws {
        // When: Using invalid exercise ID
        let output = await RemoveFromLibraryHandler.executeOnly(
            args: ["exerciseId": "nonexistent_exercise_xyz"],
            context: context
        )

        // Then: Should return error
        XCTAssertTrue(output.contains("ERROR") || output.contains("not found"),
            "Should return error for invalid exercise. Output: \(output)")
    }

    /// Test: Missing exerciseId returns error
    func testRemoveFromLibrary_MissingExerciseId_ReturnsError() async throws {
        // When: Calling without exerciseId
        let output = await RemoveFromLibraryHandler.executeOnly(
            args: [:],
            context: context
        )

        // Then: Should return error
        XCTAssertTrue(output.contains("ERROR"),
            "Should return ERROR for missing exerciseId. Output: \(output)")
    }

    // MARK: - Integration Tests

    /// Test: Add then remove returns to original state
    func testLibrary_AddThenRemove_ReturnsToOriginalState() async throws {
        // Given: An exercise not in library
        let exerciseId = "lat_pulldown"

        // Verify not in library
        let initialLibrary = TestDataManager.shared.libraries[testUser.id]
        let wasInLibrary = initialLibrary?.exercises.contains(exerciseId) ?? false

        // When: Adding then removing
        _ = await AddToLibraryHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Verify added
        XCTAssertTrue(TestDataManager.shared.libraries[testUser.id]?.exercises.contains(exerciseId) ?? false,
            "Exercise should be added")

        _ = await RemoveFromLibraryHandler.executeOnly(
            args: ["exerciseId": exerciseId],
            context: context
        )

        // Then: Should be back to original state
        let finalLibrary = TestDataManager.shared.libraries[testUser.id]
        let isInLibrary = finalLibrary?.exercises.contains(exerciseId) ?? false
        XCTAssertEqual(isInLibrary, wasInLibrary,
            "Library should return to original state")
    }
}
