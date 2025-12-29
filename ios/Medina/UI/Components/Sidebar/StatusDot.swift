//
// StatusDot.swift
// Medina
//
// Reusable status dot component for sidebar items
// Consistent color semantics matching badge schema
//

import SwiftUI

/// Status dot component for sidebar items
/// Blue = Active/Starred, Green = Completed, Grey = Draft/Scheduled/Inactive
struct StatusDot: View {
    enum Status {
        case active      // Blue - active plan, in-progress workout, active membership
        case completed   // Green - completed workout/class
        case scheduled   // Grey - scheduled workout, draft plan
        case inactive    // Grey - inactive/pending membership
        case starred     // Blue - user explicitly favorited
        case unstarred   // Grey - not starred (default state)
        case skipped     // Orange - skipped workout
    }

    let status: Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .active, .starred:
            return .accentColor
        case .completed:
            return .green
        case .scheduled, .inactive, .unstarred:
            return Color("SecondaryText")
        case .skipped:
            return .orange
        }
    }
}

// MARK: - Convenience Initializers

extension StatusDot {
    /// Create status dot from PlanStatus
    /// v172: Removed abandoned - plans are now draft/active/completed only
    init(planStatus: PlanStatus) {
        switch planStatus {
        case .active:
            self.status = .active
        case .draft:
            self.status = .scheduled
        case .completed:
            self.status = .completed
        }
    }

    /// Create status dot from ExecutionStatus (workouts)
    init(executionStatus: ExecutionStatus) {
        switch executionStatus {
        case .completed:
            self.status = .completed
        case .inProgress:
            self.status = .active
        case .scheduled:
            self.status = .scheduled
        case .skipped:
            self.status = .skipped
        }
    }

    /// Create status dot from MembershipStatus
    init(membershipStatus: MembershipStatus?) {
        switch membershipStatus {
        case .active:
            self.status = .active
        case .pending, .expired, .suspended, .cancelled, .none:
            self.status = .inactive
        }
    }

    /// Create status dot from favorite state
    init(isFavorite: Bool) {
        self.status = isFavorite ? .starred : .unstarred
    }

    // v186: Removed ClassStatus initializer (class booking deferred for beta)
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 20) {
            VStack {
                StatusDot(status: .active)
                Text("Active").font(.caption)
            }
            VStack {
                StatusDot(status: .completed)
                Text("Complete").font(.caption)
            }
            VStack {
                StatusDot(status: .scheduled)
                Text("Scheduled").font(.caption)
            }
            VStack {
                StatusDot(status: .starred)
                Text("Starred").font(.caption)
            }
            VStack {
                StatusDot(status: .skipped)
                Text("Skipped").font(.caption)
            }
        }
    }
    .padding()
}
