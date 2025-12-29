#!/bin/bash

# migrate_library_v2.sh
# v2.0 - Library Inheritance Migration
# Created: November 11, 2025
#
# Purpose: Migrate Bobby's library to new inheritance system
# - Delete old library files
# - Create trainer master library
# - Create Bobby's inherited library (beginner: 10 exercises)
#
# Usage: ./Scripts/migrate_library_v2.sh

set -e

echo "========================================="
echo "Library v2.0 Migration Script"
echo "========================================="
echo ""

# Get Bobby's documents directory from simulator
BOBBY_USER_ID="bobby"
TRAINER_ID="trainer_default"

# Find simulator Documents directory
SIM_DIR=$(find ~/Library/Developer/CoreSimulator/Devices -name "Documents" -path "*6A227F1B-6A76-47DC-A07D-6F24D0BC044D/Documents" 2>/dev/null | head -1)

if [ -z "$SIM_DIR" ]; then
    echo "❌ Error: Could not find simulator Documents directory"
    echo "Make sure the app is installed and has run at least once"
    exit 1
fi

echo "Found simulator Documents: $SIM_DIR"
echo ""

# Step 1: Delete old library files
echo "Step 1: Cleaning up old library files..."

BOBBY_LIBRARY_DIR="$SIM_DIR/$BOBBY_USER_ID/library"
if [ -d "$BOBBY_LIBRARY_DIR" ]; then
    echo "  - Deleting $BOBBY_LIBRARY_DIR"
    rm -rf "$BOBBY_LIBRARY_DIR"
fi

echo "✓ Old library files deleted"
echo ""

# Step 2: Migration will happen automatically on next app launch
echo "Step 2: Migration strategy"
echo "  - Trainer master library will be created from seed data (19 exercises, 15 protocols)"
echo "  - Bobby's library will be inherited with beginner filter (10 exercises, 3 protocols)"
echo "  - Inheritance happens automatically in LocalDataLoader.initializeUserLibrary()"
echo ""

# Step 3: Verify Bobby's experience level in users.json
echo "Step 3: Checking Bobby's experience level..."

USERS_JSON="/Users/bobbytulsiani/Desktop/medina/Resources/Data/users.json"
if [ -f "$USERS_JSON" ]; then
    BOBBY_EXPERIENCE=$(jq -r '.bobby.memberProfile.experienceLevel' "$USERS_JSON" 2>/dev/null || echo "null")
    if [ "$BOBBY_EXPERIENCE" = "null" ] || [ -z "$BOBBY_EXPERIENCE" ]; then
        echo "  ⚠️  WARNING: Bobby's experience level not set in users.json"
        echo "  ⚠️  Will default to 'beginner' (10 exercises, 3 protocols)"
    else
        echo "  ✓ Bobby's experience level: $BOBBY_EXPERIENCE"
    fi
fi

echo ""
echo "========================================="
echo "Migration Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Launch the app in Xcode"
echo "2. LocalDataLoader will detect missing library"
echo "3. Trainer library will be created (19 exercises, 15 protocols)"
echo "4. Bobby's library will be created via inheritance (10 exercises, 3 protocols)"
echo ""
echo "Expected library counts after migration:"
echo "  - Trainer library: 19 exercises, 15 protocols"
echo "  - Bobby library (beginner): 10 exercises, 3 protocols"
echo ""
echo "To verify migration:"
echo "  1. Check sidebar: Exercises (10), Protocols (~6 families)"
echo "  2. Run: ls -la \"$SIM_DIR/$BOBBY_USER_ID/library/\""
echo "  3. Run: ls -la \"$SIM_DIR/$TRAINER_ID/library/\""
echo ""
