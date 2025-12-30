'use client';

import { useState, useRef } from 'react';
import { colors } from '@/lib/colors';
import { useAuth } from '@/components/AuthProvider';
import { importCSV, type ImportResponse } from '@/lib/api';

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
  const { user } = useAuth();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isImporting, setIsImporting] = useState(false);
  const [importResult, setImportResult] = useState<ImportResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handlePhotoUpload = () => {
    // TODO: Implement photo upload with vision API
    console.log('Photo upload');
    onClose();
  };

  const handleFileClick = () => {
    fileInputRef.current?.click();
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !user) return;

    // Reset state
    setError(null);
    setImportResult(null);
    setIsImporting(true);

    try {
      // Read file as text
      const text = await file.text();

      // Convert to base64
      const base64 = btoa(unescape(encodeURIComponent(text)));

      // Get auth token
      const token = await user.getIdToken();

      // Call import API
      const result = await importCSV(token, base64, {
        createHistoricalWorkouts: true,
      });

      if (result.error) {
        setError(result.error);
      } else {
        setImportResult(result);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Import failed');
    } finally {
      setIsImporting(false);
      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  };

  const handleTrainingPreferences = () => {
    onClose();
    onOpenTrainingPreferences?.();
  };

  const handleClose = () => {
    setImportResult(null);
    setError(null);
    onClose();
  };

  // Show import results
  if (importResult?.summary) {
    return (
      <div className="fixed inset-0 z-50 overflow-y-auto">
        <div
          className="fixed inset-0 bg-black/50 transition-opacity"
          onClick={handleClose}
        />
        <div className="flex min-h-full items-end justify-center p-4 sm:items-center">
          <div
            className="relative w-full max-w-sm bg-white rounded-2xl shadow-xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="px-6 py-4 border-b border-gray-100 text-center">
              <div className="w-12 h-12 mx-auto mb-3 rounded-full bg-green-100 flex items-center justify-center">
                <svg className="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <h2 className="text-lg font-semibold text-gray-900">Import Complete</h2>
            </div>

            <div className="px-6 py-4 space-y-3">
              <ResultRow label="Sessions imported" value={importResult.summary.sessionsImported} />
              <ResultRow label="Exercises matched" value={importResult.summary.exercisesMatched} />
              <ResultRow label="Targets created" value={importResult.summary.targetsCreated} />
              <ResultRow label="Workouts created" value={importResult.summary.workoutsCreated} />

              {importResult.summary.exercisesUnmatched.length > 0 && (
                <div className="pt-2 border-t border-gray-100">
                  <p className="text-xs text-gray-500 mb-1">Unmatched exercises:</p>
                  <p className="text-xs text-orange-600">
                    {importResult.summary.exercisesUnmatched.join(', ')}
                  </p>
                </div>
              )}

              {importResult.intelligence && (
                <div className="pt-2 border-t border-gray-100">
                  <p className="text-xs font-medium text-gray-700 mb-2">Analysis</p>
                  <div className="space-y-1">
                    <p className="text-xs text-gray-600">
                      Experience: <span className="font-medium">{importResult.intelligence.inferredExperience}</span>
                    </p>
                    <p className="text-xs text-gray-600">
                      Style: <span className="font-medium">{importResult.intelligence.trainingStyle}</span>
                    </p>
                    <p className="text-xs text-gray-600">
                      Top muscles: <span className="font-medium">{importResult.intelligence.topMuscleGroups.join(', ')}</span>
                    </p>
                  </div>
                </div>
              )}
            </div>

            <div className="px-4 py-4 border-t border-gray-100">
              <button
                onClick={handleClose}
                className="w-full py-3 text-center font-medium rounded-xl transition-colors hover:bg-gray-100"
                style={{ color: colors.accentBlue }}
              >
                Done
              </button>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/50 transition-opacity"
        onClick={handleClose}
      />

      {/* Hidden file input */}
      <input
        ref={fileInputRef}
        type="file"
        accept=".csv"
        onChange={handleFileChange}
        className="hidden"
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

          {/* Error message */}
          {error && (
            <div className="mx-4 mt-4 p-3 bg-red-50 border border-red-200 rounded-lg">
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}

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
                isImporting ? (
                  <svg className="w-5 h-5 animate-spin" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                  </svg>
                ) : (
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                  </svg>
                )
              }
              label={isImporting ? "Importing..." : "CSV File"}
              description="Import workout history from CSV"
              onClick={handleFileClick}
              disabled={isImporting}
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
              onClick={handleClose}
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

function ResultRow({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-sm text-gray-600">{label}</span>
      <span className="text-sm font-semibold text-gray-900">{value}</span>
    </div>
  );
}
