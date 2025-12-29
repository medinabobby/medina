'use client';

import { colors } from '@/lib/colors';

interface KeyValueRowProps {
  label: string;
  value: string | React.ReactNode;
  valueColor?: string;
  valueWeight?: 'normal' | 'medium' | 'semibold';
}

export function KeyValueRow({
  label,
  value,
  valueColor,
  valueWeight = 'normal',
}: KeyValueRowProps) {
  const fontWeightClass = {
    normal: 'font-normal',
    medium: 'font-medium',
    semibold: 'font-semibold',
  }[valueWeight];

  return (
    <div className="flex justify-between items-center py-2 px-4">
      <span
        className="text-sm"
        style={{ color: colors.secondaryText }}
      >
        {label}
      </span>
      <span
        className={`text-sm ${fontWeightClass}`}
        style={{ color: valueColor || colors.primaryText }}
      >
        {value}
      </span>
    </div>
  );
}
