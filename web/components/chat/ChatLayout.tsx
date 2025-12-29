'use client';

import { useState, useEffect, createContext, useContext, ReactNode } from 'react';
import Sidebar from './Sidebar';
import { DetailModalProvider, DetailModalContainer, useDetailModal, DetailPanel } from '@/components/detail-views';

interface ChatLayoutContextType {
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
  toggleSidebar: () => void;
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

// Inner component that can access DetailModalContext
function ChatLayoutInner({ children }: ChatLayoutProps) {
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [isMobile, setIsMobile] = useState(false);
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

  return (
    <ChatLayoutContext.Provider value={{ sidebarOpen, setSidebarOpen, toggleSidebar }}>
      <div className="flex h-screen bg-gray-50 overflow-hidden">
        {/* Sidebar with smooth slide animation */}
        <div
          className={`flex-shrink-0 transition-all duration-300 ease-in-out ${
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
          />
        </div>

        {/* Mobile backdrop */}
        {isMobile && sidebarOpen && (
          <div
            className="fixed inset-0 bg-black/50 z-30 transition-opacity"
            onClick={() => setSidebarOpen(false)}
          />
        )}

        {/* Main content with smooth transition */}
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
