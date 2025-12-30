//
// ChatView.swift
// Medina
//
// v99.8: Claude mobile-style empty state greeting (centered, auto-focus input)
// v93.8: Refactored from 729 lines to ~420 lines
// Extracted components:
//   - ChatNavigationDestinations.swift (navigation routing)
//   - ChatAttachmentProcessor.swift (file attachment processing)
//   - ChatEntityListModal.swift (entity list modal builder)
//
// v48: Navigation refactor - unified NavigationStack
// v86.0: Added Realtime API voice session support
//

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    // v48: Navigation infrastructure
    @StateObject private var navigationModel = NavigationModel()
    private var coordinator: NavigationCoordinator {
        NavigationCoordinator(navigationModel: navigationModel)
    }

    // v18.0: Sidebar navigation state
    @State private var showSidebar = false
    @State private var shouldDismissForLogout = false

    // v72: Upload modal state
    @State private var showUploadModal = false

    // v87.6: File attachments state (Claude-style - supports multiple)
    @State private var pendingAttachments: [FileAttachment] = []

    // v106.3: Voice session state (bound to VoiceModeManager)
    // Removed @State - now observes viewModel.voiceModeManager.isActive directly

    // v48.1: Settings modal state
    @State private var showSettingsModal = false

    // v65.2: Profile edit modal state
    @State private var showProfileModal = false

    // v105: Unified sidebar context for filtering + AI integration
    @StateObject private var sidebarContext: SidebarContext

    // v54.7: Entity list modal state for "Show All" functionality
    @State private var showEntityListModal = false
    @State private var entityListTitle = ""
    @State private var entityListData: EntityListData?

    // v226: Server-side initial chips
    @State private var serverChips: [SuggestionChip] = []
    @State private var isLoadingChips = false

    init(user: UnifiedUser) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(user: user))
        _sidebarContext = StateObject(wrappedValue: SidebarContext(user: user))
    }

    var body: some View {
        NavigationStack(path: $navigationModel.path) {
            ZStack(alignment: .leading) {
                // Main chat interface
                VStack(spacing: 0) {
                    headerView
                    Divider()
                    messagesView
                    chatInputView
                }
                .disabled(showSidebar)

                // v18.0: Dimmed overlay when sidebar is visible
                if showSidebar {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showSidebar = false }
                        .transition(.opacity)
                }

                // v18.0: Sidebar drawer
                if showSidebar {
                    sidebarView
                }
            }
            .navigationDestination(for: NavigationRoute.self) { route in
                ChatNavigationDestinations.view(
                    for: route,
                    navigationModel: navigationModel,
                    selectedMemberId: sidebarContext.selectedMemberId,
                    currentUserId: viewModel.user.id
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSidebar)
        // v105: Wire sidebar context to ChatViewModel for AI integration
        .onChange(of: sidebarContext.selectedMemberId) { newValue in
            viewModel.selectedMemberId = newValue
        }
        .onAppear {
            setupNotificationObservers()
            // v99.8: Auto-focus input to drive user action (Claude mobile pattern)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
            // v226: Fetch initial chips from server
            Task {
                await loadInitialChips()
            }
        }
        .onDisappear { cleanupNotificationObservers() }
        .sheet(isPresented: $showUploadModal) { uploadModalSheet }
        .sheet(isPresented: $showSettingsModal) { settingsModalSheet }
        .sheet(isPresented: $showEntityListModal) {
            // v190: Pass sidebarContext for member filter selection
            ChatEntityListModalBuilder.view(
                for: entityListData,
                title: entityListTitle,
                coordinator: coordinator,
                sidebarContext: sidebarContext,
                onDismiss: {
                    showEntityListModal = false
                    // v191.1: Reopen sidebar for member filter selection
                    if case .memberFilter = entityListData {
                        showSidebar = true
                    }
                }
            )
        }
        .sheet(isPresented: $showProfileModal) { profileModalSheet }
        // v105: Removed MemberPickerSheet - member selection now in SidebarFilterSection
    }

    // MARK: - Chat Input

    /// v106.3: Binding to voiceModeManager.isActive for voice session state
    private var voiceSessionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceModeManager.isActive },
            set: { newValue in
                if newValue {
                    Task { await viewModel.startVoiceSession() }
                } else {
                    viewModel.endVoiceSession()
                }
            }
        )
    }

    private var chatInputView: some View {
        ChatInputView(
            text: $inputText,
            placeholder: viewModel.assistantInitialized ? "Chat with Medina" : "Connecting...",
            isDisabled: viewModel.isTyping || !viewModel.assistantInitialized,
            onSend: {
                let message = inputText
                inputText = ""
                isInputFocused = false
                Task { await viewModel.processMessage(message) }
            },
            onPlusButtonTap: { showUploadModal = true },
            attachments: $pendingAttachments,
            onSendWithAttachments: { attachments, userMessage in
                isInputFocused = false
                ChatAttachmentProcessor.process(attachments, userMessage: userMessage, viewModel: viewModel)
            },
            isVoiceSessionActive: voiceSessionBinding,
            onVoiceButtonTap: {
                // v106.3: VoiceModeManager handles state internally
                Task { await viewModel.startVoiceSession() }
            },
            onEndVoiceSession: {
                // v106.3: VoiceModeManager handles state internally
                viewModel.endVoiceSession()
            },
            isVoiceEnabled: viewModel.isVoiceEnabled,
            suggestions: buildSuggestionChips(),
            onSuggestionTap: { chip in
                // v144: Show human-readable title in chat, send command to AI
                Task { await viewModel.processMessage(chip.command, displayText: chip.title) }
            }
        )
        .focused($isInputFocused)
    }

    // MARK: - Suggestion Chips

    /// v99.9: Build role-specific suggestion chips for empty state
    /// v100.0: All roles now use simple centered greeting with chips
    /// v142: All chips render at bottom (industry standard UX)
    /// v146: Removed fallback - showing nothing is better than irrelevant chips
    private func buildSuggestionChips() -> [SuggestionChip] {
        // Priority 0 - No chips while AI is responding
        // Chips should only appear AFTER response completes, so user has context
        if viewModel.isTyping {
            return []
        }

        // Priority 1 - Response chips from last AI message
        // All handlers now set appropriate chips via context.pendingSuggestionChipsData
        if let lastAIMessage = viewModel.messages.last(where: { !$0.isUser }),
           let responseChips = lastAIMessage.suggestionChipsData,
           !responseChips.isEmpty {
            return responseChips
        }

        // Priority 1.5 - No chips when AI provides an action card
        // When user sees a rich card, their action is clear (tap the card) - no stale chips
        // v186: Removed classScheduleCardData check (class booking deferred for beta)
        if let lastAIMessage = viewModel.messages.last(where: { !$0.isUser }),
           (lastAIMessage.workoutCreatedData != nil ||
            lastAIMessage.planCreatedData != nil) {
            return []
        }

        // Priority 2 - Startup chips (empty state only)
        // v226: Use server chips instead of local chip builders
        if viewModel.messages.isEmpty {
            return serverChips
        }

        // v146: No fallback chips after conversations
        // Showing nothing is better than showing irrelevant chips
        // (e.g., workout chips after class queries, or vice versa)
        // All handlers set appropriate chips - if none exist, stay clean
        return []
    }
    // v226: Local chip builders removed - now using server-side chips from /api/initialChips

    // MARK: - Sidebar

    // v105: Pass sidebarContext instead of selectedMemberId
    private var sidebarView: some View {
        SidebarView(
            context: sidebarContext,
            onDismiss: { showSidebar = false },
            onNavigate: { entityId, entityType in
                showSidebar = false
                handleSidebarNavigation(entityId: entityId, entityType: entityType)
            },
            onShowAll: { title, data in
                showSidebar = false
                entityListTitle = title
                entityListData = data
                showEntityListModal = true
            },
            onChatCommand: { command in
                Task { await viewModel.processMessage(command) }
                showSidebar = false
            },
            onLogout: { viewModel.logout() },
            onOpenSettings: {
                showSidebar = false
                showSettingsModal = true
            }
        )
        .transition(AnyTransition.move(edge: Edge.leading))
    }

    private func handleSidebarNavigation(entityId: String, entityType: Entity) {
        switch entityType {
        case .plan:
            coordinator.navigateToPlan(id: entityId)
        case .program:
            coordinator.navigateToProgram(id: entityId)
        case .workout:
            coordinator.navigateToWorkout(id: entityId)
        case .exercise:
            coordinator.navigateToExercise(id: entityId)
        case .protocol:
            coordinator.navigateToProtocol(id: entityId)
        case .protocolFamily:
            coordinator.navigateToProtocolFamily(id: entityId)
        case .member:
            navigationModel.push(.member(id: entityId))
        case .thread:
            navigationModel.push(.thread(id: entityId))
        case .class, .classInstance, .message, .trainer, .gym, .exerciseInstance, .set, .workoutSession, .target, .schedule, .unknown:
            // v164: .message deprecated (use .thread instead)
            // v186: .class, .classInstance removed (class booking deferred for beta)
            Logger.log(.warning, component: "ChatView", message: "Detail view not implemented for entity type")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button(action: { showSidebar.toggle() }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primaryText)
            }
            .accessibilityLabel("Open navigation menu")
            .accessibilityHint("Opens sidebar navigation with plans, programs, and settings")

            Spacer()

            Text("Medina")
                .font(.headline)
                .fontWeight(.semibold)

            // v105: Removed MemberContextSelector - filter now in sidebar
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.backgroundPrimary)
    }

    // MARK: - Messages

    private var messagesView: some View {
        Group {
            // v99.8: Show empty state greeting when no messages
            // v100.0: All roles now use simple centered greeting (trainers/gym owners too)
            // v179: New users see brand-agnostic greeting, existing users see time-of-day greeting
            if viewModel.messages.isEmpty && !viewModel.isTyping {
                EmptyStateGreetingView(
                    userName: viewModel.user.firstName,
                    isNewUser: viewModel.isNewUser
                )
            } else {
                // Normal message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.messages) { message in
                                // v142: Chips now render at bottom via ChatInputView
                                MessageBubble(
                                    message: message,
                                    navigationCoordinator: coordinator
                                )
                                    .id(message.id)
                            }

                            if viewModel.isTyping {
                                TypingIndicator()
                                    .id("typing")
                            }
                        }
                        .padding()
                    }
                    .background(Color.backgroundPrimary)
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation {
                            if let lastMessage = viewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isTyping) { isTyping in
                        if isTyping {
                            withAnimation {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        viewModel.startConversation()

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UserLogout"),
            object: nil,
            queue: .main
        ) { _ in
            shouldDismissForLogout = true
            dismiss()
        }

        // v105: Use sidebarContext to set member filter programmatically
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetFocusMember"),
            object: nil,
            queue: .main
        ) { [weak sidebarContext] notification in
            if let memberId = notification.userInfo?["memberId"] as? String {
                sidebarContext?.selectMember(memberId)
            }
        }
    }

    private func cleanupNotificationObservers() {
        if shouldDismissForLogout {
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("UserLogout"),
                object: nil
            )
        }
    }

    // MARK: - v226: Server Chips

    /// Load initial suggestion chips from server
    private func loadInitialChips() async {
        guard !isLoadingChips else { return }
        isLoadingChips = true

        do {
            let response = try await FirebaseAPIClient.shared.initialChips()
            await MainActor.run {
                self.serverChips = response.chips.map {
                    SuggestionChip($0.label, command: $0.command)
                }
                self.isLoadingChips = false
            }
            Logger.log(.info, component: "ChatView",
                      message: "v226: Loaded \(response.chips.count) initial chips from server")
        } catch {
            Logger.log(.error, component: "ChatView",
                      message: "v226: Failed to load initial chips: \(error)")
            await MainActor.run {
                self.isLoadingChips = false
            }
        }
    }

    // MARK: - Sheet Views

    private var uploadModalSheet: some View {
        UploadModal(
            user: viewModel.user,
            onFilesSelected: { urls in
                for url in urls {
                    if let attachment = FileAttachment(url: url) {
                        pendingAttachments.append(attachment)
                    }
                }
                if urls.count > 0 && pendingAttachments.isEmpty {
                    viewModel.addMessage(Message(
                        content: "Sorry, I couldn't read those files. Please try again.",
                        isUser: false
                    ))
                }
            },
            onImportComplete: { result in
                let summaryText = result.summary.formatForChat()
                viewModel.addMessage(Message(
                    content: summaryText,
                    isUser: false
                ))
            }
        )
    }

    private var settingsModalSheet: some View {
        SettingsModal(
            user: viewModel.user,
            onLogout: {
                showSettingsModal = false
                viewModel.logout()
            },
            onSave: { },
            onDeleteAccount: {
                showSettingsModal = false
                viewModel.logout()
            },
            onProfileCompleted: {
                viewModel.addMessage(Message(
                    content: "Great, your profile is all set! Ready to create your first workout?",
                    isUser: false
                ))
            }
        )
    }

    private var profileModalSheet: some View {
        NavigationStack {
            UserProfileView(
                userId: viewModel.user.id,
                mode: .edit,
                onSave: { updatedUser in
                    if updatedUser.hasCompletedOnboarding {
                        viewModel.addMessage(Message(
                            content: "Great, your profile is all set! Ready to create your first workout?",
                            isUser: false
                        ))
                    }
                },
                onDeleteAccount: {
                    showProfileModal = false
                    viewModel.logout()
                }
            )
            .environmentObject(navigationModel)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showProfileModal = false
                    }
                }
            }
        }
    }
}


// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary)
        .cornerRadius(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
    }
}
