'use client';

import { useState } from 'react';
import { colors, statusColors } from '@/lib/colors';

interface EntityItem {
  id: string;
  name: string;
  status?: string;
  subtitle?: string;
  date?: Date;
}

interface EntityListModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  items: EntityItem[];
  onItemClick?: (item: EntityItem) => void;
  emptyMessage?: string;
}

export default function EntityListModal({
  isOpen,
  onClose,
  title,
  items,
  onItemClick,
  emptyMessage = 'No items found',
}: EntityListModalProps) {
  const [searchQuery, setSearchQuery] = useState('');

  if (!isOpen) return null;

  const filteredItems = items.filter((item) =>
    item.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const getStatusColor = (status?: string): string => {
    if (!status) return statusColors.draft;
    switch (status) {
      case 'active':
        return statusColors.active;
      case 'completed':
        return statusColors.completed;
      case 'in_progress':
        return statusColors.inProgress;
      case 'scheduled':
        return statusColors.scheduled;
      case 'skipped':
      case 'abandoned':
        return statusColors.skipped;
      default:
        return statusColors.draft;
    }
  };

  const formatDate = (date?: Date) => {
    if (!date) return '';
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    }).format(new Date(date));
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/50 transition-opacity"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="flex min-h-full items-center justify-center p-4">
        <div
          className="relative w-full max-w-lg bg-white rounded-2xl shadow-xl max-h-[80vh] flex flex-col"
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="sticky top-0 bg-white flex items-center justify-between px-6 py-4 border-b border-gray-100 rounded-t-2xl">
            <button
              onClick={onClose}
              className="p-2 -ml-2 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
            <h2 className="text-lg font-semibold text-gray-900">{title}</h2>
            <div className="w-9" />
          </div>

          {/* Search */}
          <div className="px-6 py-3 border-b border-gray-100">
            <div className="relative">
              <svg
                className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                />
              </svg>
              <input
                type="text"
                placeholder="Search..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full pl-10 pr-4 py-2 text-sm bg-gray-100 border-0 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
          </div>

          {/* List */}
          <div className="flex-1 overflow-y-auto px-4 py-2">
            {filteredItems.length === 0 ? (
              <div className="py-8 text-center text-gray-400">
                {searchQuery ? 'No matching items' : emptyMessage}
              </div>
            ) : (
              <div className="space-y-1">
                {filteredItems.map((item) => (
                  <button
                    key={item.id}
                    onClick={() => onItemClick?.(item)}
                    className="w-full flex items-center gap-3 px-3 py-3 text-left hover:bg-gray-100 rounded-xl transition-colors"
                  >
                    {/* Status dot */}
                    <div
                      className="w-2 h-2 rounded-full flex-shrink-0"
                      style={{ backgroundColor: getStatusColor(item.status) }}
                    />
                    {/* Content */}
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-gray-900 truncate">
                        {item.name}
                      </p>
                      {(item.subtitle || item.date) && (
                        <p className="text-xs text-gray-500">
                          {item.subtitle}
                          {item.subtitle && item.date && ' · '}
                          {item.date && formatDate(item.date)}
                        </p>
                      )}
                    </div>
                    {/* Chevron */}
                    <svg className="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                    </svg>
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="px-6 py-3 border-t border-gray-100 text-center">
            <span className="text-xs text-gray-400">
              {filteredItems.length} of {items.length} items
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
