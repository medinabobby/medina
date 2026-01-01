'use client';

import { useState, useEffect } from 'react';
import { Loader2 } from 'lucide-react';
import { colors } from '@/lib/colors';
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
  const [saving, setSaving] = useState(false);
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

  const handleSave = async () => {
    if (!user?.uid) return;

    setSaving(true);
    try {
      const db = getFirebaseDb();
      const totalHeightInches = heightFeet * 12 + heightInches;

      await updateDoc(doc(db, 'users', user.uid), {
        'profile.birthdate': profile.birthdate || null,
        'profile.gender': profile.gender || null,
        'profile.heightInches': totalHeightInches || null,
        'profile.currentWeight': profile.currentWeight || null,
      });

      onClose();
    } catch (error) {
      console.error('Failed to save profile:', error);
    } finally {
      setSaving(false);
    }
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
          <div className="px-6 py-4">
            {loading ? (
              <div className="flex items-center justify-center h-48">
                <Loader2 className="w-6 h-6 animate-spin text-blue-500" />
              </div>
            ) : (
              <div className="space-y-6">
                {/* Profile Fields - no avatar header, just editable fields */}
                <div className="space-y-4">
                  {/* Birthdate */}
                  <div className="bg-gray-50 rounded-xl p-4">
                    <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
                      Date of Birth
                    </label>
                    <div className="flex items-center justify-between">
                      <input
                        type="date"
                        value={profile.birthdate || ''}
                        onChange={(e) => setProfile({ ...profile, birthdate: e.target.value })}
                        className="flex-1 bg-transparent text-sm outline-none"
                        style={{ color: colors.primaryText }}
                      />
                      {age !== null && (
                        <span className="text-sm px-3 py-1 bg-gray-200 rounded-full" style={{ color: colors.secondaryText }}>
                          {age} years
                        </span>
                      )}
                    </div>
                  </div>

                  {/* Gender */}
                  <div className="bg-gray-50 rounded-xl p-4">
                    <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
                      Gender
                    </label>
                    <select
                      value={profile.gender || ''}
                      onChange={(e) => setProfile({ ...profile, gender: e.target.value })}
                      className="w-full bg-transparent text-sm outline-none cursor-pointer"
                      style={{ color: colors.primaryText }}
                    >
                      {GENDER_OPTIONS.map((opt) => (
                        <option key={opt.value} value={opt.value}>
                          {opt.label}
                        </option>
                      ))}
                    </select>
                  </div>

                  {/* Height */}
                  <div className="bg-gray-50 rounded-xl p-4">
                    <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
                      Height
                    </label>
                    <div className="flex items-center gap-3">
                      <div className="flex items-center gap-2">
                        <input
                          type="number"
                          min="3"
                          max="8"
                          value={heightFeet}
                          onChange={(e) => setHeightFeet(parseInt(e.target.value) || 0)}
                          className="w-16 bg-white border border-gray-300 rounded-lg px-3 py-2 text-sm text-center"
                          style={{ color: colors.primaryText }}
                        />
                        <span className="text-sm" style={{ color: colors.secondaryText }}>ft</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <input
                          type="number"
                          min="0"
                          max="11"
                          value={heightInches}
                          onChange={(e) => setHeightInches(parseInt(e.target.value) || 0)}
                          className="w-16 bg-white border border-gray-300 rounded-lg px-3 py-2 text-sm text-center"
                          style={{ color: colors.primaryText }}
                        />
                        <span className="text-sm" style={{ color: colors.secondaryText }}>in</span>
                      </div>
                    </div>
                  </div>

                  {/* Weight */}
                  <div className="bg-gray-50 rounded-xl p-4">
                    <label className="block text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
                      Weight
                    </label>
                    <div className="flex items-center gap-2">
                      <input
                        type="number"
                        min="50"
                        max="500"
                        value={profile.currentWeight || ''}
                        onChange={(e) => setProfile({ ...profile, currentWeight: parseInt(e.target.value) || undefined })}
                        placeholder="Enter weight"
                        className="w-24 bg-white border border-gray-300 rounded-lg px-3 py-2 text-sm"
                        style={{ color: colors.primaryText }}
                      />
                      <span className="text-sm" style={{ color: colors.secondaryText }}>lbs</span>
                    </div>
                  </div>
                </div>

                {/* Save Button */}
                <button
                  onClick={handleSave}
                  disabled={saving || loading}
                  className="w-full py-3 rounded-xl font-medium text-white transition-colors disabled:opacity-50"
                  style={{ backgroundColor: colors.accentBlue }}
                >
                  {saving ? (
                    <Loader2 className="w-5 h-5 animate-spin mx-auto" />
                  ) : (
                    'Save Changes'
                  )}
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
