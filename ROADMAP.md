# Medina Roadmap

**Last Updated:** December 29, 2025

---

## Current Status

| Platform | Version | Status |
|----------|---------|--------|
| iOS | v213 | TestFlight (passthrough client) |
| Web | v212 | Production |
| Backend | v212 | **22/22 handlers complete** |

---

## Handler Migration Progress

**22 of 22 handlers complete (100%)**

All tool handlers now run on Firebase Functions. iOS is a pure passthrough client.

### Complete (All Phases)

| Phase | Handler | Description |
|-------|---------|-------------|
| 0 | `show_schedule` | Query and display workout schedule |
| 0 | `update_profile` | Update user profile fields |
| 0 | `skip_workout` | Mark workout as skipped |
| 0 | `suggest_options` | Return suggestion chips |
| 0 | `delete_plan` | Delete plan and associated workouts |
| 1 | `reset_workout` | Clear workout set data |
| 1 | `activate_plan` | Set plan as active |
| 1 | `abandon_plan` | Cancel a plan |
| 1 | `start_workout` | Begin workout session |
| 1 | `end_workout` | Complete workout session |
| 1 | `create_workout` | Create single workout |
| 1 | `create_plan` | Create multi-week plan |
| 2 | `add_to_library` | Add exercise to user library |
| 2 | `remove_from_library` | Remove exercise from library |
| 2 | `update_exercise_target` | Save 1RM/working weight |
| 2 | `get_substitution_options` | Suggest exercise substitutes |
| 2 | `get_summary` | Workout/plan summary |
| 2 | `send_message` | Create message with threading |
| 2 | `reschedule_plan` | Update plan schedule |
| 3 | `modify_workout` | Edit workout parameters |
| 3 | `change_protocol` | Swap exercise protocols |
| 3 | `analyze_training_data` | Training analytics (text MVP) |

---

## Platform Features

### iOS
- Pure passthrough client (all logic on server)
- Claude-style login (Google, Apple, magic link email)
- Full workout execution with voice mode
- Apple Health integration
- Workout history and analytics
- Plan management

### Web
- Chat interface with AI coach
- Workout/plan creation via chat
- Sidebar with plans, workouts, library
- Google and Apple Sign-in

### Parity Status

| Feature | iOS | Web |
|---------|-----|-----|
| Create workout | Yes | Yes |
| Create plan | Yes | Yes |
| Start/end workout | Yes | Yes |
| Modify workout | Yes | Yes |
| Change protocol | Yes | Yes |
| Training analytics | Yes | Yes (text) |
| Workout execution UI | Yes | No |
| Voice mode | Yes | No |
| Apple Health | Yes | N/A |
| View schedule | Yes | Yes |
| Message trainer | Yes | Yes |

---

## Next Priorities

1. **Web workout execution UI** - Start workout from card, log sets
2. **Analytics charts** - Add visualization to analyze_training_data
3. **Delete AuthenticationService.swift** - Legacy beta code cleanup (unused)

---

## Future Features

| Feature | Priority | Notes |
|---------|----------|-------|
| Android app | High | After web parity |
| Web workout execution | High | Log sets, see progress |
| Apple Watch | Medium | Workout tracking companion |
| Push notifications | Medium | Workout reminders |
| Home Screen widgets | Low | iOS-specific |
| Siri Shortcuts | Low | iOS-specific |

---

## Backlog (Deferred)

| Feature | Notes |
|---------|-------|
| .edu student free tier | Auto-detect .edu emails, apply free tier on sign-up |
| Payment tiers | Stripe integration, subscription management |
| Phone/SMS OTP auth | Alternative auth method (~$0.01-0.05/SMS cost) |

## Recently Completed

| Feature | Date | Notes |
|---------|------|-------|
| Apple Sign-in for web | Dec 29 | Firebase Auth with Apple provider |
| iOS Login Redesign | Dec 29 | Claude-style UI, magic links, social auth at top |
| Web detail pages | Dec 29 | Right-side panel with Plan/Program/Workout/Exercise views |
| Handler migration | Dec 29 | All 22 handlers now on server (100%) |
| iOS parity fixes | Dec 29 | Chevrons, status colors, sidebar structure |

---

## Architecture

```
iOS App ───┐
           ├──► Firebase Functions ──► OpenAI API
Web App ───┘         │
                     └── Firestore (shared data)
```

Both clients are now "dumb" - all business logic runs on Firebase Functions.

See [ARCHITECTURE.md](ARCHITECTURE.md) for technical details.

---

## Deployment

### iOS
```bash
# Xcode → Product → Archive → Distribute App → TestFlight
```

### Web
```bash
cd web
npm run build
firebase deploy --only hosting
```

### Backend
```bash
cd web/functions
npm run build && npm test
firebase deploy --only functions
```

---

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design, data flow
- [TESTING.md](TESTING.md) - Test strategy
- [docs/archive/](docs/archive/) - Completed proposals
