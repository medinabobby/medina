/**
 * Chat Types for Firebase Functions
 *
 * Defines request/response types for the /api/chat endpoint.
 * Matches the OpenAI Responses API format for seamless integration.
 */

// ============================================================================
// Request Types
// ============================================================================

/**
 * Message in the conversation
 */
export interface ChatMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

/**
 * Tool output submitted by client after executing a tool
 */
export interface ToolOutput {
  type: 'function_call_output';
  call_id: string;
  output: string;
}

/**
 * Request body for POST /api/chat
 */
export interface ChatRequest {
  /** User's message(s) to send */
  messages: ChatMessage[];

  /** Previous response ID for conversation continuity */
  previousResponseId?: string;

  /** Tool outputs when continuing after a tool call (passthrough mode) */
  toolOutputs?: ToolOutput[];
}

// ============================================================================
// Response Types (SSE Events)
// ============================================================================

/**
 * Base SSE event structure
 */
export interface BaseStreamEvent {
  type: string;
}

/**
 * Response created - start of stream
 */
export interface ResponseCreatedEvent extends BaseStreamEvent {
  type: 'response.created';
  response_id: string;
}

/**
 * Text delta - partial text content
 */
export interface TextDeltaEvent extends BaseStreamEvent {
  type: 'response.output_text.delta';
  delta: string;
}

/**
 * Text done - text output complete
 */
export interface TextDoneEvent extends BaseStreamEvent {
  type: 'response.output_text.done';
  text: string;
}

/**
 * Function call started
 */
export interface FunctionCallAddedEvent extends BaseStreamEvent {
  type: 'response.output_item.added';
  name: string;
  call_id: string;
}

/**
 * Function call arguments complete
 */
export interface FunctionCallDoneEvent extends BaseStreamEvent {
  type: 'response.function_call_arguments.done';
  name: string;
  call_id: string;
  arguments: string;
}

/**
 * Response completed
 */
export interface ResponseCompletedEvent extends BaseStreamEvent {
  type: 'response.completed';
}

/**
 * Error event
 */
export interface ErrorEvent extends BaseStreamEvent {
  type: 'error';
  error: {
    message: string;
    code?: string;
  };
}

/**
 * Union of all SSE event types
 */
export type StreamEvent =
  | ResponseCreatedEvent
  | TextDeltaEvent
  | TextDoneEvent
  | FunctionCallAddedEvent
  | FunctionCallDoneEvent
  | ResponseCompletedEvent
  | ErrorEvent;

// ============================================================================
// User Profile Types
// ============================================================================

/**
 * User profile loaded from Firestore
 * Subset of fields needed for chat context
 */
export interface UserProfile {
  uid: string;
  email?: string;
  displayName?: string;
  profile?: {
    birthdate?: string;
    heightInches?: number;
    currentWeight?: number;
    fitnessGoal?: string;
    experienceLevel?: string;
    preferredDays?: string[];
    sessionDuration?: number;
    gender?: string;
    personalMotivation?: string;
  };
  role?: 'member' | 'trainer' | 'admin';
  gymId?: string;
  trainerId?: string;
}

// ============================================================================
// Tool Types
// ============================================================================

/**
 * Tool definition for OpenAI Responses API
 */
export interface ToolDefinition {
  type: 'function';
  name: string;
  description: string;
  parameters: {
    type: 'object';
    properties: Record<string, unknown>;
    required?: string[];
  };
}

/**
 * Parsed tool call from OpenAI response
 */
export interface ParsedToolCall {
  id: string;
  name: string;
  arguments: Record<string, unknown>;
}
