'use client';

import { useState } from 'react';
import { colors } from '@/lib/colors';

interface TrainingPreferencesModalProps {
  isOpen: boolean;
  onClose: () => void;
}

// Options for each preference
const fitnessGoals = [
  { value: 'strength', label: 'Strength' },
  { value: 'muscleGain', label: 'Build Muscle' },
  { value: 'fatLoss', label: 'Fat Loss' },
  { value: 'endurance', label: 'Endurance' },
  { value: 'general', label: 'General Fitness' },
];

const muscleFocus = [
  { value: 'balanced', label: 'Balanced' },
  { value: 'upper', label: 'Upper Body' },
  { value: 'lower', label: 'Lower Body' },
  { value: 'core', label: 'Core' },
];

const experienceLevels = [
  { value: 'beginner', label: 'Beginner' },
  { value: 'intermediate', label: 'Intermediate' },
  { value: 'advanced', label: 'Advanced' },
];

const splitTypes = [
  { value: 'auto', label: 'Auto' },
  { value: 'fullBody', label: 'Full Body' },
  { value: 'upperLower', label: 'Upper/Lower' },
  { value: 'pushPullLegs', label: 'Push/Pull/Legs' },
  { value: 'bro', label: 'Body Part Split' },
];

const sessionDurations = [
  { value: 30, label: '30 min' },
  { value: 45, label: '45 min' },
  { value: 60, label: '60 min' },
  { value: 75, label: '75 min' },
  { value: 90, label: '90 min' },
];

export default function TrainingPreferencesModal({ isOpen, onClose }: TrainingPreferencesModalProps) {
  // State for all preferences
  const [fitnessGoal, setFitnessGoal] = useState('strength');
  const [muscle, setMuscle] = useState('balanced');
  const [experience, setExperience] = useState('intermediate');
  const [workoutDays, setWorkoutDays] = useState(0);
  const [splitType, setSplitType] = useState('auto');
  const [cardioDays, setCardioDays] = useState(0);
  const [sessionDuration, setSessionDuration] = useState(60);

  if (!isOpen) return null;

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
          className="relative w-full max-w-md bg-white rounded-2xl shadow-xl max-h-[90vh] overflow-y-auto"
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="sticky top-0 bg-white flex items-center justify-between px-6 py-4 border-b border-gray-100">
            <button
              onClick={onClose}
              className="p-2 -ml-2 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
            </button>
            <h2 className="text-lg font-semibold text-gray-900">Training</h2>
            <div className="w-9" /> {/* Spacer for centering */}
          </div>

          {/* Content */}
          <div className="px-6 py-4 space-y-6">
            {/* GOALS Section */}
            <section>
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                Goals
              </h3>
              <div className="bg-gray-50 rounded-xl overflow-hidden divide-y divide-gray-200">
                <PreferenceRow
                  label="Fitness Goal"
                  value={fitnessGoals.find(g => g.value === fitnessGoal)?.label || fitnessGoal}
                  options={fitnessGoals}
                  selectedValue={fitnessGoal}
                  onChange={(v) => setFitnessGoal(String(v))}
                />
                <PreferenceRow
                  label="Muscle Focus"
                  value={muscleFocus.find(m => m.value === muscle)?.label || muscle}
                  options={muscleFocus}
                  selectedValue={muscle}
                  onChange={(v) => setMuscle(String(v))}
                  hasChevron
                />
              </div>
            </section>

            {/* SCHEDULE Section */}
            <section>
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                Schedule
              </h3>
              <div className="bg-gray-50 rounded-xl overflow-hidden divide-y divide-gray-200">
                <PreferenceRow
                  label="Experience Level"
                  value={experienceLevels.find(e => e.value === experience)?.label || experience}
                  options={experienceLevels}
                  selectedValue={experience}
                  onChange={(v) => setExperience(String(v))}
                />
                <PreferenceRow
                  label="Workout Days"
                  value={`${workoutDays} days/week`}
                  options={[0, 1, 2, 3, 4, 5, 6, 7].map(d => ({ value: d, label: `${d} days/week` }))}
                  selectedValue={workoutDays}
                  onChange={(v) => setWorkoutDays(Number(v))}
                  hasChevron
                />
                <PreferenceRow
                  label="Split Type"
                  value={splitTypes.find(s => s.value === splitType)?.label || splitType}
                  options={splitTypes}
                  selectedValue={splitType}
                  onChange={(v) => setSplitType(String(v))}
                />
                <PreferenceRow
                  label="Cardio Days"
                  value={cardioDays === 0 ? 'Auto' : `${cardioDays} days/week`}
                  options={[{ value: 0, label: 'Auto' }, ...([1, 2, 3, 4, 5].map(d => ({ value: d, label: `${d} days/week` })))]}
                  selectedValue={cardioDays}
                  onChange={(v) => setCardioDays(Number(v))}
                />
                <PreferenceRow
                  label="Session Duration"
                  value={sessionDurations.find(s => s.value === sessionDuration)?.label || `${sessionDuration} min`}
                  options={sessionDurations}
                  selectedValue={sessionDuration}
                  onChange={(v) => setSessionDuration(Number(v))}
                />
              </div>
            </section>

            {/* EQUIPMENT Section */}
            <section>
              <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                Equipment
              </h3>
              <div className="bg-gray-50 rounded-xl overflow-hidden">
                <button className="w-full flex items-center justify-between px-4 py-3 hover:bg-gray-100 transition-colors">
                  <span className="text-sm text-gray-900">Home Equipment</span>
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-gray-500">None</span>
                    <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                    </svg>
                  </div>
                </button>
              </div>
            </section>
          </div>
        </div>
      </div>
    </div>
  );
}

// Helper component for preference row with dropdown
interface PreferenceRowProps {
  label: string;
  value: string;
  options: Array<{ value: string | number; label: string }>;
  selectedValue: string | number;
  onChange: (value: string | number) => void;
  hasChevron?: boolean;
}

function PreferenceRow({ label, value, options, selectedValue, onChange, hasChevron }: PreferenceRowProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  return (
    <div>
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className="w-full flex items-center justify-between px-4 py-3 hover:bg-gray-100 transition-colors"
      >
        <span className="text-sm text-gray-900">{label}</span>
        <div className="flex items-center gap-2">
          <span className="text-sm text-gray-500">{value}</span>
          {hasChevron && (
            <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          )}
          {!hasChevron && (
            <svg
              className={`w-4 h-4 text-gray-400 transition-transform ${isExpanded ? 'rotate-180' : ''}`}
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          )}
        </div>
      </button>

      {isExpanded && !hasChevron && (
        <div className="px-4 pb-3 space-y-1">
          {options.map((option) => (
            <button
              key={option.value}
              onClick={() => {
                onChange(option.value);
                setIsExpanded(false);
              }}
              className={`w-full text-left px-3 py-2 text-sm rounded-lg transition-colors ${
                selectedValue === option.value
                  ? 'bg-blue-50 text-blue-600'
                  : 'text-gray-700 hover:bg-gray-100'
              }`}
            >
              {option.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
