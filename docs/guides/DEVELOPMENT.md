# Cross-Platform Development Guide

**Last updated:** December 28, 2025

How to work across the iOS and Web codebases.

---

## Project Layout

```
medina/
├── ios/                     # iOS app (SwiftUI)
│   ├── Medina/              # Source code
│   ├── docs/                # iOS-specific docs
│   └── Medina.xcodeproj/    # Xcode project
├── web/                     # Web app + Firebase Functions
│   ├── app/                 # Next.js pages
│   ├── components/          # React components
│   └── functions/           # Firebase Functions (TypeScript)
│       ├── src/
│       │   ├── handlers/    # Server-side tool handlers
│       │   ├── types/       # Shared types
│       │   └── prompts/     # AI system prompts
│       └── tests/
└── docs/                    # Shared documentation (this folder)
```

---

## Development Workflow

### iOS Development

```bash
cd ~/Desktop/medina/ios
open Medina.xcodeproj
```

**Key files:**
- `docs/ARCHITECTURE.md` - System design
- `docs/ROADMAP.md` - Version plan
- `docs/HANDOVER.md` - Session continuity

### Web/Functions Development

```bash
cd ~/Desktop/medina/web/functions

# Install dependencies
npm install

# Run tests in watch mode
npm test

# Single test run
npm run test:run

# Coverage report
npm run test:coverage

# Build
npm run build
```

---

## Server Handler Migration

Tools are moving from iOS (Swift) to Firebase Functions (TypeScript).

### Current Status

| Handler | Location | Status |
|---------|----------|--------|
| `show_schedule` | Server | Live |
| `update_profile` | Server | Live |
| `skip_workout` | Server | Live |
| `suggest_options` | Server | Live |
| `create_workout` | Server | Ready, pending deploy |
| 21 other tools | iOS | Passthrough mode |

### Adding a Server Handler

1. **Create handler file:** `functions/src/handlers/newTool.ts`

```typescript
import { HandlerContext, HandlerResult } from "./index";

export async function newToolHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const { uid, db } = context;

  // Validate args
  // Query/update Firestore
  // Return result

  return {
    output: "Result for AI to process",
    suggestionChips: [
      { label: "Next action", command: "Do something" }
    ]
  };
}
```

2. **Register in `handlers/index.ts`:**

```typescript
import { newToolHandler } from "./newTool";

const handlers: Record<string, HandlerFn> = {
  // ...existing
  new_tool: newToolHandler,
};
```

3. **Add tests:** `handlers/handlers.test.ts`

4. **Deploy:**

```bash
npm run build && npm test
firebase deploy --only functions
```

---

## Testing Strategy

### Unit Tests (Required)

```bash
npm test  # Watch mode
```

- Mock Firestore with `createMockDb()`
- Test handler logic in isolation
- Coverage target: 90%+

### Manual Testing (Critical for AI)

Unit tests verify handler logic, but NOT AI tool selection.

**After prompt changes, manually verify:**

| Say This | Expected Tool |
|----------|---------------|
| "I'm 30 years old" | `update_profile` |
| "Show my schedule" | `show_schedule` |
| "Skip today's workout" | `skip_workout` |
| "Create a push workout" | `create_workout` |

Check Firebase Functions logs for tool call verification.

---

## Deployment

### Functions

```bash
cd ~/Desktop/medina/web/functions
npm run build && npm test
firebase deploy --only functions
```

### iOS

1. Bump version in Xcode
2. Archive and upload to App Store Connect
3. Update `ios/docs/ROADMAP.md` with release notes

---

## Key Principles

1. **Server-First** - Prefer server handlers over iOS passthrough
2. **Test Before Deploy** - Always run `npm test` before deploying
3. **Manual AI Testing** - Verify tool selection after prompt changes
4. **Document Changes** - Update relevant docs after significant changes
5. **Cross-Platform Parity** - Same behavior on iOS and Web

---

## Common Tasks

### Run Functions Locally

```bash
cd ~/Desktop/medina/web/functions
npm run build
firebase emulators:start --only functions
```

### Check Firebase Logs

```bash
firebase functions:log --only chat
```

Or use Firebase Console > Functions > Logs

### Update System Prompt

Edit: `functions/src/prompts/systemPrompt.ts`

After changes:
1. Run tests: `npm test`
2. Deploy: `firebase deploy --only functions`
3. Manual test: Verify AI calls correct tools

---

## Troubleshooting

### "Tool not called"

AI chose not to call the tool. Check:
1. System prompt instructions
2. Tool description clarity
3. Manual test with explicit phrasing

### "Handler returned error"

Check handler logic:
1. Firestore query correctness
2. Argument validation
3. Error handling

### "Passthrough not working"

iOS didn't receive tool call. Check:
1. Event suppression logic in `index.ts`
2. `serverHandledItems` vs `passthroughToolCount`
