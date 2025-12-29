# Medina Roadmap

**Last Updated:** December 29, 2025

---

## Current Status

| Platform | Version | Status |
|----------|---------|--------|
| iOS | v212 | TestFlight |
| Web | v212 | Production |
| Backend | v212 | 19/23 handlers |

---

## Handler Migration Progress

**19 of 23 handlers complete (83%)**

### Complete

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

### Remaining (4 handlers)

| Handler | Complexity | Notes |
|---------|------------|-------|
| `modify_workout` | High | Edit workout in progress - complex state mutations |
| `change_protocol` | Medium | Swap exercise protocols |
| `analyze_training_data` | High | Charts, analytics, many edge cases |
| `create_custom_workout` | Medium | Free-form workout builder |

---

## Platform Features

### iOS
- Full workout execution with voice mode
- Apple Health integration
- Workout history and analytics
- Plan management

### Web
- Chat interface with AI coach
- Workout/plan creation via chat
- Sidebar with plans, workouts, library
- Google Sign-in (Apple Sign-in pending)

### Parity Status

| Feature | iOS | Web |
|---------|-----|-----|
| Create workout | Yes | Yes |
| Create plan | Yes | Yes |
| Start/end workout | Yes | Yes |
| Workout execution UI | Yes | No |
| Voice mode | Yes | No |
| Apple Health | Yes | N/A |
| View schedule | Yes | Yes |
| Message trainer | Yes | Yes |

---

## Next Priorities

1. **Remaining handlers** - `modify_workout`, `change_protocol`, `analyze_training_data`, `create_custom_workout`
2. **Apple Sign-in for web** - Firebase Console configuration needed
3. **Web workout execution UI** - Start workout from card, log sets

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

## Architecture

```
iOS App ───┐
           ├──► Firebase Functions ──► OpenAI API
Web App ───┘         │
                     └── Firestore (shared data)
```

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
- [docs/](docs/) - API reference, data models
