'use client';

import { useState, useEffect } from 'react';
import { X, ArrowLeft, Loader2 } from 'lucide-react';
import { colors } from '@/lib/colors';
import { BreadcrumbBar, BreadcrumbItem } from './shared/BreadcrumbBar';
import { HeroSection } from './shared/HeroSection';
import { KeyValueRow } from './shared/KeyValueRow';
import { DisclosureSection } from './shared/DisclosureSection';
import { StatusListRow } from './shared/StatusListRow';
import { ActionBanner } from './shared/ActionBanner';
import { useDetailModal } from './DetailModalContext';
import { useAuth } from '@/components/AuthProvider';
import { getPlanWithPrograms } from '@/lib/firestore';
import type { PlanDetails } from '@/lib/types';

interface PlanDetailModalProps {
  planId: string;
  onBack?: () => void;
  onClose: () => void;
  breadcrumbItems: BreadcrumbItem[];
}

export function PlanDetailModal({ planId, onBack, onClose, breadcrumbItems }: PlanDetailModalProps) {
  const { openProgram, refresh } = useDetailModal();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [plan, setPlan] = useState<PlanDetails | null>(null);
  const [activating, setActivating] = useState(false);

  useEffect(() => {
    async function fetchPlan() {
      if (!user?.uid) return;

      setLoading(true);
      try {
        const data = await getPlanWithPrograms(user.uid, planId);
        setPlan(data);
      } catch (error) {
        console.error('Failed to fetch plan:', error);
      } finally {
        setLoading(false);
      }
    }

    fetchPlan();
  }, [user?.uid, planId]);

  const handleActivate = async () => {
    if (!user?.uid || !plan) return;

    setActivating(true);
    try {
      // Call the activate handler
      const token = await user.getIdToken();
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          action: 'activatePlan',
          planId: plan.id,
        }),
      });

      if (response.ok) {
        // Refresh the data
        const data = await getPlanWithPrograms(user.uid, planId);
        setPlan(data);
        refresh();
      }
    } catch (error) {
      console.error('Failed to activate plan:', error);
    } finally {
      setActivating(false);
    }
  };

  const formatDateShort = (date?: Date) => {
    if (!date) return '';
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
    }).format(date);
  };

  const getDateRange = () => {
    if (!plan?.startDate) return undefined;
    const start = formatDateShort(plan.startDate);
    const end = plan.endDate ? formatDateShort(plan.endDate) : '';
    return end ? `${start} – ${end}` : start;
  };

  const getSubtitle = () => {
    const parts: string[] = [];
    if (plan?.goal) parts.push(plan.goal);
    if (plan?.daysPerWeek) parts.push(`${plan.daysPerWeek} days/week`);
    return parts.length > 0 ? parts.join(' · ') : undefined;
  };

  const getStatusLabel = (status: string) => {
    const labels: Record<string, string> = {
      draft: 'Draft',
      active: 'Active',
      completed: 'Completed',
      abandoned: 'Abandoned',
      pending: 'Pending',
    };
    return labels[status] || status;
  };

  const getDaysAbbreviation = (days: number) => {
    // Convert number to day abbreviations like iOS: "M, T, W, F, Sa"
    const dayMap = ['Su', 'M', 'T', 'W', 'Th', 'F', 'Sa'];
    // For now, just show the count - could enhance later with actual scheduled days
    return `${days} days/week`;
  };

  const formatProgramPhase = (program: { phase?: string; weekNumber: number }) => {
    if (program.phase) return `Phase: ${program.phase}`;
    return `Week ${program.weekNumber}`;
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
          Plan Details
        </h2>
        <div className="w-9" />
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 animate-spin" style={{ color: colors.accentBlue }} />
          </div>
        ) : !plan ? (
          <div className="flex items-center justify-center py-12">
            <p className="text-sm" style={{ color: colors.tertiaryText }}>
              Plan not found
            </p>
          </div>
        ) : (
          <>
            <BreadcrumbBar items={breadcrumbItems} />
            <HeroSection
              title={plan.name}
              dateRange={getDateRange()}
              subtitle={getSubtitle()}
              status={plan.status}
            />

            {plan.status === 'draft' && (
              <ActionBanner
                message="This plan is ready to activate"
                actionLabel="Activate"
                onAction={handleActivate}
                isLoading={activating}
              />
            )}

            <DisclosureSection title="Plan Details">
              <div className="space-y-0">
                {plan.trainingLocation && <KeyValueRow label="Location" value={plan.trainingLocation} />}
                {plan.splitType && <KeyValueRow label="Split Type" value={plan.splitType} />}
                {plan.daysPerWeek && <KeyValueRow label="Days" value={getDaysAbbreviation(plan.daysPerWeek)} />}
                {plan.emphasizedMuscleGroups && plan.emphasizedMuscleGroups.length > 0 && (
                  <KeyValueRow label="Focus Areas" value={plan.emphasizedMuscleGroups.join(', ')} />
                )}
              </div>
            </DisclosureSection>

            <DisclosureSection title={`Programs in this Plan`} count={plan.programs.length}>
              {plan.programs.length > 0 ? (
                <div className="space-y-2">
                  {plan.programs.map((program, index) => (
                    <StatusListRow
                      key={program.id}
                      number={index + 1}
                      title={program.name}
                      subtitle={formatProgramPhase(program)}
                      metadata={`${program.workoutIds?.length || 0} workouts`}
                      status={program.status}
                      statusText={getStatusLabel(program.status)}
                      onClick={() => openProgram(program.id, program.name, planId, plan.name)}
                    />
                  ))}
                </div>
              ) : (
                <p className="text-sm py-4 text-center" style={{ color: colors.tertiaryText }}>
                  No programs yet
                </p>
              )}
            </DisclosureSection>
          </>
        )}
      </div>
    </div>
  );
}
