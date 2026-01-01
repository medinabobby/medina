'use client';

import { useState, useEffect, useMemo } from 'react';
import { X, ArrowLeft, Loader2, ChevronLeft, ChevronRight } from 'lucide-react';
import { colors, statusColors } from '@/lib/colors';
import { BreadcrumbBar, BreadcrumbItem } from './shared/BreadcrumbBar';
import { HeroSection } from './shared/HeroSection';
import { useDetailModal } from './DetailModalContext';
import { useAuth } from '@/components/AuthProvider';
import { getScheduleWorkouts } from '@/lib/firestore';
import type { Workout } from '@/lib/types';

interface ScheduleDetailModalProps {
  weekStart?: string;
  weekEnd?: string;
  onBack?: () => void;
  onClose: () => void;
  breadcrumbItems: BreadcrumbItem[];
}

interface DayData {
  date: Date;
  dateStr: string;
  dayName: string;
  dayShort: string;
  isToday: boolean;
  workouts: Workout[];
}

/**
 * v248: Schedule Detail Modal
 * Shows week calendar with workouts, clickable to navigate
 */
export function ScheduleDetailModal({
  weekStart,
  weekEnd,
  onBack,
  onClose,
  breadcrumbItems
}: ScheduleDetailModalProps) {
  const { openWorkout } = useDetailModal();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [workouts, setWorkouts] = useState<Workout[]>([]);
  const [currentWeekStart, setCurrentWeekStart] = useState<Date>(() => {
    if (weekStart) return new Date(weekStart);
    // Default to Monday of current week
    const now = new Date();
    const dayOfWeek = now.getDay();
    const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const monday = new Date(now);
    monday.setDate(now.getDate() - daysToMonday);
    monday.setHours(0, 0, 0, 0);
    return monday;
  });

  // Generate days of the week
  const weekDays = useMemo((): DayData[] => {
    const days: DayData[] = [];
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    for (let i = 0; i < 7; i++) {
      const date = new Date(currentWeekStart);
      date.setDate(currentWeekStart.getDate() + i);
      date.setHours(0, 0, 0, 0);

      const dateStr = date.toISOString().split('T')[0];
      const dayWorkouts = workouts.filter(w => {
        if (!w.scheduledDate) return false;
        const wDate = new Date(w.scheduledDate);
        return wDate.toISOString().split('T')[0] === dateStr;
      });

      days.push({
        date,
        dateStr,
        dayName: date.toLocaleDateString('en-US', { weekday: 'long' }),
        dayShort: date.toLocaleDateString('en-US', { weekday: 'short' }),
        isToday: date.getTime() === today.getTime(),
        workouts: dayWorkouts,
      });
    }
    return days;
  }, [currentWeekStart, workouts]);

  // Calculate week end for display
  const weekEndDate = useMemo(() => {
    const end = new Date(currentWeekStart);
    end.setDate(currentWeekStart.getDate() + 6);
    return end;
  }, [currentWeekStart]);

  // Format date range for hero
  const dateRangeStr = useMemo(() => {
    const startMonth = currentWeekStart.toLocaleDateString('en-US', { month: 'short' });
    const startDay = currentWeekStart.getDate();
    const endMonth = weekEndDate.toLocaleDateString('en-US', { month: 'short' });
    const endDay = weekEndDate.getDate();

    if (startMonth === endMonth) {
      return `${startMonth} ${startDay} - ${endDay}`;
    }
    return `${startMonth} ${startDay} - ${endMonth} ${endDay}`;
  }, [currentWeekStart, weekEndDate]);

  // Fetch workouts for the week
  useEffect(() => {
    async function fetchWorkouts() {
      if (!user?.uid) return;

      setLoading(true);
      try {
        const startStr = currentWeekStart.toISOString().split('T')[0];
        const endStr = weekEndDate.toISOString().split('T')[0];
        const data = await getScheduleWorkouts(user.uid, startStr, endStr);
        setWorkouts(data);
      } catch (error) {
        console.error('Failed to fetch schedule:', error);
      } finally {
        setLoading(false);
      }
    }

    fetchWorkouts();
  }, [user?.uid, currentWeekStart, weekEndDate]);

  const goToPreviousWeek = () => {
    const prev = new Date(currentWeekStart);
    prev.setDate(prev.getDate() - 7);
    setCurrentWeekStart(prev);
  };

  const goToNextWeek = () => {
    const next = new Date(currentWeekStart);
    next.setDate(next.getDate() + 7);
    setCurrentWeekStart(next);
  };

  const goToThisWeek = () => {
    const now = new Date();
    const dayOfWeek = now.getDay();
    const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const monday = new Date(now);
    monday.setDate(now.getDate() - daysToMonday);
    monday.setHours(0, 0, 0, 0);
    setCurrentWeekStart(monday);
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed': return colors.success;
      case 'in_progress': return colors.accentBlue;
      case 'skipped': return colors.warning;
      default: return colors.tertiaryText;
    }
  };

  const totalWorkouts = workouts.length;
  const completedWorkouts = workouts.filter(w => w.status === 'completed').length;
  const upcomingWorkouts = workouts.filter(w => w.status === 'scheduled').length;

  // Check if we're viewing current week
  const isCurrentWeek = useMemo(() => {
    const now = new Date();
    const dayOfWeek = now.getDay();
    const daysToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const monday = new Date(now);
    monday.setDate(now.getDate() - daysToMonday);
    monday.setHours(0, 0, 0, 0);
    return currentWeekStart.getTime() === monday.getTime();
  }, [currentWeekStart]);

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
          Schedule
        </h2>
        <div className="w-9" />
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        <BreadcrumbBar items={breadcrumbItems} />

        {/* Week navigation */}
        <div className="px-4 py-3 flex items-center justify-between">
          <button
            onClick={goToPreviousWeek}
            className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
          >
            <ChevronLeft className="w-5 h-5" style={{ color: colors.secondaryText }} />
          </button>

          <div className="flex flex-col items-center">
            <span className="text-base font-semibold" style={{ color: colors.primaryText }}>
              {dateRangeStr}
            </span>
            {!isCurrentWeek && (
              <button
                onClick={goToThisWeek}
                className="text-xs mt-0.5"
                style={{ color: colors.accentBlue }}
              >
                Go to this week
              </button>
            )}
          </div>

          <button
            onClick={goToNextWeek}
            className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
          >
            <ChevronRight className="w-5 h-5" style={{ color: colors.secondaryText }} />
          </button>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 animate-spin" style={{ color: colors.accentBlue }} />
          </div>
        ) : (
          <>
            {/* Week summary */}
            <div className="px-4 pb-3">
              <p className="text-sm" style={{ color: colors.secondaryText }}>
                {totalWorkouts === 0 ? (
                  'No workouts scheduled'
                ) : (
                  <>
                    {upcomingWorkouts > 0 && `${upcomingWorkouts} upcoming`}
                    {upcomingWorkouts > 0 && completedWorkouts > 0 && ', '}
                    {completedWorkouts > 0 && `${completedWorkouts} completed`}
                  </>
                )}
              </p>
            </div>

            {/* Week calendar grid */}
            <div
              className="mx-4 mb-4 rounded-xl overflow-hidden border"
              style={{ borderColor: colors.borderSubtle }}
            >
              <div className="grid grid-cols-7">
                {weekDays.map((day) => (
                  <div
                    key={day.dateStr}
                    className="flex flex-col items-center py-2 border-r last:border-r-0"
                    style={{
                      borderColor: colors.borderSubtle,
                      backgroundColor: day.isToday ? colors.accentSubtle : colors.bgPrimary,
                    }}
                  >
                    <span
                      className="text-xs font-medium"
                      style={{ color: day.isToday ? colors.accentBlue : colors.secondaryText }}
                    >
                      {day.dayShort}
                    </span>
                    <span
                      className={`text-sm font-semibold mt-0.5 ${day.isToday ? 'w-6 h-6 rounded-full flex items-center justify-center' : ''}`}
                      style={{
                        color: day.isToday ? colors.bgPrimary : colors.primaryText,
                        backgroundColor: day.isToday ? colors.accentBlue : 'transparent',
                      }}
                    >
                      {day.date.getDate()}
                    </span>
                    {/* Workout dots */}
                    <div className="flex gap-1 mt-1 h-2">
                      {day.workouts.slice(0, 3).map((w, i) => (
                        <div
                          key={i}
                          className="w-1.5 h-1.5 rounded-full"
                          style={{ backgroundColor: getStatusColor(w.status) }}
                        />
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>

            {/* Day sections */}
            <div className="px-4 space-y-3 pb-6">
              {weekDays.map((day) => (
                <div
                  key={day.dateStr}
                  className="rounded-xl overflow-hidden"
                  style={{ backgroundColor: colors.bgSecondary }}
                >
                  {/* Day header */}
                  <div
                    className="px-3 py-2 flex items-center justify-between"
                    style={{ backgroundColor: day.isToday ? colors.accentSubtle : colors.bgSecondary }}
                  >
                    <span
                      className="text-sm font-medium"
                      style={{ color: day.isToday ? colors.accentBlue : colors.primaryText }}
                    >
                      {day.dayName}
                      {day.isToday && <span className="ml-1 text-xs">(Today)</span>}
                    </span>
                    <span
                      className="text-xs"
                      style={{ color: colors.tertiaryText }}
                    >
                      {day.date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                    </span>
                  </div>

                  {/* Workouts for this day */}
                  {day.workouts.length === 0 ? (
                    <div className="px-3 py-3">
                      <span className="text-sm" style={{ color: colors.tertiaryText }}>
                        Rest day
                      </span>
                    </div>
                  ) : (
                    <div className="divide-y" style={{ borderColor: colors.borderSubtle }}>
                      {day.workouts.map((workout) => (
                        <button
                          key={workout.id}
                          onClick={() => openWorkout(workout.id, workout.name)}
                          className="w-full px-3 py-3 flex items-center gap-3 hover:bg-white/50 transition-colors text-left"
                        >
                          {/* Status indicator */}
                          <div
                            className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                            style={{ backgroundColor: getStatusColor(workout.status) }}
                          />
                          {/* Workout info */}
                          <div className="flex-1 min-w-0">
                            <p
                              className="text-sm font-medium truncate"
                              style={{ color: colors.primaryText }}
                            >
                              {workout.name}
                            </p>
                            <p
                              className="text-xs truncate"
                              style={{ color: colors.secondaryText }}
                            >
                              {workout.splitDay?.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase()) || 'Workout'}
                              {workout.estimatedDuration && ` · ${workout.estimatedDuration} min`}
                            </p>
                          </div>
                          {/* Chevron */}
                          <ChevronRight
                            className="w-4 h-4 flex-shrink-0"
                            style={{ color: colors.tertiaryText }}
                          />
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
