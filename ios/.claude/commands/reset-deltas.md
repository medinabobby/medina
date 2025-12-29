---
description: Clear all persisted workout and set deltas from UserDefaults for a fresh start
---

Please perform the following diagnostic and cleanup sequence:

1. **Show Current Delta State**:
   - Call `DeltaStore.shared.getDeltaSummary()` to show how many deltas are currently stored
   - This helps confirm what will be cleared

2. **Clear All Deltas**:
   - Call `DeltaStore.shared.clearAllDeltas()` to remove all workout and set deltas for the current app version
   - Call `OnboardingState.reset()` to clear onboarding dismissed state and reminder timestamps
   - This resets the app to use only the base JSON data

3. **Verification**:
   - Explain that the user needs to restart the app or re-login to see the clean state
   - The next time workouts are loaded, they will reflect only the data in `workouts.json` and `sets.json`
   - No persisted deltas will be applied

4. **Expected Outcome**:
   - All workouts will match their JSON completion states exactly
   - No conflicting "Complete" badges on future workouts
   - Full schedule visible with correct dates

**Note**: This only clears deltas for the current app version (v\(DeltaStore.shared.currentVersion)). To clear deltas across ALL versions, use `DeltaStore.shared.clearAllVersions()` instead.
