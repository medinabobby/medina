//
// WorkoutScheduler.swift
// Medina
//
// Created: October 2025
// v42.0 - Plan Creation Phase 1
// v69.4 - AI-optimized day assignments support
// v69.7 - Smart interleaving fallback for cardio distribution
//
// Smart workout date scheduling service
// Honors split patterns, preferred days, and program date ranges
//

import Foundation

/// Service for scheduling workouts with smart date assignment
/// Phase 1: Generates workouts with scheduled dates only (no exercises)
enum WorkoutScheduler {

    // MARK: - Public Interface

    /// Generate workouts for a program with smart scheduling
    /// Returns workouts with scheduledDate, type, splitDay (no exercises)
    /// - Parameter dayAssignments: v69.4 - AI-provided mapping of days to workout types (optional)
    static func generateWorkouts(
        programId: String,
        startDate: Date,
        endDate: Date,
        daysPerWeek: Int,
        splitType: SplitType,
        preferredDays: Set<DayOfWeek>,
        cardioDays: Int = 0,
        dayAssignments: [DayOfWeek: SessionType]? = nil  // v69.4
    ) -> [Workout] {

        // v47.1: Validation - Prevent silent failure with 0 training days
        guard daysPerWeek > 0 || cardioDays > 0 else {
            Logger.log(.error, component: "WorkoutScheduler",
                      message: "Cannot generate workouts with 0 training days",
                      data: ["programId": programId, "daysPerWeek": daysPerWeek, "cardioDays": cardioDays])
            return []
        }

        // Calculate training days within program date range
        // v69.4: Pass AI's day assignments for optimal distribution
        let trainingDates = calculateTrainingDates(
            startDate: startDate,
            endDate: endDate,
            daysPerWeek: daysPerWeek,
            cardioDays: cardioDays,
            preferredDays: preferredDays,
            dayAssignments: dayAssignments
        )

        // Build workouts with split rotation
        return buildWorkouts(
            programId: programId,
            strengthDates: trainingDates.strength,
            cardioDates: trainingDates.cardio,
            splitType: splitType
        )
    }

    // MARK: - Date Calculation

    /// Training dates separated by type (strength vs cardio)
    private struct TrainingDates {
        let strength: [Date]
        let cardio: [Date]
    }

    /// Calculate training dates honoring preferred days and frequency
    /// Assigns strength workouts to first N preferred days, cardio to remaining days
    ///
    /// **v69.4 Strategy**: AI-optimized assignments (when provided)
    /// - AI determines optimal day→type mapping based on schedule pattern
    /// - Consecutive days: alternate strength/cardio for recovery
    /// - Split schedules: cardio on weekends when appropriate
    ///
    /// **Fallback Strategy**: Strength-first assignment
    /// - User selects 5 preferred days: Mon/Wed/Fri/Sat/Sun
    /// - 3 strength + 2 cardio → Mon/Wed/Fri (strength), Sat/Sun (cardio)
    /// - Natural recovery spacing (cardio on weekend after week of lifting)
    ///
    /// **Post-Beta**: Support advanced strategies (off-days, same-day, intensity-based)
    private static func calculateTrainingDates(
        startDate: Date,
        endDate: Date,
        daysPerWeek: Int,
        cardioDays: Int,
        preferredDays: Set<DayOfWeek>,
        dayAssignments: [DayOfWeek: SessionType]? = nil  // v69.4
    ) -> TrainingDates {

        var strengthDates: [Date] = []
        var cardioDates: [Date] = []
        let calendar = Calendar.current

        // Get ordered preferred days (Monday = 1, Sunday = 7)
        let orderedDays = preferredDays.sorted { dayNumber($0) < dayNumber($1) }

        // v69.4: Determine strength vs cardio days
        let strengthDayTypes: [DayOfWeek]
        var cardioDayTypes: [DayOfWeek]

        if let assignments = dayAssignments, !assignments.isEmpty {
            // Use AI's optimized assignments
            strengthDayTypes = orderedDays.filter { assignments[$0] == .strength }
            cardioDayTypes = orderedDays.filter { assignments[$0] == .cardio }
            Logger.log(.info, component: "WorkoutScheduler",
                      message: "✅ Using AI day assignments - Strength: \(strengthDayTypes.map { $0.displayName }), Cardio: \(cardioDayTypes.map { $0.displayName })")
        } else {
            // v69.7: Smart interleaving fallback - spreads cardio evenly among strength days
            // Instead of clustering (Mon/Tue/Wed=strength, Fri/Sat=cardio)
            // We interleave (Mon=strength, Tue=cardio, Wed=strength, Fri=strength, Sat=cardio)
            let (strength, cardio) = interleaveDays(
                orderedDays: orderedDays,
                strengthCount: daysPerWeek,
                cardioCount: cardioDays
            )
            strengthDayTypes = strength
            cardioDayTypes = cardio
            Logger.log(.warning, component: "WorkoutScheduler",
                      message: "⚠️ AI did not provide workoutDayAssignments - using interleaved fallback. Strength: \(strengthDayTypes.map { $0.displayName }), Cardio: \(cardioDayTypes.map { $0.displayName })")
        }

        // If not enough preferred days for cardio, add remaining weekdays
        if cardioDayTypes.count < cardioDays {
            let allWeekDays: [DayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            let usedDays = Set(strengthDayTypes + cardioDayTypes)
            let remainingDays = allWeekDays.filter { !usedDays.contains($0) }

            let neededDays = cardioDays - cardioDayTypes.count
            cardioDayTypes += Array(remainingDays.prefix(neededDays))
        }

        // Iterate through weeks until we reach end date
        var currentWeekStart = startOfWeek(for: startDate)

        while currentWeekStart <= endDate {
            // Add strength workouts for this week
            for day in strengthDayTypes {
                if let trainingDate = dateForDay(day, in: currentWeekStart, calendar: calendar) {
                    if trainingDate >= startDate && trainingDate <= endDate {
                        strengthDates.append(trainingDate)
                    }
                }
            }

            // Add cardio workouts for this week
            for day in cardioDayTypes {
                if let trainingDate = dateForDay(day, in: currentWeekStart, calendar: calendar) {
                    if trainingDate >= startDate && trainingDate <= endDate {
                        cardioDates.append(trainingDate)
                    }
                }
            }

            // Move to next week
            currentWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart)!
        }

        return TrainingDates(
            strength: strengthDates.sorted(),
            cardio: cardioDates.sorted()
        )
    }

    /// Get start of week (Monday) for a given date
    /// v47.1: Fixed bug mixing incompatible date components (.yearForWeekOfYear + .weekday)
    private static func startOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2  // Monday
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Get date for a specific day of week in a given week
    private static func dateForDay(_ day: DayOfWeek, in weekStart: Date, calendar: Calendar) -> Date? {
        let dayNumber = self.dayNumber(day)
        // weekStart is Monday (ISO 8601 day 1), calculate offset from Monday
        // Monday=0, Tuesday=1, Wednesday=2, Thursday=3, Friday=4, Saturday=5, Sunday=6
        let offset = dayNumber - 1 // Convert ISO day number (1-7) to offset (0-6)
        return calendar.date(byAdding: .day, value: offset, to: weekStart)
    }

    /// Convert DayOfWeek enum to ISO 8601 day number (Monday=1, Sunday=7)
    private static func dayNumber(_ day: DayOfWeek) -> Int {
        switch day {
        case .monday: return 1
        case .tuesday: return 2
        case .wednesday: return 3
        case .thursday: return 4
        case .friday: return 5
        case .saturday: return 6
        case .sunday: return 7
        }
    }

    /// v69.7: Interleave cardio days evenly among strength days for optimal recovery
    ///
    /// Example with 5 days [Mon, Tue, Wed, Fri, Sat], 3 strength + 2 cardio:
    /// - Old clustering: Mon/Tue/Wed=strength, Fri/Sat=cardio (back-to-back cardio)
    /// - New interleaving: Mon=strength, Tue=cardio, Wed=strength, Fri=cardio, Sat=strength
    ///
    /// Algorithm: Place cardio at evenly spaced intervals throughout the week
    private static func interleaveDays(
        orderedDays: [DayOfWeek],
        strengthCount: Int,
        cardioCount: Int
    ) -> (strength: [DayOfWeek], cardio: [DayOfWeek]) {
        let totalDays = orderedDays.count
        guard totalDays > 0 else { return ([], []) }

        // If no cardio, all days are strength
        guard cardioCount > 0 else {
            return (Array(orderedDays.prefix(strengthCount)), [])
        }

        // If no strength, all days are cardio
        guard strengthCount > 0 else {
            return ([], Array(orderedDays.prefix(cardioCount)))
        }

        var strengthDays: [DayOfWeek] = []
        var cardioDays: [DayOfWeek] = []

        // Calculate cardio positions to spread them evenly
        // For 5 days with 2 cardio: positions at index 1 and 3 (Tue, Fri)
        // Formula: cardio at indices floor((i+1) * totalDays / (cardioCount+1)) - 1
        var cardioIndices: Set<Int> = []
        for i in 0..<cardioCount {
            // Spread cardio evenly: index = (i+1) * total / (cardio+1) - some offset
            // Simpler approach: divide the days into (cardioCount+1) segments, put cardio at boundaries
            let position = ((i + 1) * totalDays) / (cardioCount + 1)
            let adjustedIndex = min(position, totalDays - 1)
            cardioIndices.insert(adjustedIndex)
        }

        // If we have duplicate indices (rounding issues), spread them out
        if cardioIndices.count < cardioCount {
            // Fill in missing cardio days from available slots
            for i in 0..<totalDays where cardioDays.count < cardioCount {
                if !cardioIndices.contains(i) {
                    cardioIndices.insert(i)
                    if cardioIndices.count >= cardioCount { break }
                }
            }
        }

        // Assign days based on calculated positions
        for (index, day) in orderedDays.enumerated() {
            if cardioIndices.contains(index) && cardioDays.count < cardioCount {
                cardioDays.append(day)
            } else if strengthDays.count < strengthCount {
                strengthDays.append(day)
            }
        }

        return (strengthDays, cardioDays)
    }

    // MARK: - Workout Building

    /// Build workouts with split rotation for strength and cardio
    private static func buildWorkouts(
        programId: String,
        strengthDates: [Date],
        cardioDates: [Date],
        splitType: SplitType
    ) -> [Workout] {

        var workouts: [Workout] = []
        let splitDays = getSplitDayRotation(for: splitType)

        // Build strength workouts
        for (index, date) in strengthDates.enumerated() {
            // Rotate through split days
            let splitDay = splitDays[index % splitDays.count]

            let workout = Workout(
                id: "\(programId)_w\(index + 1)",
                programId: programId,
                name: generateWorkoutName(splitDay: splitDay, date: date, index: index),
                scheduledDate: date,
                type: .strength,
                splitDay: splitDay,
                status: .scheduled,
                completedDate: nil,
                exerciseIds: [], // Phase 2: Exercise selection
                protocolVariantIds: [:], // Empty dictionary (no protocols assigned yet)
                exercisesSelectedAt: nil,
                supersetGroups: nil,
                protocolCustomizations: nil
            )

            workouts.append(workout)
        }

        // Build cardio workouts
        for (index, date) in cardioDates.enumerated() {
            let cardioIndex = strengthDates.count + index + 1

            let workout = Workout(
                id: "\(programId)_w\(cardioIndex)",
                programId: programId,
                name: generateCardioWorkoutName(date: date, index: index),
                scheduledDate: date,
                type: .cardio,
                splitDay: .notApplicable,
                status: .scheduled,
                completedDate: nil,
                exerciseIds: [], // Phase 2: Exercise selection (1 cardio exercise)
                protocolVariantIds: [:], // Empty dictionary (no protocols for cardio)
                exercisesSelectedAt: nil,
                supersetGroups: nil,
                protocolCustomizations: nil
            )

            workouts.append(workout)
        }

        // Sort by scheduled date for chronological display
        return workouts.sorted { $0.scheduledDate ?? Date.distantPast < $1.scheduledDate ?? Date.distantPast }
    }

    /// Get split day rotation pattern for a split type
    private static func getSplitDayRotation(for splitType: SplitType) -> [SplitDay] {
        switch splitType {
        case .fullBody:
            return [.fullBody]

        case .upperLower:
            return [.upper, .lower]

        case .pushPull:
            return [.push, .pull]

        case .pushPullLegs:
            return [.push, .pull, .legs]

        case .bodyPart:
            // 5-day body part split: Chest, Back, Shoulders, Legs, Arms
            return [.chest, .back, .shoulders, .legs, .arms]
        }
    }

    /// Generate descriptive workout name
    private static func generateWorkoutName(splitDay: SplitDay, date: Date, index: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d" // "Oct 27"

        return "\(splitDay.displayName) - \(formatter.string(from: date))"
    }

    /// Generate cardio workout name
    private static func generateCardioWorkoutName(date: Date, index: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d" // "Oct 27"

        return "Cardio Session - \(formatter.string(from: date))"
    }

    /// Extract memberId from programId (format: "prog_plan_{memberId}_{...}")
    private static func extractMemberId(from programId: String) -> String {
        // programId format: "prog_plan_{memberId}_{uuid}_{index}"
        // Extract middle component
        let components = programId.split(separator: "_")
        if components.count >= 3 {
            // Find "plan" component, memberId is next
            if let planIndex = components.firstIndex(of: "plan") {
                let memberIndex = planIndex + 1
                if memberIndex < components.count {
                    return String(components[memberIndex])
                }
            }
        }
        return ""
    }
}
