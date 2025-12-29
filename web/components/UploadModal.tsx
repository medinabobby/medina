'use client';

import { colors } from '@/lib/colors';

interface UploadModalProps {
  isOpen: boolean;
  onClose: () => void;
  onOpenTrainingPreferences?: () => void;
}

export default function UploadModal({
  isOpen,
  onClose,
  onOpenTrainingPreferences,
}: UploadModalProps) {
  if (!isOpen) return null;

  const handlePhotoUpload = () => {
    // TODO: Implement photo upload
    console.log('Photo upload');
    onClose();
  };

  const handleFileUpload = () => {
    // TODO: Implement file upload
    console.log('File upload');
    onClose();
  };

  const handleTrainingPreferences = () => {
    onClose();
    onOpenTrainingPreferences?.();
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/50 transition-opacity"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="flex min-h-full items-end justify-center p-4 sm:items-center">
        <div
          className="relative w-full max-w-sm bg-white rounded-2xl shadow-xl overflow-hidden"
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="px-6 py-4 border-b border-gray-100 text-center">
            <h2 className="text-lg font-semibold text-gray-900">Add Content</h2>
            <p className="text-sm text-gray-500 mt-1">
              Import files or adjust your preferences
            </p>
          </div>

          {/* Options */}
          <div className="px-4 py-3 space-y-1">
            {/* Import Section */}
            <div className="px-2 py-2">
              <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider">
                Import
              </span>
            </div>

            <OptionButton
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
              }
              label="Photos"
              description="Upload workout photos or progress pics"
              onClick={handlePhotoUpload}
            />

            <OptionButton
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
              }
              label="Files"
              description="Import training programs or data"
              onClick={handleFileUpload}
            />

            {/* Settings Section */}
            <div className="px-2 py-2 mt-2">
              <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider">
                Settings
              </span>
            </div>

            <OptionButton
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
              }
              label="Training Preferences"
              description="Adjust your workout settings"
              onClick={handleTrainingPreferences}
            />

            <OptionButton
              icon={
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                </svg>
              }
              label="Voice Coaching"
              description="Audio settings"
              disabled
              badge="Coming Soon"
            />
          </div>

          {/* Cancel Button */}
          <div className="px-4 py-4 border-t border-gray-100">
            <button
              onClick={onClose}
              className="w-full py-3 text-center font-medium rounded-xl transition-colors hover:bg-gray-100"
              style={{ color: colors.accentBlue }}
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

interface OptionButtonProps {
  icon: React.ReactNode;
  label: string;
  description: string;
  onClick?: () => void;
  disabled?: boolean;
  badge?: string;
}

function OptionButton({ icon, label, description, onClick, disabled, badge }: OptionButtonProps) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`w-full flex items-center gap-4 px-4 py-3 rounded-xl transition-colors ${
        disabled
          ? 'opacity-50 cursor-not-allowed'
          : 'hover:bg-gray-100'
      }`}
    >
      <div
        className="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0"
        style={{ backgroundColor: colors.accentSubtle, color: colors.accentBlue }}
      >
        {icon}
      </div>
      <div className="flex-1 text-left">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-gray-900">{label}</span>
          {badge && (
            <span className="text-xs px-2 py-0.5 bg-gray-100 text-gray-500 rounded-full">
              {badge}
            </span>
          )}
        </div>
        <p className="text-xs text-gray-500">{description}</p>
      </div>
      <svg className="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
      </svg>
    </button>
  );
}
