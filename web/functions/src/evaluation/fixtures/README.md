# Vision Test Fixtures

This directory contains test images for vision import tests.

## Available Fixtures (v266)

| Filename | Description | Test Usage |
|----------|-------------|------------|
| `bobby-1rm-max.png` | 1RM spreadsheet data | VIS01, TT06 - Extract and update exercise targets |
| `bobby-neurotype.png` | Neurotype assessment | VIS02 - Create plan based on neurotype |
| `mihir-history.csv` | Workout history CSV | VIS03 - Import workout history |
| `push-day-plan.png` | Push day workout plan | VIS04 - Create workout plan |
| `social-media-workout.png` | Social media workout post | VIS05 - Create workout |
| `truecoach-workout.png` | TrueCoach workout screenshot | VIS06 - Import workout |
| `truecoach-results.png` | TrueCoach results screenshot | VIS07 - Log completed workout |

## Image Guidelines

- Format: PNG or JPEG
- Resolution: 1000-2000px on longest side
- File size: Under 2MB each
- Content: Real fitness content from user's training

## Usage

These images are used by the evaluation runner when `testType: 'vision'` is set.
The runner will:
1. Load the image from this directory
2. Send to `/api/vision` for extraction
3. Pass extracted content to `/api/chat` with context
4. Validate tool execution and extracted exercises

## Removed Tests (v266)

IM01-IM10 tests were removed because they referenced placeholder fixtures that were never created:
- `spreadsheet-screenshot.jpg`, `strong-app-screenshot.jpg`, `handwritten-log.jpg`
- `instagram-post.jpg`, `pr-board.jpg`, `blurry-image.jpg`, `non-workout.jpg`
- `machine-display.jpg`, `truecoach-screenshot.jpg`, `multiple-exercises.jpg`

The VIS01-VIS07 tests use actual user-provided fixtures and are the primary vision tests.
