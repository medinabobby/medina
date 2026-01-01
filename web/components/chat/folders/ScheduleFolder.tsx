'use client';

import { useState, useEffect, useMemo } from 'react';
import { Calendar } from 'lucide-react';
import { useAuth } from '@/components/AuthProvider';
import { getScheduleWorkouts } from '@/lib/firestore';
import { statusColors } from '@/lib/colors';
import { useDetailModal } from '@/components/detail-views';
import type { Workout } from '@/lib/types';

interface ScheduleFolderProps {
  refreshKey?: number;
}

/**
 * v248: Schedule folder in sidebar
 * Shows current week's workouts with status indicators
 */
export default function ScheduleFolder({ refreshKey = 0 }: ScheduleFolderProps) {
  const [isOpen, setIsOpen] = useState(true);
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [loading, setLoading] = useState(true);
  const { user } = useAuth();
  const { openSchedule, openWorkout } = useDetailModal();

  // Calculate current week range
  const { weekStart, weekEnd, dateRangeStr } = useMemo(() => {
    const now = new Date();
    const dayOfWeek = now.getDay();
    const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const daysToSunday = dayOfWeek === 0 ? 0 : 7 - dayOfWeek;

    const start = new Date(now);
    start.setDate(now.getDate() - daysToMonday);
    start.setHours(0, 0, 0, 0);

    const end = new Date(now);
    end.setDate(now.getDate() + daysToSunday);
    end.setHours(23, 59, 59, 999);

    // Format: "Dec 30 - Jan 5"
    const startMonth = start.toLocaleDateString('en-US', { month: 'short' });
    const startDay = start.getDate();
    const endMonth = end.toLocaleDateString('en-US', { month: 'short' });
    const endDay = end.getDate();

    const rangeStr = startMonth === endMonth
      ? `${startMonth} ${startDay} - ${endDay}`
      : `${startMonth} ${startDay} - ${endMonth} ${endDay}`;

    return {
      weekStart: start.toISOString().split('T')[0],
      weekEnd: end.toISOString().split('T')[0],
      dateRangeStr: rangeStr,
    };
  }, []);

  // Fetch workouts for current week
  useEffect(() => {
    async function loadWorkouts() {
      if (!user?.uid) return;

      setLoading(true);
      try {
        const data = await getScheduleWorkouts(user.uid, weekStart, weekEnd);
        setWorkouts(data);
      } catch (error) {
        console.error('[ScheduleFolder] Error loading workouts:', error);
      } finally {
        setLoading(false);
      }
    }

    loadWorkouts();
  }, [user?.uid, weekStart, weekEnd, refreshKey]);

  // Get today's workouts vs future
  const todayStr = new Date().toISOString().split('T')[0];
  const upcomingWorkouts = workouts.filter(w => {
    if (!w.scheduledDate) return false;
    const dateStr = new Date(w.scheduledDate).toISOString().split('T')[0];
    return dateStr >= todayStr && w.status === 'scheduled';
  });

  // Show max 3 workouts in sidebar
  const visibleWorkouts = upcomingWorkouts.slice(0, 3);
  const moreCount = upcomingWorkouts.length - 3;

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed': return statusColors.completed;
      case 'in_progress': return statusColors.inProgress;
      case 'skipped': return statusColors.skipped;
      default: return statusColors.scheduled;
    }
  };

  const getDayLabel = (date: Date): string => {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const workoutDate = new Date(date);
    workoutDate.setHours(0, 0, 0, 0);

    const diffDays = Math.round((workoutDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Tomorrow';
    return workoutDate.toLocaleDateString('en-US', { weekday: 'short' });
  };

  return (
    <div>
      {/* Folder header */}
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
        {/* Calendar icon */}
        <Calendar className="w-5 h-5 text-gray-500" />
        <span className="flex-1 text-left text-sm font-medium">Schedule</span>
        {upcomingWorkouts.length > 0 && (
          <span className="text-xs text-gray-400">{upcomingWorkouts.length}</span>
        )}
      </button>

      {isOpen && (
        <div className="mt-0.5">
          {loading ? (
            <div className="pl-10 py-2">
              <div className="animate-pulse h-4 w-24 bg-gray-200 rounded" />
            </div>
          ) : workouts.length === 0 ? (
            <div className="pl-10 py-2 text-sm text-gray-400">
              No workouts this week
            </div>
          ) : upcomingWorkouts.length === 0 ? (
            <div className="space-y-0.5">
              <div className="pl-10 py-2 text-sm text-gray-400">
                All done for this week!
              </div>
              <button
                onClick={() => openSchedule(weekStart, weekEnd)}
                className="w-full pl-10 pr-3 py-2 text-left text-sm text-blue-600 hover:bg-gray-100 rounded-lg transition-colors"
              >
                View full schedule
              </button>
            </div>
          ) : (
            <div className="space-y-0.5">
              {visibleWorkouts.map(workout => (
                <button
                  key={workout.id}
                  onClick={() => openWorkout(workout.id, workout.name)}
                  className="w-full flex items-center gap-2 pl-10 pr-3 py-2 text-left hover:bg-gray-100 rounded-lg transition-colors"
                >
                  {/* Day label */}
                  <span className="text-xs text-gray-400 w-12 flex-shrink-0">
                    {workout.scheduledDate ? getDayLabel(workout.scheduledDate) : ''}
                  </span>
                  {/* Workout name */}
                  <span className="flex-1 text-sm text-gray-700 truncate">
                    {workout.name}
                  </span>
                  {/* Status dot */}
                  <div
                    className="w-2 h-2 rounded-full flex-shrink-0"
                    style={{ backgroundColor: getStatusColor(workout.status) }}
                  />
                </button>
              ))}
              {/* View all link */}
              <button
                onClick={() => openSchedule(weekStart, weekEnd)}
                className="w-full pl-10 pr-3 py-2 text-left text-sm text-blue-600 hover:bg-gray-100 rounded-lg transition-colors"
              >
                {moreCount > 0 ? `+ ${moreCount} more...` : 'View full schedule'}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
