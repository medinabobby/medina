/**
 * OpenAI Mock Factory
 *
 * Provides mock implementations for OpenAI SDK
 * Used in unit tests to avoid hitting real OpenAI API
 */

import { vi } from 'vitest';

// Response types matching OpenAI Responses API
export interface MockResponseOutput {
  type: 'text' | 'function_call';
  text?: string;
  name?: string;
  call_id?: string;
  arguments?: string;
}

export interface MockResponse {
  id: string;
  object: 'response';
  created_at: number;
  output: MockResponseOutput[];
  status: 'completed' | 'failed' | 'in_progress';
}

// Streaming event types
export interface MockStreamEvent {
  type: string;
  response_id?: string;
  delta?: string;
  name?: string;
  call_id?: string;
  arguments?: string;
}

/**
 * Create a mock OpenAI client for non-streaming responses
 *
 * Usage:
 * ```typescript
 * const mockOpenAI = createMockOpenAI();
 * mockOpenAI.responses.create.mockResolvedValue({
 *   id: 'resp_123',
 *   output: [{ type: 'text', text: 'Hello!' }],
 *   status: 'completed',
 * });
 * ```
 */
export function createMockOpenAI() {
  return {
    responses: {
      create: vi.fn().mockResolvedValue({
        id: 'resp_mock123',
        object: 'response',
        created_at: Date.now(),
        output: [{ type: 'text', text: 'Mock response' }],
        status: 'completed',
      } as MockResponse),
    },
  };
}

/**
 * Create a mock async generator for streaming responses
 *
 * Usage:
 * ```typescript
 * const events = [
 *   { type: 'response.created', response_id: 'resp_123' },
 *   { type: 'response.output_text.delta', delta: 'Hello' },
 *   { type: 'response.completed' },
 * ];
 * const mockOpenAI = createMockOpenAIStream(events);
 * ```
 */
export function createMockOpenAIStream(events: MockStreamEvent[]) {
  const mockCreate = vi.fn().mockImplementation(async function* () {
    for (const event of events) {
      yield event;
    }
  });

  return {
    responses: {
      create: mockCreate,
    },
  };
}

/**
 * Create a simple text response stream
 */
export function createMockTextStream(text: string, responseId = 'resp_mock123') {
  const events: MockStreamEvent[] = [
    { type: 'response.created', response_id: responseId },
  ];

  // Split text into chunks to simulate streaming
  const chunks = text.match(/.{1,10}/g) || [text];
  for (const chunk of chunks) {
    events.push({ type: 'response.output_text.delta', delta: chunk });
  }

  events.push({ type: 'response.output_text.done' });
  events.push({ type: 'response.completed' });

  return createMockOpenAIStream(events);
}

/**
 * Create a response stream with a tool call
 */
export function createMockToolCallStream(
  toolName: string,
  toolArgs: Record<string, unknown>,
  responseId = 'resp_mock123',
  callId = 'call_mock123'
) {
  const events: MockStreamEvent[] = [
    { type: 'response.created', response_id: responseId },
    { type: 'response.output_item.added', name: toolName, call_id: callId },
    {
      type: 'response.function_call_arguments.done',
      name: toolName,
      call_id: callId,
      arguments: JSON.stringify(toolArgs),
    },
    { type: 'response.completed' },
  ];

  return createMockOpenAIStream(events);
}

/**
 * Create a response stream with text followed by tool call
 */
export function createMockTextAndToolStream(
  text: string,
  toolName: string,
  toolArgs: Record<string, unknown>,
  responseId = 'resp_mock123',
  callId = 'call_mock123'
) {
  const events: MockStreamEvent[] = [
    { type: 'response.created', response_id: responseId },
  ];

  // Add text deltas
  const chunks = text.match(/.{1,10}/g) || [text];
  for (const chunk of chunks) {
    events.push({ type: 'response.output_text.delta', delta: chunk });
  }
  events.push({ type: 'response.output_text.done' });

  // Add tool call
  events.push({ type: 'response.output_item.added', name: toolName, call_id: callId });
  events.push({
    type: 'response.function_call_arguments.done',
    name: toolName,
    call_id: callId,
    arguments: JSON.stringify(toolArgs),
  });

  events.push({ type: 'response.completed' });

  return createMockOpenAIStream(events);
}

/**
 * Create a mock that simulates an error response
 */
export function createMockOpenAIError(errorMessage: string) {
  return {
    responses: {
      create: vi.fn().mockRejectedValue(new Error(errorMessage)),
    },
  };
}

/**
 * Create a mock that simulates a stream error
 */
export function createMockStreamError(errorMessage: string, afterEvents = 0) {
  const mockCreate = vi.fn().mockImplementation(async function* () {
    yield { type: 'response.created', response_id: 'resp_mock123' };

    for (let i = 0; i < afterEvents; i++) {
      yield { type: 'response.output_text.delta', delta: 'chunk' };
    }

    throw new Error(errorMessage);
  });

  return {
    responses: {
      create: mockCreate,
    },
  };
}
