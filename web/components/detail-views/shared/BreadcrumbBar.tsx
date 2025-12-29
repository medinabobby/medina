'use client';

import { ChevronRight } from 'lucide-react';
import { colors } from '@/lib/colors';

export interface BreadcrumbItem {
  label: string;
  onClick?: () => void;
}

interface BreadcrumbBarProps {
  items: BreadcrumbItem[];
}

export function BreadcrumbBar({ items }: BreadcrumbBarProps) {
  if (items.length === 0) return null;

  return (
    <nav
      className="flex items-center px-4 py-2 text-sm"
      style={{ backgroundColor: colors.bgSecondary }}
    >
      {items.map((item, index) => (
        <span key={index} className="flex items-center">
          {index > 0 && (
            <ChevronRight
              className="mx-1 h-4 w-4"
              style={{ color: colors.tertiaryText }}
            />
          )}
          {item.onClick && index < items.length - 1 ? (
            <button
              onClick={item.onClick}
              className="hover:underline transition-colors"
              style={{ color: colors.accentBlue }}
            >
              {item.label}
            </button>
          ) : (
            <span
              className={index === items.length - 1 ? 'font-medium' : ''}
              style={{
                color: index === items.length - 1 ? colors.primaryText : colors.secondaryText,
              }}
            >
              {item.label}
            </span>
          )}
        </span>
      ))}
    </nav>
  );
}
