import Foundation

extension Exercise {
    /// Returns the display name with equipment prefix
    /// Example: "Overhead Press" with equipment="barbell" → "Barbell Overhead Press"
    /// v87.6: Fixed - Don't add prefix if name already contains it (prevents "Dumbbell Dumbbell...")
    var exerciseDisplayName: String {
        let equipmentPrefix = equipment.exercisePrefix

        // If equipment prefix is empty, just return name
        if equipmentPrefix.isEmpty {
            return name
        }

        // v87.6: Check if name already starts with the equipment prefix (case-insensitive)
        if name.lowercased().hasPrefix(equipmentPrefix.lowercased()) {
            return name
        }

        // Add equipment prefix
        return "\(equipmentPrefix) \(name)"
    }
}

extension Equipment {
    /// Returns equipment prefix for exercise names
    /// Example: .barbell → "Barbell", .cableMachine → "Cable"
    var exercisePrefix: String {
        switch self {
        case .barbell:
            return "Barbell"
        case .dumbbells:
            return "Dumbbell"
        case .cableMachine:
            return "Cable"
        case .bodyweight:
            return ""  // Don't prefix bodyweight exercises
        case .kettlebell:
            return "Kettlebell"
        case .resistanceBand:
            return "Resistance Band"
        case .machine:
            return "Machine"
        case .smith:
            return "Smith"
        case .trx:
            return "TRX"
        case .bench:
            return "Bench"
        case .squatRack:
            return "Squat Rack"
        case .pullupBar:
            return ""  // Don't prefix (e.g., "Pull-up" not "Pull-up Bar Pull-up")
        case .dipStation:
            return ""  // Don't prefix
        case .treadmill:
            return "Treadmill"
        case .bike:
            return "Bike"
        case .rower:
            return "Rower"
        case .elliptical:
            return "Elliptical"
        case .skiErg:
            return "Ski Erg"
        case .none:
            return ""
        }
    }
}
