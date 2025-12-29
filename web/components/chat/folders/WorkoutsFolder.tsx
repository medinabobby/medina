'use client';

import { useState } from 'react';
import type { Workout } from '@/lib/types';
import { statusColors, colors } from '@/lib/colors';
import { useDetailModal } from '@/components/detail-views';

interface WorkoutsFolderProps {
  workouts: Workout[];
}

export default function WorkoutsFolder({ workouts }: WorkoutsFolderProps) {
  const [isOpen, setIsOpen] = useState(true);
  const { openWorkout } = useDetailModal();

  // Group workouts by status/time
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const upcoming = workouts.filter(w => {
    if (!w.scheduledDate) return false;
    const date = new Date(w.scheduledDate);
    return date >= today && w.status === 'scheduled';
  }).sort((a, b) => {
    const dateA = a.scheduledDate ? new Date(a.scheduledDate).getTime() : 0;
    const dateB = b.scheduledDate ? new Date(b.scheduledDate).getTime() : 0;
    return dateA - dateB;
  });

  const recent = workouts.filter(w => {
    return w.status === 'completed' || w.status === 'in_progress';
  }).slice(0, 5);

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed':
        return statusColors.completed;
      case 'in_progress':
        return statusColors.inProgress;
      case 'scheduled':
        return statusColors.scheduled;
      case 'skipped':
        return statusColors.skipped;
      default:
        return statusColors.draft;
    }
  };

  const formatDate = (date?: Date) => {
    if (!date) return '';
    const d = new Date(date);
    return new Intl.DateTimeFormat('en-US', {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
    }).format(d);
  };

  const getSplitDayLabel = (split?: string) => {
    if (!split) return '';
    return split.charAt(0).toUpperCase() + split.slice(1).replace('_', ' ');
  };

  return (
    <div>
      {/* Folder header - iOS style: chevron LEFT, icon, name, count */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center gap-2 px-3 py-2 text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
      >
        {/* Chevron on LEFT */}
        <svg
          className={`w-4 h-4 text-gray-400 transition-transform ${isOpen ? 'rotate-90' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
        </svg>
        {/* Heart icon */}
        <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
        </svg>
        <span className="flex-1 text-left text-sm font-medium">Workouts</span>
        {workouts.length > 0 && (
          <span className="text-xs text-gray-400">{workouts.length}</span>
        )}
      </button>

      {isOpen && (
        <div className="mt-0.5">
          {workouts.length === 0 ? (
            <div className="pl-10 py-2 text-sm text-gray-400">
              No workouts yet
            </div>
          ) : (
            <div className="space-y-1">
              {/* Upcoming section */}
              {upcoming.length > 0 && (
                <div>
                  <div className="pl-10 py-1 text-xs font-medium text-gray-400 uppercase tracking-wider">
                    Upcoming
                  </div>
                  <div className="space-y-0.5">
                    {upcoming.slice(0, 3).map(workout => (
                      <WorkoutItem
                        key={workout.id}
                        workout={workout}
                        statusColor={getStatusColor(workout.status)}
                        formatDate={formatDate}
                        getSplitDayLabel={getSplitDayLabel}
                        onOpenDetail={() => openWorkout(workout.id, workout.name)}
                      />
                    ))}
                    {upcoming.length > 3 && (
                      <button
                        className="w-full pl-10 pr-3 py-1.5 text-xs text-left"
                        style={{ color: colors.accentBlue }}
                      >
                        +{upcoming.length - 3} more
                      </button>
                    )}
                  </div>
                </div>
              )}

              {/* Recent section */}
              {recent.length > 0 && (
                <div>
                  <div className="pl-10 py-1 text-xs font-medium text-gray-400 uppercase tracking-wider">
                    Recent
                  </div>
                  <div className="space-y-0.5">
                    {recent.map(workout => (
                      <WorkoutItem
                        key={workout.id}
                        workout={workout}
                        statusColor={getStatusColor(workout.status)}
                        formatDate={formatDate}
                        getSplitDayLabel={getSplitDayLabel}
                        onOpenDetail={() => openWorkout(workout.id, workout.name)}
                      />
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

interface WorkoutItemProps {
  workout: Workout;
  statusColor: string;
  formatDate: (date?: Date) => string;
  getSplitDayLabel: (split?: string) => string;
  onOpenDetail: () => void;
}

function WorkoutItem({ workout, statusColor, formatDate, getSplitDayLabel, onOpenDetail }: WorkoutItemProps) {
  return (
    <button
      onClick={onOpenDetail}
      className="w-full flex items-center gap-2 pl-10 pr-3 py-2 text-left hover:bg-gray-100 rounded-lg transition-colors"
    >
      {/* Status dot on LEFT for workout items (like iOS) */}
      <div
        className="w-2 h-2 rounded-full flex-shrink-0"
        style={{ backgroundColor: statusColor }}
      />
      <div className="flex-1 min-w-0">
        <p className="text-sm text-gray-700 truncate">
          {workout.name || getSplitDayLabel(workout.splitDay) || 'Workout'}
        </p>
        <p className="text-xs text-gray-400">
          {formatDate(workout.scheduledDate || workout.completedDate)}
        </p>
      </div>
    </button>
  );
}
