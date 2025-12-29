'use client';

import { useState, useEffect } from 'react';
import { X, ArrowLeft, Loader2 } from 'lucide-react';
import { colors } from '@/lib/colors';
import { BreadcrumbBar, BreadcrumbItem } from './shared/BreadcrumbBar';
import { HeroSection } from './shared/HeroSection';
import { KeyValueRow } from './shared/KeyValueRow';
import { DisclosureSection } from './shared/DisclosureSection';
import { StatusListRow } from './shared/StatusListRow';
import { useDetailModal } from './DetailModalContext';
import { useAuth } from '@/components/AuthProvider';
import { getProgramWithWorkouts } from '@/lib/firestore';
import type { ProgramDetails } from '@/lib/types';

interface ProgramDetailModalProps {
  programId: string;
  planId: string;
  onBack?: () => void;
  onClose: () => void;
  breadcrumbItems: BreadcrumbItem[];
}

export function ProgramDetailModal({ programId, planId, onBack, onClose, breadcrumbItems }: ProgramDetailModalProps) {
  const { openWorkout } = useDetailModal();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [program, setProgram] = useState<ProgramDetails | null>(null);

  useEffect(() => {
    async function fetchProgram() {
      if (!user?.uid) return;

      setLoading(true);
      try {
        const data = await getProgramWithWorkouts(user.uid, planId, programId);
        setProgram(data);
      } catch (error) {
        console.error('Failed to fetch program:', error);
      } finally {
        setLoading(false);
      }
    }

    fetchProgram();
  }, [user?.uid, planId, programId]);

  const formatDateShort = (date?: Date) => {
    if (!date) return '';
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
    }).format(date);
  };

  const formatWorkoutDate = (date?: Date) => {
    if (!date) return undefined;
    return new Intl.DateTimeFormat('en-US', {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
    }).format(date);
  };

  const getDateRange = () => {
    if (!program?.startDate) return undefined;
    const start = formatDateShort(program.startDate);
    const end = program.endDate ? formatDateShort(program.endDate) : '';
    return end ? `${start} – ${end}` : start;
  };

  const getSubtitle = () => {
    const parts: string[] = [];
    if (program?.focus) parts.push(program.focus);
    return parts.length > 0 ? parts.join(' · ') : undefined;
  };

  const getStatusLabel = (status: string) => {
    const labels: Record<string, string> = {
      pending: 'Pending',
      active: 'Active',
      completed: 'Completed',
      draft: 'Draft',
    };
    return labels[status] || status;
  };

  const getWorkoutStatus = (workout: ProgramDetails['workouts'][0]) => {
    if (workout.status === 'completed') return 'completed';
    if (workout.status === 'in_progress') return 'in_progress';
    if (workout.status === 'skipped') return 'skipped';
    return 'scheduled';
  };

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
          Program Details
        </h2>
        <div className="w-9" />
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 animate-spin" style={{ color: colors.accentBlue }} />
          </div>
        ) : !program ? (
          <div className="flex items-center justify-center py-12">
            <p className="text-sm" style={{ color: colors.tertiaryText }}>
              Program not found
            </p>
          </div>
        ) : (
          <>
            <BreadcrumbBar items={breadcrumbItems} />
            <HeroSection
              title={program.name}
              dateRange={getDateRange()}
              subtitle={getSubtitle()}
              status={program.status}
            />

            <DisclosureSection title="Program Details">
              <div className="space-y-0">
                {program.phase && <KeyValueRow label="Phase" value={program.phase} />}
                <KeyValueRow label="Week" value={String(program.weekNumber)} />
                {program.intensity && <KeyValueRow label="Intensity" value={program.intensity} />}
                {program.progressionType && <KeyValueRow label="Progression" value={program.progressionType} />}
                {program.focus && <KeyValueRow label="Focus" value={program.focus} />}
              </div>
            </DisclosureSection>

            <DisclosureSection title="Workouts in this Program" count={program.workouts.length}>
              {program.workouts.length > 0 ? (
                <div className="space-y-2">
                  {program.workouts.map((workout, index) => (
                    <StatusListRow
                      key={workout.id}
                      number={index + 1}
                      title={formatWorkoutDate(workout.scheduledDate) || workout.name}
                      subtitle={workout.splitDay ? workout.splitDay.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase()) : undefined}
                      metadata={workout.exerciseIds?.length ? `${workout.exerciseIds.length} exercises` : undefined}
                      status={getWorkoutStatus(workout)}
                      onClick={() => openWorkout(
                        workout.id,
                        workout.name,
                        { planId, programId },
                        { planName: program.parentPlan?.name || breadcrumbItems[0]?.label, programName: program.name }
                      )}
                    />
                  ))}
                </div>
              ) : (
                <p className="text-sm py-4 text-center" style={{ color: colors.tertiaryText }}>
                  No workouts yet
                </p>
              )}
            </DisclosureSection>
          </>
        )}
      </div>
    </div>
  );
}
