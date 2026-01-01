'use client';

import { useState, useEffect, useCallback } from 'react';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/components/AuthProvider';
import { doc, getDoc, updateDoc } from 'firebase/firestore';
import { getFirebaseDb } from '@/lib/firebase';

interface ProfilePanelProps {
  isOpen: boolean;
  onClose: () => void;
}

interface ProfileData {
  birthdate?: string;
  gender?: string;
  heightInches?: number;
  currentWeight?: number;
}

// Gender options matching iOS
const GENDER_OPTIONS = [
  { value: '', label: 'Prefer not to say' },
  { value: 'male', label: 'Male' },
  { value: 'female', label: 'Female' },
  { value: 'other', label: 'Other' },
];

export default function ProfilePanel({ isOpen, onClose }: ProfilePanelProps) {
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [profile, setProfile] = useState<ProfileData>({});

  // Height in feet/inches for display
  const [heightFeet, setHeightFeet] = useState<number>(5);
  const [heightInches, setHeightInches] = useState<number>(0);

  // Load profile data
  useEffect(() => {
    async function loadProfile() {
      if (!user?.uid || !isOpen) return;

      setLoading(true);
      try {
        const db = getFirebaseDb();
        const userDoc = await getDoc(doc(db, 'users', user.uid));
        if (userDoc.exists()) {
          const data = userDoc.data();
          const profileData = data.profile || {};
          setProfile(profileData);

          // Convert height to feet/inches
          if (profileData.heightInches) {
            setHeightFeet(Math.floor(profileData.heightInches / 12));
            setHeightInches(profileData.heightInches % 12);
          }
        }
      } catch (error) {
        console.error('Failed to load profile:', error);
      } finally {
        setLoading(false);
      }
    }

    loadProfile();
  }, [user?.uid, isOpen]);

  // Auto-save helper (like Training Preferences)
  const saveField = useCallback(
    async (field: string, value: unknown) => {
      if (!user?.uid) return;
      try {
        const db = getFirebaseDb();
        await updateDoc(doc(db, 'users', user.uid), {
          [`profile.${field}`]: value,
        });
      } catch (error) {
        console.error('Failed to save profile field:', error);
      }
    },
    [user?.uid]
  );

  // Calculate age from birthdate
  const calculateAge = (birthdate: string): number | null => {
    if (!birthdate) return null;
    const birth = new Date(birthdate);
    const today = new Date();
    let age = today.getFullYear() - birth.getFullYear();
    const monthDiff = today.getMonth() - birth.getMonth();
    if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birth.getDate())) {
      age--;
    }
    return age;
  };

  // Format birthdate for display (MM/DD/YYYY)
  const formatBirthdate = (dateStr: string): string => {
    if (!dateStr) return 'Not set';
    const date = new Date(dateStr);
    return date.toLocaleDateString('en-US', { month: '2-digit', day: '2-digit', year: 'numeric' });
  };

  // Handlers
  const handleBirthdateChange = (value: string) => {
    setProfile({ ...profile, birthdate: value });
    saveField('birthdate', value || null);
  };

  const handleGenderChange = (value: string) => {
    setProfile({ ...profile, gender: value });
    saveField('gender', value || null);
  };

  const handleHeightChange = (feet: number, inches: number) => {
    setHeightFeet(feet);
    setHeightInches(inches);
    const totalInches = feet * 12 + inches;
    saveField('heightInches', totalInches || null);
  };

  const handleWeightChange = (value: number | undefined) => {
    setProfile({ ...profile, currentWeight: value });
    saveField('currentWeight', value || null);
  };

  if (!isOpen) return null;

  const age = profile.birthdate ? calculateAge(profile.birthdate) : null;

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
          {/* Header - matches TrainingPreferencesModal pattern */}
          <div className="sticky top-0 bg-white flex items-center justify-between px-6 py-4 border-b border-gray-100">
            <button
              onClick={onClose}
              className="p-2 -ml-2 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
            </button>
            <h2 className="text-lg font-semibold text-gray-900">Profile</h2>
            <div className="w-9" /> {/* Spacer for centering */}
          </div>

          {/* Content */}
          <div className="px-6 py-4 space-y-6">
            {loading ? (
              <div className="flex items-center justify-center h-48">
                <Loader2 className="w-6 h-6 animate-spin text-blue-500" />
              </div>
            ) : (
              <>
                {/* ACCOUNT Section */}
                <section>
                  <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                    Account
                  </h3>
                  <div className="bg-gray-50 rounded-xl overflow-hidden divide-y divide-gray-200">
                    {/* Gym - read-only */}
                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-sm text-gray-900">Gym</span>
                      <span className="text-sm text-gray-500">None</span>
                    </div>
                    {/* Trainer - read-only */}
                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-sm text-gray-900">Trainer</span>
                      <span className="text-sm text-gray-500">None</span>
                    </div>
                    {/* Plan - read-only */}
                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-sm text-gray-900">Plan</span>
                      <span className="text-sm text-gray-500">Free</span>
                    </div>
                  </div>
                </section>

                {/* PROFILE Section */}
                <section>
                  <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">
                    Profile
                  </h3>
                  <div className="bg-gray-50 rounded-xl overflow-hidden divide-y divide-gray-200">
                    {/* Birthdate */}
                    <ProfileRow
                      label="Date of Birth"
                      value={formatBirthdate(profile.birthdate || '')}
                      badge={age !== null ? `${age} years` : undefined}
                    >
                      <input
                        type="date"
                        value={profile.birthdate || ''}
                        onChange={(e) => handleBirthdateChange(e.target.value)}
                        className="absolute inset-0 opacity-0 cursor-pointer"
                      />
                    </ProfileRow>

                    {/* Gender */}
                    <ProfileRow
                      label="Gender"
                      value={GENDER_OPTIONS.find(g => g.value === profile.gender)?.label || 'Prefer not to say'}
                    >
                      <select
                        value={profile.gender || ''}
                        onChange={(e) => handleGenderChange(e.target.value)}
                        className="absolute inset-0 opacity-0 cursor-pointer"
                      >
                        {GENDER_OPTIONS.map((opt) => (
                          <option key={opt.value} value={opt.value}>
                            {opt.label}
                          </option>
                        ))}
                      </select>
                    </ProfileRow>

                    {/* Height */}
                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-sm text-gray-900">Height</span>
                      <div className="flex items-center gap-2">
                        <select
                          value={heightFeet}
                          onChange={(e) => handleHeightChange(parseInt(e.target.value) || 5, heightInches)}
                          className="bg-white border border-gray-300 rounded-lg px-2 py-1 text-sm text-gray-900"
                        >
                          {[3, 4, 5, 6, 7, 8].map((ft) => (
                            <option key={ft} value={ft}>{ft} ft</option>
                          ))}
                        </select>
                        <select
                          value={heightInches}
                          onChange={(e) => handleHeightChange(heightFeet, parseInt(e.target.value) || 0)}
                          className="bg-white border border-gray-300 rounded-lg px-2 py-1 text-sm text-gray-900"
                        >
                          {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((inches) => (
                            <option key={inches} value={inches}>{inches} in</option>
                          ))}
                        </select>
                      </div>
                    </div>

                    {/* Weight */}
                    <div className="flex items-center justify-between px-4 py-3">
                      <span className="text-sm text-gray-900">Weight</span>
                      <div className="flex items-center gap-2">
                        <input
                          type="number"
                          min="50"
                          max="500"
                          value={profile.currentWeight || ''}
                          onChange={(e) => handleWeightChange(parseInt(e.target.value) || undefined)}
                          placeholder="—"
                          className="w-16 bg-white border border-gray-300 rounded-lg px-2 py-1 text-sm text-gray-900 text-right"
                        />
                        <span className="text-sm text-gray-500">lbs</span>
                      </div>
                    </div>
                  </div>
                </section>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// Helper component for profile row with hidden input overlay
interface ProfileRowProps {
  label: string;
  value: string;
  badge?: string;
  children: React.ReactNode;
}

function ProfileRow({ label, value, badge, children }: ProfileRowProps) {
  return (
    <div className="relative flex items-center justify-between px-4 py-3 hover:bg-gray-100 transition-colors cursor-pointer">
      <span className="text-sm text-gray-900">{label}</span>
      <div className="flex items-center gap-2">
        <span className="text-sm text-gray-500">{value}</span>
        {badge && (
          <span className="text-xs px-2 py-0.5 bg-gray-200 rounded-full text-gray-600">
            {badge}
          </span>
        )}
        <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </div>
      {children}
    </div>
  );
}
