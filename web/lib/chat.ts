// Chat service for communicating with Firebase Functions backend

import type { ChatMessage, WorkoutCardData, PlanCardData } from './types';

export type { ChatMessage, WorkoutCardData, PlanCardData };

export interface StreamEvent {
  type: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  [key: string]: unknown;
}

const CHAT_API_URL = '/api/chat';

export async function* sendMessage(
  token: string,
  messages: ChatMessage[],
  previousResponseId?: string
): AsyncGenerator<StreamEvent> {
  const response = await fetch(CHAT_API_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      messages,
      previousResponseId,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Chat API error: ${response.status} - ${errorText}`);
  }

  if (!response.body) {
    throw new Error('No response body');
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let currentEventType = 'message'; // Default SSE event type

  while (true) {
    const { done, value } = await reader.read();

    if (done) break;

    buffer += decoder.decode(value, { stream: true });

    // Parse SSE events from buffer
    const lines = buffer.split('\n');
    buffer = lines.pop() || ''; // Keep incomplete line in buffer

    for (const line of lines) {
      // Handle named events (e.g., "event: workout_card")
      if (line.startsWith('event: ')) {
        currentEventType = line.slice(7).trim();
        continue;
      }

      if (line.startsWith('data: ')) {
        const data = line.slice(6);
        if (data === '[DONE]') {
          return;
        }
        try {
          const parsed = JSON.parse(data);

          // For custom events (workout_card, plan_card, suggestion_chips),
          // wrap the data with the event type
          if (currentEventType !== 'message' && !parsed.type) {
            yield { type: currentEventType, ...parsed };
          } else {
            yield parsed;
          }

          // Reset to default after yielding
          currentEventType = 'message';
        } catch {
          // Skip malformed JSON
          console.warn('Failed to parse SSE event:', data);
        }
      }
    }
  }
}

export function extractTextFromEvents(events: StreamEvent[]): string {
  let text = '';
  for (const event of events) {
    if (event.type === 'response.output_text.delta') {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      text += (event as any).delta || '';
    }
  }
  return text;
}

export function getResponseIdFromEvents(events: StreamEvent[]): string | undefined {
  for (const event of events) {
    if (event.type === 'response.created') {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return (event as any).response?.id;
    }
  }
  return undefined;
}
