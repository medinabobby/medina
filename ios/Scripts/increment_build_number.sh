#!/bin/bash

# Auto-increment build number for Release/Archive builds
# Add this as a Run Script build phase in Xcode (before Compile Sources)
#
# Usage in Xcode:
#   Build Phases → + → New Run Script Phase
#   Shell: /bin/bash
#   Script: ${SRCROOT}/Scripts/increment_build_number.sh

# Only increment for Release builds (not Debug)
if [ "${CONFIGURATION}" != "Release" ] && [ "${CONFIGURATION}" != "Archive" ]; then
    echo "Skipping build number increment for ${CONFIGURATION} build"
    exit 0
fi

# Get current build number from project
BUILD_NUMBER=$(grep -m1 'CURRENT_PROJECT_VERSION' "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj" | grep -o '[0-9]\+')

if [ -z "$BUILD_NUMBER" ]; then
    echo "Error: Could not find CURRENT_PROJECT_VERSION"
    exit 1
fi

# Increment
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))

# Update all occurrences in project.pbxproj
sed -i '' "s/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/CURRENT_PROJECT_VERSION = ${NEW_BUILD_NUMBER}/g" "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj/project.pbxproj"

echo "Build number incremented: ${BUILD_NUMBER} → ${NEW_BUILD_NUMBER}"
