//
// SharedEnums.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

// MARK: - Training Split Architecture (Cross-Entity)

/// Training split type used by Plan (overall structure) and referenced by Workout (split day)
/// v16.7: Moved from Plan/PlanEnums.swift to SharedEnums (cross-entity)
enum SplitType: String, CaseIterable, Codable {
    case fullBody = "full_body"
    case upperLower = "upper_lower"
    case pushPull = "push_pull"
    case pushPullLegs = "push_pull_legs"
    case bodyPart = "body_part"

    var displayName: String {
        switch self {
        case .fullBody: return "Full Body"
        case .upperLower: return "Upper/Lower"
        case .pushPull: return "Push/Pull"
        case .pushPullLegs: return "Push/Pull/Legs"
        case .bodyPart: return "Body Part"
        }
    }

    var educationalDescription: String {
        switch self {
        case .fullBody:
            return "This works all major muscle groups each session for balanced development and high training frequency."
        case .upperLower:
            return "This alternates upper and lower body days for focused recovery while maintaining training frequency."
        case .pushPull:
            return "This separates pushing and pulling movements to optimize recovery and effective muscle pairing."
        case .pushPullLegs:
            return "This three-way split maximizes recovery time while allowing specialized focus per session."
        case .bodyPart:
            return "This focuses on individual muscle groups for maximum isolation and targeted development."
        }
    }
}

/// Specific day within a training split assigned to a workout
/// v16.7: New enum to make split day assignment explicit (not embedded in workout name)
enum SplitDay: String, Codable, CaseIterable {
    // Upper/Lower split
    case upper = "upper"
    case lower = "lower"

    // Push/Pull/Legs split
    case push = "push"
    case pull = "pull"
    case legs = "legs"

    // Full body (no specific split)
    case fullBody = "full_body"

    // Body part splits
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case arms = "arms"

    // Not applicable (cardio, classes, mobility sessions)
    case notApplicable = "not_applicable"

    var displayName: String {
        switch self {
        case .upper: return "Upper Body"
        case .lower: return "Lower Body"
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .fullBody: return "Full Body"
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .notApplicable: return "N/A"
        }
    }

    var icon: String {
        switch self {
        case .upper: return "figure.arms.open"
        case .lower: return "figure.walk"
        case .push: return "arrow.forward.circle.fill"
        case .pull: return "arrow.backward.circle.fill"
        case .legs: return "figure.walk"
        case .fullBody: return "figure.strengthtraining.traditional"
        case .chest: return "figure.arms.open"
        case .back: return "figure.flexibility"
        case .shoulders: return "triangle.fill"
        case .arms: return "figure.arms.open"
        case .notApplicable: return "circle"
        }
    }
}

/// Isolation approach strategy for accessory/isolation exercises
/// v19.7: Moved from Plan/PlanEnums.swift to SharedEnums (cross-entity)
/// Used by Plan (defines strategy) and can be referenced by Workout (executes strategy)
enum IsolationApproach: String, Codable, CaseIterable {
    case antagonistPairing = "antagonist_pairing"
    case weakPointFocused = "weak_point_focused"
    case postExhaust = "post_exhaust"
    case volumeAccumulation = "volume_accumulation"
    case minimal = "minimal"

    var displayName: String {
        switch self {
        case .antagonistPairing: return "Antagonist Pairing"
        case .weakPointFocused: return "Weak Point Focused"
        case .postExhaust: return "Post-Exhaust"
        case .volumeAccumulation: return "Volume Accumulation"
        case .minimal: return "Minimal"
        }
    }

    var description: String {
        switch self {
        case .antagonistPairing:
            return "Balance opposing muscle groups for symmetry"
        case .weakPointFocused:
            return "Target lagging muscle groups for development"
        case .postExhaust:
            return "Finish muscle groups after compounds for additional volume"
        case .volumeAccumulation:
            return "Maximum isolation volume for muscle growth"
        case .minimal:
            return "Only critical gaps and imbalances"
        }
    }

    // v42.3: Comprehensive educational descriptions for detail cards
    var educationalDescription: String {
        switch self {
        case .antagonistPairing:
            return "Balance opposing muscle groups (e.g., biceps/triceps) for symmetry and injury prevention."
        case .weakPointFocused:
            return "Target lagging muscle groups with extra volume to correct imbalances and improve aesthetics."
        case .postExhaust:
            return "Finish muscle groups with isolation after compounds to maximize growth stimulus and volume."
        case .volumeAccumulation:
            return "Maximum isolation volume (high sets/reps) for muscle growth and hypertrophy focus."
        case .minimal:
            return "Only critical gaps and imbalances addressed to keep focus on compound movements."
        }
    }
}

// MARK: - Session Type (Cross-Entity)

/// Session type used by both Workout and Plan entities
/// V14.5+ Enhanced SessionType for multiple sessions per day
enum SessionType: String, CaseIterable, Codable {
    case strength = "strength"        // Strength/resistance training
    case cardio = "cardio"            // Cardio-focused session
    case `class` = "class"            // Group fitness class
    case hybrid = "hybrid"            // Mixed session type
    case mobility = "mobility"        // Stretching/recovery

    var displayName: String {
        switch self {
        case .strength: return "Strength Session"
        case .cardio: return "Cardio Session"
        case .class: return "Class Session"
        case .hybrid: return "Hybrid Session"
        case .mobility: return "Mobility Session"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .strength: return "Lifting"  // v47.1: Match plan creation terminology
        case .cardio: return "Cardio"
        case .class: return "Class"
        case .hybrid: return "Hybrid"
        case .mobility: return "Mobility"
        }
    }

    /// SF Symbol icon name for this session type
    var icon: String {
        switch self {
        case .strength: return "dumbbell"
        case .cardio: return "heart"
        case .class: return "person.3"
        case .hybrid: return "star.circle"
        case .mobility: return "figure.flexibility"
        }
    }

    /// v41.9: Emoji icon for schedule card display
    var emojiIcon: String {
        switch self {
        case .strength, .hybrid: return "🏋️"  // Dumbbell
        case .cardio: return "🚴"              // Bike
        case .class: return "🧘"               // Yoga/class
        case .mobility: return "🧘"            // Mobility (same as class)
        }
    }

    /// Typical duration for this session type (in minutes)
    var typicalDuration: Int {
        switch self {
        case .strength: return 60
        case .cardio: return 45
        case .class: return 50
        case .hybrid: return 75
        case .mobility: return 30
        }
    }
}

// MARK: - Completion (Cross-Entity)
// v21.0: ExecutionStatus deleted - replaced by ExecutionStatus
// See: Medina/Data/Models/Status/ExecutionStatus.swift

// MARK: - Equipment (Cross-Entity)

enum Equipment: String, Codable, CaseIterable {
    case barbell = "barbell"
    case dumbbells = "dumbbells"
    case cableMachine = "cable_machine"
    case bodyweight = "bodyweight"
    case kettlebell = "kettlebell"
    case resistanceBand = "resistance_band"
    case machine = "machine"
    case smith = "smith"
    case trx = "trx"
    case bench = "bench"
    case squatRack = "squat_rack"
    case pullupBar = "pullup_bar"
    case dipStation = "dip_station"
    case treadmill = "treadmill"
    case bike = "bike"
    case rower = "rower"
    case elliptical = "elliptical"
    case skiErg = "ski_erg"
    case none = "none"

    var displayName: String {
        switch self {
        case .cableMachine: return "Cable Machine"
        case .resistanceBand: return "Resistance Band"
        case .squatRack: return "Squat Rack"
        case .pullupBar: return "Pull-up Bar"
        case .dipStation: return "Dip Station"
        case .skiErg: return "Ski Erg"
        default: return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// v82.7: Standard gym equipment set (used when gym location but no equipment specified)
    static var fullGymEquipment: Set<Equipment> {
        Set([
            .barbell,
            .dumbbells,
            .cableMachine,
            .machine,
            .bench,
            .squatRack,
            .pullupBar,
            .dipStation,
            .kettlebell,
            .bodyweight,
            .none
        ])
    }
}

// MARK: - Muscle Group (Cross-Entity)

enum MuscleGroup: String, Codable, CaseIterable {
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case biceps = "biceps"
    case triceps = "triceps"
    case quadriceps = "quadriceps"
    case hamstrings = "hamstrings"
    case glutes = "glutes"
    case calves = "calves"
    case core = "core"
    case forearms = "forearms"
    case lats = "lats"
    case traps = "traps"
    case abs = "abs"
    case fullBody = "full_body"

    var displayName: String {
        switch self {
        case .fullBody: return "Full Body"
        case .lats: return "Lats"
        case .traps: return "Traps"
        case .abs: return "Abs"
        default: return rawValue.capitalized
        }
    }

    /// Simplified muscle groups for user-facing selection (6 options vs 15 raw values)
    /// Maps user-friendly names to underlying MuscleGroup sets
    static let simplifiedGroups: [(name: String, groups: Set<MuscleGroup>)] = [
        ("Chest", [.chest]),
        ("Back", [.back, .lats, .traps]),
        ("Shoulders", [.shoulders]),
        ("Legs", [.quadriceps, .hamstrings, .glutes, .calves]),
        ("Arms", [.biceps, .triceps, .forearms]),
        ("Core", [.core, .abs])
    ]
}

// MARK: - Loading Pattern (Cross-Entity)

enum LoadingPattern: String, Codable, CaseIterable {
    case straightSets = "straight_sets"
    case progressive = "progressive"
    case undulating = "undulating"
    case cluster = "cluster"
    case density = "density"
    case circuit = "circuit"
    
    var displayName: String {
        switch self {
        case .straightSets: return "Straight Sets"
        case .progressive: return "Progressive"
        case .undulating: return "Undulating"
        case .cluster: return "Cluster"
        case .density: return "Density"
        case .circuit: return "Circuit"
        }
    }
    
    var description: String {
        switch self {
        case .straightSets:
            return "Consistent load and reps across all sets"
        case .progressive:
            return "Increasing weight while decreasing reps"
        case .undulating:
            return "Vary intensity weekly to prevent adaptation"
        case .cluster:
            return "Rest between reps for maximum power"
        case .density:
            return "Time-constrained work for conditioning"
        case .circuit:
            return "Minimal rest between exercises"
        }
    }

    // v42.3: Comprehensive educational descriptions for detail cards
    var educationalDescription: String {
        switch self {
        case .straightSets:
            return "Same weight and reps across all sets to build consistency and volume tolerance."
        case .progressive:
            return "Increasing weight while decreasing reps to build maximum strength through progressive overload."
        case .undulating:
            return "Varying intensity weekly (heavy/medium/light) to prevent plateaus and maintain consistent progress."
        case .cluster:
            return "Brief rest between reps to maximize power output for advanced strength development."
        case .density:
            return "Time-constrained work (max reps in fixed time) to build conditioning and work capacity."
        case .circuit:
            return "Minimal rest between exercises for efficient full-body training and conditioning."
        }
    }
}

// MARK: - Day of Week (Cross-Entity)

enum DayOfWeek: String, Codable, CaseIterable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    
    var displayName: String {
        rawValue.capitalized
    }

    /// v47.2: Single/double letter abbreviations for compact UI
    /// M, T, W, Th, F, Sa, Su (distinguishes Thursday/Tuesday, Saturday/Sunday)
    var shortName: String {
        switch self {
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "Th"
        case .friday: return "F"
        case .saturday: return "Sa"
        case .sunday: return "Su"
        }
    }
}

// MARK: - Effort Level (Single Workout)

/// v58.3: Effort level for single workout creation
/// Maps user-friendly effort selection to intensity ranges for protocol selection
enum EffortLevel: String, Codable, CaseIterable {
    case recovery = "recovery"
    case standard = "standard"
    case pushIt = "push_it"

    var displayName: String {
        switch self {
        case .recovery: return "Recovery"
        case .standard: return "Standard"
        case .pushIt: return "Push It"
        }
    }

    var description: String {
        switch self {
        case .recovery: return "Light recovery day"
        case .standard: return "Balanced session"
        case .pushIt: return "High intensity"
        }
    }

    /// Target intensity for protocol selection and weight calculation
    /// This becomes Program.startingIntensity == Program.endingIntensity
    var intensity: Double {
        switch self {
        case .recovery: return 0.60
        case .standard: return 0.70
        case .pushIt: return 0.80
        }
    }

    /// Target RPE range for this effort level
    var rpeRange: ClosedRange<Double> {
        switch self {
        case .recovery: return 6.0...7.0
        case .standard: return 7.0...8.0
        case .pushIt: return 8.0...9.5
        }
    }

    /// SF Symbol icon for UI display
    var icon: String {
        switch self {
        case .recovery: return "leaf"
        case .standard: return "flame"
        case .pushIt: return "flame.fill"
        }
    }
}

// MARK: - Superset Style (Workout Structure)

/// v83.0: Superset pairing style for workout creation
/// Determines how exercises are grouped into supersets
enum SupersetStyle: String, Codable, CaseIterable {
    case none = "none"                          // Traditional straight sets
    case antagonist = "antagonist"              // Push-pull pairs (chest↔back, biceps↔triceps)
    case agonist = "agonist"                    // Same muscle (compound + isolation)
    case compoundIsolation = "compound_isolation" // Compound followed by isolation
    case circuit = "circuit"                    // All exercises flow back-to-back
    case explicit = "explicit"                  // User-defined pairings with custom rest

    var displayName: String {
        switch self {
        case .none: return "Traditional"
        case .antagonist: return "Push-Pull Pairs"
        case .agonist: return "Same Muscle"
        case .compoundIsolation: return "Compound + Isolation"
        case .circuit: return "Circuit"
        case .explicit: return "Custom Pairs"
        }
    }

    var description: String {
        switch self {
        case .none: return "Complete all sets of one exercise before moving on"
        case .antagonist: return "Alternate opposing muscles for time efficiency"
        case .agonist: return "Same muscle back-to-back for maximum fatigue"
        case .compoundIsolation: return "Heavy compound followed by isolation finisher"
        case .circuit: return "All exercises flow with minimal rest"
        case .explicit: return "User-specified pairings with custom rest times"
        }
    }

    /// Whether this style uses system auto-pairing vs user-specified groups
    var isAutoPair: Bool {
        switch self {
        case .none, .explicit: return false
        case .antagonist, .agonist, .compoundIsolation, .circuit: return true
        }
    }

    /// Default rest between exercises in pair (1a→1b) in seconds
    var defaultRestBetween: Int {
        switch self {
        case .none: return 0
        case .antagonist: return 20
        case .agonist: return 30
        case .compoundIsolation: return 20
        case .circuit: return 10
        case .explicit: return 30  // User provides actual values
        }
    }

    /// Default rest after completing full rotation in seconds
    var defaultRestAfter: Int {
        switch self {
        case .none: return 90
        case .antagonist: return 60
        case .agonist: return 90
        case .compoundIsolation: return 75
        case .circuit: return 45
        case .explicit: return 90  // User provides actual values
        }
    }
}

// MARK: - Entity and Query Slot Enums
// Used by WorkoutDataStore, WorkoutResolver, SidebarView, etc.
// for filtering and resolving workout queries.

enum Entity {
    case plan
    case workout
    case program
    case member
    case trainer
    case gym
    case exercise
    case `protocol`
    case protocolFamily  // v88.0: For grouped protocol navigation
    case exerciseInstance
    case set
    case workoutSession
    case schedule
    case target
    case `class`
    case classInstance  // v99: Class instance for 3-tier class architecture
    case message  // v93.0: Trainer message (deprecated, use thread)
    case thread   // v93.1: Message thread (two-way conversation)
    case unknown
}

enum ScopeSlot {
    case my
    case all
    case unspecified
}

enum QuantitySlot {
    case single
    case multiple
}

enum ModalitySlot {
    case strength
    case cardio
    case mobility
    case recovery
    case unspecified
}

enum TemporalSlot {
    case today
    case tomorrow
    case thisWeek
    case upcoming
    case past
    case unspecified
}

enum MetricType {
    case sessions    // Workout/session completion percentage
    case exercises   // Exercise completion percentage
    case sets        // Set completion percentage
    case reps        // Rep completion percentage
    case unspecified // Show all available metrics
}

enum RelationshipType {
    case contains        // Plan contains Programs, Program contains Workouts
    case belongsTo       // Program belongs to Plan, Workout belongs to Program
    case references      // Workout references Program/Template
    case schedules       // Calendar schedules Workouts
}

enum RelationshipScope {
    case direct          // immediate parent-child relationship
    case transitive      // multi-hop traversal (Plan → Program → Workout)
    case aggregate       // for counting/statistics operations
}

struct EntityRelationship {
    let sourceEntity: Entity
    let targetEntity: Entity
    let relationshipType: RelationshipType
    let sourceStatusHint: String?
    let scope: RelationshipScope

    init(sourceEntity: Entity, targetEntity: Entity, relationshipType: RelationshipType, sourceStatusHint: String?, scope: RelationshipScope) {
        self.sourceEntity = sourceEntity
        self.targetEntity = targetEntity
        self.relationshipType = relationshipType
        self.sourceStatusHint = sourceStatusHint
        self.scope = scope
    }

    init(source: Entity, target: Entity, sourceStatusHint: String? = nil) {
        self.sourceEntity = source
        self.targetEntity = target
        self.relationshipType = RelationshipType.contains
        self.sourceStatusHint = sourceStatusHint
        self.scope = RelationshipScope.direct
    }
}
