'use client';

import { useState } from 'react';
import type { Plan } from '@/lib/types';
import { statusColors } from '@/lib/colors';

interface PlansFolderProps {
  plans: Plan[];
}

export default function PlansFolder({ plans }: PlansFolderProps) {
  const [isOpen, setIsOpen] = useState(true);
  const [expandedPlanId, setExpandedPlanId] = useState<string | null>(null);

  const activePlans = plans.filter(p => p.status === 'active');
  const otherPlans = plans.filter(p => p.status !== 'active');

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

  const formatDate = (date?: Date) => {
    if (!date) return '';
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
    }).format(date);
  };

  return (
    <div>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center gap-2 px-3 py-2 text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
      >
        <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
        </svg>
        <span className="flex-1 text-left text-sm font-medium">Plans</span>
        {plans.length > 0 && (
          <span className="text-xs text-gray-400">{plans.length}</span>
        )}
        <svg
          className={`w-4 h-4 text-gray-400 transition-transform ${isOpen ? 'rotate-90' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
        </svg>
      </button>

      {isOpen && (
        <div className="mt-1 pl-2">
          {plans.length === 0 ? (
            <div className="pl-5 py-2 text-sm text-gray-400">
              No plans yet
            </div>
          ) : (
            <div className="space-y-0.5">
              {/* Active plans first */}
              {activePlans.map(plan => (
                <PlanItem
                  key={plan.id}
                  plan={plan}
                  isExpanded={expandedPlanId === plan.id}
                  onToggle={() => setExpandedPlanId(expandedPlanId === plan.id ? null : plan.id)}
                  statusColor={getStatusColor(plan.status)}
                  formatDate={formatDate}
                />
              ))}

              {/* Other plans */}
              {otherPlans.map(plan => (
                <PlanItem
                  key={plan.id}
                  plan={plan}
                  isExpanded={expandedPlanId === plan.id}
                  onToggle={() => setExpandedPlanId(expandedPlanId === plan.id ? null : plan.id)}
                  statusColor={getStatusColor(plan.status)}
                  formatDate={formatDate}
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
  isExpanded: boolean;
  onToggle: () => void;
  statusColor: string;
  formatDate: (date?: Date) => string;
}

function PlanItem({ plan, isExpanded, onToggle, statusColor, formatDate }: PlanItemProps) {
  return (
    <div>
      <button
        onClick={onToggle}
        className="w-full flex items-center gap-2 px-3 py-2 text-left hover:bg-gray-100 rounded-lg transition-colors group"
      >
        <div
          className="w-1.5 h-1.5 rounded-full flex-shrink-0"
          style={{ backgroundColor: statusColor }}
        />
        <span className="flex-1 text-sm text-gray-700 truncate">{plan.name}</span>
        {plan.startDate && (
          <span className="text-xs text-gray-400 opacity-0 group-hover:opacity-100 transition-opacity">
            {formatDate(plan.startDate)}
          </span>
        )}
        <svg
          className={`w-3 h-3 text-gray-400 transition-transform ${isExpanded ? 'rotate-90' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
        </svg>
      </button>

      {isExpanded && (
        <div className="pl-6 mt-0.5 space-y-0.5">
          {plan.programIds && plan.programIds.length > 0 ? (
            plan.programIds.map((programId, index) => (
              <button
                key={programId}
                className="w-full flex items-center gap-2 px-3 py-1.5 text-left hover:bg-gray-100 rounded-lg transition-colors"
              >
                <div className="w-1 h-1 rounded-full bg-gray-300 flex-shrink-0" />
                <span className="text-sm text-gray-600">Week {index + 1}</span>
              </button>
            ))
          ) : (
            <div className="px-3 py-1.5 text-xs text-gray-400">
              No programs
            </div>
          )}
        </div>
      )}
    </div>
  );
}
