/**
 * Initial Chips API endpoint
 *
 * Returns context-aware suggestion chips for chat initialization.
 * Replaces iOS GreetingContextBuilder - single source of truth for all clients.
 *
 * GET /api/initialChips
 * Response: { chips: [{label, command}], greeting: string }
 */

import {onRequest} from "firebase-functions/v2/https";

// Lazy-loaded admin module
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminModule: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminApp: any = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getAdmin(): any {
  if (!adminModule) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    adminModule = require("firebase-admin");
  }
  if (!adminApp) {
    if (adminModule.apps.length === 0) {
      adminApp = adminModule.initializeApp();
    } else {
      adminApp = adminModule.apps[0];
    }
  }
  return adminModule;
}

/**
 * Verify Firebase ID token and return uid
 */
async function verifyAuth(authHeader: string | undefined): Promise<string | null> {
  if (!authHeader?.startsWith("Bearer ")) {
    return null;
  }
  const token = authHeader.substring(7);
  try {
    const admin = getAdmin();
    const decoded = await admin.auth().verifyIdToken(token);
    return decoded.uid;
  } catch {
    return null;
  }
}

interface SuggestionChip {
  label: string;
  command: string;
}

interface UserProfile {
  role?: string;
  trainerId?: string;
  hasCompletedOnboarding?: boolean;
  displayName?: string;
  firstName?: string;
}

interface Plan {
  id: string;
  status: string;
  name: string;
  weightliftingDays: number;
  cardioDays: number;
}

interface Workout {
  id: string;
  status: string;
  scheduledDate?: {toDate: () => Date};
}

interface Session {
  id: string;
  status: string;
  workoutId: string;
}

/**
 * Build time-of-day greeting
 */
function buildGreeting(name: string | undefined): string {
  const hour = new Date().getHours();
  const displayName = name || "there";

  if (hour >= 5 && hour < 12) {
    return `Morning, ${displayName}. What's on the agenda today?`;
  } else if (hour >= 12 && hour < 17) {
    return `Afternoon, ${displayName}. Ready to train?`;
  } else if (hour >= 17 && hour < 21) {
    return `Evening, ${displayName}. Time to get after it?`;
  } else {
    return `Night owl session, ${displayName}. Let's make it count.`;
  }
}

/**
 * Build member suggestion chips based on context
 */
function buildMemberChips(
  activePlan: Plan | null,
  todaysWorkout: Workout | null,
  nextWorkout: Workout | null,
  inProgressWorkout: Workout | null,
  hasTrainer: boolean
): SuggestionChip[] {
  const chips: SuggestionChip[] = [];

  // Priority 1: Continue in-progress workout
  if (inProgressWorkout) {
    chips.push({
      label: "Continue workout",
      command: "Continue my workout",
    });
  }

  // Priority 2: Start today's scheduled workout
  if (!inProgressWorkout && todaysWorkout) {
    chips.push({
      label: "Start today's workout",
      command: "Start my workout",
    });
  } else if (!inProgressWorkout && !todaysWorkout && nextWorkout) {
    // Priority 2b: Start next scheduled workout (if no workout today)
    chips.push({
      label: "Start next workout",
      command: "Start my workout",
    });
  }

  // Priority 3: Message trainer
  if (hasTrainer) {
    chips.push({
      label: "Message trainer",
      command: "Send a message to my trainer",
    });
  }

  // General options
  chips.push({
    label: "Create workout",
    command: "Create a workout for me",
  });

  chips.push({
    label: "Analyze progress",
    command: "Analyze my training progress",
  });

  // Only show "Create plan" if user doesn't have an active plan
  if (!activePlan) {
    chips.push({
      label: "Create plan",
      command: "Help me create a training plan",
    });
  }

  return chips;
}

/**
 * Build new user suggestion chips
 */
function buildNewUserChips(hasCompletedOnboarding: boolean): SuggestionChip[] {
  const chips: SuggestionChip[] = [];

  // Priority 1: Create a workout (immediate value)
  chips.push({
    label: "Create a workout",
    command: "Create a workout for me",
  });

  // Priority 2: Create a training plan (structured approach)
  chips.push({
    label: "Create a training plan",
    command: "Help me create a training plan",
  });

  // Priority 3: Complete profile (helps AI give better recommendations)
  if (!hasCompletedOnboarding) {
    chips.push({
      label: "Complete my profile",
      command: "Help me complete my profile",
    });
  }

  return chips;
}

/**
 * Build trainer suggestion chips
 */
function buildTrainerChips(hasMember: boolean): SuggestionChip[] {
  const chips: SuggestionChip[] = [];

  // Member management
  if (hasMember) {
    chips.push({
      label: "Create member plan",
      command: "Help me create a training plan for one of my members",
    });

    chips.push({
      label: "Message member",
      command: "Send a message to one of my members",
    });
  }

  // View class schedule
  chips.push({
    label: "View schedule",
    command: "Show me the class schedule for this week",
  });

  // General fitness questions
  chips.push({
    label: "Ask a question",
    command: "I have a question about training",
  });

  return chips;
}

// MARK: - Main Endpoint

export const initialChips = onRequest(
  {cors: true, invoker: "public"},
  async (req, res) => {
    // Auth check
    const uid = await verifyAuth(req.headers.authorization);
    if (!uid) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    if (req.method !== "GET" && req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      const admin = getAdmin();
      const db = admin.firestore();

      // 1. Get user profile
      const userDoc = await db.collection("users").doc(uid).get();
      const userProfile = userDoc.exists ? (userDoc.data() as UserProfile) : {};

      const role = userProfile.role || "member";
      const hasTrainer = !!userProfile.trainerId;
      const hasCompletedOnboarding = userProfile.hasCompletedOnboarding ?? false;
      const displayName = userProfile.firstName || userProfile.displayName;

      // 2. Build greeting
      const greeting = buildGreeting(displayName);

      // 3. Get context data for members
      let chips: SuggestionChip[] = [];

      if (role === "trainer") {
        // Check if trainer has members
        const membersSnapshot = await db
          .collection("users")
          .where("trainerId", "==", uid)
          .limit(1)
          .get();
        const hasMember = !membersSnapshot.empty;

        chips = buildTrainerChips(hasMember);
      } else {
        // Member or new user
        const now = new Date();
        const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const endOfDay = new Date(startOfDay.getTime() + 24 * 60 * 60 * 1000);

        // Get active plan
        const plansSnapshot = await db
          .collection("users")
          .doc(uid)
          .collection("plans")
          .where("status", "==", "active")
          .limit(1)
          .get();
        const activePlan = plansSnapshot.empty ? null : (plansSnapshot.docs[0].data() as Plan);

        // Get active session (in-progress workout)
        const sessionsSnapshot = await db
          .collection("users")
          .doc(uid)
          .collection("sessions")
          .where("status", "==", "active")
          .limit(1)
          .get();
        const activeSession = sessionsSnapshot.empty ? null : (sessionsSnapshot.docs[0].data() as Session);

        let inProgressWorkout: Workout | null = null;
        if (activeSession) {
          const workoutDoc = await db
            .collection("users")
            .doc(uid)
            .collection("workouts")
            .doc(activeSession.workoutId)
            .get();
          if (workoutDoc.exists) {
            inProgressWorkout = {id: workoutDoc.id, ...workoutDoc.data()} as Workout;
          }
        }

        // Get today's scheduled workout
        const todaysWorkoutsSnapshot = await db
          .collection("users")
          .doc(uid)
          .collection("workouts")
          .where("status", "==", "scheduled")
          .where("scheduledDate", ">=", startOfDay)
          .where("scheduledDate", "<", endOfDay)
          .limit(1)
          .get();
        const todaysWorkout = todaysWorkoutsSnapshot.empty
          ? null
          : ({id: todaysWorkoutsSnapshot.docs[0].id, ...todaysWorkoutsSnapshot.docs[0].data()} as Workout);

        // Get next scheduled workout (if no workout today)
        let nextWorkout: Workout | null = null;
        if (!todaysWorkout) {
          const upcomingWorkoutsSnapshot = await db
            .collection("users")
            .doc(uid)
            .collection("workouts")
            .where("status", "==", "scheduled")
            .where("scheduledDate", ">=", now)
            .orderBy("scheduledDate", "asc")
            .limit(1)
            .get();
          nextWorkout = upcomingWorkoutsSnapshot.empty
            ? null
            : ({id: upcomingWorkoutsSnapshot.docs[0].id, ...upcomingWorkoutsSnapshot.docs[0].data()} as Workout);
        }

        // Determine if new user (no workouts at all)
        const anyWorkoutsSnapshot = await db
          .collection("users")
          .doc(uid)
          .collection("workouts")
          .limit(1)
          .get();
        const isNewUser = anyWorkoutsSnapshot.empty;

        if (isNewUser) {
          chips = buildNewUserChips(hasCompletedOnboarding);
        } else {
          chips = buildMemberChips(activePlan, todaysWorkout, nextWorkout, inProgressWorkout, hasTrainer);
        }
      }

      res.json({
        success: true,
        greeting,
        chips,
      });
    } catch (error) {
      console.error("[initialChips] Error:", error);
      res.status(500).json({error: "Internal server error"});
    }
  }
);
