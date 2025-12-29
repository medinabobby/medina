'use client';

import { useState, useEffect } from 'react';
import { X, ArrowLeft, Loader2, Play, SkipForward, CheckCircle } from 'lucide-react';
import { colors } from '@/lib/colors';
import { BreadcrumbBar, BreadcrumbItem } from './shared/BreadcrumbBar';
import { HeroSection } from './shared/HeroSection';
import { KeyValueRow } from './shared/KeyValueRow';
import { DisclosureSection } from './shared/DisclosureSection';
import { StatusListRow } from './shared/StatusListRow';
import { useDetailModal } from './DetailModalContext';
import { useAuth } from '@/components/AuthProvider';
import { getWorkoutWithExercises } from '@/lib/firestore';
import type { WorkoutDetails } from '@/lib/types';

interface WorkoutDetailModalProps {
  workoutId: string;
  onBack?: () => void;
  onClose: () => void;
  breadcrumbItems: BreadcrumbItem[];
}

export function WorkoutDetailModal({ workoutId, onBack, onClose, breadcrumbItems }: WorkoutDetailModalProps) {
  const { openExercise, refresh } = useDetailModal();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [workout, setWorkout] = useState<WorkoutDetails | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  useEffect(() => {
    async function fetchWorkout() {
      if (!user?.uid) return;

      setLoading(true);
      try {
        const data = await getWorkoutWithExercises(user.uid, workoutId);
        setWorkout(data);
      } catch (error) {
        console.error('Failed to fetch workout:', error);
      } finally {
        setLoading(false);
      }
    }

    fetchWorkout();
  }, [user?.uid, workoutId]);

  const callHandler = async (action: string) => {
    if (!user?.uid || !workout) return;

    setActionLoading(action);
    try {
      const token = await user.getIdToken();
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          action,
          workoutId: workout.id,
        }),
      });

      if (response.ok) {
        // Refresh the data
        const data = await getWorkoutWithExercises(user.uid, workoutId);
        setWorkout(data);
        refresh();
      }
    } catch (error) {
      console.error(`Failed to ${action} workout:`, error);
    } finally {
      setActionLoading(null);
    }
  };

  const handleStart = () => callHandler('startWorkout');
  const handleSkip = () => callHandler('skipWorkout');
  const handleComplete = () => callHandler('endWorkout');

  const formatDate = (date?: Date) => {
    if (!date) return '-';
    return new Intl.DateTimeFormat('en-US', {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
    }).format(date);
  };

  const formatDuration = (minutes?: number) => {
    if (!minutes) return '-';
    if (minutes < 60) return `${minutes} min`;
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
  };

  const canStart = workout?.status === 'scheduled';
  const canSkip = workout?.status === 'scheduled' || workout?.status === 'in_progress';
  const canComplete = workout?.status === 'in_progress';

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div
        className="sticky top-0 flex items-center justify-between px-4 py-3 border-b z-10"
        style={{ backgroundColor: colors.bgPrimary, borderColor: colors.borderSubtle }}
      >
        <button
          onClick={onBack || onClose}
          className="p-2 -ml-2 hover:bg-gray-100 rounded-lg transition-colors"
        >
          {onBack ? (
            <ArrowLeft className="w-5 h-5" style={{ color: colors.secondaryText }} />
          ) : (
            <X className="w-5 h-5" style={{ color: colors.secondaryText }} />
          )}
        </button>
        <h2
          className="text-base font-semibold"
          style={{ color: colors.primaryText }}
        >
          Workout Details
        </h2>
        <div className="w-9" />
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 animate-spin" style={{ color: colors.accentBlue }} />
          </div>
        ) : !workout ? (
          <div className="flex items-center justify-center py-12">
            <p className="text-sm" style={{ color: colors.tertiaryText }}>
              Workout not found
            </p>
          </div>
        ) : (
          <>
            <BreadcrumbBar items={breadcrumbItems} />
            <HeroSection
              title={workout.name}
              dateRange={formatDate(workout.scheduledDate)}
              subtitle={workout.splitDay ? workout.splitDay.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase()) : undefined}
              status={workout.status}
            />

            {/* iOS-style Start Workout action row */}
            {canStart && (
              <div className="px-4 py-3">
                <button
                  onClick={handleStart}
                  disabled={actionLoading !== null}
                  className="w-full flex items-center gap-3 px-4 py-3 rounded-xl transition-colors disabled:opacity-50"
                  style={{ backgroundColor: colors.accentSubtle }}
                >
                  {actionLoading === 'startWorkout' ? (
                    <Loader2 className="w-5 h-5 animate-spin" style={{ color: colors.accentBlue }} />
                  ) : (
                    <Play className="w-5 h-5" style={{ color: colors.accentBlue }} fill={colors.accentBlue} />
                  )}
                  <span className="flex-1 text-left font-medium" style={{ color: colors.accentBlue }}>
                    Start Workout
                  </span>
                  <svg className="w-5 h-5" style={{ color: colors.accentBlue }} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                  </svg>
                </button>
              </div>
            )}

            {/* Action buttons for Skip/Complete */}
            {(canSkip || canComplete) && !canStart && (
              <div className="flex gap-2 px-4 py-3">
                {canComplete && (
                  <button
                    onClick={handleComplete}
                    disabled={actionLoading !== null}
                    className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm transition-colors disabled:opacity-50"
                    style={{ backgroundColor: colors.success, color: '#FFFFFF' }}
                  >
                    {actionLoading === 'endWorkout' ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      <>
                        <CheckCircle className="w-4 h-4" />
                        Complete
                      </>
                    )}
                  </button>
                )}
                {canSkip && (
                  <button
                    onClick={handleSkip}
                    disabled={actionLoading !== null}
                    className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl font-medium text-sm transition-colors disabled:opacity-50"
                    style={{ backgroundColor: colors.bgSecondary, color: colors.secondaryText }}
                  >
                    {actionLoading === 'skipWorkout' ? (
                      <Loader2 className="w-4 h-4 animate-spin" />
                    ) : (
                      <>
                        <SkipForward className="w-4 h-4" />
                        Skip
                      </>
                    )}
                  </button>
                )}
              </div>
            )}

            {/* Workout Details section - iOS style */}
            <DisclosureSection title="Workout Details">
              <div className="space-y-0">
                {workout.sessionType && (
                  <KeyValueRow label="Session Type" value={workout.sessionType.charAt(0).toUpperCase() + workout.sessionType.slice(1)} />
                )}
                {workout.estimatedDuration && (
                  <KeyValueRow label="Est. Duration" value={formatDuration(workout.estimatedDuration)} />
                )}
                {workout.actualDuration && (
                  <KeyValueRow label="Actual Duration" value={formatDuration(workout.actualDuration)} />
                )}
                {workout.parentProgram && (
                  <KeyValueRow label="Program" value={workout.parentProgram.name} />
                )}
                {workout.parentPlan && (
                  <KeyValueRow label="Plan" value={workout.parentPlan.name} />
                )}
              </div>
            </DisclosureSection>

            <DisclosureSection title="Exercises in this Workout" count={workout.exercises.length}>
              {workout.exercises.length > 0 ? (
                <div className="space-y-2">
                  {workout.exercises.map((exercise, index) => (
                    <StatusListRow
                      key={exercise.id}
                      number={index + 1}
                      title={exercise.name}
                      subtitle={exercise.equipment}
                      metadata={exercise.prescription}
                      status={exercise.status}
                      onClick={() => openExercise(exercise.exerciseId, exercise.name, workoutId, workout.name)}
                    />
                  ))}
                </div>
              ) : (
                <p className="text-sm py-4 text-center" style={{ color: colors.tertiaryText }}>
                  No exercises yet
                </p>
              )}
            </DisclosureSection>
          </>
        )}
      </div>
    </div>
  );
}
