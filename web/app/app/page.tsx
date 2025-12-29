'use client';

import { useState, useCallback } from 'react';
import ProtectedRoute from '@/components/ProtectedRoute';
import { useAuth } from '@/components/AuthProvider';
import { sendMessage, StreamEvent, WorkoutCardData, PlanCardData } from '@/lib/chat';
import type { ChatMessage } from '@/lib/types';

interface CardState {
  workoutCards: WorkoutCardData[];
  planCards: PlanCardData[];
}
import ChatLayout, { useChatLayout } from '@/components/chat/ChatLayout';
import ChatMessages from '@/components/chat/ChatMessages';
import ChatInput from '@/components/chat/ChatInput';

function ChatArea() {
  const { getIdToken } = useAuth();
  const { toggleSidebar } = useChatLayout();
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      role: 'assistant',
      content: "Hey! I'm Medina, your AI fitness coach. Tell me about your fitness goals, and I'll help you create a personalized workout plan. What would you like to work on?",
    },
  ]);
  const [isLoading, setIsLoading] = useState(false);
  const [streamingText, setStreamingText] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [responseId, setResponseId] = useState<string | undefined>();
  const [pendingCards, setPendingCards] = useState<CardState>({ workoutCards: [], planCards: [] });

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
          onCards({ workoutCards, planCards: [] });
        }
        break;
      case 'plan_card':
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const planCards = (event as any).cards as PlanCardData[];
        if (planCards?.length) {
          console.log('[Chat] Received plan cards:', planCards);
          onCards({ workoutCards: [], planCards });
        }
        break;
    }
  }, []);

  const handleSend = async (userMessage: string) => {
    if (isLoading) return;

    setError(null);

    // Add user message immediately
    const newMessages: ChatMessage[] = [...messages, { role: 'user', content: userMessage }];
    setMessages(newMessages);
    setIsLoading(true);
    setStreamingText('');

    try {
      const token = await getIdToken();
      if (!token) {
        throw new Error('Not authenticated');
      }

      // Send only the new user message (backend has conversation history via responseId)
      const messagesToSend: ChatMessage[] = responseId
        ? [{ role: 'user', content: userMessage }]
        : newMessages;

      let fullText = '';
      let newResponseId: string | undefined;
      let collectedCards: CardState = { workoutCards: [], planCards: [] };

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
            };
            setPendingCards(collectedCards);
          }
        );
      }

      console.log('[Chat] Stream complete. fullText length:', fullText.length);
      console.log('[Chat] New responseId:', newResponseId);
      console.log('[Chat] Collected cards:', collectedCards);

      // Add complete assistant message with any cards
      if (fullText || collectedCards.workoutCards.length || collectedCards.planCards.length) {
        setMessages((prev) => [...prev, {
          role: 'assistant',
          content: fullText,
          workoutCards: collectedCards.workoutCards.length ? collectedCards.workoutCards : undefined,
          planCards: collectedCards.planCards.length ? collectedCards.planCards : undefined,
        }]);
      } else {
        console.warn('[Chat] No text or cards received from stream');
      }
      setStreamingText('');
      setPendingCards({ workoutCards: [], planCards: [] });

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
      {/* Chat Header */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-gray-200">
        <button
          onClick={toggleSidebar}
          className="p-2 hover:bg-gray-100 rounded-lg transition-colors md:hidden"
        >
          <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
          </svg>
        </button>
        <div className="w-8 h-8 bg-gradient-to-br from-blue-500 to-blue-600 rounded-lg flex items-center justify-center">
          <span className="text-white font-bold text-sm">M</span>
        </div>
        <div className="flex-1 min-w-0">
          <h1 className="font-semibold text-gray-900 text-sm">Medina</h1>
          <p className="text-xs text-gray-500">AI Fitness Coach</p>
        </div>
      </div>

      {/* Messages Area */}
      <ChatMessages
        messages={messages}
        streamingText={streamingText}
        isLoading={isLoading}
      />

      {/* Error Banner */}
      {error && (
        <div className="px-4 py-2 bg-red-50 border-t border-red-200">
          <p className="text-sm text-red-700 text-center">{error}</p>
        </div>
      )}

      {/* Input Area */}
      <ChatInput
        onSend={handleSend}
        isLoading={isLoading}
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
