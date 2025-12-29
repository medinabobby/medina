//
// PeriodizationEngine.swift
// Medina
//
// v69.0: AI-driven periodization logic for multi-program plan generation
// Calculates optimal phase structure based on goal, duration, and style
// v74.7: Added custom intensity range support
//

import Foundation

/// v69.0: Generates phase structures for training plans
/// Uses professional periodization principles to break long plans into mesocycles
struct PeriodizationEngine {

    // MARK: - Phase Definition

    /// A single training phase (becomes a Program)
    struct Phase {
        let focus: TrainingFocus
        let weeks: Int
        let intensityRange: ClosedRange<Double>
        let progressionType: ProgressionType
        let rationale: String
    }

    // MARK: - Public API

    /// Calculate optimal phase structure for a plan
    /// - Parameters:
    ///   - goal: User's fitness goal
    ///   - weeks: Total plan duration in weeks
    ///   - style: Periodization style (auto lets AI decide)
    ///   - includeDeloads: Whether to insert deload weeks
    ///   - deloadFrequency: Weeks between deloads (typically 4-6)
    ///   - customIntensityStart: v74.7 - User-specified starting intensity (0.40-0.95)
    ///   - customIntensityEnd: v74.7 - User-specified ending intensity (0.40-0.95)
    /// - Returns: Array of phases to become Programs
    static func calculatePhases(
        goal: FitnessGoal,
        weeks: Int,
        style: PeriodizationStyle,
        includeDeloads: Bool,
        deloadFrequency: Int,
        customIntensityStart: Double? = nil,
        customIntensityEnd: Double? = nil
    ) -> [Phase] {

        // For very short plans or "none" style, use single program
        if weeks <= 3 || style == .none {
            let basePhase = singlePhase(goal: goal, weeks: weeks)
            // v74.7: Apply custom intensity if provided
            if let start = customIntensityStart, let end = customIntensityEnd {
                return [Phase(
                    focus: basePhase.focus,
                    weeks: basePhase.weeks,
                    intensityRange: start...end,
                    progressionType: basePhase.progressionType,
                    rationale: basePhase.rationale
                )]
            }
            return [basePhase]
        }

        // Get base template based on goal and style
        let effectiveStyle = (style == .auto) ? recommendStyle(goal: goal, weeks: weeks) : style
        var phases = getGoalTemplate(goal: goal, weeks: weeks, style: effectiveStyle)

        // Insert deloads if requested
        if includeDeloads && weeks > 4 {
            phases = insertDeloads(phases: phases, frequency: deloadFrequency)
        }

        // v74.7: Scale intensities to custom range if provided
        if let customStart = customIntensityStart, let customEnd = customIntensityEnd {
            phases = scaleIntensities(phases: phases, targetStart: customStart, targetEnd: customEnd)
        } else if let customStart = customIntensityStart {
            // Only start provided - shift all phases proportionally
            phases = shiftIntensitiesFromStart(phases: phases, targetStart: customStart)
        } else if let customEnd = customIntensityEnd {
            // Only end provided - shift all phases proportionally
            phases = shiftIntensitiesToEnd(phases: phases, targetEnd: customEnd)
        }

        return phases
    }

    // MARK: - Custom Intensity Scaling (v74.7)

    /// Scale all phase intensities to fit within a custom range
    /// Preserves relative progression while mapping to user-specified bounds
    private static func scaleIntensities(
        phases: [Phase],
        targetStart: Double,
        targetEnd: Double
    ) -> [Phase] {
        // Find the overall intensity range across all phases (excluding deloads)
        let trainingPhases = phases.filter { $0.focus != .deload }
        guard !trainingPhases.isEmpty else { return phases }

        let minIntensity = trainingPhases.map { $0.intensityRange.lowerBound }.min() ?? 0.50
        let maxIntensity = trainingPhases.map { $0.intensityRange.upperBound }.max() ?? 0.90
        let originalRange = maxIntensity - minIntensity

        // Avoid division by zero
        guard originalRange > 0 else { return phases }

        let targetRange = targetEnd - targetStart

        return phases.map { phase in
            if phase.focus == .deload {
                // Deloads stay at reduced intensity (scale down from target start)
                let deloadIntensity = max(0.40, targetStart - 0.15)
                return Phase(
                    focus: phase.focus,
                    weeks: phase.weeks,
                    intensityRange: deloadIntensity...(deloadIntensity + 0.10),
                    progressionType: phase.progressionType,
                    rationale: phase.rationale
                )
            }

            // Scale the phase's intensity range to the custom range
            let scaledLower = targetStart + ((phase.intensityRange.lowerBound - minIntensity) / originalRange) * targetRange
            let scaledUpper = targetStart + ((phase.intensityRange.upperBound - minIntensity) / originalRange) * targetRange

            // Clamp to valid bounds
            let clampedLower = min(max(scaledLower, 0.40), 0.95)
            let clampedUpper = min(max(scaledUpper, 0.40), 0.95)

            return Phase(
                focus: phase.focus,
                weeks: phase.weeks,
                intensityRange: clampedLower...max(clampedLower, clampedUpper),
                progressionType: phase.progressionType,
                rationale: phase.rationale
            )
        }
    }

    /// Shift all phases so the first non-deload phase starts at targetStart
    private static func shiftIntensitiesFromStart(phases: [Phase], targetStart: Double) -> [Phase] {
        let trainingPhases = phases.filter { $0.focus != .deload }
        guard let firstPhase = trainingPhases.first else { return phases }

        let shift = targetStart - firstPhase.intensityRange.lowerBound

        return phases.map { phase in
            if phase.focus == .deload {
                let deloadIntensity = max(0.40, targetStart - 0.15)
                return Phase(
                    focus: phase.focus,
                    weeks: phase.weeks,
                    intensityRange: deloadIntensity...(deloadIntensity + 0.10),
                    progressionType: phase.progressionType,
                    rationale: phase.rationale
                )
            }

            let newLower = min(max(phase.intensityRange.lowerBound + shift, 0.40), 0.95)
            let newUpper = min(max(phase.intensityRange.upperBound + shift, 0.40), 0.95)

            return Phase(
                focus: phase.focus,
                weeks: phase.weeks,
                intensityRange: newLower...max(newLower, newUpper),
                progressionType: phase.progressionType,
                rationale: phase.rationale
            )
        }
    }

    /// Shift all phases so the last non-deload phase ends at targetEnd
    private static func shiftIntensitiesToEnd(phases: [Phase], targetEnd: Double) -> [Phase] {
        let trainingPhases = phases.filter { $0.focus != .deload }
        guard let lastPhase = trainingPhases.last else { return phases }

        let shift = targetEnd - lastPhase.intensityRange.upperBound

        return phases.map { phase in
            if phase.focus == .deload {
                // Calculate deload based on shifted intensity
                let firstTrainingLower = (trainingPhases.first?.intensityRange.lowerBound ?? 0.60) + shift
                let deloadIntensity = max(0.40, firstTrainingLower - 0.15)
                return Phase(
                    focus: phase.focus,
                    weeks: phase.weeks,
                    intensityRange: deloadIntensity...(deloadIntensity + 0.10),
                    progressionType: phase.progressionType,
                    rationale: phase.rationale
                )
            }

            let newLower = min(max(phase.intensityRange.lowerBound + shift, 0.40), 0.95)
            let newUpper = min(max(phase.intensityRange.upperBound + shift, 0.40), 0.95)

            return Phase(
                focus: phase.focus,
                weeks: phase.weeks,
                intensityRange: newLower...max(newLower, newUpper),
                progressionType: phase.progressionType,
                rationale: phase.rationale
            )
        }
    }

    /// Generate educational explanation of the phase structure
    static func generateExplanation(phases: [Phase], goal: FitnessGoal) -> String {
        var explanation = "I've structured your plan with professional periodization:\n\n"

        for (index, phase) in phases.enumerated() {
            let weekRange = calculateWeekRange(phases: phases, index: index)
            explanation += "**\(phase.focus.displayName) Phase (Weeks \(weekRange))** - \(phase.rationale)\n\n"
        }

        explanation += "Each phase builds on the last. When you complete one phase, I'll automatically move you into the next."

        return explanation
    }

    // MARK: - Style Recommendation

    /// Recommend periodization style based on goal and duration
    private static func recommendStyle(goal: FitnessGoal, weeks: Int) -> PeriodizationStyle {
        switch goal {
        case .strength, .powerlifting, .strengthConditioning:
            return weeks >= 12 ? .block : .linear
        case .muscleGain, .bodybuilding:
            return .linear  // Progressive hypertrophy works well with linear
        case .fatLoss, .weightManagement:
            return .linear  // Consistent deficit with progressive conditioning
        case .endurance, .enduranceTraining:
            return .block   // Build base → develop → peak
        case .generalFitness, .personalTraining, .nutrition, .specialPopulations:
            return .linear  // Simple progressive approach
        case .athleticPerformance, .sportSpecific:
            return weeks >= 12 ? .block : .linear  // Sport-specific peaking
        case .mobility, .yoga, .rehabilitative:
            return .linear  // Gentle progressive approach
        }
    }

    // MARK: - Goal Templates

    /// Get phase template based on goal, duration, and style
    private static func getGoalTemplate(goal: FitnessGoal, weeks: Int, style: PeriodizationStyle) -> [Phase] {
        switch goal {
        case .strength, .powerlifting, .strengthConditioning:
            return strengthTemplate(weeks: weeks, style: style)
        case .muscleGain, .bodybuilding:
            return hypertrophyTemplate(weeks: weeks, style: style)
        case .fatLoss, .weightManagement:
            return fatLossTemplate(weeks: weeks, style: style)
        case .endurance, .enduranceTraining:
            return enduranceTemplate(weeks: weeks, style: style)
        case .generalFitness, .personalTraining, .nutrition, .specialPopulations:
            return generalFitnessTemplate(weeks: weeks, style: style)
        case .athleticPerformance, .sportSpecific:
            return athleticTemplate(weeks: weeks, style: style)
        case .mobility, .yoga, .rehabilitative:
            return enduranceTemplate(weeks: weeks, style: style)  // Use gentle progression
        }
    }

    // MARK: - Strength Templates

    private static func strengthTemplate(weeks: Int, style: PeriodizationStyle) -> [Phase] {
        if weeks <= 4 {
            // Short: Just development
            return [
                Phase(
                    focus: .development,
                    weeks: weeks,
                    intensityRange: 0.70...0.85,
                    progressionType: .linear,
                    rationale: "Progressive strength building with compound movements"
                )
            ]
        } else if weeks <= 8 {
            // Medium: Development → Peak
            let devWeeks = Int(Double(weeks) * 0.6)
            let peakWeeks = weeks - devWeeks
            return [
                Phase(
                    focus: .development,
                    weeks: devWeeks,
                    intensityRange: 0.70...0.80,
                    progressionType: .linear,
                    rationale: "Build strength base with progressive overload"
                ),
                Phase(
                    focus: .peak,
                    weeks: peakWeeks,
                    intensityRange: 0.80...0.90,
                    progressionType: .linear,
                    rationale: "Maximize strength with higher intensity, lower volume"
                )
            ]
        } else if weeks <= 16 {
            // Long: Foundation → Development → Peak
            let foundWeeks = max(2, Int(Double(weeks) * 0.25))
            let peakWeeks = max(2, Int(Double(weeks) * 0.25))
            let devWeeks = weeks - foundWeeks - peakWeeks
            return [
                Phase(
                    focus: .foundation,
                    weeks: foundWeeks,
                    intensityRange: 0.60...0.70,
                    progressionType: .linear,
                    rationale: "Build work capacity and perfect movement patterns"
                ),
                Phase(
                    focus: .development,
                    weeks: devWeeks,
                    intensityRange: 0.70...0.82,
                    progressionType: .linear,
                    rationale: "Progressive overload drives strength gains"
                ),
                Phase(
                    focus: .peak,
                    weeks: peakWeeks,
                    intensityRange: 0.82...0.92,
                    progressionType: .linear,
                    rationale: "Peak intensity for maximum strength expression"
                )
            ]
        } else {
            // Annual: Multiple cycles
            return buildAnnualCycles(weeks: weeks, goal: .strength)
        }
    }

    // MARK: - Hypertrophy Templates

    private static func hypertrophyTemplate(weeks: Int, style: PeriodizationStyle) -> [Phase] {
        if weeks <= 4 {
            return [
                Phase(
                    focus: .development,
                    weeks: weeks,
                    intensityRange: 0.65...0.75,
                    progressionType: .linear,
                    rationale: "Volume-focused training for muscle growth"
                )
            ]
        } else if weeks <= 8 {
            // Medium: Foundation → Development
            let foundWeeks = max(2, Int(Double(weeks) * 0.35))
            let devWeeks = weeks - foundWeeks
            return [
                Phase(
                    focus: .foundation,
                    weeks: foundWeeks,
                    intensityRange: 0.60...0.68,
                    progressionType: .linear,
                    rationale: "Build work capacity and establish training habits"
                ),
                Phase(
                    focus: .development,
                    weeks: devWeeks,
                    intensityRange: 0.68...0.78,
                    progressionType: .linear,
                    rationale: "Progressive overload with hypertrophy-focused volume"
                )
            ]
        } else if weeks <= 16 {
            // Long: Foundation → Development → Development → Peak
            let foundWeeks = max(2, Int(Double(weeks) * 0.2))
            let peakWeeks = max(2, Int(Double(weeks) * 0.15))
            let devWeeks = weeks - foundWeeks - peakWeeks
            let dev1Weeks = devWeeks / 2
            let dev2Weeks = devWeeks - dev1Weeks
            return [
                Phase(
                    focus: .foundation,
                    weeks: foundWeeks,
                    intensityRange: 0.58...0.68,
                    progressionType: .linear,
                    rationale: "Build work capacity for high-volume training"
                ),
                Phase(
                    focus: .development,
                    weeks: dev1Weeks,
                    intensityRange: 0.68...0.75,
                    progressionType: .linear,
                    rationale: "Volume accumulation phase for muscle growth"
                ),
                Phase(
                    focus: .development,
                    weeks: dev2Weeks,
                    intensityRange: 0.72...0.80,
                    progressionType: .undulating,
                    rationale: "Intensification phase with varied rep ranges"
                ),
                Phase(
                    focus: .peak,
                    weeks: peakWeeks,
                    intensityRange: 0.78...0.85,
                    progressionType: .linear,
                    rationale: "Consolidate gains with slightly higher intensity"
                )
            ]
        } else {
            return buildAnnualCycles(weeks: weeks, goal: .muscleGain)
        }
    }

    // MARK: - Fat Loss Templates

    private static func fatLossTemplate(weeks: Int, style: PeriodizationStyle) -> [Phase] {
        if weeks <= 4 {
            return [
                Phase(
                    focus: .development,
                    weeks: weeks,
                    intensityRange: 0.60...0.72,
                    progressionType: .linear,
                    rationale: "Metabolic conditioning with strength preservation"
                )
            ]
        } else if weeks <= 12 {
            // Medium: Development cycles with maintenance break
            let dev1Weeks = Int(Double(weeks) * 0.45)
            let maintWeeks = max(1, Int(Double(weeks) * 0.15))
            let dev2Weeks = weeks - dev1Weeks - maintWeeks
            return [
                Phase(
                    focus: .development,
                    weeks: dev1Weeks,
                    intensityRange: 0.60...0.72,
                    progressionType: .linear,
                    rationale: "High-volume metabolic training for fat loss"
                ),
                Phase(
                    focus: .maintenance,
                    weeks: maintWeeks,
                    intensityRange: 0.65...0.70,
                    progressionType: .staticProgression,
                    rationale: "Diet break week - maintain intensity, reduce volume"
                ),
                Phase(
                    focus: .development,
                    weeks: dev2Weeks,
                    intensityRange: 0.65...0.75,
                    progressionType: .linear,
                    rationale: "Progressive conditioning with preserved muscle"
                )
            ]
        } else {
            return buildAnnualCycles(weeks: weeks, goal: .fatLoss)
        }
    }

    // MARK: - Endurance Templates

    private static func enduranceTemplate(weeks: Int, style: PeriodizationStyle) -> [Phase] {
        if weeks <= 4 {
            return [
                Phase(
                    focus: .foundation,
                    weeks: weeks,
                    intensityRange: 0.55...0.68,
                    progressionType: .linear,
                    rationale: "Build aerobic base and work capacity"
                )
            ]
        } else if weeks <= 12 {
            let foundWeeks = Int(Double(weeks) * 0.4)
            let devWeeks = Int(Double(weeks) * 0.4)
            let peakWeeks = weeks - foundWeeks - devWeeks
            return [
                Phase(
                    focus: .foundation,
                    weeks: foundWeeks,
                    intensityRange: 0.50...0.65,
                    progressionType: .linear,
                    rationale: "Build aerobic base with low-intensity volume"
                ),
                Phase(
                    focus: .development,
                    weeks: devWeeks,
                    intensityRange: 0.65...0.78,
                    progressionType: .undulating,
                    rationale: "Develop threshold capacity with intervals"
                ),
                Phase(
                    focus: .peak,
                    weeks: peakWeeks,
                    intensityRange: 0.78...0.88,
                    progressionType: .linear,
                    rationale: "Race-specific intensity and taper"
                )
            ]
        } else {
            return buildAnnualCycles(weeks: weeks, goal: .endurance)
        }
    }

    // MARK: - General Fitness Templates

    private static func generalFitnessTemplate(weeks: Int, style: PeriodizationStyle) -> [Phase] {
        if weeks <= 6 {
            return [
                Phase(
                    focus: .maintenance,
                    weeks: weeks,
                    intensityRange: 0.62...0.72,
                    progressionType: .linear,
                    rationale: "Balanced training for overall fitness"
                )
            ]
        } else if weeks <= 12 {
            let foundWeeks = Int(Double(weeks) * 0.3)
            let maintWeeks = weeks - foundWeeks
            return [
                Phase(
                    focus: .foundation,
                    weeks: foundWeeks,
                    intensityRange: 0.58...0.68,
                    progressionType: .linear,
                    rationale: "Establish movement quality and work capacity"
                ),
                Phase(
                    focus: .maintenance,
                    weeks: maintWeeks,
                    intensityRange: 0.65...0.75,
                    progressionType: .undulating,
                    rationale: "Varied training for well-rounded fitness"
                )
            ]
        } else {
            return buildAnnualCycles(weeks: weeks, goal: .generalFitness)
        }
    }

    // MARK: - Athletic Performance Templates

    private static func athleticTemplate(weeks: Int, style: PeriodizationStyle) -> [Phase] {
        if weeks <= 6 {
            return [
                Phase(
                    focus: .development,
                    weeks: weeks,
                    intensityRange: 0.68...0.82,
                    progressionType: .undulating,
                    rationale: "Sport-specific power and conditioning"
                )
            ]
        } else if weeks <= 16 {
            let foundWeeks = max(2, Int(Double(weeks) * 0.25))
            let devWeeks = Int(Double(weeks) * 0.45)
            let peakWeeks = weeks - foundWeeks - devWeeks
            return [
                Phase(
                    focus: .foundation,
                    weeks: foundWeeks,
                    intensityRange: 0.60...0.70,
                    progressionType: .linear,
                    rationale: "Build general physical preparedness"
                ),
                Phase(
                    focus: .development,
                    weeks: devWeeks,
                    intensityRange: 0.70...0.82,
                    progressionType: .undulating,
                    rationale: "Develop sport-specific power and explosiveness"
                ),
                Phase(
                    focus: .peak,
                    weeks: peakWeeks,
                    intensityRange: 0.82...0.92,
                    progressionType: .linear,
                    rationale: "Competition preparation and peaking"
                )
            ]
        } else {
            return buildAnnualCycles(weeks: weeks, goal: .athleticPerformance)
        }
    }

    // MARK: - Annual Cycles

    /// Build repeating mesocycles for annual plans
    private static func buildAnnualCycles(weeks: Int, goal: FitnessGoal) -> [Phase] {
        // Each cycle is ~12-13 weeks: Foundation(3) → Development(6) → Peak(2) → Deload(1-2)
        let cycleLength = 12
        let fullCycles = weeks / cycleLength
        let remainingWeeks = weeks % cycleLength

        var phases: [Phase] = []

        for cycleNum in 0..<fullCycles {
            let cyclePhases = getBaseCycle(goal: goal, cycleNumber: cycleNum + 1)
            phases.append(contentsOf: cyclePhases)
        }

        // Handle remaining weeks
        if remainingWeeks > 0 {
            if remainingWeeks <= 4 {
                phases.append(Phase(
                    focus: .maintenance,
                    weeks: remainingWeeks,
                    intensityRange: 0.65...0.72,
                    progressionType: .staticProgression,
                    rationale: "Transition period before next training block"
                ))
            } else {
                // Partial cycle
                let foundWeeks = min(3, remainingWeeks / 3)
                let devWeeks = remainingWeeks - foundWeeks
                phases.append(Phase(
                    focus: .foundation,
                    weeks: foundWeeks,
                    intensityRange: 0.60...0.68,
                    progressionType: .linear,
                    rationale: "Begin new training cycle"
                ))
                phases.append(Phase(
                    focus: .development,
                    weeks: devWeeks,
                    intensityRange: 0.68...0.78,
                    progressionType: .linear,
                    rationale: "Progressive overload continuation"
                ))
            }
        }

        return phases
    }

    /// Get a single 12-week mesocycle
    private static func getBaseCycle(goal: FitnessGoal, cycleNumber: Int) -> [Phase] {
        // Intensity ranges increase slightly each cycle (progressive difficulty)
        let intensityOffset = Double(min(cycleNumber - 1, 3)) * 0.02

        return [
            Phase(
                focus: .foundation,
                weeks: 3,
                intensityRange: (0.58 + intensityOffset)...(0.68 + intensityOffset),
                progressionType: .linear,
                rationale: "Cycle \(cycleNumber): Build work capacity and movement quality"
            ),
            Phase(
                focus: .development,
                weeks: 6,
                intensityRange: (0.68 + intensityOffset)...(0.80 + intensityOffset),
                progressionType: .linear,
                rationale: "Cycle \(cycleNumber): Progressive overload for adaptation"
            ),
            Phase(
                focus: .peak,
                weeks: 2,
                intensityRange: (0.80 + intensityOffset)...(0.88 + intensityOffset),
                progressionType: .linear,
                rationale: "Cycle \(cycleNumber): Maximize performance"
            ),
            Phase(
                focus: .deload,
                weeks: 1,
                intensityRange: 0.50...0.60,
                progressionType: .staticProgression,
                rationale: "Cycle \(cycleNumber): Active recovery before next block"
            )
        ]
    }

    // MARK: - Deload Insertion

    /// Insert deload weeks into phase structure
    private static func insertDeloads(phases: [Phase], frequency: Int) -> [Phase] {
        // If phases already have deloads (from annual cycle), skip
        if phases.contains(where: { $0.focus == .deload }) {
            return phases
        }

        var result: [Phase] = []
        var weekCount = 0

        for phase in phases {
            // Check if we need a deload before this phase
            if weekCount > 0 && weekCount % frequency == 0 {
                result.append(Phase(
                    focus: .deload,
                    weeks: 1,
                    intensityRange: 0.50...0.60,
                    progressionType: .staticProgression,
                    rationale: "Scheduled recovery week to prevent overtraining"
                ))
            }

            result.append(phase)
            weekCount += phase.weeks
        }

        return result
    }

    // MARK: - Helpers

    /// Create single-phase structure for short plans or no periodization
    private static func singlePhase(goal: FitnessGoal, weeks: Int) -> Phase {
        let (intensityRange, rationale) = goalDefaults(goal: goal)
        return Phase(
            focus: .development,
            weeks: weeks,
            intensityRange: intensityRange,
            progressionType: .linear,
            rationale: rationale
        )
    }

    /// Get default intensity range and rationale for a goal
    private static func goalDefaults(goal: FitnessGoal) -> (ClosedRange<Double>, String) {
        switch goal {
        case .strength, .powerlifting, .strengthConditioning:
            return (0.70...0.85, "Progressive strength building with compound movements")
        case .muscleGain, .bodybuilding:
            return (0.65...0.78, "Volume-focused training for muscle growth")
        case .fatLoss, .weightManagement:
            return (0.60...0.72, "Metabolic conditioning with strength preservation")
        case .endurance, .enduranceTraining:
            return (0.55...0.70, "Build aerobic capacity and work tolerance")
        case .generalFitness, .personalTraining, .nutrition, .specialPopulations:
            return (0.62...0.75, "Balanced training for overall fitness")
        case .athleticPerformance, .sportSpecific:
            return (0.68...0.82, "Sport-specific power and conditioning")
        case .mobility, .yoga, .rehabilitative:
            return (0.50...0.65, "Gentle movement with focus on form and flexibility")
        }
    }

    /// Calculate week range string for a phase (e.g., "1-3")
    private static func calculateWeekRange(phases: [Phase], index: Int) -> String {
        var startWeek = 1
        for i in 0..<index {
            startWeek += phases[i].weeks
        }
        let endWeek = startWeek + phases[index].weeks - 1
        return endWeek > startWeek ? "\(startWeek)-\(endWeek)" : "\(startWeek)"
    }
}
