'use client';

import { colors } from '@/lib/colors';
import { StatusBadge } from './StatusBadge';

type StatusType = 'active' | 'completed' | 'in_progress' | 'scheduled' | 'skipped' | 'abandoned' | 'draft' | 'pending';

interface HeroSectionProps {
  title: string;
  dateRange?: string;
  subtitle?: string;
  status?: StatusType;
  stats?: Array<{ label: string; value: string }>;
}

export function HeroSection({ title, dateRange, subtitle, status, stats }: HeroSectionProps) {
  return (
    <div
      className="px-4 py-4"
      style={{ backgroundColor: colors.bgPrimary }}
    >
      {/* Title */}
      <h1
        className="text-lg font-semibold"
        style={{ color: colors.primaryText }}
      >
        {title}
      </h1>

      {/* Date range + Status badge row (iOS style) */}
      {(dateRange || status) && (
        <div className="flex items-center justify-between mt-1.5">
          {dateRange && (
            <span
              className="text-sm"
              style={{ color: colors.primaryText }}
            >
              {dateRange}
            </span>
          )}
          {status && <StatusBadge status={status} />}
        </div>
      )}

      {/* Subtitle (goal · days/week · duration) */}
      {subtitle && (
        <p
          className="text-sm mt-1"
          style={{ color: colors.secondaryText }}
        >
          {subtitle}
        </p>
      )}

      {/* Stats row if no date range provided (alternative layout) */}
      {stats && stats.length > 0 && !dateRange && (
        <div className="flex gap-6 mt-3">
          {stats.map((stat, index) => (
            <div key={index} className="flex flex-col">
              <span
                className="text-lg font-semibold"
                style={{ color: colors.primaryText }}
              >
                {stat.value}
              </span>
              <span
                className="text-xs"
                style={{ color: colors.tertiaryText }}
              >
                {stat.label}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
