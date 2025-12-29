// Medina Web Types - matching iOS app data structures

// ============================================
// User & Auth
// ============================================

export interface UserProfile {
  uid: string;
  email: string;
  displayName: string;
  photoURL?: string;
  role: 'member' | 'trainer' | 'admin';
  gymId?: string;
  trainerId?: string;
  profile?: {
    birthdate?: string;
    gender?: string;
    heightInches?: number;
    currentWeight?: number;
    fitnessGoal?: string;
    experienceLevel?: string;
    preferredDays?: string[];
    sessionDuration?: number;
    personalMotivation?: string;
  };
}

// ============================================
// Plans & Programs
// ============================================

export interface Plan {
  id: string;
  userId: string;
  name: string;
  status: 'active' | 'completed' | 'abandoned' | 'draft';
  startDate?: Date;
  endDate?: Date;
  createdAt: Date;
  updatedAt: Date;
  programIds: string[];
}

export interface Program {
  id: string;
  planId: string;
  name: string;
  phase: string;
  weekNumber: number;
  status: 'pending' | 'active' | 'completed';
  workoutIds: string[];
}

// ============================================
// Workouts
// ============================================

export type WorkoutStatus = 'scheduled' | 'in_progress' | 'completed' | 'skipped';
export type SplitDay = 'upper' | 'lower' | 'push' | 'pull' | 'legs' | 'full_body' | 'chest' | 'back' | 'shoulders' | 'arms' | 'core';
export type SessionType = 'strength' | 'cardio' | 'hybrid' | 'mobility';

export interface Workout {
  id: string;
  userId: string;
  name: string;
  scheduledDate?: Date;
  completedDate?: Date;
  status: WorkoutStatus;
  splitDay?: SplitDay;
  sessionType?: SessionType;
  estimatedDuration?: number;
  actualDuration?: number;
  exerciseIds: string[];
  programId?: string;
  planId?: string;
}

export interface ExerciseInstance {
  id: string;
  workoutId: string;
  exerciseId: string;
  position: number;
  protocolVariantId?: string;
  isCompleted: boolean;
}

export interface ExerciseSet {
  id: string;
  instanceId: string;
  setNumber: number;
  targetWeight?: number;
  targetReps?: number;
  actualWeight?: number;
  actualReps?: number;
  isCompleted: boolean;
  rpe?: number;
}

// ============================================
// Exercises & Library
// ============================================

export interface Exercise {
  id: string;
  name: string;
  baseExercise?: string;
  equipment?: string;
  muscleGroups: string[];
  movementPattern?: string;
  description?: string;
  videoUrl?: string;
}

export interface ProtocolConfig {
  id: string;
  variantName: string;
  familyId: string;
  sets: number;
  reps: number[];
  restBetweenSets: number[];
  tempo?: string;
}

// ============================================
// Messages & Threads
// ============================================

export interface Thread {
  id: string;
  participantIds: string[];
  lastMessageAt: Date;
  lastMessagePreview?: string;
  unreadCount?: number;
}

export interface ThreadMessage {
  id: string;
  threadId: string;
  senderId: string;
  content: string;
  createdAt: Date;
  readAt?: Date;
}

// ============================================
// Chat & Conversations
// ============================================

export interface WorkoutCardData {
  workoutId: string;
  workoutName: string;
}

export interface PlanCardData {
  planId: string;
  planName: string;
  workoutCount: number;
  durationWeeks: number;
}

export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp?: Date;
  workoutCards?: WorkoutCardData[];
  planCards?: PlanCardData[];
  metadata?: {
    toolCalls?: ToolCall[];
    workoutCreated?: Workout;
    planCreated?: Plan;
  };
}

export interface ToolCall {
  id: string;
  name: string;
  arguments: Record<string, unknown>;
  result?: string;
}

export interface Conversation {
  id: string;
  userId: string;
  title: string;
  createdAt: Date;
  updatedAt: Date;
  messages: ChatMessage[];
  responseId?: string; // OpenAI response ID for continuation
}

// ============================================
// UI State
// ============================================

export interface SidebarState {
  isOpen: boolean;
  expandedFolders: Set<string>;
  selectedConversationId?: string;
}

export interface FolderItem {
  id: string;
  type: 'plan' | 'program' | 'workout' | 'exercise' | 'protocol' | 'thread';
  title: string;
  subtitle?: string;
  status?: string;
  statusColor?: string;
  children?: FolderItem[];
}
