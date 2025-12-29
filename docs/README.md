# Medina Technical Documentation

**Last updated:** December 28, 2025

Technical reference documentation. For high-level docs, see root:
- **[ROADMAP.md](../ROADMAP.md)** - Version plan, priorities
- **[ARCHITECTURE.md](../ARCHITECTURE.md)** - System architecture

---

## Contents

| Document | Purpose |
|----------|---------|
| [API Reference](api/README.md) | Firebase Functions endpoints, request/response formats |
| [Data Models](data-models/README.md) | Firestore schema, TypeScript interfaces |
| [Development Guide](guides/DEVELOPMENT.md) | Cross-platform dev workflow, testing |

---

## Project Structure

```
medina/
├── ROADMAP.md              # Unified roadmap
├── ARCHITECTURE.md         # System architecture
├── docs/                   # Technical reference (this folder)
│   ├── api/                # API documentation
│   ├── data-models/        # Firestore schema
│   └── guides/             # Development guides
├── shared/                 # Cross-platform code
│   ├── types/              # Shared TypeScript types
│   └── constants/          # Shared configuration
├── ios/                    # iOS app (SwiftUI)
└── web/                    # Web app + Firebase Functions
    └── functions/          # Server-side handlers
```

---

## Shared Code

The `shared/` directory contains cross-platform TypeScript code:

### Types (`shared/types/index.ts`)

- User roles and profiles
- Workout/plan status enums
- Training focus and progression types
- Exercise categories and muscle groups

### Constants (`shared/constants/index.ts`)

- Intensity ranges by training focus
- Effort level mappings
- Protocol defaults
- Weight calculation constants

**Usage:**
```typescript
import { WorkoutStatus, TrainingFocus } from '../../shared/types';
import { INTENSITY_RANGES } from '../../shared/constants';
```
