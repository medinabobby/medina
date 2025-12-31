'use client';

import { useState, useEffect, createContext, useContext, ReactNode } from 'react';
import Sidebar from './Sidebar';
import { DetailModalProvider, DetailModalContainer, useDetailModal, DetailPanel } from '@/components/detail-views';
import { useAuth } from '@/components/AuthProvider';

interface ChatLayoutContextType {
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
  toggleSidebar: () => void;
  // v235: Refresh sidebar data (e.g., after plan creation)
  refreshSidebar: () => void;
  sidebarRefreshKey: number;
}

const ChatLayoutContext = createContext<ChatLayoutContextType | undefined>(undefined);

export function useChatLayout() {
  const context = useContext(ChatLayoutContext);
  if (!context) {
    throw new Error('useChatLayout must be used within ChatLayout');
  }
  return context;
}

interface ChatLayoutProps {
  children: ReactNode;
}

// v232: Get user initials for collapsed rail avatar
function getInitials(nameOrEmail: string): string {
  if (nameOrEmail.includes('@')) {
    return nameOrEmail.charAt(0).toUpperCase();
  }
  const parts = nameOrEmail.trim().split(/\s+/);
  if (parts.length >= 2) {
    return (parts[0].charAt(0) + parts[1].charAt(0)).toUpperCase();
  }
  return nameOrEmail.slice(0, 2).toUpperCase();
}

// v233: Handle new chat - reloads page to reset conversation state
function handleNewChat() {
  // Simple approach: reload the page to clear all chat state
  // This matches behavior of Claude/ChatGPT "new chat" which clears conversation
  window.location.reload();
}

// v232: ChatGPT-style collapsed rail with icons and avatar
function CollapsedRail({ onToggle }: { onToggle: () => void }) {
  const { user } = useAuth();

  return (
    <div className="w-12 h-full bg-white border-r border-gray-200 flex flex-col items-center py-3">
      {/* Toggle sidebar */}
      <button
        onClick={onToggle}
        className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
        title="Open sidebar"
      >
        <svg className="w-5 h-5 text-gray-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <rect x="3" y="3" width="18" height="18" rx="2" />
          <line x1="9" y1="3" x2="9" y2="21" />
        </svg>
      </button>

      {/* v233: New chat icon - clears conversation */}
      <button
        onClick={handleNewChat}
        className="p-2 hover:bg-gray-100 rounded-lg transition-colors mt-1"
        title="New chat"
      >
        <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
        </svg>
      </button>

      {/* Spacer */}
      <div className="flex-1" />

      {/* User avatar at bottom */}
      {user && (
        <div
          className="w-8 h-8 rounded-full flex items-center justify-center text-white text-sm font-bold cursor-default"
          style={{ backgroundColor: '#3B82F6' }}
          title={user.displayName || user.email || 'User'}
        >
          {getInitials(user.displayName || user.email || '?')}
        </div>
      )}
    </div>
  );
}

// Inner component that can access DetailModalContext
function ChatLayoutInner({ children }: ChatLayoutProps) {
  // v230: Sidebar collapsed by default (Claude style)
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [isMobile, setIsMobile] = useState(false);
  // v235: Sidebar refresh mechanism for cross-client consistency
  const [sidebarRefreshKey, setSidebarRefreshKey] = useState(0);
  const { isOpen: isPanelOpen, close: closePanel } = useDetailModal();

  // Handle responsive behavior
  useEffect(() => {
    const checkMobile = () => {
      const mobile = window.innerWidth < 768;
      setIsMobile(mobile);
      // On mobile, sidebar starts closed
      if (mobile) {
        setSidebarOpen(false);
      }
    };

    checkMobile();
    window.addEventListener('resize', checkMobile);
    return () => window.removeEventListener('resize', checkMobile);
  }, []);

  const toggleSidebar = () => setSidebarOpen(!sidebarOpen);
  // v235: Refresh sidebar data (called when plan card received from chat)
  const refreshSidebar = () => setSidebarRefreshKey(k => k + 1);

  return (
    <ChatLayoutContext.Provider value={{ sidebarOpen, setSidebarOpen, toggleSidebar, refreshSidebar, sidebarRefreshKey }}>
      <div className="flex h-screen bg-gray-50 overflow-hidden">
        {/* v232: ChatGPT-style collapsed rail (desktop only, when sidebar collapsed) */}
        {!isMobile && !sidebarOpen && (
          <CollapsedRail onToggle={toggleSidebar} />
        )}

        {/* Sidebar with smooth slide animation */}
        <div
          className={`flex-shrink-0 transition-all duration-300 ease-in-out overflow-hidden ${
            isMobile
              ? 'fixed inset-y-0 left-0 z-40'
              : ''
          }`}
          style={{
            width: isMobile ? '280px' : (sidebarOpen ? '280px' : '0px'),
            marginLeft: isMobile ? (sidebarOpen ? '0px' : '-280px') : '0px',
          }}
        >
          <Sidebar
            isOpen={sidebarOpen}
            onClose={() => setSidebarOpen(false)}
            isMobile={isMobile}
            refreshKey={sidebarRefreshKey}
          />
        </div>

        {/* Mobile backdrop */}
        {isMobile && sidebarOpen && (
          <div
            className="fixed inset-0 bg-black/50 z-30 transition-opacity"
            onClick={() => setSidebarOpen(false)}
          />
        )}

        {/* Mobile: floating toggle when sidebar closed */}
        {isMobile && !sidebarOpen && (
          <button
            onClick={toggleSidebar}
            className="fixed top-4 left-4 p-2 bg-white hover:bg-gray-100 rounded-lg shadow-md transition-colors z-10"
            title="Open sidebar"
          >
            <svg className="w-5 h-5 text-gray-600" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <rect x="3" y="3" width="18" height="18" rx="2" />
              <line x1="9" y1="3" x2="9" y2="21" />
            </svg>
          </button>
        )}

        {/* Main content */}
        <main className="flex-1 flex flex-col min-w-0 transition-all duration-300 ease-in-out">
          {children}
        </main>

        {/* Right-side detail panel */}
        <DetailPanel isOpen={isPanelOpen} onClose={closePanel}>
          <DetailModalContainer />
        </DetailPanel>
      </div>
    </ChatLayoutContext.Provider>
  );
}

export default function ChatLayout({ children }: ChatLayoutProps) {
  return (
    <DetailModalProvider>
      <ChatLayoutInner>{children}</ChatLayoutInner>
    </DetailModalProvider>
  );
}
