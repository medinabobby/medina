//
//  SidebarFilter.swift
//  Medina
//
//  v105: Unified filter enum for sidebar context
//
//  Represents all possible filter states across trainer and admin roles.
//  Supports trainer member selection AND gym manager drill-down.
//

import Foundation

/// Unified filter states for sidebar content filtering
enum SidebarFilter: Equatable, Hashable {
    // Aggregate views (no specific selection)
    case allMembers              // Default: show all/aggregate data
    case allTrainers             // Gym manager: view all trainers
    case classSchedule           // Gym manager: view class schedule

    // Trainer selecting a member
    case member(String)          // memberId - trainer viewing specific member

    // Gym manager selecting a trainer (for drill-down)
    case trainer(String)         // trainerId - manager viewing trainer

    // Gym manager drilling into trainer's member
    case trainerMember(String, String)  // (trainerId, memberId)

    /// Whether this filter shows aggregate data (no specific selection)
    var isAggregate: Bool {
        switch self {
        case .allMembers, .allTrainers, .classSchedule:
            return true
        default:
            return false
        }
    }

    /// Icon for filter row display
    var icon: String {
        switch self {
        case .allMembers:
            return "person.2.fill"
        case .allTrainers:
            return "figure.run"
        case .classSchedule:
            return "calendar.badge.clock"
        case .member, .trainerMember:
            return "person.fill"
        case .trainer:
            return "figure.run"
        }
    }

    /// Display title for the filter (used in filter section header)
    var title: String {
        switch self {
        case .allMembers:
            return "All Members"
        case .allTrainers:
            return "All Trainers"
        case .classSchedule:
            return "Class Schedule"
        case .member, .trainer, .trainerMember:
            // These need member/trainer name lookup - handled by SidebarContext
            return ""
        }
    }
}
