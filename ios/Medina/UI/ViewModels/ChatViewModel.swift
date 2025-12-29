//
// ChatViewModel.swift
// Medina
//
// v80.0: Updated to use ResponsesManager (Responses API) instead of AssistantManager
// v80.2: Fixed parallel tool calls - collect all before continuing (fixes HTTP 400)
// v141: Added suggestion chips consumption in handleCollectedToolCalls
// v148: Added fallback chips for workout choice scenarios when AI responds without calling suggest_options
// v150: Strip internal instructions ([VOICE_READY], [INSTRUCTION]) from direct command output
// v155: Don't show "Start X" fallback chips when there's an active session
//

import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {

    // MARK: - Properties

    let user: UnifiedUser

    @Published var messages: [Message] = []
    @Published var isTyping = false

    // v31.0: Voice service for TTS workout guidance
    // v46.3: Internal access for context menu handlers in ChatView
    let voiceService: VoiceService

    // v80.0: Responses API architecture (replaces AssistantManager)
    private let responsesManager = ResponsesManager()
    @Published var assistantInitialized = false
    private var useAIAssistant = true

    // v60.2: Track last created workout for modify_workout tool
    private var lastCreatedWorkoutId: String?

    // v106.3: Unified voice chat manager (STT → GPT → TTS loop)
    let voiceModeManager = VoiceModeManager()

    // v179: Check if user is new (needs onboarding, no workout history)
    // Used by ChatView to show appropriate empty state greeting and chips
    var isNewUser: Bool {
        let hasWorkoutHistory = !WorkoutDataStore.workouts(
            for: user.id, temporal: .unspecified, dateInterval: nil
        ).isEmpty
        return needsOnboarding() && !hasWorkoutHistory && !OnboardingState.wasDismissed(for: user.id)
    }

    // v91.0: Trainer member context selection
    // v94.0: Added authorization validation
    var selectedMemberId: String? {
        didSet {
            // v94.0: Validate trainer can access this member
            if let memberId = selectedMemberId {
                guard AuthorizationService.canTrainerAccessMember(
                    trainerId: user.id,
                    memberId: memberId
                ) else {
                    Logger.log(.warning, component: "ChatViewModel",
                              message: "⚠️ Invalid member selection: trainer \(user.id) cannot access \(memberId)")
                    // Reset to nil without triggering didSet again
                    selectedMemberId = nil
                    return
                }
            }
            responsesManager.selectedMemberId = selectedMemberId
        }
    }

    // MARK: - Initialization

    init(user: UnifiedUser) {
        self.user = user
        self.voiceService = VoiceService(apiKey: Config.openAIKey)

        // v80.0: Initialize ResponsesManager (much simpler - no API calls needed)
        Task {
            do {
                try await responsesManager.initialize(for: user)
                await MainActor.run {
                    self.assistantInitialized = true
                }
            } catch {
                Logger.log(.error, component: "ChatViewModel", message: "ResponsesManager init failed: \(error.localizedDescription)")
            }
        }

        // v17.5: Listen for confirmation card actions
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SendChatMessage"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.userInfo?["message"] as? String {
                Task {
                    await self?.processMessage(message)
                }
            }
        }

        // v47: Listen for direct message additions (e.g., plan creation success)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AddChatMessage"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let message = notification.userInfo?["message"] as? Message {
                self?.addMessage(message)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods

    func startConversation() {
        // v99.8: Only show greeting message for trainers/gym owners and new users
        // Established returning users see the centered empty state greeting instead
        if let greeting = getOnboardingGreeting() {
            addMessage(Message(
                content: greeting,
                isUser: false
            ))
        }

        // v65.2: OnboardingState is now user-specific
        // v80.3.4: Only log for truly new users (no workout history)
        let hasWorkoutHistory = !WorkoutDataStore.workouts(for: user.id, temporal: .unspecified, dateInterval: nil).isEmpty
        if needsOnboarding() && !hasWorkoutHistory && !OnboardingState.wasDismissed(for: user.id) {
            Logger.log(.info, component: "ChatViewModel", message: "Started onboarding flow for new user: \(user.name)")
        }
    }

    /// v179: All users see centered empty state greeting (no chat message)
    /// New users get brand-agnostic greeting, existing users get time-of-day greeting
    /// Both handled by EmptyStateGreetingView based on isNewUser property
    private func getOnboardingGreeting() -> String? {
        // v179: All users (trainers, gym owners, new members, returning members)
        // now see centered empty state greeting instead of a chat message
        return nil
    }

    /// Check if user has an active plan
    private func hasActivePlan() -> Bool {
        PlanResolver.activePlan(for: user.id) != nil
    }

    /// Get today's scheduled workout if any (kept for compatibility)
    private func getTodaysScheduledWorkout() -> Workout? {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let todayInterval = DateInterval(start: today, end: tomorrow)

        let todaysWorkouts = WorkoutResolver.workouts(
            for: user.id,
            temporal: .upcoming,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: PlanResolver.activePlan(for: user.id),
            program: nil,
            dateInterval: todayInterval
        )

        return todaysWorkouts.first
    }
    
    /// Process a user message
    /// - Parameters:
    ///   - text: The message/command to send to the AI
    ///   - displayText: Optional human-readable text to show in the chat bubble (v144: for chip taps)
    func processMessage(_ text: String, displayText: String? = nil) async {
        // v144: Set typing FIRST so chips hide immediately on re-render
        isTyping = true
        // Add user message (show displayText if provided, otherwise show the command)
        addMessage(Message(content: displayText ?? text, isUser: true))

        // v106.1: Detect and fetch URL content inline (like ChatGPT/Claude)
        var messageForAI = text
        if URLContentFetcher.containsURL(text) {
            Logger.log(.info, component: "ChatViewModel", message: "🔗 URL detected, fetching content...")

            let (augmentedMessage, fetchResults) = await URLContentFetcher.augmentMessageWithURLContent(text)

            // Log fetch results
            for result in fetchResults {
                if result.success {
                    Logger.log(.info, component: "ChatViewModel",
                              message: "✅ Fetched: \(result.title ?? result.originalURL)")
                } else {
                    Logger.log(.warning, component: "ChatViewModel",
                              message: "⚠️ Failed to fetch: \(result.originalURL) - \(result.error ?? "unknown")")
                }
            }

            messageForAI = augmentedMessage
        }

        // v149: Handle direct tool commands from chips (bypass AI for immediate execution)
        if let directResult = await handleDirectToolCommand(text) {
            // Direct command handled - add response message
            addMessage(directResult)
            isTyping = false
            return
        }

        // v59.2: Use AI assistant if available, otherwise fall back to pattern matching
        if useAIAssistant && assistantInitialized {
            await processMessageWithAI(messageForAI)
        } else {
            await processMessageWithPatternMatching(text)
        }

        isTyping = false
    }

    // MARK: - v149: Direct Tool Command Handling
    // v209: Removed - all commands now go through AI/server path
    // Direct tool handlers (start_workout, skip_workout) migrated to Firebase Functions

    /// Handle direct tool commands from chips (format: toolName:arg1:arg2)
    /// v209: Always returns nil - all commands go through AI/server
    private func handleDirectToolCommand(_ text: String) async -> Message? {
        // Previously handled start_workout:id and skip_workout:id directly
        // Now all commands flow through AI → Server for execution
        return nil
    }

    /// v75.0.3: Send context to AI without displaying it as a user message
    /// Used for import context where we want AI to respond but not show raw context to user
    func sendContextToAI(_ context: String) async {
        isTyping = true

        if useAIAssistant && assistantInitialized {
            await processMessageWithAI(context)
        }

        isTyping = false
    }

    /// v87.6: Send message with image attachments (Claude-style)
    /// Images are sent directly to AI vision for natural conversation
    func sendMessageWithImages(_ text: String, images: [UIImage]) async {
        isTyping = true

        guard useAIAssistant && assistantInitialized else {
            addMessage(Message(
                content: "I'm having trouble connecting. Please try again.",
                isUser: false
            ))
            isTyping = false
            return
        }

        // Create placeholder for streaming response
        let placeholderMessage = Message(content: "", isUser: false)
        addMessage(placeholderMessage)
        let placeholderIndex = messages.count - 1

        var accumulatedText = ""
        var pendingToolCalls: [ResponseStreamProcessor.ToolCall] = []

        do {
            let stream = responsesManager.sendMessageWithImagesStreaming(text, images: images)

            for try await event in stream {
                switch event {
                case .responseCreated:
                    break

                case .textDelta(let delta):
                    accumulatedText += delta
                    messages[placeholderIndex] = Message(content: accumulatedText, isUser: false)

                case .textDone:
                    break

                case .toolCall(let toolCall):
                    Logger.spine("ChatViewModel", "🔧 Queued tool (vision): \(toolCall.name)")
                    pendingToolCalls.append(toolCall)

                case .toolCalls(let toolCalls):
                    Logger.spine("ChatViewModel", "🔧 Queued batch (vision): \(toolCalls.count) tools")
                    pendingToolCalls.append(contentsOf: toolCalls)

                case .responseCompleted(let responseId):
                    Logger.spine("ChatViewModel", "✅ Vision complete: \(responseId.prefix(20))...")

                    if !pendingToolCalls.isEmpty {
                        Logger.spine("ChatViewModel", "🔧 Processing \(pendingToolCalls.count) tool(s) from vision")
                        await handleCollectedToolCalls(pendingToolCalls, accumulatedText: &accumulatedText, placeholderIndex: placeholderIndex)
                        pendingToolCalls.removeAll()
                    }

                case .responseFailed(let error):
                    Logger.spine("ChatViewModel", "❌ Vision failed: \(error)")
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex] = Message(
                            content: "I had trouble analyzing the image. Please try again.",
                            isUser: false
                        )
                    }

                case .error(let error):
                    Logger.log(.error, component: "ChatViewModel", message: "Vision stream error: \(error.localizedDescription)")
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex] = Message(
                            content: "I encountered an error processing the image. Please try again.",
                            isUser: false
                        )
                    }

                // v210: Workout card from server handler
                case .workoutCard(let cardData):
                    Logger.spine("ChatViewModel", "📋 Workout card (vision): \(cardData.workoutName)")
                    messages.append(Message(
                        content: "",
                        isUser: false,
                        workoutCreatedData: WorkoutCreatedData(
                            workoutId: cardData.workoutId,
                            workoutName: cardData.workoutName
                        )
                    ))

                // v210: Plan card from server handler
                case .planCard(let cardData):
                    Logger.spine("ChatViewModel", "📋 Plan card (vision): \(cardData.planName)")
                    messages.append(Message(
                        content: "",
                        isUser: false,
                        planCreatedData: PlanCreatedData(
                            planId: cardData.planId,
                            planName: cardData.planName,
                            workoutCount: cardData.workoutCount,
                            durationWeeks: cardData.durationWeeks
                        )
                    ))

                // v211: Suggestion chips from server (ignored in vision stream for now)
                case .suggestionChips:
                    break
                }
            }

        } catch {
            Logger.log(.error, component: "ChatViewModel", message: "Vision AI failed: \(error.localizedDescription)")

            if !messages.isEmpty {
                messages.removeLast()
            }

            addMessage(Message(
                content: "I had trouble analyzing the image. Please try again.",
                isUser: false
            ))
        }

        isTyping = false
    }

    // v80.0: Process message with Responses API streaming
    // v80.2: Fixed parallel tool call handling - collect all tools, then continue once
    private func processMessageWithAI(_ text: String) async {
        // Create placeholder message for streaming
        let placeholderMessage = Message(content: "", isUser: false)
        addMessage(placeholderMessage)
        let placeholderIndex = messages.count - 1

        var accumulatedText = ""
        var pendingToolCalls: [ResponseStreamProcessor.ToolCall] = []

        do {
            let stream = responsesManager.sendMessageStreaming(text)

            for try await event in stream {
                switch event {
                case .responseCreated:
                    // v80.1: Response ID captured early by ResponsesManager for tool continuation
                    break

                case .textDelta(let delta):
                    accumulatedText += delta
                    messages[placeholderIndex] = Message(content: accumulatedText, isUser: false)

                case .textDone:
                    break

                case .toolCall(let toolCall):
                    // v80.2: Collect tool calls, don't execute immediately
                    // Multiple tools may stream in before response.completed
                    Logger.spine("ChatViewModel", "🔧 Queued tool: \(toolCall.name)")
                    pendingToolCalls.append(toolCall)

                case .toolCalls(let toolCalls):
                    // v80.2: Batch add all tool calls
                    Logger.spine("ChatViewModel", "🔧 Queued batch: \(toolCalls.count) tools")
                    pendingToolCalls.append(contentsOf: toolCalls)

                case .responseCompleted(let responseId):
                    Logger.spine("ChatViewModel", "✅ Complete: \(responseId.prefix(20))...")

                    // v80.2: NOW process all collected tool calls together
                    if !pendingToolCalls.isEmpty {
                        Logger.spine("ChatViewModel", "🔧 Processing \(pendingToolCalls.count) tool(s)")
                        await handleCollectedToolCalls(pendingToolCalls, accumulatedText: &accumulatedText, placeholderIndex: placeholderIndex)
                        pendingToolCalls.removeAll()
                    } else {
                        // v148: No tool calls - check for workout choice scenarios that need fallback chips
                        // This handles cases where AI responds with text but doesn't call suggest_options
                        if let fallbackChips = generateFallbackWorkoutChips() {
                            Logger.spine("ChatViewModel", "🏷️ Adding \(fallbackChips.count) fallback workout chips")
                            messages[placeholderIndex] = Message(
                                content: accumulatedText,
                                isUser: false,
                                suggestionChipsData: fallbackChips
                            )
                        }
                    }

                case .responseFailed(let error):
                    Logger.spine("ChatViewModel", "❌ Failed: \(error)")
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex] = Message(
                            content: "I encountered an error: \(error). Please try again.",
                            isUser: false
                        )
                    }

                case .error(let error):
                    Logger.log(.error, component: "ChatViewModel", message: "Stream error: \(error.localizedDescription)")
                    if let lastIndex = messages.indices.last {
                        messages[lastIndex] = Message(
                            content: "I encountered an error processing your message. Please try again.",
                            isUser: false
                        )
                    }

                // v210: Workout card from server handler
                case .workoutCard(let cardData):
                    Logger.spine("ChatViewModel", "📋 Workout card: \(cardData.workoutName)")

                    // v211: Fetch newly created workout from Firestore into local cache
                    if let userId = TestDataManager.shared.currentUserId {
                        Task {
                            do {
                                if let workout = try await FirestoreWorkoutRepository.shared.fetchWorkout(
                                    id: cardData.workoutId,
                                    memberId: userId
                                ) {
                                    await MainActor.run {
                                        TestDataManager.shared.workouts[cardData.workoutId] = workout
                                        Logger.log(.info, component: "ChatViewModel",
                                                  message: "✅ Synced workout \(cardData.workoutId) from Firestore")
                                    }
                                }
                            } catch {
                                Logger.log(.warning, component: "ChatViewModel",
                                          message: "Failed to fetch workout \(cardData.workoutId): \(error)")
                            }
                        }
                    }

                    messages.append(Message(
                        content: "",
                        isUser: false,
                        workoutCreatedData: WorkoutCreatedData(
                            workoutId: cardData.workoutId,
                            workoutName: cardData.workoutName
                        )
                    ))

                // v210: Plan card from server handler
                case .planCard(let cardData):
                    Logger.spine("ChatViewModel", "📋 Plan card: \(cardData.planName)")

                    // v211: Fetch newly created plan from Firestore into local cache
                    if let userId = TestDataManager.shared.currentUserId {
                        Task {
                            do {
                                if let plan = try await FirestorePlanRepository.shared.fetchPlan(
                                    id: cardData.planId,
                                    memberId: userId
                                ) {
                                    await MainActor.run {
                                        TestDataManager.shared.plans[cardData.planId] = plan
                                        Logger.log(.info, component: "ChatViewModel",
                                                  message: "✅ Synced plan \(cardData.planId) from Firestore")
                                    }
                                }
                            } catch {
                                Logger.log(.warning, component: "ChatViewModel",
                                          message: "Failed to fetch plan \(cardData.planId): \(error)")
                            }
                        }
                    }

                    messages.append(Message(
                        content: "",
                        isUser: false,
                        planCreatedData: PlanCreatedData(
                            planId: cardData.planId,
                            planName: cardData.planName,
                            workoutCount: cardData.workoutCount,
                            durationWeeks: cardData.durationWeeks
                        )
                    ))

                // v211: Suggestion chips from server (ignored for now)
                case .suggestionChips:
                    break
                }
            }

        } catch {
            Logger.log(.error, component: "ChatViewModel", message: "AI processing failed: \(error.localizedDescription)")

            // Remove placeholder message
            if !messages.isEmpty {
                messages.removeLast()
            }

            // Fall back to error message
            await processMessageWithPatternMatching(text)
        }
    }

    // v59.4: Fallback when AI fails - show error message
    private func processMessageWithPatternMatching(_ text: String) async {
        addMessage(Message(
            content: "I'm having trouble connecting to my AI assistant. Please try again in a moment.",
            isUser: false
        ))

        Logger.log(.error, component: "ChatViewModel", message: "AI unavailable for: '\(text.prefix(30))...'")
    }

    // v80.2: Handle ALL collected tool calls after response.completed
    // This fixes the issue where parallel tool calls each tried to continue separately
    private func handleCollectedToolCalls(
        _ toolCalls: [ResponseStreamProcessor.ToolCall],
        accumulatedText: inout String,
        placeholderIndex: Int
    ) async {
        let context = createToolCallContext()

        // Execute ALL tools and store ALL outputs
        for toolCall in toolCalls {
            guard let jsonData = toolCall.arguments.data(using: .utf8),
                  let args = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                context.responsesManager.executeToolAndStoreOutput(
                    toolCallId: toolCall.id,
                    output: "ERROR: Failed to parse tool arguments"
                )
                continue
            }

            Logger.spine("ChatViewModel", "🔧 Executing: \(toolCall.name)")
            let output = await ToolHandlerRouter.executeOnly(toolName: toolCall.name, args: args, context: context)
            context.responsesManager.executeToolAndStoreOutput(toolCallId: toolCall.id, output: output)
        }

        // v108.1: Consume any pending analysis card data from tool execution
        let analysisCardData = context.pendingAnalysisCardData
        context.pendingAnalysisCardData = nil

        // v186: Removed class schedule card data (class booking deferred for beta)

        // v141: Consume any pending suggestion chips from tool execution
        let suggestionChipsData = context.pendingSuggestionChipsData
        context.pendingSuggestionChipsData = nil

        // v177: Consume any pending workout created data (start_workout card)
        let workoutCreatedData = context.pendingWorkoutCreatedData
        context.pendingWorkoutCreatedData = nil

        // Continue conversation with ALL tool outputs at once
        let continueStream = context.responsesManager.continueAfterToolExecution()

        // Collect any new tool calls from the continuation
        var nestedToolCalls: [ResponseStreamProcessor.ToolCall] = []

        do {
            for try await event in continueStream {
                switch event {
                case .responseCreated:
                    // Response ID captured by ResponsesManager
                    break
                case .textDelta(let delta):
                    accumulatedText += delta
                    // v108.1/v141/v177/v186: Preserve card/chip data during streaming
                    messages[placeholderIndex] = Message(
                        content: accumulatedText,
                        isUser: false,
                        workoutCreatedData: workoutCreatedData,
                        analysisCardData: analysisCardData,
                        suggestionChipsData: suggestionChipsData
                    )
                case .toolCall(let nestedToolCall):
                    // v80.2: Collect nested tool calls too
                    Logger.spine("ChatViewModel", "🔧 Queued nested: \(nestedToolCall.name)")
                    nestedToolCalls.append(nestedToolCall)
                case .toolCalls(let batchNested):
                    Logger.spine("ChatViewModel", "🔧 Queued nested batch: \(batchNested.count)")
                    nestedToolCalls.append(contentsOf: batchNested)
                case .responseCompleted:
                    // v80.2: Process any nested tool calls after this continuation completes
                    if !nestedToolCalls.isEmpty {
                        Logger.spine("ChatViewModel", "🔧 Processing \(nestedToolCalls.count) nested tool(s)")
                        await handleCollectedToolCalls(nestedToolCalls, accumulatedText: &accumulatedText, placeholderIndex: placeholderIndex)
                        nestedToolCalls.removeAll()
                    }
                // v210: Workout card from server handler (continuation stream)
                case .workoutCard(let cardData):
                    Logger.spine("ChatViewModel", "📋 Workout card (continuation): \(cardData.workoutName)")
                    messages.append(Message(
                        content: "",
                        isUser: false,
                        workoutCreatedData: WorkoutCreatedData(
                            workoutId: cardData.workoutId,
                            workoutName: cardData.workoutName
                        )
                    ))

                // v210: Plan card from server handler (continuation stream)
                case .planCard(let cardData):
                    Logger.spine("ChatViewModel", "📋 Plan card (continuation): \(cardData.planName)")
                    messages.append(Message(
                        content: "",
                        isUser: false,
                        planCreatedData: PlanCreatedData(
                            planId: cardData.planId,
                            planName: cardData.planName,
                            workoutCount: cardData.workoutCount,
                            durationWeeks: cardData.durationWeeks
                        )
                    ))

                // v211: Suggestion chips from server (ignored in continuation for now)
                case .suggestionChips:
                    break

                default:
                    break
                }
            }
        } catch {
            Logger.log(.error, component: "ChatViewModel", message: "Tool continuation error: \(error)")
        }

        // Flush any pending cards from tool execution
        context.flushPendingCards()
    }

    // v80.0: Shared context creation using ResponsesManager
    // v126: Added lastUserMessage for server-side home intent detection
    private func createToolCallContext() -> ToolCallContext {
        // v126: Find the last user message for server-side intent detection
        let lastUserMessage = messages.last(where: { $0.isUser })?.content

        return ToolCallContext(
            user: user,
            responsesManager: responsesManager,
            addMessage: { [weak self] message in
                self?.addMessage(message)
            },
            updateMessage: { [weak self] index, message in
                self?.messages[index] = message
            },
            messagesCount: { [weak self] in
                self?.messages.count ?? 0
            },
            getLastCreatedWorkoutId: { [weak self] in
                self?.lastCreatedWorkoutId
            },
            setLastCreatedWorkoutId: { [weak self] id in
                self?.lastCreatedWorkoutId = id
            },
            lastUserMessage: lastUserMessage
        )
    }

    // MARK: - v63.2: Tool handlers refactored
    // All tool handlers are now in separate files under:
    // Medina/Services/AI/ToolHandling/Handlers/
    // See docs/AI_ARCHITECTURE.md for architecture details

    // v19.0: Send message from UI components (e.g., rest timer buttons)
    func sendMessage(_ text: String) {
        Task {
            await processMessage(text)
        }
    }


    // MARK: - Private Methods

    /// v46.3: Made internal for ChatView context menu actions
    /// v47.5: Added modal action handling
    /// v53.0: Simplified to text-only messages (removed card support)
    func addMessage(_ message: Message) {
        messages.append(message)
    }

    /// v74.9: Allow external control of typing indicator (for file import processing)
    func setTyping(_ typing: Bool) {
        isTyping = typing
    }

    // v18.0: Logout method to return to login screen
    func logout() {
        Logger.log(.info, component: "ChatViewModel",
                  message: "User logout requested: \(user.name)")

        // Post notification to trigger login screen
        // ChatView listens for this and shows LoginView
        NotificationCenter.default.post(
            name: NSNotification.Name("UserLogout"),
            object: nil
        )
    }

    // MARK: - v47: Onboarding Flow

    /// Check if user needs onboarding (profile incomplete)
    /// Made internal for ChatView to show onboarding buttons
    func needsOnboarding() -> Bool {
        return !user.hasCompletedOnboarding
    }

    /// Check if we should show a reminder to complete profile
    // v66: Removed shouldShowOnboardingReminder - conversational flow handles onboarding

    // MARK: - v106.3: Voice Mode Management

    /// Whether voice conversations are enabled in user settings
    /// v106.3: Default to true so button shows even if voiceSettings not configured yet
    var isVoiceEnabled: Bool {
        user.memberProfile?.voiceSettings?.chatVoiceEnabled ?? true
    }

    /// Start voice mode (STT → GPT → TTS loop)
    func startVoiceSession() async {
        Logger.log(.info, component: "ChatViewModel", message: "Starting voice mode")

        // Configure callbacks
        voiceModeManager.onUserMessage = { [weak self] transcript in
            guard let self = self else { return }
            self.addMessage(Message(content: transcript, isUser: true))
        }

        voiceModeManager.onAIResponse = { [weak self] response in
            guard let self = self else { return }
            self.addMessage(Message(content: response, isUser: false))
        }

        // Wire up GPT communication
        voiceModeManager.sendToGPT = { [weak self] text in
            guard let self = self else { return nil }
            return await self.getAIResponseForVoice(text)
        }

        // Start voice mode
        voiceModeManager.startVoiceMode(userId: user.id)
    }

    /// Get AI response without adding to UI (voice mode handles display)
    private func getAIResponseForVoice(_ text: String) async -> String? {
        guard useAIAssistant && assistantInitialized else {
            return "I'm having trouble connecting. Please try again."
        }

        do {
            // Use non-streaming for voice to get complete response
            let response = try await responsesManager.sendMessage(text)
            return response
        } catch {
            Logger.log(.error, component: "ChatViewModel", message: "Voice AI error: \(error)")
            return "Sorry, I couldn't process that. Please try again."
        }
    }

    /// End the current voice session
    func endVoiceSession() {
        Logger.log(.info, component: "ChatViewModel", message: "Ending voice mode")
        voiceModeManager.endVoiceMode()
    }

    // MARK: - v148: Fallback Chips for Workout Choices

    /// v148: Generate fallback chips when AI responds without calling suggest_options
    /// Detects workout choice scenarios and returns appropriate chips
    /// v155: Don't show "Start X" chips when there's an active session
    /// v161: Also check for workout.status == .inProgress (persisted state after app restart)
    private func generateFallbackWorkoutChips() -> [SuggestionChip]? {
        // v155: If there's an active session, don't suggest starting a different workout
        if TestDataManager.shared.activeSession(for: user.id) != nil {
            return nil  // Let the AI's response about continuing be sufficient
        }

        // v161: Also check for workout with .inProgress status (persisted state)
        // This handles app restart where session is lost but workout status is persisted
        let allWorkouts = WorkoutDataStore.workouts(for: user.id, temporal: .unspecified, dateInterval: nil)
        if allWorkouts.contains(where: { $0.status == .inProgress }) {
            return nil  // Don't show "Start X" when there's an in-progress workout
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get today's workout
        let todayWorkout = WorkoutResolver.workouts(
            for: user.id,
            temporal: .today,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: PlanResolver.activePlan(for: user.id),
            program: nil,
            dateInterval: DateInterval(start: today, end: calendar.date(byAdding: .day, value: 1, to: today)!)
        ).first

        // If there's a today workout, no fallback needed (user should see card)
        if todayWorkout != nil {
            return nil
        }

        // Get missed workouts
        let missedWorkouts = WorkoutResolver.workouts(
            for: user.id,
            temporal: .past,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: PlanResolver.activePlan(for: user.id),
            program: nil,
            dateInterval: DateInterval(start: Date.distantPast, end: today)
        ).sorted { ($0.scheduledDate ?? .distantPast) > ($1.scheduledDate ?? .distantPast) }

        // Get next scheduled workout
        let nextWorkout = WorkoutResolver.workouts(
            for: user.id,
            temporal: .upcoming,
            status: .scheduled,
            modality: .unspecified,
            splitDay: nil,
            source: nil,
            plan: PlanResolver.activePlan(for: user.id),
            program: nil,
            dateInterval: DateInterval(start: today, end: Date.distantFuture)
        ).sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }.first

        // No workout today - check if we have options that need chips
        var chips: [SuggestionChip] = []

        // Add chip for next scheduled workout
        if let next = nextWorkout {
            let shortName = String(next.displayName.prefix(12))
            chips.append(SuggestionChip(
                "Start \(shortName)",
                command: "Start workout \(next.id)"
            ))
        }

        // Add chip for missed workout
        if let missed = missedWorkouts.first {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE"
            let dateStr = missed.scheduledDate.map { dateFormatter.string(from: $0) } ?? ""
            chips.append(SuggestionChip(
                "Do \(dateStr) workout",
                command: "Start workout \(missed.id)"
            ))

            // Add skip option for missed
            chips.append(SuggestionChip(
                "Skip missed",
                command: "Skip workout \(missed.id)"
            ))
        }

        // If we have workout options but no chips yet, add create option
        if chips.isEmpty && (nextWorkout != nil || !missedWorkouts.isEmpty) {
            chips.append(SuggestionChip(
                "Create workout",
                command: "Create a workout for today"
            ))
        }

        // Only return chips if we have a workout choice scenario
        return chips.isEmpty ? nil : chips
    }
}
