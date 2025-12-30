'use client';

import { useRef, useEffect } from 'react';
import type { ChatMessage, WorkoutCardData, PlanCardData } from '@/lib/types';
import { colors } from '@/lib/colors';
import { useDetailModal } from '@/components/detail-views';
import { MedinaIcon } from '@/components/icons/MedinaIcon';

interface ChatMessagesProps {
  messages: ChatMessage[];
  streamingText?: string;
  isLoading: boolean;
  greeting?: string; // v227: Server-side greeting for empty state
}

// v232: Default greeting shows while server greeting loads
const DEFAULT_GREETING = "Ready when you are.";

export default function ChatMessages({ messages, streamingText, isLoading, greeting }: ChatMessagesProps) {
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, streamingText]);

  // v227: Show greeting when no messages
  const showGreeting = messages.length === 0 && !streamingText && !isLoading;
  const displayGreeting = greeting || DEFAULT_GREETING;

  return (
    <div className="flex-1 overflow-y-auto">
      <div className="max-w-3xl mx-auto px-4 py-6 space-y-6">
        {/* v233: Centered greeting with Medina brand icon */}
        {showGreeting && displayGreeting && (
          <div className="flex flex-col items-center justify-center min-h-[40vh] text-center">
            {/* Medina tic-tac-toe brand icon */}
            <MedinaIcon className="w-12 h-12 mb-4 text-blue-500" />
            <p className="text-xl text-gray-800 font-medium">
              {displayGreeting}
            </p>
          </div>
        )}

        {messages.map((message, index) => (
          <MessageBubble key={index} message={message} />
        ))}

        {/* Streaming message */}
        {streamingText && (
          <div className="flex justify-start">
            <div className="text-gray-800 whitespace-pre-wrap">
              {streamingText}
              <span className="inline-block w-2 h-4 bg-gray-400 ml-0.5 animate-pulse" />
            </div>
          </div>
        )}

        {/* v233: Loading indicator - animated Medina icon */}
        {isLoading && !streamingText && (
          <div className="flex justify-start">
            <MedinaIcon className="w-6 h-6 text-blue-500" animate />
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>
    </div>
  );
}

interface MessageBubbleProps {
  message: ChatMessage;
}

function MessageBubble({ message }: MessageBubbleProps) {
  const isUser = message.role === 'user';
  const { openWorkout, openPlan } = useDetailModal();

  if (isUser) {
    // User message: right-aligned, blue bubble
    return (
      <div className="flex justify-end">
        <div
          className="max-w-[80%] px-4 py-3 text-white rounded-2xl rounded-br-md"
          style={{ backgroundColor: colors.accentBlue }}
        >
          <p className="whitespace-pre-wrap">{message.content}</p>
        </div>
      </div>
    );
  }

  // AI message: left-aligned, plain text (no bubble) - Claude/ChatGPT style
  // v230: Removed avatar to match Claude pattern
  return (
    <div className="flex justify-start">
      <div className="max-w-[85%] space-y-3">
        {message.content && (
          <p className="text-gray-800 whitespace-pre-wrap leading-relaxed">
            {message.content}
          </p>
        )}

        {/* Workout Cards */}
        {message.workoutCards?.map((card) => (
          <WorkoutCard
            key={card.workoutId}
            card={card}
            onClick={() => openWorkout(card.workoutId, card.workoutName)}
          />
        ))}

        {/* Plan Cards */}
        {message.planCards?.map((card) => (
          <PlanCard
            key={card.planId}
            card={card}
            onClick={() => openPlan(card.planId, card.planName)}
          />
        ))}
      </div>
    </div>
  );
}

// Workout Card Component
function WorkoutCard({ card, onClick }: { card: WorkoutCardData; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full border rounded-xl p-4 bg-gradient-to-br from-blue-50 to-white shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left"
      style={{ borderColor: colors.accentBlue + '40' }}
    >
      <div className="flex items-center gap-3">
        <div
          className="w-10 h-10 rounded-lg flex items-center justify-center"
          style={{ backgroundColor: colors.accentBlue + '20' }}
        >
          <svg className="w-5 h-5" style={{ color: colors.accentBlue }} fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 10h16M4 14h16M4 18h16" />
          </svg>
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-gray-900 truncate">{card.workoutName}</p>
          <p className="text-sm text-gray-500">Workout created</p>
        </div>
        <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
        </svg>
      </div>
    </button>
  );
}

// Plan Card Component
function PlanCard({ card, onClick }: { card: PlanCardData; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full border rounded-xl p-4 bg-gradient-to-br from-emerald-50 to-white shadow-sm hover:shadow-md transition-shadow cursor-pointer text-left"
      style={{ borderColor: colors.success + '40' }}
    >
      <div className="flex items-center gap-3">
        <div
          className="w-10 h-10 rounded-lg flex items-center justify-center"
          style={{ backgroundColor: colors.success + '20' }}
        >
          <svg className="w-5 h-5" style={{ color: colors.success }} fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-gray-900 truncate">{card.planName}</p>
          <p className="text-sm text-gray-500">
            {card.workoutCount} workouts • {card.durationWeeks} weeks
          </p>
        </div>
        <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
        </svg>
      </div>
    </button>
  );
}
