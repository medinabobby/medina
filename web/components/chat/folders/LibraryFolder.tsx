'use client';

import { useState, useEffect } from 'react';
import { useAuth } from '@/components/AuthProvider';
import { getLibraryExercises } from '@/lib/firestore';
import { useDetailModal } from '@/components/detail-views';
import type { Exercise } from '@/lib/types';

// v242: Maximum exercises to show in sidebar (matches iOS sidebarItemLimit)
const SIDEBAR_ITEM_LIMIT = 3;

interface LibraryFolderProps {
  refreshKey?: number;
}

export default function LibraryFolder({ refreshKey = 0 }: LibraryFolderProps) {
  const { user } = useAuth();
  const { openExercise } = useDetailModal();
  const [isOpen, setIsOpen] = useState(true);
  const [showExercises, setShowExercises] = useState(true);
  const [showAll, setShowAll] = useState(false);
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    async function loadLibrary() {
      if (!user?.uid) return;

      setLoading(true);
      try {
        const libraryExercises = await getLibraryExercises(user.uid);
        setExercises(libraryExercises);
      } catch (error) {
        console.error('[LibraryFolder] Failed to load library:', error);
      } finally {
        setLoading(false);
      }
    }

    loadLibrary();
  }, [user?.uid, refreshKey]);

  // Display either limited or all exercises
  const displayedExercises = showAll ? exercises : exercises.slice(0, SIDEBAR_ITEM_LIMIT);
  const moreCount = exercises.length - SIDEBAR_ITEM_LIMIT;

  return (
    <div>
      {/* Library folder header */}
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
        {/* Bar chart icon like iOS */}
        <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        </svg>
        <span className="flex-1 text-left text-sm font-medium">Library</span>
      </button>

      {isOpen && (
        <div className="mt-0.5 pl-6">
          {/* Exercises subfolder */}
          <button
            onClick={() => setShowExercises(!showExercises)}
            className="w-full flex items-center gap-2 px-3 py-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
          >
            <svg
              className={`w-3 h-3 text-gray-400 transition-transform ${showExercises ? 'rotate-90' : ''}`}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
            {/* Dumbbell icon - matches iOS dumbbell.fill */}
            <svg
              className="w-4 h-4 text-gray-500"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8h3m12 0h3M3 16h3m12 0h3M6 8v8M18 8v8M9 6h6v12H9V6z" />
            </svg>
            <span className="flex-1 text-left text-sm">Exercises</span>
            {exercises.length > 0 && (
              <span className="text-xs text-gray-400">{exercises.length}</span>
            )}
          </button>

          {showExercises && (
            <div className="mt-0.5 pl-4 space-y-0.5">
              {loading ? (
                <p className="px-3 py-2 text-xs text-gray-400">Loading...</p>
              ) : exercises.length === 0 ? (
                <p className="px-3 py-2 text-xs text-gray-400">No exercises in library</p>
              ) : (
                <>
                  {displayedExercises.map((exercise) => (
                    <button
                      key={exercise.id}
                      onClick={() => openExercise(exercise.id, exercise.name)}
                      className="w-full text-left px-3 py-2 text-sm text-gray-600 hover:bg-gray-100 rounded-lg truncate transition-colors"
                      title={exercise.name}
                    >
                      {exercise.name}
                    </button>
                  ))}
                  {!showAll && moreCount > 0 && (
                    <button
                      onClick={() => setShowAll(true)}
                      className="w-full text-left px-3 py-2 text-sm text-blue-600 hover:bg-gray-100 rounded-lg transition-colors"
                    >
                      + {moreCount} more...
                    </button>
                  )}
                  {showAll && moreCount > 0 && (
                    <button
                      onClick={() => setShowAll(false)}
                      className="w-full text-left px-3 py-2 text-sm text-gray-500 hover:bg-gray-100 rounded-lg transition-colors"
                    >
                      Show less
                    </button>
                  )}
                </>
              )}
            </div>
          )}

          {/* Protocols subfolder - placeholder for future */}
          <button
            className="w-full flex items-center gap-2 px-3 py-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors opacity-50 cursor-not-allowed"
            disabled
          >
            <svg
              className="w-3 h-3 text-gray-400"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
            <span className="flex-1 text-left text-sm">Protocols</span>
          </button>
        </div>
      )}
    </div>
  );
}
