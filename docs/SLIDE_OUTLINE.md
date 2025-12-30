# Medina Technical Presentation - Slide Outline

Quick reference for building the PowerPoint deck.

---

## OPTION A: Condensed (6 Slides)

### Slide 1: Platform Overview
**Title:** Medina: AI Fitness Intelligence Platform
**Key Visual:** Two-box diagram (Backend 13K LOC, iOS 28K LOC)
**Stats:** 41K+ LOC, 9 endpoints, 22 handlers, 6 prompt modules

### Slide 2: Backend Intelligence
**Title:** 9 API Endpoints + 22 Tool Handlers
**Key Visual:** Table with endpoint/capabilities
**Message:** "Not 22 things — a complete fitness intelligence API"

### Slide 3: Algorithms
**Title:** What Powers the AI
**Key Visual:** Three formula boxes
- Recency-weighted 1RM
- Import intelligence pipeline
- Exercise selection scoring

### Slide 4: Prompt Engineering
**Title:** Dynamic Context Assembly
**Key Visual:** Tree diagram of prompt modules
**Stats:** 1,200+ LOC, 6 modules

### Slide 5: iOS Services
**Title:** 28,000 LOC Across 17 Domains
**Key Visual:** Directory tree
**Highlight:** Voice, WorkoutExecution, Calculations

### Slide 6: Summary
**Title:** By The Numbers
**Key Visual:** Stats table
**Message:** "Full fitness intelligence platform, not a chatbot"

---

## OPTION B: Full Version (14 Slides)

### Slide 1: Service Layer Overview
- Architecture diagram
- 41K+ LOC total

### Slide 2: API Endpoint Layer
- Table of 9 endpoints
- Complexity indicators

### Slide 3: Calculation Engine
- 5 algorithms with formulas
- Recency-weighted 1RM detail

### Slide 4: Import Pipeline
- 4-stage flow diagram
- Intelligence output example

### Slide 5: Exercise Selection
- Scoring algorithm
- Diversity/balance logic

### Slide 6: Prompt Engineering
- Module tree diagram
- 6 modules explained

### Slide 7: Tool Handlers
- 22 handlers by category
- What each does

### Slide 8: iOS Services
- 17 domains
- 91 Swift files

### Slide 9: iOS-Only Features
- Voice, HealthKit, etc.
- Why they stay on client

### Slide 10: Request Flow
- End-to-end diagram
- User → Response

### Slide 11: Migration Status
- Server vs iOS split
- 100% handlers on server

### Slide 12: Technical Summary
- Full stats table
- All metrics

### Slide 13: Competitive Diff
- vs Generic apps
- vs "AI-powered" apps

### Slide 14: Technical Moat
- Time to replicate
- Component breakdown

---

## KEY VISUALS TO CREATE

### 1. System Architecture
```
iOS + Web → Firebase Backend → OpenAI + Firestore
```

### 2. Request Flow
```
User → Auth → Context → OpenAI → Handler → Response
```

### 3. Import Pipeline
```
CSV → Parse → Match → Analyze → Persist
```

### 4. Prompt Assembly Tree
```
System Prompt
├── Base Identity
├── User Context
├── Training Data
├── Core Rules
├── Tool Instructions
└── Examples
```

### 5. Service Layer Breakdown
```
Backend (13K LOC)          iOS (28K LOC)
├── API Layer              ├── Voice
├── Handlers               ├── Execution
├── Prompts                ├── Calculations
└── Types                  └── Firebase
```

---

## KEY MESSAGES

1. **Not "22 handlers"** → Complete service layer (41K LOC)
2. **Not a ChatGPT wrapper** → Deep tool integration
3. **Proprietary algorithms** → Can't npm install these
4. **12-18 months to replicate** → Technical moat
5. **Voice-first unique** → No competitor has this

---

## STATS TO HIGHLIGHT

| Metric | Value | Impact |
|--------|-------|--------|
| Total LOC | 41,000+ | Complexity |
| API Endpoints | 9 | More than just chat |
| Tool Handlers | 22 | Deep AI integration |
| Prompt LOC | 1,200+ | Sophisticated AI |
| Algorithms | 5 | Domain expertise |
| Import Stages | 4 | Intelligence pipeline |
| iOS Domains | 17 | Platform depth |
| Time to Replicate | 12-18 months | Technical moat |

---

## DOCUMENTS CREATED

1. **TECHNICAL_OVERVIEW_DECK.md** - Full slide content
2. **TECHNICAL_DEEP_DIVE.md** - Algorithm details
3. **COMPETITIVE_DIFFERENTIATION.md** - Market positioning
4. **SLIDE_OUTLINE.md** - This file

All in `/medina/docs/`
