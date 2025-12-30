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

## Current Version

v232
