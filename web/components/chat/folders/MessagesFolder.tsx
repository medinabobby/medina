'use client';

import { useState, useEffect } from 'react';
import { MessageSquare } from 'lucide-react';
import { useAuth } from '@/components/AuthProvider';
import { getThreads } from '@/lib/firestore';
import { useDetailModal } from '@/components/detail-views';
import type { Thread } from '@/lib/types';

interface MessagesFolderProps {
  refreshKey?: number;
}

/**
 * v269: Messages folder in sidebar
 * Shows recent message threads with trainer/members
 */
export default function MessagesFolder({ refreshKey = 0 }: MessagesFolderProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [threads, setThreads] = useState<Thread[]>([]);
  const [loading, setLoading] = useState(true);
  const { user } = useAuth();
  const { openThread } = useDetailModal();

  // Fetch threads
  useEffect(() => {
    async function loadThreads() {
      if (!user?.uid) return;

      setLoading(true);
      try {
        const data = await getThreads(user.uid);
        setThreads(data);
      } catch (error) {
        console.error('[MessagesFolder] Error loading threads:', error);
      } finally {
        setLoading(false);
      }
    }

    loadThreads();
  }, [user?.uid, refreshKey]);

  // Show max 3 threads in sidebar
  const visibleThreads = threads.slice(0, 3);
  const moreCount = threads.length - 3;

  // Calculate total unread count
  const totalUnread = threads.reduce((sum, t) => sum + (t.unreadCount || 0), 0);

  // Format relative time
  const getTimeAgo = (date: Date): string => {
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffMins < 1) return 'now';
    if (diffMins < 60) return `${diffMins}m`;
    if (diffHours < 24) return `${diffHours}h`;
    if (diffDays < 7) return `${diffDays}d`;
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  };

  return (
    <div>
      {/* Folder header */}
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
        {/* Message icon */}
        <MessageSquare className="w-5 h-5 text-gray-500" />
        <span className="flex-1 text-left text-sm font-medium">Messages</span>
        {totalUnread > 0 && (
          <span className="px-1.5 py-0.5 text-xs bg-blue-500 text-white rounded-full">
            {totalUnread}
          </span>
        )}
      </button>

      {isOpen && (
        <div className="mt-0.5">
          {loading ? (
            <div className="pl-10 py-2">
              <div className="animate-pulse h-4 w-24 bg-gray-200 rounded" />
            </div>
          ) : threads.length === 0 ? (
            <div className="pl-10 py-2 text-sm text-gray-400">
              No messages yet
            </div>
          ) : (
            <div className="space-y-0.5">
              {visibleThreads.map(thread => (
                <button
                  key={thread.id}
                  onClick={() => openThread(thread.id, thread.subject)}
                  className="w-full flex items-center gap-2 pl-10 pr-3 py-2 text-left hover:bg-gray-100 rounded-lg transition-colors"
                >
                  {/* Subject */}
                  <span className={`flex-1 text-sm truncate ${thread.unreadCount ? 'font-medium text-gray-900' : 'text-gray-700'}`}>
                    {thread.subject}
                  </span>
                  {/* Time ago */}
                  <span className="text-xs text-gray-400 flex-shrink-0">
                    {getTimeAgo(thread.lastMessageAt)}
                  </span>
                  {/* Unread indicator */}
                  {thread.unreadCount ? (
                    <div className="w-2 h-2 rounded-full bg-blue-500 flex-shrink-0" />
                  ) : null}
                </button>
              ))}
              {/* View all link */}
              {moreCount > 0 && (
                <button
                  onClick={() => {
                    // TODO: Open all messages modal
                    if (threads[0]) {
                      openThread(threads[0].id, threads[0].subject);
                    }
                  }}
                  className="w-full pl-10 pr-3 py-2 text-left text-sm text-blue-600 hover:bg-gray-100 rounded-lg transition-colors"
                >
                  + {moreCount} more...
                </button>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
