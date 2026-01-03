'use client';

import { useState, useEffect, useRef } from 'react';
import { X, ArrowLeft, Loader2, User } from 'lucide-react';
import { colors } from '@/lib/colors';
import { BreadcrumbBar, BreadcrumbItem } from './shared/BreadcrumbBar';
import { useAuth } from '@/components/AuthProvider';
import { getThreadWithMessages, getUserDisplayName } from '@/lib/firestore';
import type { Thread, ThreadMessage } from '@/lib/types';

interface ThreadDetailModalProps {
  threadId: string;
  onBack?: () => void;
  onClose: () => void;
  breadcrumbItems: BreadcrumbItem[];
}

/**
 * v269: Thread detail view for Messages parity
 * Shows thread subject, participants, and message history
 */
export function ThreadDetailModal({ threadId, onBack, onClose, breadcrumbItems }: ThreadDetailModalProps) {
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [thread, setThread] = useState<Thread | null>(null);
  const [messages, setMessages] = useState<ThreadMessage[]>([]);
  const [participantNames, setParticipantNames] = useState<Record<string, string>>({});
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    async function fetchThread() {
      if (!user?.uid) return;

      setLoading(true);
      try {
        const data = await getThreadWithMessages(user.uid, threadId);
        if (data) {
          setThread(data.thread);
          setMessages(data.messages);

          // Fetch participant names
          const names: Record<string, string> = {};
          for (const participantId of data.thread.participantIds) {
            if (participantId !== user.uid) {
              names[participantId] = await getUserDisplayName(participantId);
            } else {
              names[participantId] = 'You';
            }
          }
          setParticipantNames(names);
        }
      } catch (error) {
        console.error('Failed to fetch thread:', error);
      } finally {
        setLoading(false);
      }
    }

    fetchThread();
  }, [threadId, user?.uid]);

  // Scroll to bottom when messages load
  useEffect(() => {
    if (messages.length > 0) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages]);

  const formatTime = (date: Date) => {
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffDays === 0) {
      return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    } else if (diffDays === 1) {
      return 'Yesterday ' + date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    } else if (diffDays < 7) {
      return date.toLocaleDateString('en-US', { weekday: 'short' }) + ' ' +
        date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    } else {
      return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' ' +
        date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    }
  };

  const isCurrentUser = (senderId: string) => senderId === user?.uid;

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div
        className="sticky top-0 flex items-center justify-between px-4 py-3 border-b z-10"
        style={{ backgroundColor: colors.bgPrimary, borderColor: colors.borderSubtle }}
      >
        <button
          onClick={onBack || onClose}
          className="p-2 -ml-2 hover:bg-gray-100 rounded-lg transition-colors"
        >
          {onBack ? (
            <ArrowLeft className="w-5 h-5" style={{ color: colors.secondaryText }} />
          ) : (
            <X className="w-5 h-5" style={{ color: colors.secondaryText }} />
          )}
        </button>
        <h2
          className="text-base font-semibold truncate max-w-[200px]"
          style={{ color: colors.primaryText }}
        >
          {thread?.subject || 'Message'}
        </h2>
        <div className="w-9" /> {/* Spacer for alignment */}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 animate-spin" style={{ color: colors.accentBlue }} />
          </div>
        ) : !thread ? (
          <div className="flex items-center justify-center py-12">
            <p className="text-sm" style={{ color: colors.tertiaryText }}>
              Thread not found
            </p>
          </div>
        ) : (
          <>
            <BreadcrumbBar items={breadcrumbItems} />

            {/* Thread Header */}
            <div className="px-4 py-4 border-b" style={{ borderColor: colors.borderSubtle }}>
              <h1
                className="text-lg font-semibold"
                style={{ color: colors.primaryText }}
              >
                {thread.subject}
              </h1>
              <div className="flex items-center gap-2 mt-2">
                <span className="text-sm" style={{ color: colors.secondaryText }}>
                  Conversation with
                </span>
                {thread.participantIds
                  .filter(id => id !== user?.uid)
                  .map(id => (
                    <span
                      key={id}
                      className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium"
                      style={{ backgroundColor: colors.bgSecondary, color: colors.primaryText }}
                    >
                      <User className="w-3 h-3" />
                      {participantNames[id] || 'Unknown'}
                    </span>
                  ))
                }
              </div>
            </div>

            {/* Messages */}
            <div className="px-4 py-4 space-y-4">
              {messages.length === 0 ? (
                <p className="text-center text-sm py-8" style={{ color: colors.tertiaryText }}>
                  No messages in this thread
                </p>
              ) : (
                messages.map(message => (
                  <div
                    key={message.id}
                    className={`flex ${isCurrentUser(message.senderId) ? 'justify-end' : 'justify-start'}`}
                  >
                    <div
                      className={`max-w-[80%] rounded-2xl px-4 py-2 ${
                        isCurrentUser(message.senderId)
                          ? 'rounded-br-md'
                          : 'rounded-bl-md'
                      }`}
                      style={{
                        backgroundColor: isCurrentUser(message.senderId)
                          ? colors.accentBlue
                          : colors.bgSecondary,
                        color: isCurrentUser(message.senderId)
                          ? '#FFFFFF'
                          : colors.primaryText,
                      }}
                    >
                      {/* Sender name (for other participant) */}
                      {!isCurrentUser(message.senderId) && (
                        <p className="text-xs font-medium mb-1" style={{ color: colors.accentBlue }}>
                          {participantNames[message.senderId] || 'Unknown'}
                        </p>
                      )}
                      {/* Message content */}
                      <p className="text-sm whitespace-pre-wrap">
                        {message.content}
                      </p>
                      {/* Timestamp */}
                      <p
                        className="text-xs mt-1 text-right"
                        style={{
                          color: isCurrentUser(message.senderId)
                            ? 'rgba(255,255,255,0.7)'
                            : colors.tertiaryText,
                        }}
                      >
                        {formatTime(message.createdAt)}
                      </p>
                    </div>
                  </div>
                ))
              )}
              <div ref={messagesEndRef} />
            </div>

            {/* Reply composer placeholder - Phase 2 */}
            <div
              className="sticky bottom-0 px-4 py-3 border-t"
              style={{ backgroundColor: colors.bgPrimary, borderColor: colors.borderSubtle }}
            >
              <p className="text-center text-xs" style={{ color: colors.tertiaryText }}>
                Reply via chat: &quot;Send a message to my trainer&quot;
              </p>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
