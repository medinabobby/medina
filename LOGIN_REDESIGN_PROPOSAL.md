# Login Redesign Proposal

**Created:** December 29, 2025
**Status:** Approved, ready to implement

---

## Overview

Redesign the iOS login screen to match modern best practices (Claude-style), replace insecure beta email/password with magic links, and add developer bypass for simulator testing.

---

## Current Problems

1. **UI Layout Issues:**
   - Username/Email + Password forms too prominent
   - "New user? Sign up" awkwardly placed below Continue button
   - Apple/Google social buttons buried at bottom
   - "Reset Workout Progress" doesn't belong on login screen

2. **Security Issues:**
   - Beta email/password stores passwords in plain text
   - No proper hashing (bcrypt) or secure storage

3. **Testing Issues:**
   - Can't test in simulator without Firebase Auth
   - No dev/test user bypass

---

## Target Design

Inspired by Claude's login screen:

```
┌─────────────────────────────────────┐
│         🏋️ DISTRICT                │
│                                     │
│   Your AI-powered fitness coach     │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  G  Continue with Google    │   │  ← Most users (one tap)
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │  🍎 Continue with Apple     │   │  ← Required by App Store
│  └─────────────────────────────┘   │
│                                     │
│  ──────────── OR ────────────      │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Personal or work email      │   │  ← Magic link (no password)
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │      Continue with Email    │   │
│  └─────────────────────────────┘   │
│                                     │
│  By continuing, you agree to our   │
│  Terms of Service and Privacy      │
│                                     │
│  #if DEBUG                         │
│  [ 🔧 Dev Login ]                  │  ← Hidden in release builds
│  #endif                            │
└─────────────────────────────────────┘
```

---

## Authentication Methods

### Primary: Social Login (Google + Apple)
- **Already implemented** with Firebase Auth
- One-tap sign in for most users
- Apple required by App Store if other social logins present

### Secondary: Magic Links (Email)
- User enters email → Firebase sends link → User clicks → Signed in
- **No passwords** to store, hash, or leak
- Works for any email domain (.edu, work, personal)
- Firebase handles everything (free tier: 10K emails/month)
- Same approach as Claude, Slack, Notion

### Development: Dev Bypass
- DEBUG builds only (not in production)
- Instant login as test user
- No Firebase Auth required in simulator

---

## Implementation Phases

### Phase 1: Login UI Redesign (2-3 hours)
- Remove username/password fields
- Remove "New user? Sign up" link
- Remove "Stay logged in" toggle
- Move Apple/Google buttons to top
- Add "OR" divider
- Add email field + "Continue with Email" button
- Add Terms/Privacy links
- Add Dev Login button (DEBUG only)

### Phase 2: Magic Link Auth (2-3 hours)
- Add `sendMagicLink()` to FirebaseAuthService
- Configure Firebase Console for Email Link sign-in
- Handle deep links in MedinaApp.swift
- Configure URL scheme in Info.plist

### Phase 3: Cleanup (30 min)
- Remove `AuthenticationService.swift` (beta code)
- Remove `passwordHash` field handling
- Move "Reset Workout Progress" to Settings

---

## Files to Modify

| File | Changes |
|------|---------|
| `ios/Medina/UI/Screens/LoginView.swift` | Complete redesign |
| `ios/Medina/Services/Firebase/FirebaseAuthService.swift` | Add magic link methods |
| `ios/Medina/MedinaApp.swift` | Handle deep links |
| `ios/Medina/Info.plist` | URL scheme for magic links |
| `ios/Medina/Services/Core/AuthenticationService.swift` | DELETE |

---

## Firebase Console Setup Required

1. **Authentication → Sign-in method:**
   - Enable "Email/Password"
   - Enable "Email link (passwordless sign-in)"

2. **Authentication → Authorized domains:**
   - Add: `district.fitness`

3. **Dynamic Links:**
   - Create link: `https://district.fitness/auth`

---

## Estimated Effort

| Task | Time |
|------|------|
| Login UI redesign | 2-3 hours |
| Magic link implementation | 2-3 hours |
| Dev bypass button | 30 min |
| Cleanup beta code | 30 min |
| **Total** | **5-6 hours** |

---

## Deferred Items

The following are tracked in ROADMAP.md backlog:

- **.edu student free tier** - Auto-detect .edu emails and apply student tier
- **Payment tiers** - Subscription/payment integration
- **Phone/SMS OTP** - Alternative auth method (has per-SMS cost)
