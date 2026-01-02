# Vision Test Fixtures

This directory contains test images for the v253 vision import tests.

## Required Images

Please provide the following images for the evaluation suite:

| Filename | Description | Expected Content |
|----------|-------------|------------------|
| `spreadsheet-screenshot.jpg` | Excel/Google Sheets workout log | Should contain exercises with sets/reps/weights |
| `strong-app-screenshot.jpg` | Screenshot from Strong app | Workout with exercise names visible |
| `handwritten-log.jpg` | Handwritten workout notes | Readable exercise names and sets |
| `instagram-post.jpg` | Fitness influencer workout post | Visible workout routine |
| `pr-board.jpg` | Gym PR board or whiteboard | 1RM numbers for bench/squat/deadlift |
| `blurry-image.jpg` | Intentionally low-quality photo | Any workout-related content (blurred) |
| `non-workout.jpg` | Non-fitness image (e.g., cat) | Used to test graceful decline |
| `machine-display.jpg` | Gym machine display screen | Weight and rep counts visible |
| `truecoach-screenshot.jpg` | TrueCoach app program view | Full training program visible |
| `multiple-exercises.jpg` | Image with multiple exercises | List of 5+ exercises |

## Image Guidelines

- Format: JPEG preferred (smaller file size)
- Resolution: 1000-2000px on longest side
- File size: Under 2MB each
- Content: Real or realistic fitness content

## Usage

These images are used by the evaluation runner when `testType: 'vision'` is set.
The runner will:
1. Load the image from this directory
2. Send to `/api/vision` for extraction
3. Validate extracted exercises against `expectedExtractions`
