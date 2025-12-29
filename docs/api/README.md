# Medina API Reference

**Last updated:** December 28, 2025
**Base URL:** `https://us-central1-medina-fitness.cloudfunctions.net/`

---

## Authentication

All authenticated endpoints require a Firebase ID token in the Authorization header:

```
Authorization: Bearer <firebase-id-token>
```

---

## Endpoints

### GET `/hello`

Health check endpoint.

**Response:**
```json
{
  "message": "Hello from Medina!",
  "timestamp": "2025-12-28T12:00:00.000Z"
}
```

---

### GET `/getUser`

Get or create user profile.

**Headers:**
- `Authorization: Bearer <token>` (required)

**Response:**
```json
{
  "uid": "user-id",
  "email": "user@example.com",
  "displayName": "John Doe",
  "profile": { ... },
  "createdAt": "2025-12-28T12:00:00.000Z",
  "updatedAt": "2025-12-28T12:00:00.000Z"
}
```

---

### POST `/chat`

AI chat endpoint with OpenAI streaming.

**Headers:**
- `Authorization: Bearer <token>` (required)
- `Content-Type: application/json`

**Request Body:**
```json
{
  "messages": [
    { "role": "user", "content": "Show me my schedule" }
  ],
  "previousResponseId": "resp_xxx"  // optional, for conversation continuity
}
```

**Tool Continuation Mode:**
```json
{
  "previousResponseId": "resp_xxx",
  "toolOutputs": [
    {
      "call_id": "call_xxx",
      "output": "{ \"result\": \"success\" }"
    }
  ]
}
```

**Response:** Server-Sent Events (SSE) stream

```
event: response.created
data: {"type":"response.created","response":{"id":"resp_xxx"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"Hello"}

event: response.completed
data: {"type":"response.completed"}
```

**Custom Events:**
- `suggestion_chips` - Quick action buttons from server handlers

---

## Server Handlers

Tools progressively moving from iOS to server:

| Tool | Status | Description |
|------|--------|-------------|
| `show_schedule` | Server | Query workout schedule |
| `update_profile` | Server | Update user profile fields |
| `skip_workout` | Server | Mark workout as skipped |
| `suggest_options` | Server | Return suggestion chips |
| `create_workout` | Ready | Full workout creation (pending deploy) |

### show_schedule

**Arguments:**
```json
{
  "period": "week" | "month"
}
```

**Returns:** Formatted workout schedule with suggestion chips.

### update_profile

**Arguments:**
```json
{
  "birthdate": "1990-01-15",
  "currentWeight": 175,
  "heightInches": 70,
  "experienceLevel": "intermediate",
  "goal": "strength"
}
```

**Returns:** Confirmation of updated fields.

### skip_workout

**Arguments:**
```json
{
  "workoutId": "workout-uuid",
  "reason": "feeling tired"
}
```

**Returns:** Confirmation with next scheduled workout info.

### suggest_options

**Arguments:**
```json
{
  "options": [
    { "label": "Start workout", "command": "Start my workout" },
    { "label": "Show schedule", "command": "Show me my schedule" }
  ]
}
```

**Returns:** Suggestion chips for UI.

---

## Admin Endpoints

Protected by `x-seed-secret` header. For development only.

### POST `/seedExercises`

Seed exercises to Firestore.

### POST `/seedProtocols`

Seed training protocols.

### POST `/seedGyms`

Seed gym data.

---

## Error Responses

```json
{
  "error": "Error message"
}
```

| Status | Meaning |
|--------|---------|
| 400 | Bad request (missing/invalid params) |
| 401 | Unauthorized (invalid/missing token) |
| 405 | Method not allowed |
| 500 | Internal server error |

---

## SSE Event Types

| Event | Description |
|-------|-------------|
| `response.created` | New response started |
| `response.output_item.added` | New output item (text or tool call) |
| `response.output_text.delta` | Text token streamed |
| `response.function_call_arguments.delta` | Tool arguments streaming |
| `response.function_call_arguments.done` | Tool arguments complete |
| `response.output_item.done` | Output item finished |
| `response.completed` | Response finished |
| `suggestion_chips` | Custom: Suggestion chips from server handler |
