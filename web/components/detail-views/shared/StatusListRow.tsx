'use client';

import { ChevronRight } from 'lucide-react';
import { colors, statusColors } from '@/lib/colors';

type StatusType = 'active' | 'completed' | 'in_progress' | 'scheduled' | 'skipped' | 'abandoned' | 'draft' | 'pending';

interface StatusListRowProps {
  number?: string | number;
  title: string;
  subtitle?: string;
  metadata?: string;
  status?: StatusType;
  statusText?: string;
  timeText?: string;
  showChevron?: boolean;
  onClick?: () => void;
}

export function StatusListRow({
  number,
  title,
  subtitle,
  metadata,
  status,
  statusText,
  timeText,
  showChevron = true,
  onClick,
}: StatusListRowProps) {
  const getStatusColor = (): string => {
    if (!status) return colors.accentBlue;
    switch (status) {
      case 'active':
        return statusColors.active;
      case 'in_progress':
        return statusColors.inProgress;
      case 'completed':
        return statusColors.completed;
      case 'scheduled':
        return statusColors.scheduled;
      case 'skipped':
      case 'abandoned':
        return statusColors.skipped;
      case 'draft':
        return statusColors.draft;
      case 'pending':
      default:
        return statusColors.pending;
    }
  };

  const statusColor = getStatusColor();

  return (
    <button
      onClick={onClick}
      disabled={!onClick}
      className="w-full flex items-stretch rounded-xl bg-white hover:bg-gray-50 transition-colors text-left overflow-hidden"
      style={{
        cursor: onClick ? 'pointer' : 'default',
      }}
    >
      {/* iOS-style vertical color bar on left */}
      <div
        className="w-1 flex-shrink-0 rounded-l-xl"
        style={{ backgroundColor: statusColor }}
      />

      {/* Content area */}
      <div className="flex items-center gap-3 flex-1 min-w-0 p-3 pl-3">
        {/* Number indicator */}
        {number !== undefined && (
          <span
            className="text-sm min-w-[20px] text-center"
            style={{ color: colors.tertiaryText }}
          >
            {number}
          </span>
        )}

        {/* Main content */}
        <div className="flex-1 min-w-0">
          {/* Title row with optional status badge */}
          <div className="flex items-center gap-2">
            <span
              className="font-medium text-sm"
              style={{ color: colors.primaryText }}
            >
              {title}
            </span>
            {statusText && (
              <span
                className="text-xs px-2 py-0.5 rounded-full border flex-shrink-0"
                style={{
                  borderColor: colors.borderStandard,
                  color: colors.secondaryText,
                }}
              >
                {statusText}
              </span>
            )}
          </div>

          {/* Subtitle/metadata row */}
          {(subtitle || metadata) && (
            <p
              className="text-xs mt-0.5 truncate"
              style={{ color: colors.secondaryText }}
            >
              {subtitle}
              {subtitle && metadata && ' · '}
              {metadata}
            </p>
          )}
        </div>

        {/* Right side: time text or chevron */}
        {timeText && (
          <span
            className="text-xs whitespace-nowrap flex-shrink-0"
            style={{ color: colors.tertiaryText }}
          >
            {timeText}
          </span>
        )}

        {showChevron && onClick && (
          <ChevronRight
            className="h-5 w-5 flex-shrink-0"
            style={{ color: colors.tertiaryText }}
          />
        )}
      </div>
    </button>
  );
}
