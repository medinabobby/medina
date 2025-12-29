//
//  AIToolDefinitions.swift
//  Medina
//
//  v67.1: Extracted from AssistantManager.swift
//  v68.0: Added activate_plan and start_workout tools
//  v69.0: Added periodization parameters to create_plan
//  v69.4: Added workoutDayAssignments to create_plan, added reschedule_plan tool
//  v74.7: Added intensityStart/intensityEnd parameters to create_plan
//  v81.0: AI-first exercise selection - AI returns exerciseIds, Swift validates
//  v83.0: Added supersetStyle and supersetGroups parameters to create_workout
//  v93.0: Added send_message tool for trainer-member messaging
//  v140: Added skip_workout tool for proper skip handling with next workout info
//  v141: Added suggest_options tool for quick-action response chips
//  v184: Added abandon_plan, delete_plan, end_workout, reset_workout, add_to_library, remove_from_library
//  Contains all OpenAI tool schema definitions for the fitness assistant
//

import Foundation

/// All tool schema definitions for the OpenAI Assistants API
/// Extracted for maintainability - add new tools here without touching AssistantManager
struct AIToolDefinitions {

    // MARK: - All Tools

    static var allTools: [[String: Any]] {
        [
            showSchedule,
            createWorkout,
            createCustomWorkout,
            modifyWorkout,
            changeProtocol,    // v84.0: PREFERRED for protocol changes
            getSubstitutionOptions,
            getSummary,
            createPlan,
            updateProfile,
            updateExerciseTarget,  // v72.1
            activatePlan,      // v68.0
            startWorkout,      // v68.0
            skipWorkout,       // v140
            reschedulePlan,    // v69.4
            sendMessage,       // v93.0 Trainer-only
            analyzeTrainingData, // v107: Historical data analysis
            suggestOptions,    // v141: Quick-action response chips
            // v184: Plan & workout lifecycle
            abandonPlan,       // v184: End plan early
            deletePlan,        // v184: Delete draft/completed plans
            endWorkout,        // v184: End workout in progress
            resetWorkout,      // v184: Reset workout to initial state
            // v184: Exercise library management
            addToLibrary,      // v184: Add exercise to favorites
            removeFromLibrary  // v184: Remove exercise from favorites
        ]
    }

    // MARK: - Schedule

    /// v59.3: Show user's workout schedule
    static var showSchedule: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "show_schedule",
                "description": "Show user's workout schedule for a time period. Use this when the user asks to see their schedule, workouts, or calendar.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "period": [
                            "type": "string",
                            "enum": ["week", "month"],
                            "description": "Time period to show schedule for (week or month)"
                        ]
                    ],
                    "required": ["period"]
                ]
            ]
        ]
    }

    // MARK: - Workout Creation

    /// v60.0: Create workout with auto-selected exercises (fast path)
    /// v80.3: Added trainingLocation and availableEquipment for home workout support
    /// v81.0: AI-first - AI selects exerciseIds from provided context, Swift validates
    static var createWorkout: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "create_workout",
                "description": """
                Create a new workout for the user. You MUST select exercises from the EXERCISE OPTIONS section in your context.

                CRITICAL SELECTION RULES:
                1. ALWAYS include ★ FAVORITES when their muscle group matches the workout
                2. PREFER recent exercises with high completion rate
                3. ONLY use exercise IDs from your context tables - other IDs will fail validation
                4. Exercise count: 30min→3, 45min→4, 60min→5, 75min→6, 90min→7 exercises
                5. NEVER use excluded exercises (marked with ❌)

                After creating the workout, tell the user they can modify it if they want different exercises.
                """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Workout name (e.g., 'Upper Body - Chest Focus', 'Full Body Strength', '30 Min Cardio')"
                        ],
                        "splitDay": [
                            "type": "string",
                            "enum": ["upper", "lower", "push", "pull", "legs", "fullBody", "chest", "back", "shoulders", "arms", "notApplicable"],
                            "description": "Split type for this workout. Use 'notApplicable' for cardio sessions."
                        ],
                        "scheduledDate": [
                            "type": "string",
                            "description": "ISO8601 date string (YYYY-MM-DD, e.g., '2025-11-25')"
                        ],
                        "duration": [
                            "type": "integer",
                            "minimum": 15,
                            "maximum": 120,
                            "description": "Target duration in minutes (15-120). Use the user's requested duration. Default to 45 if not specified."
                        ],
                        "effortLevel": [
                            "type": "string",
                            "enum": ["recovery", "standard", "push"],
                            "description": "Effort level: recovery=light, standard=balanced, push=high intensity. Default to 'standard' if not specified."
                        ],
                        // v101.1: Session type for cardio vs strength workouts
                        "sessionType": [
                            "type": "string",
                            "enum": ["strength", "cardio"],
                            "description": """
                            Type of workout session. Default: 'strength'.

                            - 'strength': Traditional weightlifting workout with reps/sets
                            - 'cardio': Duration-based cardio session (treadmill, bike, rower, etc.)

                            Use 'cardio' when user requests:
                            - "30 minute cardio workout"
                            - "cardio session"
                            - "treadmill workout"
                            - "running workout"

                            IMPORTANT: When sessionType='cardio':
                            1. Use exerciseIds from cardio exercises ONLY (treadmill_run, bike_steady_state, rower_intervals, etc.)
                            2. Set splitDay to 'notApplicable' (cardio doesn't use splits)
                            3. Cardio protocols use duration instead of reps
                            """
                        ],
                        // v81.0: AI-first exercise selection
                        "exerciseIds": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "REQUIRED: Array of exercise IDs selected from your EXERCISE OPTIONS context. Must match exercise count for duration. Include favorites when muscle groups match."
                        ],
                        "selectionReasoning": [
                            "type": "string",
                            "description": "Brief explanation of why you chose these exercises (e.g., 'Included 2 favorites, plus recent exercises with high completion')"
                        ],
                        // v80.3: Equipment constraints for home workouts
                        // v126: Strengthened instruction - AI was missing home intent
                        "trainingLocation": [
                            "type": "string",
                            "enum": ["gym", "home", "outdoor"],
                            "description": """
                            Where user will train. DEFAULT: 'gym' if user doesn't mention location.

                            ⚠️ PASS 'home' when user says ANY of these:
                            - "home workout"
                            - "at home"
                            - "work from home"
                            - "from home"
                            - "no gym"
                            - "workout at my place"

                            When passing trainingLocation='home':
                            - Check profile for "Home Equipment: [list]"
                            - If equipment listed → pass availableEquipment with those values
                            - If "Not configured" or "None" → ASK user what equipment they have BEFORE calling this tool
                            """
                        ],
                        "availableEquipment": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "For home workouts: Check user profile first. If 'Home Equipment: Not configured', ASK user before calling. If profile has equipment listed, use that. Values: 'bodyweight', 'dumbbells', 'barbell', 'kettlebell', 'resistance_band', 'pullup_bar', 'bench', 'cable_machine'."
                        ],
                        // v82.4: AI Protocol Customization
                        // v83.3: Added tempoOverride for tempo requests
                        "protocolCustomizations": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "exercisePosition": ["type": "integer", "description": "Position in exerciseIds array (0-indexed)"],
                                    "setsAdjustment": ["type": "integer", "minimum": -2, "maximum": 2, "description": "Adjust sets: -2 to +2"],
                                    "repsAdjustment": ["type": "integer", "minimum": -10, "maximum": 10, "description": "Adjust reps per set: -10 to +10. GBC protocol needs +7 (5→12 reps)"],
                                    "restAdjustment": ["type": "integer", "minimum": -60, "maximum": 60, "description": "Adjust rest in seconds: -60 to +60. GBC needs -60 (90→30s)"],
                                    "tempoOverride": ["type": "string", "description": "Tempo override like '3010', '2010', '4020'. GBC uses '3010'"],
                                    "rpeOverride": ["type": "number", "minimum": 6, "maximum": 10, "description": "Override RPE for all sets (6-10). GBC uses 8.0"],
                                    "rationale": ["type": "string", "description": "Why you're customizing this exercise's protocol"]
                                ]
                            ],
                            "description": "Customize protocols for specific exercises. For GBC: repsAdjustment=+7, restAdjustment=-60, tempoOverride='3010', rpeOverride=8.0"
                        ],
                        // v87.0: Movement pattern filtering (movement-first)
                        "movementPatterns": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": """
                            Filter exercises by movement pattern. Use for movement-based requests like 'squat pull', 'hinge day'.

                            Values: squat, hinge, push, pull, horizontal_press, vertical_press, horizontal_pull, vertical_pull, lunge, carry.

                            When specified:
                            - ALL exercises filtered by movement pattern (not by muscle groups)
                            - Generic patterns expand automatically: 'pull' → horizontalPull + verticalPull

                            Examples:
                            - 'squat pull workout' → ["squat", "pull"]
                            - 'hinge day' → ["hinge"]
                            - 'push pull' → ["push", "pull"]
                            """
                        ],
                        // v87.1: Protocol selection for entire workout
                        "protocolId": [
                            "type": "string",
                            "description": """
                            Apply a specific protocol to ALL exercises in this workout. Use when user explicitly requests a protocol.

                            Common values:
                            - 'gbc_relative_compound': GBC (German Body Composition) - 12 reps, 30s rest, 3010 tempo
                            - 'strength_5x5_compound': Strength 5x5 - 5 reps, 120s rest
                            - 'hypertrophy_3x10_compound': Hypertrophy 3x10 - 10 reps, 60s rest

                            When to use:
                            - User says 'use GBC protocol' → protocolId: 'gbc_relative_compound'
                            - User says 'do 5x5 strength' → protocolId: 'strength_5x5_compound'

                            If NOT specified, protocols are auto-selected based on exercise type and user goals.
                            """
                        ],
                        // v83.0: Superset support
                        "supersetStyle": [
                            "type": "string",
                            "enum": ["none", "antagonist", "agonist", "compound_isolation", "circuit", "explicit"],
                            "description": "Superset structure. 'none'=traditional (default), 'antagonist'=push-pull pairs, 'agonist'=same muscle, 'compound_isolation'=compound+isolation pairs, 'circuit'=all exercises flow, 'explicit'=use supersetGroups for custom pairings."
                        ],
                        "supersetGroups": [
                            "type": "array",
                            "description": "Required when supersetStyle='explicit'. User-defined superset groupings with custom rest times.",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "positions": ["type": "array", "items": ["type": "integer"], "description": "Exercise positions (0-indexed) to pair (e.g., [0, 1] for first two exercises)"],
                                    "restBetween": ["type": "integer", "description": "Rest in seconds between exercises in this group (e.g., 1a→1b)"],
                                    "restAfter": ["type": "integer", "description": "Rest in seconds after completing full rotation before next cycle"]
                                ],
                                "required": ["positions", "restBetween", "restAfter"]
                            ]
                        ],
                        // v103: Exercise count override for image-based workout creation
                        // v122: Made description stricter - AI was using this for text requests
                        "exerciseCount": [
                            "type": "integer",
                            "minimum": 3,
                            "maximum": 12,
                            "description": "⚠️ ONLY use when: (1) extracting from an image with visible exercises, OR (2) user explicitly says a number like 'give me 4 exercises'. Do NOT use for text requests like 'upper body' or 'create a workout' - let the system calculate from user's session duration."
                        ],
                    ],
                    "required": ["name", "splitDay", "scheduledDate", "duration", "effortLevel", "exerciseIds"]
                ]
            ]
        ]
    }

    /// v60.0: Create workout with explicit exercise selection (flexible path)
    /// v103: Deprecated for images - use create_workout with intent extraction instead
    static var createCustomWorkout: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "create_custom_workout",
                "description": """
                Create a workout with SPECIFIC exercises that the user explicitly names in text.

                ⚠️ DO NOT use for images - you cannot reliably map image exercises to exact library IDs.
                For images, use create_workout with exerciseCount and movementPatterns instead.

                Only use when user EXPLICITLY names exercises in their message:
                - "I want bench press and squats" → use create_custom_workout
                - "Create a push workout from this image" → use create_workout with intent
                """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Workout name"
                        ],
                        "splitDay": [
                            "type": "string",
                            "enum": ["upper", "lower", "push", "pull", "legs", "fullBody", "chest", "back", "shoulders", "arms"],
                            "description": "Split type for this workout"
                        ],
                        "scheduledDate": [
                            "type": "string",
                            "description": "ISO8601 date string (YYYY-MM-DD)"
                        ],
                        "duration": [
                            "type": "integer",
                            "minimum": 15,
                            "maximum": 120,
                            "description": "Target duration in minutes (15-120)"
                        ],
                        "effortLevel": [
                            "type": "string",
                            "enum": ["recovery", "standard", "push"],
                            "description": "Effort level"
                        ],
                        "exerciseIds": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Array of exercise IDs from user's library. Must match the exercise count for duration."
                        ],
                        "protocolVariantIds": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Array of protocol variant IDs, ordered to match exerciseIds array."
                        ]
                    ],
                    "required": ["name", "splitDay", "scheduledDate", "duration", "effortLevel", "exerciseIds", "protocolVariantIds"]
                ]
            ]
        ]
    }

    /// v60.2: Modify recently created workouts (delete + recreate)
    /// v83.3: Added protocolCustomizations for RPE/tempo/reps changes
    /// v83.5: CRITICAL: When using protocolCustomizations, do NOT pass newDuration/newSplitDay
    /// v101.1: Added newSessionType for changing between strength/cardio
    static var modifyWorkout: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "modify_workout",
                "description": "Modify a workout that was created in this conversation. Two modes: (1) STRUCTURAL changes (duration, split, sessionType): pass newDuration/newSplitDay/newSessionType, exercises may be replaced. (2) PROTOCOL-ONLY changes (reps, tempo, RPE, 'use GBC protocol'): pass ONLY protocolCustomizations, do NOT pass newDuration/newSplitDay - this preserves the exact exercises. CRITICAL: For protocol changes like 'change to GBC' or 'update RPE to 9', use ONLY protocolCustomizations without other params.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "workoutId": [
                            "type": "string",
                            "description": "The ID of the workout to modify (from create_workout response)"
                        ],
                        "newDuration": [
                            "type": "integer",
                            "minimum": 15,
                            "maximum": 120,
                            "description": "New target duration in minutes (15-120, optional)"
                        ],
                        "newSplitDay": [
                            "type": "string",
                            "enum": ["upper", "lower", "push", "pull", "legs", "fullBody", "chest", "back", "shoulders", "arms", "notApplicable"],
                            "description": "New split type (optional). Use 'notApplicable' for cardio."
                        ],
                        "newEffortLevel": [
                            "type": "string",
                            "enum": ["recovery", "standard", "push"],
                            "description": "New effort level (optional)"
                        ],
                        // v101.1: Session type change (strength <-> cardio)
                        "newSessionType": [
                            "type": "string",
                            "enum": ["strength", "cardio"],
                            "description": "Change workout type. Use 'cardio' when user wants to convert to a cardio workout (e.g., 'make it a cardio workout'). When changing to cardio, exercises will be replaced with cardio exercises (treadmill, bike, etc)."
                        ],
                        "newName": [
                            "type": "string",
                            "description": "New workout name (optional)"
                        ],
                        // v129: Training location change (gym <-> home)
                        "newTrainingLocation": [
                            "type": "string",
                            "enum": ["gym", "home", "outdoor"],
                            "description": "Change training location. Use 'home' when user says 'make it a home workout', 'workout from home', 'at home'. This REPLACES exercises with equipment-appropriate alternatives (bodyweight for home)."
                        ],
                        // v83.5: Protocol customizations - expanded ranges for named protocols (GBC, etc.)
                        "protocolCustomizations": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "exercisePosition": ["type": "integer", "description": "Position in workout (0-indexed). Apply to ALL positions: 0, 1, 2, 3, etc."],
                                    "setsAdjustment": ["type": "integer", "minimum": -2, "maximum": 2, "description": "Adjust sets: -2 to +2"],
                                    "repsAdjustment": ["type": "integer", "minimum": -10, "maximum": 10, "description": "Adjust reps: -10 to +10. GBC needs +7 (5→12 reps)"],
                                    "restAdjustment": ["type": "integer", "minimum": -60, "maximum": 60, "description": "Adjust rest: -60 to +60 seconds. GBC needs -60 (90→30s)"],
                                    "tempoOverride": ["type": "string", "description": "Tempo override: '3010' (GBC), '2010', '4020'"],
                                    "rpeOverride": ["type": "number", "minimum": 6, "maximum": 10, "description": "RPE 6-10. GBC uses 8.0"],
                                    "rationale": ["type": "string", "description": "Why you're customizing"]
                                ]
                            ],
                            "description": "PROTOCOL-ONLY mode: Pass this WITHOUT newDuration/newSplitDay to preserve exercises. For GBC: repsAdjustment=+7, restAdjustment=-60, tempoOverride='3010', rpeOverride=8.0. Apply to ALL exercise positions."
                        ]
                    ],
                    "required": ["workoutId"]
                ]
            ]
        ]
    }

    /// v84.1: Data-driven protocol change tool - PREFERRED for protocol changes
    /// Uses in-place modification, never loses exercises
    /// ProtocolResolver handles name→ID mapping for 56+ protocols
    static var changeProtocol: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "change_protocol",
                "description": "Change a workout's training protocol. ALWAYS use this instead of modify_workout for protocol changes. Supports: (1) Named protocols - system resolves all values. (2) Custom values only. (3) Named protocol WITH overrides (e.g., 'GBC but with RPE 9'). Never loses exercises.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "workoutId": [
                            "type": "string",
                            "description": "Workout ID (optional if changing the most recently created workout)"
                        ],
                        "namedProtocol": [
                            "type": "string",
                            "description": "Protocol name or ID. Common aliases: 'gbc' (12 reps, 30s rest, 3010 tempo), 'hypertrophy' (10 reps, 60s rest), 'strength' (5 reps, 180s rest), 'drop set'/'drop sets', 'waves', 'pyramid', 'myo'/'myo reps', 'rest pause', '5x5', 'wendler'/'531'. Can also use exact protocol IDs from protocol_configs.json."
                        ],
                        // Custom values - use alone OR as overrides to named protocol
                        "targetReps": [
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 20,
                            "description": "Target reps. Can override namedProtocol value."
                        ],
                        "targetSets": [
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 10,
                            "description": "Number of sets. Can override namedProtocol value."
                        ],
                        "restBetweenSets": [
                            "type": "integer",
                            "minimum": 15,
                            "maximum": 300,
                            "description": "Rest in seconds. Can override namedProtocol value (e.g., 'GBC with 45s rest')."
                        ],
                        "tempo": [
                            "type": "string",
                            "description": "Tempo (e.g., '3010', '4020'). Can override namedProtocol value."
                        ],
                        "targetRPE": [
                            "type": "number",
                            "minimum": 6,
                            "maximum": 10,
                            "description": "RPE target. Can override namedProtocol value (e.g., 'GBC but with RPE 9')."
                        ]
                    ],
                    "required": []
                ]
            ]
        ]
    }

    // MARK: - Plan Creation

    /// v63.0: Create multi-week training plan
    /// v67.0: Added AI-overridable parameters (splitType, trainingLocation, etc.)
    /// v69.0: Added periodization parameters for multi-program generation
    static var createPlan: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "create_plan",
                "description": "Create a multi-week training plan with professional periodization. Plans are automatically structured into phases (Foundation→Development→Peak→Deload) based on goal and duration. ALWAYS explain the phase structure to the user after creating a plan. Use this when the user asks to create a training plan, program, or schedule spanning multiple weeks.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "description": "Plan name (e.g., 'Summer Strength Program', '8-Week Hypertrophy Plan')"
                        ],
                        "durationWeeks": [
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 52,
                            "description": "Plan duration in weeks (1-52). Use the user's requested duration. Default to 8 if not specified. Longer plans (12+ weeks) are automatically structured into multiple phases."
                        ],
                        "goal": [
                            "type": "string",
                            "enum": ["strength", "muscleGain", "fatLoss", "endurance", "generalFitness", "athleticPerformance"],
                            "description": "Primary fitness goal for this plan"
                        ],
                        "daysPerWeek": [
                            "type": "integer",
                            "minimum": 2,
                            "maximum": 6,
                            "description": "Number of training days per week. Default to 4 if not specified."
                        ],
                        "sessionDuration": [
                            "type": "integer",
                            "minimum": 15,
                            "maximum": 120,
                            "description": "Target duration per workout in minutes (15-120). Default to 45 if not specified."
                        ],
                        "preferredDays": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Preferred training days (e.g., ['monday', 'tuesday', 'thursday', 'friday']). If not specified, system will auto-select based on daysPerWeek."
                        ],
                        "startDate": [
                            "type": "string",
                            "description": "ISO8601 date string (YYYY-MM-DD) for plan start. Default to today if not specified."
                        ],
                        // v69.1: Target date for timeline validation
                        "targetDate": [
                            "type": "string",
                            "description": "ISO8601 date string (YYYY-MM-DD) for user's goal deadline. CRITICAL: When user says 'by Dec 25th' or 'by end of 2026', YOU MUST send this parameter. System will calculate actual weeks from startDate to targetDate and validate the timeline is realistic for the goal."
                        ],
                        // v69.2: Goal amount for realistic validation
                        "goalWeightChange": [
                            "type": "number",
                            "description": "Target weight change in lbs (positive = gain, negative = lose). Extract from user input like 'gain 15lbs' or 'lose 20lbs'. System validates if goal is realistic for the timeline and provides appropriate warnings."
                        ],
                        // v67.0: AI-overridable parameters
                        "splitType": [
                            "type": "string",
                            "enum": ["fullBody", "upperLower", "pushPull", "pushPullLegs", "bodyPart"],
                            "description": "Training split type. Use when user explicitly requests a specific split (e.g., 'I want push/pull' → 'pushPull'). If not specified, system auto-recommends based on schedule."
                        ],
                        "trainingLocation": [
                            "type": "string",
                            "enum": ["gym", "home", "outdoor"],
                            "description": "Where user will train. Use when user mentions location (e.g., 'I'm working out at home' → 'home')."
                        ],
                        "experienceLevel": [
                            "type": "string",
                            "enum": ["beginner", "intermediate", "advanced", "expert"],
                            "description": "User's training experience. Use when user mentions experience (e.g., 'I'm a beginner' → 'beginner')."
                        ],
                        "emphasizedMuscles": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Muscle groups to emphasize (e.g., ['chest', 'shoulders']). Use when user wants focus on specific muscles."
                        ],
                        "excludedMuscles": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Muscle groups to avoid (e.g., ['back'] if injured). Use when user mentions injuries or avoidances."
                        ],
                        "cardioDaysPerWeek": [
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 5,
                            "description": "Number of cardio sessions per week. Use when user explicitly requests cardio days (e.g., 'add 2 days of cardio' → 2)."
                        ],
                        // v69.0: Periodization parameters
                        "periodizationStyle": [
                            "type": "string",
                            "enum": ["auto", "linear", "block", "undulating", "none"],
                            "description": "How to structure training phases. 'auto' (default) lets AI decide optimal periodization based on goal/duration. 'linear' = Foundation→Development→Peak. 'block' = focused training blocks. 'undulating' = varied intensity patterns. 'none' = single program with no phases."
                        ],
                        "includeDeloads": [
                            "type": "boolean",
                            "description": "Whether to include deload (recovery) weeks. Default: true for plans > 4 weeks. Set false if user says 'no deloads' or 'skip recovery weeks'."
                        ],
                        "deloadFrequency": [
                            "type": "integer",
                            "minimum": 3,
                            "maximum": 8,
                            "description": "Weeks between deload weeks (typically 4-6). Only used if includeDeloads is true. Use when user specifies 'deload every X weeks'."
                        ],
                        // v69.4: AI-optimized day distribution
                        "workoutDayAssignments": [
                            "type": "object",
                            "description": "Optimal mapping of days to workout types. Keys: lowercase day names (monday-sunday). Values: 'strength' or 'cardio'. AI should determine based on schedule pattern: alternate for consecutive days, cardio on weekends for split schedules. If not provided, system uses strength-first fallback.",
                            "additionalProperties": ["type": "string", "enum": ["strength", "cardio"]]
                        ],
                        // v74.7: Custom intensity range
                        "intensityStart": [
                            "type": "number",
                            "minimum": 0.40,
                            "maximum": 0.95,
                            "description": "Starting intensity as decimal (e.g., 0.60 for 60%). Use when user specifies intensity range like 'start at 60%' or '60-80% intensity'. Default is goal-based."
                        ],
                        "intensityEnd": [
                            "type": "number",
                            "minimum": 0.40,
                            "maximum": 0.95,
                            "description": "Ending intensity as decimal (e.g., 0.80 for 80%). Use when user specifies intensity range like 'end at 80%' or '70-90% over the plan'. Must be >= intensityStart. Default is goal-based."
                        ],
                        // v92.0: Trainer mode - create plans for members
                        "forMemberId": [
                            "type": "string",
                            "description": "TRAINER ONLY: Member ID to create plan for. Use when trainer says 'create plan for Bobby' or when a member is selected in member context. The plan will be owned by the member, not the trainer."
                        ]
                    ],
                    "required": ["name", "goal"]
                ]
            ]
        ]
    }

    // MARK: - Utilities

    /// v61.0: Find alternative exercises for substitution
    static var getSubstitutionOptions: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "get_substitution_options",
                "description": "Find alternative exercises that can substitute for a given exercise. Use this when the user asks 'what can I do instead of X', 'I don't have equipment for Y', or wants to swap an exercise in their workout.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "exerciseId": [
                            "type": "string",
                            "description": "The ID of the exercise to find alternatives for (from exercise library)"
                        ],
                        "workoutId": [
                            "type": "string",
                            "description": "Optional: The workout ID for context (helps determine equipment availability)"
                        ]
                    ],
                    "required": ["exerciseId"]
                ]
            ]
        ]
    }

    /// v62.0: Get workout/program/plan progress summary
    static var getSummary: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "get_summary",
                "description": "Get workout, program, or plan progress summary with completion metrics. Use this when the user asks 'how did my workout go', 'summarize my workout', 'how is my plan going', or asks about their progress.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "scope": [
                            "type": "string",
                            "enum": ["workout", "program", "plan"],
                            "description": "What to summarize: 'workout' for single workout, 'program' for program progress, 'plan' for full plan progress"
                        ],
                        "id": [
                            "type": "string",
                            "description": "The ID of the workout, program, or plan to summarize"
                        ]
                    ],
                    "required": ["scope", "id"]
                ]
            ]
        ]
    }

    // MARK: - Profile

    /// v66.2: Update user profile from conversation
    static var updateProfile: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "update_profile",
                "description": "Update the user's profile with information they shared in conversation. Use when user mentions their age, birthdate, height, weight, fitness goal, schedule, or other profile information. Call this IMMEDIATELY when user shares any personal or fitness-related details.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "birthdate": [
                            "type": "string",
                            "description": "User's birthdate in ISO format (YYYY-MM-DD). Extract from age ('I'm 13' → calculate), grade level ('7th grade' → ~12-13yo), or explicit date."
                        ],
                        "heightInches": [
                            "type": "number",
                            "description": "User's height in total inches. Convert from feet/inches (e.g., 6'2\" = 74 inches, 5'10\" = 70 inches)"
                        ],
                        "currentWeight": [
                            "type": "number",
                            "description": "User's current weight in pounds"
                        ],
                        "fitnessGoal": [
                            "type": "string",
                            "enum": ["strength", "muscleGain", "fatLoss", "endurance", "generalFitness", "athleticPerformance"],
                            "description": "User's primary fitness goal. Infer from context: basketball/vertical/sports → athleticPerformance, bigger/muscle → muscleGain, lose weight → fatLoss"
                        ],
                        "personalMotivation": [
                            "type": "string",
                            "description": "User's 'why' - their motivation for training (e.g., 'increase vertical jump for basketball', 'look good for summer')"
                        ],
                        "preferredDays": [
                            "type": "array",
                            "items": ["type": "string", "enum": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]],
                            "description": "Days user can work out (e.g., ['monday', 'wednesday', 'friday'])"
                        ],
                        "sessionDuration": [
                            "type": "integer",
                            "description": "Preferred session duration in minutes (e.g., 30, 45, 60)"
                        ],
                        // v72.2: Added gender parameter
                        "gender": [
                            "type": "string",
                            "enum": ["male", "female", "other", "prefer_not_to_say"],
                            "description": "User's gender. Extract from 'I'm male/female/etc.' or 'I am a man/woman'."
                        ],
                        // v73.0: Added experienceLevel parameter
                        "experienceLevel": [
                            "type": "string",
                            "enum": ["beginner", "intermediate", "advanced", "expert"],
                            "description": "User's lifting/training experience level. Extract from 'I'm a beginner', 'expert lifter', '5+ years experience', etc."
                        ]
                    ],
                    "required": []
                ]
            ]
        ]
    }

    // MARK: - v68.0: Plan & Workout Activation

    /// v68.0: Activate a plan to start tracking workouts
    static var activatePlan: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "activate_plan",
                "description": "Activate a plan to begin tracking workouts. IMPORTANT: Only call this tool when user EXPLICITLY says 'yes', 'activate', 'start it', 'let's go', or similar confirmation. Do NOT call automatically after create_plan or change_protocol - always ASK user first and wait for their confirmation. If another plan is already active, this will automatically deactivate it.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "planId": [
                            "type": "string",
                            "description": "The ID of the plan to activate (from create_plan response or schedule)"
                        ],
                        "confirmOverlap": [
                            "type": "boolean",
                            "description": "If true, confirms user wants to replace existing active plan. Set to true only if user has already confirmed they want to replace their current plan."
                        ]
                    ],
                    "required": ["planId"]
                ]
            ]
        ]
    }

    /// v68.0: Start a workout session
    static var startWorkout: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "start_workout",
                "description": "Start a workout session for guided execution. Use this when user asks to start their workout, begin their workout, or says they're ready to train. Validates that the plan is active and no other workout is in progress.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "workoutId": [
                            "type": "string",
                            "description": "The ID of the workout to start (from schedule or plan)"
                        ]
                    ],
                    "required": ["workoutId"]
                ]
            ]
        ]
    }

    /// v140: Skip a scheduled workout
    static var skipWorkout: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "skip_workout",
                "description": """
                    Skip a scheduled or missed workout. Use when user says:
                    - "skip my workout"
                    - "skip it"
                    - "I'll skip today"
                    - "mark it as skipped"

                    After skipping, shows the NEXT scheduled workout with date context
                    (e.g., "See you tomorrow!" or "Next workout is Monday").

                    IMPORTANT: Only use workout IDs from context - never fabricate IDs.
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "workoutId": [
                            "type": "string",
                            "description": "The ID of the workout to skip (from schedule, Today's Workout, or Missed Workouts context)"
                        ]
                    ],
                    "required": ["workoutId"]
                ]
            ]
        ]
    }

    // MARK: - v69.4: Plan Rescheduling

    /// v69.4: Reschedule an existing plan's training days
    static var reschedulePlan: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "reschedule_plan",
                "description": "Change the schedule of an existing plan (draft or active). Use when user wants to change training days or cardio/strength distribution without recreating the entire plan. Preserves completed workout progress for active plans. For draft plans, consider using create_plan instead (old draft auto-deleted). Examples: 'Change my schedule to Mon/Wed/Fri', 'Move cardio to weekends', 'I can only train 3 days now'.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "planId": [
                            "type": "string",
                            "description": "ID of plan to reschedule. Use 'current' for active plan or 'draft' for current draft plan."
                        ],
                        "newPreferredDays": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "New training days as lowercase day names (e.g., ['monday', 'wednesday', 'friday'])"
                        ],
                        "newDaysPerWeek": [
                            "type": "integer",
                            "minimum": 2,
                            "maximum": 6,
                            "description": "New total training days per week. Optional - inferred from newPreferredDays if not provided."
                        ],
                        "newCardioDays": [
                            "type": "integer",
                            "minimum": 0,
                            "maximum": 5,
                            "description": "New number of cardio days per week. Optional - keeps existing if not provided."
                        ],
                        "workoutDayAssignments": [
                            "type": "object",
                            "description": "Optional: explicit day→type mapping. Keys: lowercase day names. Values: 'strength' or 'cardio'. If not provided, AI should determine optimal distribution.",
                            "additionalProperties": ["type": "string", "enum": ["strength", "cardio"]]
                        ]
                    ],
                    "required": ["planId", "newPreferredDays"]
                ]
            ]
        ]
    }

    // MARK: - v72.1: Exercise Target Update

    /// v72.1: Update user's 1RM or working weight via natural language
    static var updateExerciseTarget: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "update_exercise_target",
                "description": "Update a user's 1RM (one rep max) or working weight for an exercise. Use when user tells you their max or typical working weight. Examples: 'my bench 1RM is 225', 'I usually do 45lb dumbbells for curls', 'I can squat 315 for 5 reps'.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "exercise_id": [
                            "type": "string",
                            "description": "Exercise ID from the database (e.g., 'barbell_bench_press', 'dumbbell_bicep_curl'). Use snake_case format."
                        ],
                        "weight_lbs": [
                            "type": "number",
                            "description": "Weight in pounds (convert from kg if needed: kg * 2.2)"
                        ],
                        "weight_type": [
                            "type": "string",
                            "enum": ["1rm", "working"],
                            "description": "Type of weight: '1rm' if user stated their max, 'working' if user mentioned typical training weight"
                        ],
                        "reps": [
                            "type": "integer",
                            "description": "Number of reps (REQUIRED if weight_type is 'working'). Used to calculate 1RM via Brzycki formula."
                        ]
                    ],
                    "required": ["exercise_id", "weight_lbs", "weight_type"]
                ]
            ]
        ]
    }

    // MARK: - v93.0: Trainer Messaging
    // v93.1: Two-way threaded messaging (both trainers and members can send)

    /// v93.1: Send a message to trainer or member (two-way, threaded)
    static var sendMessage: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "send_message",
                "description": """
                Send a message to your trainer (if you're a member) or to a member (if you're a trainer).
                Creates a new thread or replies to an existing thread.

                TRAINERS: 'send Bobby a message', 'tell Sarah good job', 'remind Alex about leg day'
                MEMBERS: 'send Nick a message', 'tell my trainer about my schedule', 'reply to Nick's message'

                Messages appear in the Messages folder in the sidebar and are grouped by conversation thread.
                """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "recipientId": [
                            "type": "string",
                            "description": "User ID to send message to. For trainers: member ID from roster. For members: trainer ID from profile."
                        ],
                        "content": [
                            "type": "string",
                            "description": "Message content. Keep it natural and conversational. Will be delivered as-is."
                        ],
                        "subject": [
                            "type": "string",
                            "description": "Thread subject (REQUIRED for new threads). Examples: 'Training Schedule Update', 'Great workout today!', 'Question about my plan'. Not needed when replying to existing thread."
                        ],
                        "threadId": [
                            "type": "string",
                            "description": "Existing thread ID to reply to. Omit to start a new thread. Use when user says 'reply to...' or 'respond to that message'."
                        ],
                        "messageType": [
                            "type": "string",
                            "enum": ["encouragement", "planUpdate", "checkIn", "reminder", "general"],
                            "description": "Category of message: 'encouragement' for praise/motivation, 'planUpdate' for plan-related updates, 'checkIn' for wellness checks, 'reminder' for workout reminders, 'general' for everything else. Default to 'general' if unclear."
                        ]
                    ],
                    "required": ["recipientId", "content"]
                ]
            ]
        ]
    }

    // MARK: - Training Analysis (v107)

    /// v107.0: Analyze historical training data across date ranges
    /// Enables rich data analysis: period summaries, exercise progression, strength trends, period comparisons
    static var analyzeTrainingData: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "analyze_training_data",
                "description": """
                    Analyze user's historical training data. Use this when the user asks about:
                    - Progress over time ("How am I tracking Jan-Dec?")
                    - Exercise progression ("Show my bench press progress")
                    - Strength trends ("Am I getting stronger? What's regressing?")
                    - Period comparisons ("Compare October vs November")

                    This tool queries the ACTUAL workout data (sets, reps, weights) - NOT just scheduled workouts.
                    Always use date ranges to scope the analysis appropriately.
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "analysisType": [
                            "type": "string",
                            "enum": ["period_summary", "exercise_progression", "strength_trends", "period_comparison"],
                            "description": """
                                Type of analysis to perform:
                                - period_summary: Overall stats for a time period (volume, adherence, muscle breakdown)
                                - exercise_progression: Track a specific exercise's progression over time (weight/reps trends)
                                - strength_trends: Identify which exercises are improving, maintaining, or regressing
                                - period_comparison: Compare two time periods side by side
                                """
                        ],
                        "dateRange": [
                            "type": "object",
                            "description": "Time period to analyze. IMPORTANT: For exercise_progression, ALWAYS use 1 full year (365 days back from today) so the chart can show time-frame filters. For period_summary, use appropriate range. Omit to use default (1 year).",
                            "properties": [
                                "start": [
                                    "type": "string",
                                    "description": "Start date in YYYY-MM-DD format. For exercise_progression, use 1 year ago."
                                ],
                                "end": [
                                    "type": "string",
                                    "description": "End date in YYYY-MM-DD format (typically today)"
                                ]
                            ],
                            "required": ["start", "end"]
                        ],
                        "comparisonDateRange": [
                            "type": "object",
                            "description": "Second time period for period_comparison analysis type",
                            "properties": [
                                "start": [
                                    "type": "string",
                                    "description": "Start date in YYYY-MM-DD format"
                                ],
                                "end": [
                                    "type": "string",
                                    "description": "End date in YYYY-MM-DD format"
                                ]
                            ],
                            "required": ["start", "end"]
                        ],
                        "exerciseId": [
                            "type": "string",
                            "description": "Specific exercise ID for exercise_progression analysis (e.g., 'barbell_bench_press')"
                        ],
                        "exerciseName": [
                            "type": "string",
                            "description": "Exercise name if ID unknown - will fuzzy match (e.g., 'bench press')"
                        ],
                        "muscleGroup": [
                            "type": "string",
                            "enum": ["chest", "back", "shoulders", "biceps", "triceps", "forearms", "core", "quads", "hamstrings", "glutes", "calves", "fullBody"],
                            "description": "Filter analysis to specific muscle group"
                        ],
                        "includeDetails": [
                            "type": "boolean",
                            "description": "Include detailed weekly breakdown (default: false, use for deep dives)"
                        ]
                    ],
                    "required": ["analysisType"]
                ]
            ]
        ]
    }

    // MARK: - v141: Suggestion Chips

    /// v141: Present quick-action chips to user at decision points
    static var suggestOptions: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "suggest_options",
                "description": """
                    Present quick-action chips to user at decision points.
                    Use when presenting 2-4 options the user can tap instead of typing.

                    CRITICAL: Only use workout IDs from context - NEVER fabricate IDs.

                    ALLOWED COMMANDS ONLY - only suggest these existing features:
                    - "Start my workout" / "Start workout [ID]"
                    - "Skip my workout" / "Skip workout [ID]"
                    - "Show my schedule"
                    - "Create a workout for today"
                    - "Create a training plan"
                    - "Analyze my progress"
                    - "Send a message to my trainer" (v189)
                    - "Continue workout" (for paused workouts)

                    Do NOT suggest non-existent features like:
                    - calorie/nutrition tracking, meal plans
                    - membership management
                    - payments, billing
                    - social features
                    - anything not listed above

                    Example (missed workout scenario):
                    User: "Start my workout"
                    Context: No today workout, missed "Full Body" (ID: wk_dec12)
                    → suggest_options(options: [
                        { label: "Do Dec 12 workout", command: "Start workout wk_dec12" },
                        { label: "Skip missed", command: "Skip my missed workouts" },
                        { label: "Create new workout", command: "Create a workout for today" }
                    ])
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "options": [
                            "type": "array",
                            "description": "2-4 quick-action options for user to tap",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "label": [
                                        "type": "string",
                                        "description": "Short button text (2-4 words)"
                                    ],
                                    "command": [
                                        "type": "string",
                                        "description": "Message to send when tapped (from ALLOWED COMMANDS list)"
                                    ]
                                ],
                                "required": ["label", "command"]
                            ],
                            "minItems": 2,
                            "maxItems": 4
                        ]
                    ],
                    "required": ["options"]
                ]
            ]
        ]
    }

    // MARK: - v184: Plan Lifecycle

    /// v184: Abandon an active plan (end early, mark remaining workouts as skipped)
    static var abandonPlan: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "abandon_plan",
                "description": """
                    End an active plan early. Marks all remaining scheduled workouts as skipped.
                    Use when user says:
                    - "abandon my plan"
                    - "end my plan early"
                    - "stop this plan"
                    - "I want to quit my current plan"

                    Only works on ACTIVE plans. For draft plans, suggest delete_plan instead.
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "planId": [
                            "type": "string",
                            "description": "Plan ID to abandon. Use 'current' or 'active' to abandon the user's active plan."
                        ]
                    ],
                    "required": ["planId"]
                ]
            ]
        ]
    }

    /// v184: Delete a draft or completed plan permanently
    static var deletePlan: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "delete_plan",
                "description": """
                    Permanently delete a plan and all its workouts.
                    Use when user says:
                    - "delete my draft plan"
                    - "remove this plan"
                    - "delete the plan"

                    Only works on DRAFT or COMPLETED plans. For active plans, suggest abandon_plan first.
                    Requires confirmation before deletion (confirmDelete=true).
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "planId": [
                            "type": "string",
                            "description": "Plan ID to delete. Use 'draft' to delete the user's draft plan."
                        ],
                        "confirmDelete": [
                            "type": "boolean",
                            "description": "Set to true to confirm deletion. Without confirmation, returns a warning first."
                        ]
                    ],
                    "required": ["planId"]
                ]
            ]
        ]
    }

    // MARK: - v184: Workout Lifecycle

    /// v184: End an in-progress workout
    static var endWorkout: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "end_workout",
                "description": """
                    End an in-progress workout. Marks completed sets as done, skips remaining sets.
                    Use when user says:
                    - "end my workout"
                    - "finish my workout"
                    - "I'm done with my workout"
                    - "stop my workout"

                    Returns a summary of completed vs skipped sets and shows the next scheduled workout.
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "workoutId": [
                            "type": "string",
                            "description": "Workout ID to end. Optional - defaults to current active session's workout."
                        ]
                    ],
                    "required": []
                ]
            ]
        ]
    }

    /// v184: Reset a workout to initial state
    static var resetWorkout: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "reset_workout",
                "description": """
                    Reset a workout to its initial state. Clears all logged data (weights, reps, completion).
                    Use when user says:
                    - "reset my workout"
                    - "start this workout over"
                    - "clear my workout data"
                    - "redo this workout from scratch"

                    Requires confirmation before reset (confirmReset=true).
                    Works on any workout status (scheduled, in-progress, completed, skipped).
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "workoutId": [
                            "type": "string",
                            "description": "Workout ID to reset."
                        ],
                        "confirmReset": [
                            "type": "boolean",
                            "description": "Set to true to confirm reset. Without confirmation, returns a warning about data loss."
                        ]
                    ],
                    "required": ["workoutId"]
                ]
            ]
        ]
    }

    // MARK: - v184: Exercise Library

    /// v184: Add an exercise to user's library (favorites)
    static var addToLibrary: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "add_to_library",
                "description": """
                    Add an exercise to the user's favorites library.
                    Favorited exercises are prioritized when creating workouts.
                    Use when user says:
                    - "add bench press to my library"
                    - "favorite this exercise"
                    - "save squats to my favorites"
                    - "add this to my library"
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "exerciseId": [
                            "type": "string",
                            "description": "Exercise ID to add (e.g., 'barbell_bench_press', 'dumbbell_curl'). Supports fuzzy matching if exact ID unknown."
                        ]
                    ],
                    "required": ["exerciseId"]
                ]
            ]
        ]
    }

    /// v184: Remove an exercise from user's library (favorites)
    static var removeFromLibrary: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": "remove_from_library",
                "description": """
                    Remove an exercise from the user's favorites library.
                    Use when user says:
                    - "remove bench press from my library"
                    - "unfavorite this exercise"
                    - "remove this from my favorites"
                    """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "exerciseId": [
                            "type": "string",
                            "description": "Exercise ID to remove (e.g., 'barbell_bench_press'). Supports fuzzy matching."
                        ]
                    ],
                    "required": ["exerciseId"]
                ]
            ]
        ]
    }
}
