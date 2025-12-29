# Medina Data Models

**Last updated:** December 28, 2025

Documentation for Firestore collections and shared data types.

---

## Firestore Collections

### `users/{uid}`

Root user document.

```typescript
interface User {
  uid: string;
  email: string;
  displayName: string;
  profile: UserProfile;
  role: 'member' | 'trainer' | 'admin' | 'gymOwner';
  gymId?: string;        // For gym members
  trainerId?: string;    // Assigned trainer
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

interface UserProfile {
  birthdate?: string;           // ISO date "1990-01-15"
  heightInches?: number;        // Height in inches
  currentWeight?: number;       // Weight in lbs
  fitnessGoal?: string;         // "strength" | "muscle" | "fatLoss" | "general"
  experienceLevel?: string;     // "beginner" | "intermediate" | "advanced"
  preferredDays?: string[];     // ["monday", "wednesday", "friday"]
  sessionDuration?: number;     // Preferred workout duration in minutes
  gender?: string;
  personalMotivation?: string;
}
```

---

### `users/{uid}/plans/{planId}`

Training plans for a user.

```typescript
interface Plan {
  id: string;
  name: string;
  goal: string;
  splitType: string;           // "fullBody" | "upperLower" | "pushPullLegs"
  isSingleWorkout: boolean;    // true for quick workouts
  startDate: string;           // ISO date
  endDate: string;
  trainingLocation: string;    // "gym" | "home"
  emphasizedMuscleGroups: string[];
  status: 'draft' | 'active' | 'completed' | 'abandoned';
  createdAt: Timestamp;
}
```

---

### `users/{uid}/plans/{planId}/programs/{programId}`

Training phases within a plan.

```typescript
interface Program {
  id: string;
  name: string;
  focus: TrainingFocus;
  startingIntensity: number;   // 0.0-1.0
  endingIntensity: number;
  progressionType: 'linear' | 'wave' | 'static';
  weekCount: number;
}

type TrainingFocus =
  | 'foundation'    // 60-70% intensity
  | 'development'   // 70-80% intensity
  | 'peak'          // 80-90% intensity
  | 'maintenance'   // 65-75% intensity
  | 'deload';       // 50-60% intensity
```

---

### `users/{uid}/workouts/{workoutId}`

Individual workout sessions.

```typescript
interface Workout {
  id: string;
  name: string;
  planId?: string;
  programId?: string;
  scheduledDate: string;       // ISO datetime
  splitDay: string;            // "push" | "pull" | "legs" | "upper" | "lower" | "fullBody"
  exerciseIds: string[];
  protocolVariantIds: { [exerciseIndex: number]: string };
  status: 'scheduled' | 'inProgress' | 'completed' | 'skipped';
  startedAt?: Timestamp;
  completedAt?: Timestamp;
}
```

---

### `users/{uid}/workouts/{workoutId}/instances/{instanceId}`

Exercise instances within a workout.

```typescript
interface ExerciseInstance {
  id: string;
  exerciseId: string;
  protocolVariantId: string;
  order: number;
  status: 'pending' | 'inProgress' | 'completed' | 'skipped';
}
```

---

### `users/{uid}/workouts/{workoutId}/instances/{instanceId}/sets/{setId}`

Individual sets within an exercise.

```typescript
interface ExerciseSet {
  id: string;
  setNumber: number;
  targetWeight: number;
  targetReps: number;
  actualWeight?: number;
  actualReps?: number;
  rpe?: number;                // 1-10 scale
  notes?: string;
  completedAt?: Timestamp;
}
```

---

### `users/{uid}/exerciseLibrary/{exerciseId}`

User's curated exercise collection.

```typescript
interface LibraryExercise {
  exerciseId: string;
  addedAt: Timestamp;
  notes?: string;
}
```

---

### `users/{uid}/exerciseTargets/{exerciseId}`

1RM and weight data per exercise.

```typescript
interface ExerciseTarget {
  exerciseId: string;
  estimated1RM: number;        // Calculated via Epley formula
  lastWeight: number;
  lastReps: number;
  updatedAt: Timestamp;
}
```

---

### `exercises/{exerciseId}` (Global)

Master exercise database.

```typescript
interface Exercise {
  id: string;
  name: string;
  category: 'compound' | 'isolation';
  primaryMuscles: string[];
  secondaryMuscles: string[];
  equipment: string[];         // ["barbell", "dumbbell", "cable"]
  movementPattern: string;     // "push" | "pull" | "squat" | "hinge"
  experienceLevel: string;     // "beginner" | "intermediate" | "advanced"
  instructions?: string;
}
```

---

### `protocols/{protocolId}` (Global)

Training protocol templates.

```typescript
interface ProtocolConfig {
  id: string;
  name: string;                // "3x5 Heavy"
  sets: number;
  reps: number | [number, number];  // Fixed or range
  restSeconds: number;
  intensityRange: [number, number]; // [0.65, 0.80]
  targetRPE: number;
  exerciseTypes: ('compound' | 'isolation')[];
  intensityAdjustments: number[];   // Per-set adjustments [0.0, 0.05, 0.10]
}
```

---

### `gyms/{gymId}` (Global)

Gym/facility data.

```typescript
interface Gym {
  id: string;
  name: string;
  location: string;
  equipment: string[];
  createdAt: Timestamp;
}
```

---

## Entity Hierarchy

```
Plan
 └── Program (1+)
      └── Workout (n per week)
           └── ExerciseInstance (n per workout)
                └── ExerciseSet (n per instance)
```

---

## Key Design Decisions

1. **Cloud-Only** - Firestore is the sole source of truth
2. **User-Scoped** - All user data under `users/{uid}/`
3. **Global Reference Data** - Exercises, protocols, gyms are shared
4. **Denormalized** - Workout contains exercise IDs, not nested objects
5. **Timestamp Handling** - ISO strings for iOS compatibility, Firestore Timestamps internally
