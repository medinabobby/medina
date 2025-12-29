//
// SendMessageHandlerTests.swift
// MedinaTests
//
// v188: Tests for send_message tool handler
// Tests: trainer-member messaging, permission validation, threading, draft flow
//
// Created: December 2025
//

import XCTest
@testable import Medina

@MainActor
class SendMessageHandlerTests: XCTestCase {

    // MARK: - Properties

    var mockContext: MockToolContext!
    var testTrainer: UnifiedUser!
    var testMember: UnifiedUser!
    var unassignedMember: UnifiedUser!
    var context: ToolCallContext!

    // MARK: - Test User IDs

    private let trainerId = "test_trainer_msg"
    private let memberId = "test_member_msg"
    private let unassignedMemberId = "test_unassigned_member_msg"

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        TestDataManager.shared.resetAndReload()

        mockContext = MockToolContext()

        // Create test trainer
        testTrainer = UnifiedUser(
            id: trainerId,
            firebaseUID: "firebase_trainer",
            authProvider: .email,
            email: "trainer@test.com",
            name: "Test Trainer",
            birthdate: Date(),
            gender: .male,
            roles: [.trainer],
            gymId: "test_gym",
            trainerProfile: TrainerProfile(
                bio: "Test trainer",
                specialties: [.strengthConditioning],
                certifications: ["CPT"]
            )
        )
        TestDataManager.shared.users[trainerId] = testTrainer

        // Create test member assigned to trainer
        testMember = UnifiedUser(
            id: memberId,
            firebaseUID: "firebase_member",
            authProvider: .email,
            email: "member@test.com",
            name: "Test Member",
            birthdate: Date(),
            gender: .female,
            roles: [.member],
            gymId: "test_gym",
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .intermediate,
                preferredSessionDuration: 60,
                trainerId: trainerId,
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        TestDataManager.shared.users[memberId] = testMember

        // Create unassigned member (not assigned to trainer)
        unassignedMember = UnifiedUser(
            id: unassignedMemberId,
            firebaseUID: "firebase_unassigned",
            authProvider: .email,
            email: "unassigned@test.com",
            name: "Unassigned Member",
            birthdate: Date(),
            gender: .male,
            roles: [.member],
            gymId: "test_gym",
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .beginner,
                preferredSessionDuration: 60,
                trainerId: nil,  // No trainer assigned
                membershipStatus: .active,
                memberSince: Date()
            )
        )
        TestDataManager.shared.users[unassignedMemberId] = unassignedMember

        // Clear any existing threads
        TestDataManager.shared.messageThreads.removeAll()
    }

    override func tearDown() async throws {
        mockContext.reset()
        TestDataManager.shared.reset()
        try await super.tearDown()
    }

    // MARK: - Trainer to Member Tests

    /// Test: Trainer can send message to assigned member
    func testTrainerSendsToAssignedMember_Success() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending message to assigned member
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": memberId,
                "content": "Great workout today!"
            ],
            context: context
        )

        // Then: Should succeed with draft created
        XCTAssertTrue(output.contains("SUCCESS"),
            "Should succeed for assigned member. Output: \(output)")
        XCTAssertTrue(output.contains("draft created"),
            "Should mention draft created. Output: \(output)")
        XCTAssertTrue(output.contains(testMember.name),
            "Should mention recipient name. Output: \(output)")
    }

    /// Test: Trainer cannot send message to non-assigned member
    func testTrainerSendsToNonAssignedMember_Fails() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending message to unassigned member
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": unassignedMemberId,
                "content": "Hello!"
            ],
            context: context
        )

        // Then: Should fail with error
        XCTAssertTrue(output.contains("ERROR"),
            "Should fail for non-assigned member. Output: \(output)")
        XCTAssertTrue(output.contains("not one of your assigned members"),
            "Should explain the error. Output: \(output)")
    }

    // MARK: - Member to Trainer Tests

    /// Test: Member can send message to assigned trainer
    func testMemberSendsToAssignedTrainer_Success() async throws {
        // Given: Member context
        context = mockContext.build(for: testMember)

        // When: Sending message to assigned trainer
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": trainerId,
                "content": "Question about my plan"
            ],
            context: context
        )

        // Then: Should succeed
        XCTAssertTrue(output.contains("SUCCESS"),
            "Should succeed for assigned trainer. Output: \(output)")
    }

    /// Test: Member cannot send message to non-assigned trainer
    func testMemberSendsToWrongTrainer_Fails() async throws {
        // Given: Member context and a different trainer
        let otherTrainerId = "other_trainer"
        let otherTrainer = UnifiedUser(
            id: otherTrainerId,
            firebaseUID: "firebase_other",
            authProvider: .email,
            email: "other@test.com",
            name: "Other Trainer",
            birthdate: Date(),
            gender: .male,
            roles: [.trainer],
            gymId: "test_gym"
        )
        TestDataManager.shared.users[otherTrainerId] = otherTrainer

        context = mockContext.build(for: testMember)

        // When: Sending message to wrong trainer
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": otherTrainerId,
                "content": "Hello!"
            ],
            context: context
        )

        // Then: Should fail
        XCTAssertTrue(output.contains("ERROR"),
            "Should fail for non-assigned trainer. Output: \(output)")
        XCTAssertTrue(output.contains("only message your assigned trainer"),
            "Should explain the restriction. Output: \(output)")
    }

    /// Test: Member without trainer cannot send messages
    func testMemberWithoutTrainer_CannotSend() async throws {
        // Given: Unassigned member context
        context = mockContext.build(for: unassignedMember)

        // When: Trying to send message
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": trainerId,
                "content": "Hello!"
            ],
            context: context
        )

        // Then: Should fail
        XCTAssertTrue(output.contains("ERROR"),
            "Should fail for member without trainer. Output: \(output)")
        XCTAssertTrue(output.contains("don't have an assigned trainer"),
            "Should explain no trainer assigned. Output: \(output)")
    }

    // MARK: - Threading Tests

    /// Test: New thread created with subject
    func testNewThread_SubjectProvided() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending message with subject
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": memberId,
                "content": "Let's discuss your progress",
                "subject": "Weekly Check-in"
            ],
            context: context
        )

        // Then: Should succeed
        XCTAssertTrue(output.contains("SUCCESS"), "Should succeed. Output: \(output)")

        // And: Pending card should have draft data
        let pendingCards = mockContext.lastBuiltContext?.pendingCards ?? []
        XCTAssertFalse(pendingCards.isEmpty, "Should have pending card with draft")

        if let draftCard = pendingCards.first,
           let draftData = draftCard.draftMessageData {
            XCTAssertEqual(draftData.subject, "Weekly Check-in",
                "Draft should have provided subject")
        }
    }

    /// Test: Auto-generated subject from content
    func testNewThread_AutoGeneratedSubject() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending message without subject
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": memberId,
                "content": "Great job on your workout today! Keep up the good work."
            ],
            context: context
        )

        // Then: Should succeed
        XCTAssertTrue(output.contains("SUCCESS"), "Should succeed. Output: \(output)")

        // And: Should have auto-generated subject
        let pendingCards = mockContext.lastBuiltContext?.pendingCards ?? []
        if let draftCard = pendingCards.first,
           let draftData = draftCard.draftMessageData {
            XCTAssertNotNil(draftData.subject, "Should have auto-generated subject")
            XCTAssertTrue(draftData.subject?.contains("Great job") ?? false,
                "Subject should be based on content")
        }
    }

    /// Test: Reply to existing thread
    func testReplyToExistingThread() async throws {
        // Given: An existing thread
        let existingThreadId = "existing_thread_123"
        let existingThread = MessageThread(
            id: existingThreadId,
            participantIds: [trainerId, memberId],
            subject: "Progress Check",
            messages: [
                TrainerMessage(
                    id: "msg1",
                    senderId: trainerId,
                    recipientId: memberId,
                    content: "How's your progress?",
                    messageType: .checkIn,
                    threadId: existingThreadId
                )
            ]
        )
        TestDataManager.shared.messageThreads[existingThreadId] = existingThread

        context = mockContext.build(for: testMember)

        // When: Replying to thread
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": trainerId,
                "content": "Going great, thanks for asking!",
                "threadId": existingThreadId
            ],
            context: context
        )

        // Then: Should succeed
        XCTAssertTrue(output.contains("SUCCESS"),
            "Should succeed for reply. Output: \(output)")
    }

    /// Test: v93.3 - Empty threadId handled as new thread
    func testEmptyThreadId_TreatedAsNewThread() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending with empty threadId (AI quirk)
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": memberId,
                "content": "New conversation",
                "threadId": ""  // Empty string, not nil
            ],
            context: context
        )

        // Then: Should succeed (treated as new thread)
        XCTAssertTrue(output.contains("SUCCESS"),
            "Empty threadId should be treated as new thread. Output: \(output)")
    }

    /// Test: Cannot reply to thread you're not a participant of
    func testReplyToNonParticipantThread_Fails() async throws {
        // Given: A thread the user is not part of
        let otherThreadId = "other_thread_456"
        let otherThread = MessageThread(
            id: otherThreadId,
            participantIds: ["someone_else", "another_person"],
            subject: "Private Chat",
            messages: []
        )
        TestDataManager.shared.messageThreads[otherThreadId] = otherThread

        context = mockContext.build(for: testMember)

        // When: Trying to reply to thread
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": trainerId,
                "content": "Hello",
                "threadId": otherThreadId
            ],
            context: context
        )

        // Then: Should fail
        XCTAssertTrue(output.contains("ERROR"),
            "Should fail for non-participant. Output: \(output)")
        XCTAssertTrue(output.contains("not a participant"),
            "Should explain not a participant. Output: \(output)")
    }

    // MARK: - Message Type Tests

    /// Test: Message type classification
    func testMessageTypeClassification() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending message with type
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": memberId,
                "content": "Your new plan is ready!",
                "messageType": "planUpdate"
            ],
            context: context
        )

        // Then: Should succeed
        XCTAssertTrue(output.contains("SUCCESS"), "Should succeed. Output: \(output)")

        // And: Draft should have correct type
        let pendingCards = mockContext.lastBuiltContext?.pendingCards ?? []
        if let draftCard = pendingCards.first,
           let draftData = draftCard.draftMessageData {
            XCTAssertEqual(draftData.messageType, .planUpdate,
                "Should have planUpdate message type")
        }
    }

    // MARK: - Draft Flow Tests

    /// Test: Draft card data populated correctly
    func testDraftCardDataPopulated() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending message
        _ = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": memberId,
                "content": "Test message content",
                "subject": "Test Subject",
                "messageType": "encouragement"
            ],
            context: context
        )

        // Then: Draft card should have all data
        let pendingCards = mockContext.lastBuiltContext?.pendingCards ?? []
        XCTAssertEqual(pendingCards.count, 1, "Should have one pending card")

        if let draftCard = pendingCards.first,
           let draftData = draftCard.draftMessageData {
            XCTAssertEqual(draftData.recipientId, memberId, "Should have correct recipient")
            XCTAssertEqual(draftData.recipientName, testMember.name, "Should have recipient name")
            XCTAssertEqual(draftData.content, "Test message content", "Should have content")
            XCTAssertEqual(draftData.subject, "Test Subject", "Should have subject")
            XCTAssertEqual(draftData.messageType, .encouragement, "Should have type")
            XCTAssertNotNil(draftData.onSend, "Should have onSend callback")
            XCTAssertNotNil(draftData.onCancel, "Should have onCancel callback")
        } else {
            XCTFail("Draft card should have draftMessageData")
        }
    }

    // MARK: - Error Cases

    /// Test: Invalid recipient ID returns error with suggestions
    func testInvalidRecipientId_ReturnsErrorWithSuggestions() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending to non-existent user
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": "nonexistent_user_xyz",
                "content": "Hello"
            ],
            context: context
        )

        // Then: Should fail with suggestions
        XCTAssertTrue(output.contains("ERROR"),
            "Should fail. Output: \(output)")
        XCTAssertTrue(output.contains("not found"),
            "Should say not found. Output: \(output)")
        XCTAssertTrue(output.contains("Your assigned members"),
            "Should list assigned members. Output: \(output)")
    }

    /// Test: Missing recipientId parameter
    func testMissingRecipientId_ReturnsError() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending without recipientId
        let output = await SendMessageHandler.executeOnly(
            args: [
                "content": "Hello"
            ],
            context: context
        )

        // Then: Should fail
        XCTAssertTrue(output.contains("ERROR"),
            "Should fail for missing recipientId. Output: \(output)")
        XCTAssertTrue(output.contains("recipientId"),
            "Should mention missing recipientId. Output: \(output)")
    }

    /// Test: Missing content parameter
    func testMissingContent_ReturnsError() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending without content
        let output = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": memberId
            ],
            context: context
        )

        // Then: Should fail
        XCTAssertTrue(output.contains("ERROR"),
            "Should fail for missing content. Output: \(output)")
        XCTAssertTrue(output.contains("content"),
            "Should mention missing content. Output: \(output)")
    }

    // MARK: - Subject Generation Tests

    /// Test: Long content truncated in auto-subject
    func testAutoSubject_LongContentTruncated() async throws {
        // Given: Trainer context
        context = mockContext.build(for: testTrainer)

        // When: Sending message with very long content
        let longContent = "This is a very long message that should be truncated when generating an automatic subject line because it exceeds the maximum length allowed for subjects."

        _ = await SendMessageHandler.executeOnly(
            args: [
                "recipientId": memberId,
                "content": longContent
            ],
            context: context
        )

        // Then: Subject should be truncated
        let pendingCards = mockContext.lastBuiltContext?.pendingCards ?? []
        if let draftCard = pendingCards.first,
           let draftData = draftCard.draftMessageData,
           let subject = draftData.subject {
            XCTAssertLessThanOrEqual(subject.count, 50,
                "Auto-subject should be max 50 chars. Got: \(subject.count)")
            XCTAssertTrue(subject.hasSuffix("..."),
                "Truncated subject should end with ellipsis")
        }
    }
}
