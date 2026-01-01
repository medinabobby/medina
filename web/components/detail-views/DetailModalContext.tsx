'use client';

import { createContext, useContext, useState, useCallback, ReactNode } from 'react';

type EntityType = 'plan' | 'program' | 'workout' | 'exercise' | 'schedule';

interface NavigationItem {
  type: EntityType;
  id: string;
  label: string;
  parentIds?: {
    planId?: string;
    programId?: string;
    workoutId?: string;
  };
  // v248: Schedule-specific metadata
  scheduleData?: {
    weekStart: string;
    weekEnd: string;
  };
}

interface DetailModalContextType {
  // State
  isOpen: boolean;
  currentEntity: NavigationItem | null;
  navigationStack: NavigationItem[];

  // Actions
  openPlan: (planId: string, planName: string) => void;
  openProgram: (programId: string, programName: string, planId: string, planName: string) => void;
  openWorkout: (workoutId: string, workoutName: string, parentIds?: { planId?: string; programId?: string }, parentLabels?: { planName?: string; programName?: string }) => void;
  openExercise: (exerciseId: string, exerciseName: string, workoutId?: string, workoutName?: string) => void;
  // v248: Schedule navigation
  openSchedule: (weekStart?: string, weekEnd?: string) => void;
  goBack: () => void;
  close: () => void;
  refresh: () => void;
}

const DetailModalContext = createContext<DetailModalContextType | undefined>(undefined);

export function DetailModalProvider({ children }: { children: ReactNode }) {
  const [navigationStack, setNavigationStack] = useState<NavigationItem[]>([]);
  const [refreshKey, setRefreshKey] = useState(0);

  const isOpen = navigationStack.length > 0;
  const currentEntity = navigationStack.length > 0 ? navigationStack[navigationStack.length - 1] : null;

  const openPlan = useCallback((planId: string, planName: string) => {
    setNavigationStack([
      { type: 'plan', id: planId, label: planName }
    ]);
  }, []);

  const openProgram = useCallback((programId: string, programName: string, planId: string, planName: string) => {
    setNavigationStack([
      { type: 'plan', id: planId, label: planName },
      { type: 'program', id: programId, label: programName, parentIds: { planId } }
    ]);
  }, []);

  const openWorkout = useCallback((
    workoutId: string,
    workoutName: string,
    parentIds?: { planId?: string; programId?: string },
    parentLabels?: { planName?: string; programName?: string }
  ) => {
    const stack: NavigationItem[] = [];

    if (parentIds?.planId && parentLabels?.planName) {
      stack.push({ type: 'plan', id: parentIds.planId, label: parentLabels.planName });
    }
    if (parentIds?.programId && parentLabels?.programName) {
      stack.push({
        type: 'program',
        id: parentIds.programId,
        label: parentLabels.programName,
        parentIds: { planId: parentIds.planId }
      });
    }
    stack.push({
      type: 'workout',
      id: workoutId,
      label: workoutName,
      parentIds
    });

    setNavigationStack(stack);
  }, []);

  const openExercise = useCallback((
    exerciseId: string,
    exerciseName: string,
    workoutId?: string,
    workoutName?: string
  ) => {
    // If we have a workout context, push onto existing stack
    if (workoutId && workoutName) {
      setNavigationStack(prev => {
        // If we're already viewing the workout, just push the exercise
        if (prev.length > 0 && prev[prev.length - 1].id === workoutId) {
          return [...prev, { type: 'exercise', id: exerciseId, label: exerciseName, parentIds: { workoutId } }];
        }
        // Otherwise, start fresh with just the exercise
        return [{ type: 'exercise', id: exerciseId, label: exerciseName, parentIds: { workoutId } }];
      });
    } else {
      // Standalone exercise view
      setNavigationStack([
        { type: 'exercise', id: exerciseId, label: exerciseName }
      ]);
    }
  }, []);

  // v248: Open schedule view
  const openSchedule = useCallback((weekStart?: string, weekEnd?: string) => {
    // Generate default week range if not provided
    const now = new Date();
    const dayOfWeek = now.getDay();
    const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const daysToSunday = dayOfWeek === 0 ? 0 : 7 - dayOfWeek;

    const startOfWeek = new Date(now);
    startOfWeek.setDate(now.getDate() - daysToMonday);
    const endOfWeek = new Date(now);
    endOfWeek.setDate(now.getDate() + daysToSunday);

    const start = weekStart || startOfWeek.toISOString().split('T')[0];
    const end = weekEnd || endOfWeek.toISOString().split('T')[0];

    setNavigationStack([
      {
        type: 'schedule',
        id: `schedule-${start}`,
        label: 'Schedule',
        scheduleData: { weekStart: start, weekEnd: end }
      }
    ]);
  }, []);

  const goBack = useCallback(() => {
    setNavigationStack(prev => {
      if (prev.length <= 1) return [];
      return prev.slice(0, -1);
    });
  }, []);

  const close = useCallback(() => {
    setNavigationStack([]);
  }, []);

  const refresh = useCallback(() => {
    setRefreshKey(k => k + 1);
  }, []);

  return (
    <DetailModalContext.Provider
      value={{
        isOpen,
        currentEntity,
        navigationStack,
        openPlan,
        openProgram,
        openWorkout,
        openExercise,
        openSchedule,
        goBack,
        close,
        refresh,
      }}
    >
      {children}
    </DetailModalContext.Provider>
  );
}

export function useDetailModal() {
  const context = useContext(DetailModalContext);
  if (context === undefined) {
    throw new Error('useDetailModal must be used within a DetailModalProvider');
  }
  return context;
}
