/**
 * Update Profile Handler
 *
 * Saves user profile information extracted from conversation.
 * Merges updates into existing profile - only provided fields are updated.
 */

import {HandlerContext, HandlerResult} from "./index";

// Profile fields that can be updated
const PROFILE_FIELDS = [
  "birthdate",
  "gender",
  "heightInches",
  "currentWeight",
  "fitnessGoal",
  "personalMotivation",
  "experienceLevel",
  "preferredDays",
  "sessionDuration",
] as const;

/**
 * Handle update_profile tool call
 *
 * @param args - Profile fields to update (all optional)
 * @param context - Handler context with uid and db
 * @returns Success message listing updated fields
 */
export async function updateProfileHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;

  // Build update object with only provided fields
  const updates: Record<string, unknown> = {};
  const updatedFields: string[] = [];

  for (const field of PROFILE_FIELDS) {
    if (args[field] !== undefined && args[field] !== null) {
      updates[field] = args[field];
      updatedFields.push(formatFieldName(field));
    }
  }

  if (updatedFields.length === 0) {
    return {
      output: "No profile fields provided to update.",
    };
  }

  // Merge into user document
  await db.collection("users").doc(uid).set(
    {
      profile: updates,
      updatedAt: new Date().toISOString(),
    },
    {merge: true}
  );

  const fieldList = updatedFields.join(", ");

  return {
    output: `SUCCESS: Profile updated.
Fields changed: ${fieldList}

INSTRUCTIONS:
1. Acknowledge what you learned about the user
2. If schedule and duration are set, you can proceed to create a plan
3. If schedule or duration are NOT set, ask for them before creating a plan
4. Keep response conversational and brief`,
  };
}

/**
 * Format camelCase field name for display
 */
function formatFieldName(field: string): string {
  switch (field) {
  case "heightInches":
    return "height";
  case "currentWeight":
    return "weight";
  case "fitnessGoal":
    return "fitness goal";
  case "personalMotivation":
    return "motivation";
  case "experienceLevel":
    return "experience level";
  case "preferredDays":
    return "training schedule";
  case "sessionDuration":
    return "session duration";
  default:
    return field;
  }
}
