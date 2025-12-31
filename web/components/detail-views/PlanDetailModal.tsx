'use client';

import { useState, useEffect, useRef } from 'react';
import { X, ArrowLeft, Loader2, MoreHorizontal, Trash2, XCircle } from 'lucide-react';
import { colors } from '@/lib/colors';
import { BreadcrumbBar, BreadcrumbItem } from './shared/BreadcrumbBar';
import { HeroSection } from './shared/HeroSection';
import { KeyValueRow } from './shared/KeyValueRow';
import { DisclosureSection } from './shared/DisclosureSection';
import { StatusListRow } from './shared/StatusListRow';
import { ActionBanner } from './shared/ActionBanner';
import { useDetailModal } from './DetailModalContext';
import { useAuth } from '@/components/AuthProvider';
import { useChatLayout } from '@/components/chat/ChatLayout';
import { getPlanWithPrograms } from '@/lib/firestore';
import type { PlanDetails } from '@/lib/types';

interface PlanDetailModalProps {
  planId: string;
  onBack?: () => void;
  onClose: () => void;
  breadcrumbItems: BreadcrumbItem[];
}

export function PlanDetailModal({ planId, onBack, onClose, breadcrumbItems }: PlanDetailModalProps) {
  const { openProgram, refresh, close } = useDetailModal();
  const { user } = useAuth();
  const { refreshSidebar } = useChatLayout();
  const [loading, setLoading] = useState(true);
  const [plan, setPlan] = useState<PlanDetails | null>(null);
  const [activating, setActivating] = useState(false);

  // v227: Actions menu state
  const [showActionsMenu, setShowActionsMenu] = useState(false);
  const [showConfirmDialog, setShowConfirmDialog] = useState<'abandon' | 'delete' | null>(null);
  const [actionLoading, setActionLoading] = useState(false);
  const actionsMenuRef = useRef<HTMLDivElement>(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (actionsMenuRef.current && !actionsMenuRef.current.contains(event.target as Node)) {
        setShowActionsMenu(false);
      }
    }
    if (showActionsMenu) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [showActionsMenu]);

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

  // v227: Abandon plan handler (active → abandoned)
  const handleAbandon = async () => {
    if (!user?.uid || !plan) return;

    setActionLoading(true);
    try {
      const token = await user.getIdToken();
      const response = await fetch('https://us-central1-medinaintelligence.cloudfunctions.net/abandonPlan', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ planId: plan.id }),
      });

      if (response.ok) {
        // Refresh the data
        const data = await getPlanWithPrograms(user.uid, planId);
        setPlan(data);
        refreshSidebar();  // v237: Use sidebar refresh to update plan status
        setShowConfirmDialog(null);
      } else {
        console.error('Failed to abandon plan:', await response.text());
      }
    } catch (error) {
      console.error('Failed to abandon plan:', error);
    } finally {
      setActionLoading(false);
    }
  };

  // v227: Delete plan handler (draft/abandoned/completed → deleted)
  const handleDelete = async () => {
    if (!user?.uid || !plan) return;

    setActionLoading(true);
    try {
      const token = await user.getIdToken();
      const response = await fetch('https://us-central1-medinaintelligence.cloudfunctions.net/deletePlan', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ planId: plan.id, confirmDelete: true }),
      });

      if (response.ok) {
        // Close the detail panel after deletion
        refreshSidebar();  // v237: Use sidebar refresh to update plan list
        close();
      } else {
        console.error('Failed to delete plan:', await response.text());
      }
    } catch (error) {
      console.error('Failed to delete plan:', error);
    } finally {
      setActionLoading(false);
      setShowConfirmDialog(null);
    }
  };

  // v227: Get available actions based on plan status
  const getAvailableActions = () => {
    if (!plan) return [];
    const actions: Array<{ id: 'abandon' | 'delete'; label: string; icon: typeof Trash2; destructive: boolean }> = [];

    if (plan.status === 'active') {
      actions.push({ id: 'abandon', label: 'Abandon Plan', icon: XCircle, destructive: true });
    }
    // v236: Allow delete for completed plans (parity with iOS)
    if (plan.status === 'draft' || plan.status === 'abandoned' || plan.status === 'completed') {
      actions.push({ id: 'delete', label: 'Delete Plan', icon: Trash2, destructive: true });
    }

    return actions;
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

  // v228: Format preferred days as abbreviations (e.g., "M, T, W, F, Sa")
  const formatPreferredDays = (days: string[]) => {
    const abbrevs: Record<string, string> = {
      sunday: 'Su', monday: 'M', tuesday: 'T', wednesday: 'W',
      thursday: 'Th', friday: 'F', saturday: 'Sa'
    };
    return days.map(d => abbrevs[d.toLowerCase()] || d).join(', ');
  };

  // v228: Calculate intensity range from programs
  const getIntensityRange = () => {
    const programs = plan?.programs || [];
    const intensities = programs
      .flatMap(p => [p.startingIntensity, p.endingIntensity])
      .filter((i): i is number => typeof i === 'number');
    if (intensities.length === 0) return null;
    const min = Math.min(...intensities);
    const max = Math.max(...intensities);
    return min === max ? `${min}%` : `${min}% → ${max}%`;
  };

  // v228: Format weekly mix (e.g., "3 strength • 2 cardio")
  const getWeeklyMix = () => {
    if (!plan?.weightliftingDays && !plan?.cardioDays) return null;
    const parts: string[] = [];
    if (plan.weightliftingDays) parts.push(`${plan.weightliftingDays} strength`);
    if (plan.cardioDays) parts.push(`${plan.cardioDays} cardio`);
    return parts.join(' • ');
  };

  return (
    <div className="flex flex-col h-full">
      {/* Header - v227: Added actions menu */}
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
        {/* v227: Actions menu */}
        <div className="relative" ref={actionsMenuRef}>
          {getAvailableActions().length > 0 ? (
            <>
              <button
                onClick={() => setShowActionsMenu(!showActionsMenu)}
                className="p-2 -mr-2 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <MoreHorizontal className="w-5 h-5" style={{ color: colors.secondaryText }} />
              </button>
              {showActionsMenu && (
                <div className="absolute right-0 top-full mt-1 w-48 bg-white rounded-lg shadow-lg border border-gray-200 py-1 z-50">
                  {getAvailableActions().map((action) => (
                    <button
                      key={action.id}
                      onClick={() => {
                        setShowActionsMenu(false);
                        setShowConfirmDialog(action.id);
                      }}
                      className="w-full flex items-center gap-3 px-4 py-2 text-sm hover:bg-gray-50 transition-colors"
                      style={{ color: action.destructive ? colors.error : colors.primaryText }}
                    >
                      <action.icon className="w-4 h-4" />
                      {action.label}
                    </button>
                  ))}
                </div>
              )}
            </>
          ) : (
            <div className="w-9" />
          )}
        </div>
      </div>

      {/* v227: Confirmation dialog */}
      {showConfirmDialog && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl p-6 max-w-sm mx-4 shadow-xl">
            <h3 className="text-lg font-semibold mb-2" style={{ color: colors.primaryText }}>
              {showConfirmDialog === 'abandon' ? 'Abandon Plan?' : 'Delete Plan?'}
            </h3>
            <p className="text-sm mb-4" style={{ color: colors.secondaryText }}>
              {showConfirmDialog === 'abandon'
                ? `Are you sure you want to abandon "${plan?.name}"? This will mark all remaining workouts as skipped.`
                : `Are you sure you want to delete "${plan?.name}"? This action cannot be undone.`}
            </p>
            <div className="flex gap-3 justify-end">
              <button
                onClick={() => setShowConfirmDialog(null)}
                disabled={actionLoading}
                className="px-4 py-2 text-sm font-medium rounded-lg hover:bg-gray-100 transition-colors"
                style={{ color: colors.secondaryText }}
              >
                Cancel
              </button>
              <button
                onClick={showConfirmDialog === 'abandon' ? handleAbandon : handleDelete}
                disabled={actionLoading}
                className="px-4 py-2 text-sm font-medium text-white rounded-lg transition-colors flex items-center gap-2"
                style={{ backgroundColor: colors.error }}
              >
                {actionLoading && <Loader2 className="w-4 h-4 animate-spin" />}
                {showConfirmDialog === 'abandon' ? 'Abandon' : 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}

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
                {/* v228: Show preferred days if available, otherwise fall back to count */}
                {plan.preferredDays && plan.preferredDays.length > 0 ? (
                  <KeyValueRow label="Days" value={formatPreferredDays(plan.preferredDays)} />
                ) : plan.daysPerWeek ? (
                  <KeyValueRow label="Days" value={getDaysAbbreviation(plan.daysPerWeek)} />
                ) : null}
                {/* v228: Weekly mix (strength/cardio breakdown) */}
                {getWeeklyMix() && <KeyValueRow label="Weekly Mix" value={getWeeklyMix()!} />}
                {/* v228: Intensity range from programs */}
                {getIntensityRange() && <KeyValueRow label="Intensity" value={getIntensityRange()!} />}
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
                      metadata={`${(program as any).workoutCount ?? program.workoutIds?.length ?? 0} workouts`}
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
