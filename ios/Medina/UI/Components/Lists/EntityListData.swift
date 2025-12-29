//
// EntityListData.swift
// Medina
//
// v54.7: Typed enum for entity list modal data
// v99.1: Added users for admin sidebar
// v186: Removed class-related cases (class booking deferred for beta)
// Created: November 2025
// Purpose: Preserve type information when passing entity arrays between views
//

import Foundation

/// Typed enum that preserves entity type information through view boundaries
/// Solves Swift's type erasure issue with [AnyHashable]
enum EntityListData {
    case workouts([Workout])
    case exercises([Exercise])
    case protocols([ProtocolConfig])
    case plans([Plan])
    case programs([Program])
    case users([UnifiedUser])  // v99.1: For admin member/trainer lists
    case threads([MessageThread], userId: String)  // v189: For messages list modal
    case memberFilter([UnifiedUser])  // v190: For sidebar member filter selection (selects, doesn't navigate)
}
