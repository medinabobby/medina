# Firestore Security Rules Proposal

**Created:** January 1, 2026 | **Status:** Pending Implementation

> Reference document for production security rules. Current rules are development-only.

---

## Current State (CRITICAL)

**File:** `web/firestore.rules`

```firestore-rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Development mode: allow all reads/writes
    // TODO: Lock down before production
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

**Vulnerabilities:**
- User A can read/write User B's data
- No protection for global catalogs
- No messaging security

---

## Data Structure

| Path | Ownership | Access |
|------|-----------|--------|
| `users/{uid}/**` | User-scoped | Owner only |
| `users/{uid}/plans/{planId}/**` | User-scoped | Owner only |
| `users/{uid}/workouts/{workoutId}/**` | User-scoped | Owner only |
| `users/{uid}/targets/{exerciseId}` | User-scoped | Owner only |
| `users/{uid}/preferences/exercise` | User-scoped | Owner only |
| `exercises/{id}` | Global catalog | Read-only |
| `protocols/{id}` | Global catalog | Read-only |
| `gyms/{id}` | Global catalog | Read-only |
| `messages/{id}` | Cross-user | Sender/recipient only |
| `threads/{id}` | Cross-user | Participants only |

---

## Proposed Production Rules

```firestore-rules
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // === HELPER FUNCTIONS ===
    function isAuthenticated() {
      return request.auth != null;
    }

    function isOwner(uid) {
      return request.auth.uid == uid;
    }

    // === USER-SCOPED DATA ===
    match /users/{uid} {
      allow read, write: if isOwner(uid);

      // Plans and nested programs
      match /plans/{planId} {
        allow read, write: if isOwner(uid);

        match /programs/{programId} {
          allow read, write: if isOwner(uid);
        }
      }

      // Workouts and nested instances/sets
      match /workouts/{workoutId} {
        allow read, write: if isOwner(uid);

        match /exerciseInstances/{instanceId} {
          allow read, write: if isOwner(uid);

          match /sets/{setId} {
            allow read, write: if isOwner(uid);
          }
        }
      }

      // Targets, preferences, library, conversations, sessions
      match /{subcollection}/{docId} {
        allow read, write: if isOwner(uid);
      }
    }

    // === GLOBAL CATALOGS (Read-only) ===
    match /exercises/{exerciseId} {
      allow read: if isAuthenticated();
      allow write: if false; // Admin SDK only
    }

    match /protocols/{protocolId} {
      allow read: if isAuthenticated();
      allow write: if false;
    }

    match /gyms/{gymId} {
      allow read: if isAuthenticated();
      allow write: if false;
    }

    // === CROSS-USER MESSAGING ===
    match /messages/{messageId} {
      allow create: if isAuthenticated() &&
                      request.resource.data.senderId == request.auth.uid;
      allow read: if isAuthenticated() &&
                    (resource.data.senderId == request.auth.uid ||
                     resource.data.recipientId == request.auth.uid);
      allow update, delete: if isAuthenticated() &&
                               resource.data.senderId == request.auth.uid;
    }

    match /threads/{threadId} {
      allow create: if isAuthenticated();
      allow read, update: if isAuthenticated() &&
                            request.auth.uid in resource.data.participantIds;
    }

    // === DENY ALL OTHER PATHS ===
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

---

## Implementation Steps

1. **Backup current rules**
   ```bash
   cp web/firestore.rules web/firestore.rules.dev
   ```

2. **Replace with production rules**

3. **Test with emulator**
   ```bash
   cd web
   firebase emulators:start --only firestore
   ```

4. **Test in Firebase Console** (Rules Playground)

5. **Deploy**
   ```bash
   firebase deploy --only firestore:rules
   ```

---

## Testing Checklist

| Test Case | Expected |
|-----------|----------|
| User reads own profile | Allow |
| User reads other user's profile | Deny |
| User reads exercises catalog | Allow |
| User writes to exercises catalog | Deny |
| User reads own workouts | Allow |
| User reads other user's workouts | Deny |
| Sender reads own message | Allow |
| Recipient reads message | Allow |
| Third party reads message | Deny |

---

## Design Decisions

- **Messaging:** Sender/recipient only (no special trainer access)
- **Global catalogs:** Read-only for all authenticated users, write via Admin SDK only
- **Deny-all fallback:** Any undefined paths are blocked
