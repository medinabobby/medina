# Medina

AI-powered fitness coach with iOS and web clients sharing a Firebase backend.

## Structure

```
medina/
├── ios/           # iOS app (SwiftUI)
├── web/           # Web app (Next.js) + Firebase Functions
├── docs/          # Shared documentation
├── ARCHITECTURE.md
├── ROADMAP.md
└── TESTING.md
```

## Quick Start

### Web
```bash
cd web
npm install
npm run dev
```

### iOS
Open `ios/Medina.xcodeproj` in Xcode.

### Backend (Firebase Functions)
```bash
cd web/functions
npm install
npm run build
firebase deploy --only functions
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System design
- [ROADMAP.md](ROADMAP.md) - Migration status, priorities
- [TESTING.md](TESTING.md) - Test strategy

## Deployment

- **Web:** https://medinaintelligence.web.app
- **iOS:** TestFlight
