'use client';

import { useAuth } from '@/components/AuthProvider';
import { colors } from '@/lib/colors';

interface SettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onOpenTrainingPreferences?: () => void;
}

export default function SettingsModal({ isOpen, onClose, onOpenTrainingPreferences }: SettingsModalProps) {
  const { user, signOut } = useAuth();

  if (!isOpen) return null;

  const handleSignOut = async () => {
    await signOut();
    onClose();
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
          className="relative w-full max-w-md bg-white rounded-2xl shadow-xl"
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100">
            <h2 className="text-lg font-semibold text-gray-900">Settings</h2>
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium rounded-lg hover:bg-gray-100 transition-colors"
              style={{ color: colors.accentBlue }}
            >
              Done
            </button>
          </div>

          {/* Content */}
          <div className="px-6 py-4 space-y-6">
            {/* ACCOUNT Section */}
            <section>
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                Account
              </h3>
              <div className="bg-gray-50 rounded-xl overflow-hidden divide-y divide-gray-200">
                <SettingsRow
                  icon={
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                    </svg>
                  }
                  label="Member"
                  value={user?.email || 'Unknown'}
                />
                <SettingsRow
                  icon={
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
                    </svg>
                  }
                  label="Plan"
                  value="Free"
                />
              </div>
            </section>

            {/* TRAINING Section */}
            <section>
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                Training
              </h3>
              <div className="bg-gray-50 rounded-xl overflow-hidden">
                <button
                  onClick={() => {
                    onOpenTrainingPreferences?.();
                  }}
                  className="w-full flex items-center justify-between px-4 py-3 hover:bg-gray-100 transition-colors"
                >
                  <div className="flex items-center gap-3">
                    <span className="text-blue-500">
                      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                      </svg>
                    </span>
                    <span className="text-sm text-gray-900">Preferences</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-gray-500">0 days, 60 min</span>
                    <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                    </svg>
                  </div>
                </button>
              </div>
            </section>

            {/* APP INFORMATION Section */}
            <section>
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                App Information
              </h3>
              <div className="bg-gray-50 rounded-xl overflow-hidden">
                <SettingsRow
                  icon={
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                    </svg>
                  }
                  label="Version"
                  value="1.0 (Build 212)"
                />
              </div>
            </section>

            {/* LEGAL Section */}
            <section>
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                Legal
              </h3>
              <div className="bg-gray-50 rounded-xl overflow-hidden divide-y divide-gray-200">
                <SettingsLink
                  icon={
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                    </svg>
                  }
                  label="Terms of Service"
                  href="https://medinaintelligence.com/terms"
                />
                <SettingsLink
                  icon={
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                    </svg>
                  }
                  label="Privacy Policy"
                  href="https://medinaintelligence.com/privacy"
                />
              </div>
            </section>

            {/* CREDITS Section */}
            <section>
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                Credits
              </h3>
              <div className="bg-gray-50 rounded-xl px-4 py-3">
                <p className="text-sm text-gray-600">
                  Built with ❤️ by the Medina team
                </p>
                <p className="text-xs text-gray-400 mt-1">
                  © 2025 Medina. All rights reserved.
                </p>
              </div>
            </section>

            {/* Sign Out Button */}
            <button
              onClick={handleSignOut}
              className="w-full py-3 text-center text-red-500 font-medium hover:bg-red-50 rounded-xl transition-colors"
            >
              Sign Out
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// Helper component for settings row
interface SettingsRowProps {
  icon: React.ReactNode;
  label: string;
  value: string;
}

function SettingsRow({ icon, label, value }: SettingsRowProps) {
  return (
    <div className="flex items-center justify-between px-4 py-3">
      <div className="flex items-center gap-3">
        <span className="text-blue-500">{icon}</span>
        <span className="text-sm text-gray-900">{label}</span>
      </div>
      <span className="text-sm text-gray-500">{value}</span>
    </div>
  );
}

// Helper component for settings link
interface SettingsLinkProps {
  icon: React.ReactNode;
  label: string;
  href: string;
}

function SettingsLink({ icon, label, href }: SettingsLinkProps) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="flex items-center justify-between px-4 py-3 hover:bg-gray-100 transition-colors"
    >
      <div className="flex items-center gap-3">
        <span className="text-blue-500">{icon}</span>
        <span className="text-sm text-gray-900">{label}</span>
      </div>
      <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
      </svg>
    </a>
  );
}
