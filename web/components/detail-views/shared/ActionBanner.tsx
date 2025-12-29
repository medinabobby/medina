'use client';

import { colors } from '@/lib/colors';
import { Loader2 } from 'lucide-react';

interface ActionBannerProps {
  message: string;
  actionLabel: string;
  onAction: () => void;
  isLoading?: boolean;
  variant?: 'primary' | 'success' | 'warning';
}

export function ActionBanner({
  message,
  actionLabel,
  onAction,
  isLoading = false,
  variant = 'primary',
}: ActionBannerProps) {
  const variantStyles = {
    primary: {
      bg: colors.accentBlue,
      text: '#FFFFFF',
      buttonBg: 'rgba(255, 255, 255, 0.2)',
      buttonHover: 'rgba(255, 255, 255, 0.3)',
    },
    success: {
      bg: colors.success,
      text: '#FFFFFF',
      buttonBg: 'rgba(255, 255, 255, 0.2)',
      buttonHover: 'rgba(255, 255, 255, 0.3)',
    },
    warning: {
      bg: colors.warning,
      text: '#FFFFFF',
      buttonBg: 'rgba(255, 255, 255, 0.2)',
      buttonHover: 'rgba(255, 255, 255, 0.3)',
    },
  };

  const styles = variantStyles[variant];

  return (
    <div
      className="flex items-center justify-between px-4 py-3"
      style={{ backgroundColor: styles.bg }}
    >
      <span
        className="text-sm font-medium"
        style={{ color: styles.text }}
      >
        {message}
      </span>
      <button
        onClick={onAction}
        disabled={isLoading}
        className="px-3 py-1.5 rounded-md text-sm font-medium transition-colors disabled:opacity-50"
        style={{
          backgroundColor: styles.buttonBg,
          color: styles.text,
        }}
      >
        {isLoading ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          actionLabel
        )}
      </button>
    </div>
  );
}
