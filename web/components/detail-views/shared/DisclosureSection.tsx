'use client';

import { useState } from 'react';
import { ChevronDown, ChevronUp } from 'lucide-react';
import { colors } from '@/lib/colors';

interface DisclosureSectionProps {
  title: string;
  count?: number;
  defaultOpen?: boolean;
  children: React.ReactNode;
}

export function DisclosureSection({
  title,
  count,
  defaultOpen = true,
  children,
}: DisclosureSectionProps) {
  const [isOpen, setIsOpen] = useState(defaultOpen);

  return (
    <div className="border-t" style={{ borderColor: colors.borderSubtle }}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center justify-between px-4 py-3 hover:bg-gray-50 transition-colors"
      >
        <span
          className="text-sm font-medium"
          style={{ color: colors.primaryText }}
        >
          {title}
          {count !== undefined && (
            <span
              className="ml-1.5"
              style={{ color: colors.tertiaryText }}
            >
              ({count})
            </span>
          )}
        </span>
        {isOpen ? (
          <ChevronUp
            className="h-4 w-4"
            style={{ color: colors.tertiaryText }}
          />
        ) : (
          <ChevronDown
            className="h-4 w-4"
            style={{ color: colors.tertiaryText }}
          />
        )}
      </button>

      {isOpen && (
        <div className="px-4 pb-3">
          {children}
        </div>
      )}
    </div>
  );
}
