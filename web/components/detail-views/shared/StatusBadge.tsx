'use client';

import { statusColors } from '@/lib/colors';

type StatusType = 'active' | 'completed' | 'in_progress' | 'scheduled' | 'skipped' | 'abandoned' | 'draft' | 'pending';

interface StatusBadgeProps {
  status: StatusType;
  className?: string;
}

const statusLabels: Record<StatusType, string> = {
  active: 'Active',
  completed: 'Completed',
  in_progress: 'In Progress',
  scheduled: 'Scheduled',
  skipped: 'Skipped',
  abandoned: 'Abandoned',
  draft: 'Draft',
  pending: 'Pending',
};

export function StatusBadge({ status, className = '' }: StatusBadgeProps) {
  const getStatusColor = (): string => {
    switch (status) {
      case 'active':
      case 'in_progress':
        return statusColors.active;
      case 'completed':
        return statusColors.completed;
      case 'scheduled':
        return statusColors.scheduled;
      case 'skipped':
      case 'abandoned':
        return statusColors.skipped;
      case 'draft':
      case 'pending':
      default:
        return statusColors.draft;
    }
  };

  const color = getStatusColor();

  return (
    <span
      className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${className}`}
      style={{
        backgroundColor: `${color}15`,
        color: color,
      }}
    >
      {statusLabels[status] || status}
    </span>
  );
}
