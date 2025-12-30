'use client';

import { useState } from 'react';
import type { Plan } from '@/lib/types';
import { statusColors } from '@/lib/colors';
import { useDetailModal } from '@/components/detail-views';

interface PlansFolderProps {
  plans: Plan[];
}

// v227: Smart 3-plan limit matching iOS SidebarContext logic
// Priority: 1. Active plan, 2. Draft/future plan, 3. Recent completed, then fill to 3
function getSidebarPlans(plans: Plan[]): { visible: Plan[]; moreCount: number } {
  const result: Plan[] = [];
  const usedIds = new Set<string>();

  // 1. Active plan first (most important)
  const active = plans.find(p => p.status === 'active');
  if (active) {
    result.push(active);
    usedIds.add(active.id);
  }

  // 2. Draft or future-dated plan
  const draftOrFuture = plans.find(p =>
    !usedIds.has(p.id) && (
      p.status === 'draft' ||
      (p.startDate && new Date(p.startDate) > new Date())
    )
  );
  if (draftOrFuture) {
    result.push(draftOrFuture);
    usedIds.add(draftOrFuture.id);
  }

  // 3. Most recent completed
  const completed = plans.find(p => !usedIds.has(p.id) && p.status === 'completed');
  if (completed) {
    result.push(completed);
    usedIds.add(completed.id);
  }

  // Fill remaining slots up to 3
  for (const plan of plans) {
    if (result.length >= 3) break;
    if (!usedIds.has(plan.id)) {
      result.push(plan);
      usedIds.add(plan.id);
    }
  }

  return { visible: result, moreCount: plans.length - result.length };
}

export default function PlansFolder({ plans }: PlansFolderProps) {
  const [isOpen, setIsOpen] = useState(true);
  const [showAll, setShowAll] = useState(false);
  const { openPlan } = useDetailModal();

  // v227: Apply smart 3-plan limit
  const { visible: sidebarPlans, moreCount } = getSidebarPlans(plans);

  // Sort all plans for "show all" view: active first, then by name
  const allPlansSorted = [...plans].sort((a, b) => {
    if (a.status === 'active' && b.status !== 'active') return -1;
    if (a.status !== 'active' && b.status === 'active') return 1;
    return a.name.localeCompare(b.name);
  });

  // Display either smart 3 or all plans
  const displayPlans = showAll ? allPlansSorted : sidebarPlans;

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return statusColors.active;
      case 'completed':
        return statusColors.completed;
      case 'abandoned':
        return statusColors.abandoned;
      default:
        return statusColors.draft;
    }
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
        {/* Folder icon */}
        <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
        </svg>
        <span className="flex-1 text-left text-sm font-medium">Plans</span>
        {plans.length > 0 && (
          <span className="text-xs text-gray-400">{plans.length}</span>
        )}
      </button>

      {isOpen && (
        <div className="mt-0.5">
          {plans.length === 0 ? (
            <div className="pl-10 py-2 text-sm text-gray-400">
              No plans yet
            </div>
          ) : (
            <div className="space-y-0.5">
              {displayPlans.map(plan => (
                <PlanItem
                  key={plan.id}
                  plan={plan}
                  onOpenDetail={() => openPlan(plan.id, plan.name)}
                  statusColor={getStatusColor(plan.status)}
                />
              ))}
              {/* v227: Show "+ N more plans..." if there are hidden plans */}
              {!showAll && moreCount > 0 && (
                <button
                  onClick={() => setShowAll(true)}
                  className="w-full pl-10 pr-3 py-2 text-left text-sm text-blue-600 hover:bg-gray-100 rounded-lg transition-colors"
                >
                  + {moreCount} more {moreCount === 1 ? 'plan' : 'plans'}...
                </button>
              )}
              {/* Show "Show less" when expanded */}
              {showAll && moreCount > 0 && (
                <button
                  onClick={() => setShowAll(false)}
                  className="w-full pl-10 pr-3 py-2 text-left text-sm text-gray-500 hover:bg-gray-100 rounded-lg transition-colors"
                >
                  Show less
                </button>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

interface PlanItemProps {
  plan: Plan;
  onOpenDetail: () => void;
  statusColor: string;
}

function PlanItem({ plan, onOpenDetail, statusColor }: PlanItemProps) {
  return (
    <button
      onClick={onOpenDetail}
      className="w-full flex items-center gap-2 pl-10 pr-3 py-2 text-left hover:bg-gray-100 rounded-lg transition-colors"
    >
      {/* Plan name - truncated */}
      <span className="flex-1 text-sm text-gray-700 truncate">
        {plan.name}
      </span>
      {/* Status dot on RIGHT - iOS style */}
      <div
        className="w-2 h-2 rounded-full flex-shrink-0"
        style={{ backgroundColor: statusColor }}
      />
    </button>
  );
}
