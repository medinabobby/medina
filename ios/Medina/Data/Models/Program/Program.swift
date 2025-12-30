//
// Program.swift
// Medina
//
// Last reviewed: October 2025
//

import Foundation

struct Program: Identifiable, Codable {
    // Identity & Relationships
    let id: String
    let planId: String
    
    // AI-Generated Strategy
    var name: String
    var focus: TrainingFocus
    var rationale: String
    
    // Program Schedule
    var startDate: Date
    var endDate: Date
    
    // Progression Strategy
    var startingIntensity: Double
    var endingIntensity: Double
    var progressionType: ProgressionType

    // v21.0: Status field (stored, not computed)
    var status: ProgramStatus

    // MARK: - Computed Status Pattern

    /// Computed effective status that inherits from parent plan and applies date-based logic
    ///
    /// **Pattern: Status Inheritance with Date-Based Overrides**
    ///
    /// Rules:
    /// 1. **Inheritance**: Programs inherit parent plan status for completed/abandoned/draft plans
    /// 2. **Date-based overrides**: For active plans, program status depends on dates:
    ///    - Future programs (now < startDate) → `.draft` (grey "Not Started")
    ///    - Current programs (startDate ≤ now ≤ endDate) → `.active` (blue "In Progress")
    ///    - Past programs (now > endDate) → `.completed` (green)
    ///
    /// Example (Active Plan):
    /// ```
    /// Plan: "Powerlifting" (Active)
    ///   1. Development (Oct 1-31, current) → .active (blue)
    ///   2. Peak (Nov 1-30, future) → .draft (grey)
    ///   3. Maintenance (Dec 1-31, future) → .draft (grey)
    /// ```
    ///
    /// Example (Completed Plan):
    /// ```
    /// Plan: "Muscle Gain" (Completed)
    ///   All programs → .completed (green)
    /// ```
    ///
    /// Used by:
    /// - PlanShowHandler: Determines left stripe color and badge for program rows
    /// - UI components: Badge color mapping (green/blue/grey/orange)
    ///
    /// - Returns: Computed program status considering parent plan and dates
    var effectiveStatus: ProgramStatus {
        // Get parent plan
        guard let plan = LocalDataStore.shared.plans[planId] else {
            return status  // Fallback to stored status if no parent found
        }

        let now = Date()

        // v172: If plan is completed (natural or early), all programs are completed
        if plan.effectiveStatus == .completed {
            return .completed
        }

        // If plan is draft, all programs are draft
        if plan.effectiveStatus == .draft {
            return .draft
        }

        // Plan is active - check program dates
        if now < startDate {
            return .draft  // Future program = "Not Started" (grey)
        } else if now > endDate {
            return .completed  // Past program = completed (green)
        } else {
            return .active  // Current program = "In Progress" (blue)
        }
    }
}
