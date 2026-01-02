'use client';

import { useState, useCallback, useEffect } from 'react';
import ProtectedRoute from '@/components/ProtectedRoute';
import { useAuth } from '@/components/AuthProvider';
import { sendMessage, StreamEvent, WorkoutCardData, PlanCardData, ScheduleCardData } from '@/lib/chat';
import { analyzeImage } from '@/lib/api';
import type { ChatMessage } from '@/lib/types';
import type { AttachedFile } from '@/components/chat/ChatInput';

// v226: Server-side suggestion chips
interface SuggestionChip {
  label: string;
  command: string;
}

interface CardState {
  workoutCards: WorkoutCardData[];
  planCards: PlanCardData[];
  scheduleCards: ScheduleCardData[]; // v248
}
import ChatLayout, { useChatLayout } from '@/components/chat/ChatLayout';
import ChatMessages from '@/components/chat/ChatMessages';
import ChatInput from '@/components/chat/ChatInput';

function ChatArea() {
  const { getIdToken } = useAuth();
  // v235: Access sidebar refresh for cross-client sync
  const { refreshSidebar } = useChatLayout();
  // v227: Start with empty messages - greeting shown separately
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [streamingText, setStreamingText] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [responseId, setResponseId] = useState<string | undefined>();
  const [pendingCards, setPendingCards] = useState<CardState>({ workoutCards: [], planCards: [], scheduleCards: [] });

  // v226: Server-side initial chips
  const [serverChips, setServerChips] = useState<SuggestionChip[]>([]);
  // v227: Server-side greeting
  const [serverGreeting, setServerGreeting] = useState<string>('');

  // v226: Fetch initial chips and greeting from server on mount
  useEffect(() => {
    async function loadInitialChips() {
      try {
        const token = await getIdToken();
        if (!token) return;

        const response = await fetch(
          'https://us-central1-medinaintelligence.cloudfunctions.net/initialChips',
          {
            method: 'GET',
            headers: {
              Authorization: `Bearer ${token}`,
            },
          }
        );

        if (response.ok) {
          const data = await response.json();
          if (data.chips) {
            setServerChips(data.chips);
            console.log('[Chat] Loaded initial chips:', data.chips.length);
          }
          // v227: Use server greeting
          if (data.greeting) {
            setServerGreeting(data.greeting);
            console.log('[Chat] Loaded greeting:', data.greeting);
          }
        }
      } catch (err) {
        console.error('[Chat] Failed to load initial chips:', err);
      }
    }

    loadInitialChips();
  }, [getIdToken]);

  const handleStreamEvent = useCallback((
    event: StreamEvent,
    onDelta: (delta: string) => void,
    onResponseId: (id: string) => void,
    onCards: (cards: CardState) => void
  ) => {
    // OpenAI events have fields at root level, not nested in event.data
    switch (event.type) {
      case 'response.created':
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const responseId = (event as any).response?.id;
        if (responseId) {
          onResponseId(responseId);
        }
        break;
      case 'response.output_text.delta':
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const delta = (event as any).delta;
        if (delta) {
          onDelta(delta);
        }
        break;
      case 'response.output_item.added':
        // Tool call detected - could show indicator
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const item = (event as any).item;
        if (item?.type === 'function_call') {
          console.log('Tool call:', item.name);
        }
        break;
      case 'response.completed':
        // Stream complete
        break;
      case 'workout_card':
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const workoutCards = (event as any).cards as WorkoutCardData[];
        if (workoutCards?.length) {
          console.log('[Chat] Received workout cards:', workoutCards);
          onCards({ workoutCards, planCards: [], scheduleCards: [] });
        }
        break;
      case 'plan_card':
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const planCards = (event as any).cards as PlanCardData[];
        if (planCards?.length) {
          console.log('[Chat] Received plan cards:', planCards);
          onCards({ workoutCards: [], planCards, scheduleCards: [] });
        }
        break;
      case 'schedule_card':
        // v248: Schedule card for calendar display
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const scheduleCards = (event as any).cards as ScheduleCardData[];
        if (scheduleCards?.length) {
          console.log('[Chat] Received schedule cards:', scheduleCards);
          onCards({ workoutCards: [], planCards: [], scheduleCards });
        }
        break;
    }
  }, []);

  // v254: Process image attachments with vision API
  const processImageAttachments = async (
    attachments: AttachedFile[],
    token: string
  ): Promise<string[]> => {
    const results: string[] = [];

    for (const attachment of attachments) {
      if (attachment.type === 'image') {
        try {
          // Extract base64 data (remove data:image/...;base64, prefix)
          const base64 = attachment.preview.split(',')[1];

          console.log('[Chat] v254: Processing image with vision API:', attachment.file.name);

          const visionResult = await analyzeImage(
            token,
            base64,
            `Extract all workout data from this image. Include:
- Exercise names (be specific)
- Sets, reps, and weights if visible
- Any dates or timestamps
- Any notes or instructions

Return the data in a structured format.`,
            { jsonMode: true }
          );

          results.push(visionResult);
          console.log('[Chat] v254: Vision result received');
        } catch (err) {
          console.error('[Chat] v254: Vision API error:', err);
          results.push(`[Error processing image: ${attachment.file.name}]`);
        }
      }
    }

    return results;
  };

  const handleSend = async (userMessage: string, attachments?: AttachedFile[]) => {
    if (isLoading) return;

    setError(null);

    // v254: Build message content with attachment context
    let messageContent = userMessage;
    let visionContext = '';

    // Add user message immediately (show what user typed + attachment indicator)
    const displayMessage = attachments?.length
      ? `${userMessage}${userMessage ? '\n\n' : ''}[${attachments.length} file${attachments.length > 1 ? 's' : ''} attached]`
      : userMessage;

    const newMessages: ChatMessage[] = [...messages, { role: 'user', content: displayMessage }];
    setMessages(newMessages);
    setIsLoading(true);
    setStreamingText('');

    try {
      const token = await getIdToken();
      if (!token) {
        throw new Error('Not authenticated');
      }

      // v254: Process image attachments with vision API
      if (attachments?.length) {
        const imageAttachments = attachments.filter(a => a.type === 'image');
        const csvAttachments = attachments.filter(a => a.type === 'csv');

        if (imageAttachments.length > 0) {
          console.log('[Chat] v254: Processing', imageAttachments.length, 'image(s)');
          const visionResults = await processImageAttachments(imageAttachments, token);

          if (visionResults.length > 0) {
            visionContext = `\n\n[Extracted from attached image${visionResults.length > 1 ? 's' : ''}:\n${visionResults.join('\n---\n')}\n]`;
          }
        }

        if (csvAttachments.length > 0) {
          // For CSV, we could read the file content, but for now just indicate it's attached
          // Full CSV import should use the dedicated import flow
          visionContext += `\n\n[CSV file attached: ${csvAttachments.map(a => a.file.name).join(', ')}]`;
        }
      }

      // Combine user message with vision context
      messageContent = userMessage + visionContext;

      // Send only the new user message (backend has conversation history via responseId)
      const messagesToSend: ChatMessage[] = responseId
        ? [{ role: 'user', content: messageContent }]
        : [...messages, { role: 'user', content: messageContent }];

      let fullText = '';
      let newResponseId: string | undefined;
      let collectedCards: CardState = { workoutCards: [], planCards: [], scheduleCards: [] };

      console.log('[Chat] Sending message:', userMessage);
      console.log('[Chat] Previous responseId:', responseId);

      for await (const event of sendMessage(token, messagesToSend, responseId)) {
        console.log('[Chat] SSE event:', event.type);
        handleStreamEvent(
          event,
          (delta) => {
            fullText += delta;
            setStreamingText(fullText);
          },
          (id) => {
            newResponseId = id;
          },
          (cards) => {
            // Accumulate cards from stream
            collectedCards = {
              workoutCards: [...collectedCards.workoutCards, ...cards.workoutCards],
              planCards: [...collectedCards.planCards, ...cards.planCards],
              scheduleCards: [...collectedCards.scheduleCards, ...cards.scheduleCards],
            };
            setPendingCards(collectedCards);
          }
        );
      }

      console.log('[Chat] Stream complete. fullText length:', fullText.length);
      console.log('[Chat] New responseId:', newResponseId);
      console.log('[Chat] Collected cards:', collectedCards);

      // Add complete assistant message with any cards
      if (fullText || collectedCards.workoutCards.length || collectedCards.planCards.length || collectedCards.scheduleCards.length) {
        setMessages((prev) => [...prev, {
          role: 'assistant',
          content: fullText,
          workoutCards: collectedCards.workoutCards.length ? collectedCards.workoutCards : undefined,
          planCards: collectedCards.planCards.length ? collectedCards.planCards : undefined,
          scheduleCards: collectedCards.scheduleCards.length ? collectedCards.scheduleCards : undefined,
        }]);

        // v235: Refresh sidebar when plan cards received (cross-client sync)
        if (collectedCards.planCards.length > 0) {
          console.log('[Chat] v235: Refreshing sidebar after plan creation');
          refreshSidebar();
        }
      } else {
        console.warn('[Chat] No text or cards received from stream');
      }
      setStreamingText('');
      setPendingCards({ workoutCards: [], planCards: [], scheduleCards: [] });

      if (newResponseId) {
        setResponseId(newResponseId);
      }
    } catch (err) {
      console.error('Chat error:', err);
      setError(err instanceof Error ? err.message : 'Something went wrong');
      // Add error message as assistant response
      setMessages((prev) => [
        ...prev,
        { role: 'assistant', content: "I'm having trouble connecting right now. Please try again in a moment." },
      ]);
    } finally {
      setIsLoading(false);
      setStreamingText('');
    }
  };

  return (
    <div className="flex flex-col h-full bg-white">
      {/* v231: Removed duplicate header - sidebar has toggle. Just pass toggleSidebar to ChatMessages */}

      {/* Messages Area - v227: Pass greeting for empty state */}
      <ChatMessages
        messages={messages}
        streamingText={streamingText}
        isLoading={isLoading}
        greeting={serverGreeting}
      />

      {/* Error Banner */}
      {error && (
        <div className="px-4 py-2 bg-red-50 border-t border-red-200">
          <p className="text-sm text-red-700 text-center">{error}</p>
        </div>
      )}

      {/* Input Area - v227: Show chips when no user messages */}
      <ChatInput
        onSend={handleSend}
        isLoading={isLoading}
        suggestions={messages.length === 0 ? serverChips : []}
      />
    </div>
  );
}

function ChatApp() {
  return (
    <ChatLayout>
      <ChatArea />
    </ChatLayout>
  );
}

export default function ChatPage() {
  return (
    <ProtectedRoute>
      <ChatApp />
    </ProtectedRoute>
  );
}
