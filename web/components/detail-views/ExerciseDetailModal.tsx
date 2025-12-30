'use client';

import { useState, useEffect } from 'react';
import { X, ArrowLeft, Loader2, Star } from 'lucide-react';
import { colors } from '@/lib/colors';
import { BreadcrumbBar, BreadcrumbItem } from './shared/BreadcrumbBar';
import { KeyValueRow } from './shared/KeyValueRow';
import { DisclosureSection } from './shared/DisclosureSection';
import { useAuth } from '@/components/AuthProvider';
import { getExerciseDetails } from '@/lib/firestore';
import { calculateWorkingWeight, formatWeight } from '@/lib/api';
import type { ExerciseDetails } from '@/lib/types';

interface ExerciseDetailModalProps {
  exerciseId: string;
  onBack?: () => void;
  onClose: () => void;
  breadcrumbItems: BreadcrumbItem[];
}

export function ExerciseDetailModal({ exerciseId, onBack, onClose, breadcrumbItems }: ExerciseDetailModalProps) {
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [exercise, setExercise] = useState<ExerciseDetails | null>(null);
  const [isInLibrary, setIsInLibrary] = useState(false);
  const [libraryLoading, setLibraryLoading] = useState(false);

  useEffect(() => {
    async function fetchExercise() {
      setLoading(true);
      try {
        const data = await getExerciseDetails(exerciseId, user?.uid);
        setExercise(data);
      } catch (error) {
        console.error('Failed to fetch exercise:', error);
      } finally {
        setLoading(false);
      }
    }

    fetchExercise();
  }, [exerciseId, user?.uid]);

  const toggleLibrary = async () => {
    if (!user?.uid || libraryLoading) return;

    setLibraryLoading(true);
    try {
      const token = await user.getIdToken();
      const action = isInLibrary ? 'removeFromLibrary' : 'addToLibrary';
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({
          action,
          exerciseId,
        }),
      });

      if (response.ok) {
        setIsInLibrary(!isInLibrary);
      }
    } catch (error) {
      console.error('Failed to toggle library:', error);
    } finally {
      setLibraryLoading(false);
    }
  };

  const formatDate = (date?: Date) => {
    if (!date) return '-';
    return new Intl.DateTimeFormat('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    }).format(date);
  };

  // Weight suggestion using shared calculation from api.ts
  const getWeightSuggestion = (oneRM: number, percentage: number) => {
    return formatWeight(calculateWorkingWeight(oneRM, percentage));
  };

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
          className="text-base font-semibold"
          style={{ color: colors.primaryText }}
        >
          Exercise Details
        </h2>
        <button
          onClick={toggleLibrary}
          disabled={libraryLoading}
          className="p-2 -mr-2 hover:bg-gray-100 rounded-lg transition-colors disabled:opacity-50"
        >
          {libraryLoading ? (
            <Loader2 className="w-5 h-5 animate-spin" style={{ color: colors.tertiaryText }} />
          ) : (
            <Star
              className="w-5 h-5"
              style={{ color: isInLibrary ? colors.warning : colors.tertiaryText }}
              fill={isInLibrary ? colors.warning : 'none'}
            />
          )}
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 animate-spin" style={{ color: colors.accentBlue }} />
          </div>
        ) : !exercise ? (
          <div className="flex items-center justify-center py-12">
            <p className="text-sm" style={{ color: colors.tertiaryText }}>
              Exercise not found
            </p>
          </div>
        ) : (
          <>
            <BreadcrumbBar items={breadcrumbItems} />

            {/* Exercise Header */}
            <div className="px-4 py-5" style={{ backgroundColor: colors.bgPrimary }}>
              <h1
                className="text-xl font-semibold"
                style={{ color: colors.primaryText }}
              >
                {exercise.name}
              </h1>
              {exercise.equipment && (
                <span
                  className="inline-flex items-center px-2 py-0.5 mt-2 rounded-full text-xs font-medium"
                  style={{ backgroundColor: colors.bgSecondary, color: colors.secondaryText }}
                >
                  {exercise.equipment}
                </span>
              )}
            </div>

            <DisclosureSection title="Exercise Info">
              <div style={{ backgroundColor: colors.bgSecondary }} className="rounded-lg">
                <KeyValueRow
                  label="Primary Muscles"
                  value={exercise.primaryMuscles?.join(', ') || '-'}
                />
                <KeyValueRow
                  label="Secondary Muscles"
                  value={exercise.secondaryMuscles?.join(', ') || '-'}
                />
                <KeyValueRow
                  label="Equipment"
                  value={exercise.equipment || '-'}
                />
                {exercise.movementPattern && (
                  <KeyValueRow
                    label="Movement"
                    value={exercise.movementPattern}
                  />
                )}
                {exercise.difficulty && (
                  <KeyValueRow
                    label="Difficulty"
                    value={exercise.difficulty}
                  />
                )}
              </div>
            </DisclosureSection>

            <DisclosureSection title="Your Stats" defaultOpen={true}>
              <div style={{ backgroundColor: colors.bgSecondary }} className="rounded-lg">
                <KeyValueRow
                  label="Current 1RM"
                  value={exercise.userStats?.current1RM ? `${exercise.userStats.current1RM} lbs` : '-'}
                  valueWeight="semibold"
                />
                <KeyValueRow
                  label="Last Calibrated"
                  value={exercise.userStats?.lastCalibrated ? formatDate(exercise.userStats.lastCalibrated) : '-'}
                />
                {exercise.estimated1RM && !exercise.userStats?.current1RM && (
                  <KeyValueRow
                    label="Estimated 1RM"
                    value={`${exercise.estimated1RM.value} lbs (from ${exercise.estimated1RM.sourceExercise})`}
                  />
                )}
              </div>
              {!exercise.userStats?.current1RM && !exercise.estimated1RM && (
                <p className="text-xs mt-2 px-2" style={{ color: colors.tertiaryText }}>
                  Complete workouts with this exercise to track your strength progress.
                </p>
              )}
            </DisclosureSection>

            <DisclosureSection title="Working Weight Suggestions" defaultOpen={true}>
              {exercise.userStats?.current1RM ? (
                <div className="space-y-2">
                  <div
                    className="flex justify-between items-center p-3 rounded-lg"
                    style={{ backgroundColor: colors.bgSecondary }}
                  >
                    <span className="text-sm" style={{ color: colors.secondaryText }}>Light (60%)</span>
                    <span className="text-sm font-medium" style={{ color: colors.primaryText }}>
                      {getWeightSuggestion(exercise.userStats.current1RM, 0.6)}
                    </span>
                  </div>
                  <div
                    className="flex justify-between items-center p-3 rounded-lg"
                    style={{ backgroundColor: colors.bgSecondary }}
                  >
                    <span className="text-sm" style={{ color: colors.secondaryText }}>Moderate (75%)</span>
                    <span className="text-sm font-medium" style={{ color: colors.primaryText }}>
                      {getWeightSuggestion(exercise.userStats.current1RM, 0.75)}
                    </span>
                  </div>
                  <div
                    className="flex justify-between items-center p-3 rounded-lg"
                    style={{ backgroundColor: colors.bgSecondary }}
                  >
                    <span className="text-sm" style={{ color: colors.secondaryText }}>Heavy (85%)</span>
                    <span className="text-sm font-medium" style={{ color: colors.primaryText }}>
                      {getWeightSuggestion(exercise.userStats.current1RM, 0.85)}
                    </span>
                  </div>
                </div>
              ) : (
                <p className="text-sm py-4 text-center" style={{ color: colors.tertiaryText }}>
                  Set your 1RM to see working weight suggestions
                </p>
              )}
            </DisclosureSection>

            {exercise.instructions && (
              <DisclosureSection title="Instructions" defaultOpen={false}>
                <p className="text-sm whitespace-pre-wrap" style={{ color: colors.secondaryText }}>
                  {exercise.instructions}
                </p>
              </DisclosureSection>
            )}
          </>
        )}
      </div>
    </div>
  );
}
