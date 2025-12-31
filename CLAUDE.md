# Medina

AI fitness coach with iOS and web clients sharing a Firebase backend.

## Vision

**Server-first, dumb clients.** All business logic lives on Firebase Functions. Clients are thin UI layers that display data from Firestore, send user actions to server, and render responses.

## Architecture

```
iOS App ───┐
           ├──► Firebase Functions ──► OpenAI API
Web App ───┘         │
                     └── Firestore (shared data)
```

### Service Layer (Firebase Functions)

| Category | Endpoints |
|----------|-----------|
| AI Services | `/api/chat`, `/api/tts`, `/api/vision`, `/api/chatSimple` |
| Workout Services | `/api/calculate`, `/api/selectExercises` |
| Data Services | `/api/import`, `/api/initialChips`, plan endpoints |
| Tool Handlers | 22 AI-invokable tools (`web/functions/src/tools/`) |

### Client Layer

| Platform | Role | Key Features |
|----------|------|--------------|
| iOS | UI shell + workout execution | SwiftUI, voice mode, Apple Health |
| Web | Chat UI + data views | Next.js, React components |

## Key Files

| Purpose | Path |
|---------|------|
| Chat endpoint | `web/functions/src/index.ts` |
| Tool registry | `web/functions/src/tools/index.ts` |
| Tool definitions | `web/functions/src/tools/definitions.ts` |
| API endpoints | `web/functions/src/api/` |
| iOS services | `ios/Medina/Services/` (75 files) |
| Web client | `web/lib/`, `web/components/` |

## Data Flow

```
Server creates data → Firestore → Client reads via listener → UI renders
```

Clients never create authoritative data. Server writes to Firestore, clients read.

## Development Guidelines

### Cross-Client Verification (v235)

**Always verify changes across both iOS and web clients.**

When fixing bugs or implementing features:
1. Check if the change affects shared behavior (data display, status colors, API calls)
2. Implement the fix on BOTH platforms if needed
3. Test on both iOS simulator and web browser

Common areas requiring cross-client sync:
- **Status colors** - Both platforms must use same color scheme (see `StatusHelpers.swift` and `colors.ts`)
- **Sidebar/navigation refresh** - When data is created via chat, both platforms need to refresh
- **Entity actions** - Available actions should match across platforms (delete, activate, etc.)
- **API token handling** - Both platforms should get tokens on-demand, not rely on cached state

Files to check for parity:
| Feature | iOS | Web |
|---------|-----|-----|
| Status colors | `StatusHelpers.swift`, `SelectablePlansFolder.swift` | `lib/colors.ts` |
| Entity actions | `EntityActionProvider.swift` | `PlanDetailModal.tsx` |
| Sidebar refresh | `ChatViewModel.swift` | `Sidebar.tsx`, `ChatLayout.tsx` |
| API auth | `FirebaseAPIClient.swift` | Uses `getIdToken()` directly |

## Current Version

v235
