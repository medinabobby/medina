'use client';

import { useState } from 'react';
import type { Plan } from '@/lib/types';
import { statusColors } from '@/lib/colors';
import { useDetailModal } from '@/components/detail-views';

interface PlansFolderProps {
  plans: Plan[];
}

export default function PlansFolder({ plans }: PlansFolderProps) {
  const [isOpen, setIsOpen] = useState(true);
  const { openPlan } = useDetailModal();

  // Sort: active first, then by name
  const sortedPlans = [...plans].sort((a, b) => {
    if (a.status === 'active' && b.status !== 'active') return -1;
    if (a.status !== 'active' && b.status === 'active') return 1;
    return a.name.localeCompare(b.name);
  });

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
              {sortedPlans.map(plan => (
                <PlanItem
                  key={plan.id}
                  plan={plan}
                  onOpenDetail={() => openPlan(plan.id, plan.name)}
                  statusColor={getStatusColor(plan.status)}
                />
              ))}
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
