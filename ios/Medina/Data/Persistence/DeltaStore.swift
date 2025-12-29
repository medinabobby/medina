//
// DeltaStore.swift
// Medina
//
// v16.4 - Version-scoped delta persistence
// Last reviewed: October 2025
//

import Foundation

/// Manages persistence of user data changes (deltas) to UserDefaults
/// Version-scoped: Each app version gets its own delta storage
/// On TestFlight update, old deltas are ignored and user gets fresh start
class DeltaStore {
    static let shared = DeltaStore()

    private let defaults = UserDefaults.standard
    private let appVersion: String

    private init() {
        // Get app version from Info.plist
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: - Keys (Version-Scoped)

    /// Version-scoped key for workout deltas
    /// Example: "medina.workout.deltas.v16.4.0"
    private var workoutDeltasKey: String {
        "medina.workout.deltas.v\(appVersion)"
    }

    /// Version-scoped key for set deltas
    /// Example: "medina.set.deltas.v17.0.0"
    private var setDeltasKey: String {
        "medina.set.deltas.v\(appVersion)"
    }

    /// Version-scoped key for instance deltas
    /// Example: "medina.instance.deltas.v17.4.0"
    private var instanceDeltasKey: String {
        "medina.instance.deltas.v\(appVersion)"
    }

    // MARK: - Models

    /// Represents a change to a workout's fields
    struct WorkoutDelta: Codable, Identifiable {
        let id: UUID
        let workoutId: String
        let scheduledDate: Date?
        let completion: ExecutionStatus?
        let timestamp: Date

        init(id: UUID = UUID(), workoutId: String, scheduledDate: Date? = nil, completion: ExecutionStatus? = nil, timestamp: Date = Date()) {
            self.id = id
            self.workoutId = workoutId
            self.scheduledDate = scheduledDate
            self.completion = completion
            self.timestamp = timestamp
        }
    }

    /// Represents a change to a set's fields (v17.0)
    /// v101.2: Added actualDuration and actualDistance for cardio sets
    struct SetDelta: Codable, Identifiable {
        let id: UUID
        let setId: String
        let actualWeight: Double?
        let actualReps: Int?
        let completion: ExecutionStatus?
        let recordedDate: Date?
        let notes: String?
        // v101.2: Cardio fields
        let actualDuration: Int?       // Seconds
        let actualDistance: Double?    // Miles
        let timestamp: Date

        init(
            id: UUID = UUID(),
            setId: String,
            actualWeight: Double? = nil,
            actualReps: Int? = nil,
            completion: ExecutionStatus? = nil,
            recordedDate: Date? = nil,
            notes: String? = nil,
            actualDuration: Int? = nil,
            actualDistance: Double? = nil,
            timestamp: Date = Date()
        ) {
            self.id = id
            self.setId = setId
            self.actualWeight = actualWeight
            self.actualReps = actualReps
            self.completion = completion
            self.recordedDate = recordedDate
            self.notes = notes
            self.actualDuration = actualDuration
            self.actualDistance = actualDistance
            self.timestamp = timestamp
        }
    }

    /// Represents a change to an exercise instance's fields (v17.4)
    struct InstanceDelta: Codable, Identifiable {
        let id: UUID
        let instanceId: String
        let completion: ExecutionStatus?
        let timestamp: Date

        init(
            id: UUID = UUID(),
            instanceId: String,
            completion: ExecutionStatus? = nil,
            timestamp: Date = Date()
        ) {
            self.id = id
            self.instanceId = instanceId
            self.completion = completion
            self.timestamp = timestamp
        }
    }

    // MARK: - Workout Deltas

    /// Save a workout delta to UserDefaults
    func saveWorkoutDelta(_ delta: WorkoutDelta) {
        var deltas = loadWorkoutDeltas()
        deltas.append(delta)

        do {
            let data = try JSONEncoder().encode(deltas)
            defaults.set(data, forKey: workoutDeltasKey)
            defaults.synchronize() // Force immediate write

            print("💾 DeltaStore: Saved workout delta for \(delta.workoutId)")
        } catch {
            print("❌ DeltaStore: Failed to encode workout delta: \(error)")
        }
    }

    /// Load all workout deltas for current app version
    func loadWorkoutDeltas() -> [WorkoutDelta] {
        guard let data = defaults.data(forKey: workoutDeltasKey) else {
            return []
        }

        do {
            let deltas = try JSONDecoder().decode([WorkoutDelta].self, from: data)
            print("📦 DeltaStore: Loaded \(deltas.count) workout deltas from v\(appVersion)")
            return deltas
        } catch {
            print("❌ DeltaStore: Failed to decode workout deltas: \(error)")
            return []
        }
    }

    /// Apply workout deltas to freshly loaded workout data
    /// Returns updated workouts dictionary with deltas applied
    func applyWorkoutDeltas(to workouts: [String: Workout]) -> [String: Workout] {
        var updated = workouts
        let deltas = loadWorkoutDeltas()

        // Group deltas by workoutId, keeping only the latest for each field
        var latestDeltas: [String: WorkoutDelta] = [:]
        for delta in deltas.sorted(by: { $0.timestamp < $1.timestamp }) {
            latestDeltas[delta.workoutId] = delta
        }

        // Apply each delta
        var appliedCount = 0
        for (workoutId, delta) in latestDeltas {
            guard var workout = updated[workoutId] else {
                print("⚠️ DeltaStore: Workout \(workoutId) not found in base data, skipping delta")
                continue
            }

            if let date = delta.scheduledDate {
                workout.scheduledDate = date
            }
            if let completion = delta.completion {
                workout.status = completion
            }

            updated[workoutId] = workout
            appliedCount += 1
        }

        if appliedCount > 0 {
            print("✅ DeltaStore: Applied \(appliedCount) workout deltas")
        }

        return updated
    }

    // MARK: - Set Deltas (v17.0)

    /// Save a set delta to UserDefaults
    func saveSetDelta(_ delta: SetDelta) {
        var deltas = loadSetDeltas()
        deltas.append(delta)

        do {
            let data = try JSONEncoder().encode(deltas)
            defaults.set(data, forKey: setDeltasKey)
            defaults.synchronize() // Force immediate write

            print("💾 DeltaStore: Saved set delta for \(delta.setId)")
        } catch {
            print("❌ DeltaStore: Failed to encode set delta: \(error)")
        }
    }

    /// Load all set deltas for current app version
    func loadSetDeltas() -> [SetDelta] {
        guard let data = defaults.data(forKey: setDeltasKey) else {
            return []
        }

        do {
            let deltas = try JSONDecoder().decode([SetDelta].self, from: data)
            print("📦 DeltaStore: Loaded \(deltas.count) set deltas from v\(appVersion)")
            return deltas
        } catch {
            print("❌ DeltaStore: Failed to decode set deltas: \(error)")
            return []
        }
    }

    /// Apply set deltas to freshly loaded set data
    /// Returns updated sets dictionary with deltas applied
    func applySetDeltas(to sets: [String: ExerciseSet]) -> [String: ExerciseSet] {
        var updated = sets
        let deltas = loadSetDeltas()

        // Group deltas by setId, keeping only the latest for each field
        var latestDeltas: [String: SetDelta] = [:]
        for delta in deltas.sorted(by: { $0.timestamp < $1.timestamp }) {
            latestDeltas[delta.setId] = delta
        }

        // Apply each delta
        var appliedCount = 0
        for (setId, delta) in latestDeltas {
            guard var set = updated[setId] else {
                print("⚠️ DeltaStore: Set \(setId) not found in base data, skipping delta")
                continue
            }

            if let weight = delta.actualWeight {
                set.actualWeight = weight
            }
            if let reps = delta.actualReps {
                set.actualReps = reps
            }
            if let completion = delta.completion {
                set.completion = completion
            }
            if let date = delta.recordedDate {
                set.recordedDate = date
            }
            if let notes = delta.notes {
                set.notes = notes
            }
            // v101.2: Apply cardio fields
            if let duration = delta.actualDuration {
                set.actualDuration = duration
            }
            if let distance = delta.actualDistance {
                set.actualDistance = distance
            }

            updated[setId] = set
            appliedCount += 1
        }

        if appliedCount > 0 {
            print("✅ DeltaStore: Applied \(appliedCount) set deltas")
        }

        return updated
    }

    // MARK: - Instance Deltas (v17.4)

    /// Save an instance delta to UserDefaults
    func saveInstanceDelta(_ delta: InstanceDelta) {
        var deltas = loadInstanceDeltas()
        deltas.append(delta)

        do {
            let data = try JSONEncoder().encode(deltas)
            defaults.set(data, forKey: instanceDeltasKey)
            defaults.synchronize() // Force immediate write

            print("💾 DeltaStore: Saved instance delta for \(delta.instanceId)")
        } catch {
            print("❌ DeltaStore: Failed to encode instance delta: \(error)")
        }
    }

    /// Load all instance deltas for current app version
    func loadInstanceDeltas() -> [InstanceDelta] {
        guard let data = defaults.data(forKey: instanceDeltasKey) else {
            return []
        }

        do {
            let deltas = try JSONDecoder().decode([InstanceDelta].self, from: data)
            print("📦 DeltaStore: Loaded \(deltas.count) instance deltas from v\(appVersion)")
            return deltas
        } catch {
            print("❌ DeltaStore: Failed to decode instance deltas: \(error)")
            return []
        }
    }

    /// Apply instance deltas to freshly loaded instance data
    /// Returns updated instances dictionary with deltas applied
    func applyInstanceDeltas(to instances: [String: ExerciseInstance]) -> [String: ExerciseInstance] {
        var updated = instances
        let deltas = loadInstanceDeltas()

        // Group deltas by instanceId, keeping only the latest for each field
        var latestDeltas: [String: InstanceDelta] = [:]
        for delta in deltas.sorted(by: { $0.timestamp < $1.timestamp }) {
            latestDeltas[delta.instanceId] = delta
        }

        // Apply each delta
        var appliedCount = 0
        for (instanceId, delta) in latestDeltas {
            guard var instance = updated[instanceId] else {
                print("⚠️ DeltaStore: Instance \(instanceId) not found in base data, skipping delta")
                continue
            }

            if let completion = delta.completion {
                instance.status = completion
            }

            updated[instanceId] = instance
            appliedCount += 1
        }

        if appliedCount > 0 {
            print("✅ DeltaStore: Applied \(appliedCount) instance deltas")
        }

        return updated
    }

    // MARK: - Debug & Maintenance

    /// Clear all workout deltas for current version
    func clearWorkoutDeltas() {
        defaults.removeObject(forKey: workoutDeltasKey)
        defaults.synchronize()
        print("🗑️ DeltaStore: Cleared all workout deltas for v\(appVersion)")
    }

    /// Clear all set deltas for current version
    func clearSetDeltas() {
        defaults.removeObject(forKey: setDeltasKey)
        defaults.synchronize()
        print("🗑️ DeltaStore: Cleared all set deltas for v\(appVersion)")
    }

    /// Clear all instance deltas for current version
    func clearInstanceDeltas() {
        defaults.removeObject(forKey: instanceDeltasKey)
        defaults.synchronize()
        print("🗑️ DeltaStore: Cleared all instance deltas for v\(appVersion)")
    }

    /// Clear all deltas (workouts, sets, and instances) for current version
    func clearAllDeltas() {
        clearWorkoutDeltas()
        clearSetDeltas()
        clearInstanceDeltas()
        print("🗑️ DeltaStore: Cleared all deltas for v\(appVersion)")
    }

    /// Clear ALL deltas across all versions (for debugging)
    func clearAllVersions() {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("medina.") && key.contains(".deltas.") {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        print("🗑️ DeltaStore: Cleared deltas for all versions")
    }

    // MARK: - Filtered Clear (for reset functionality)

    /// Clear deltas for specific sets
    func clearSetDeltas(for setIds: Set<String>) {
        var deltas = loadSetDeltas()
        deltas.removeAll { setIds.contains($0.setId) }

        if let data = try? JSONEncoder().encode(deltas) {
            defaults.set(data, forKey: setDeltasKey)
            defaults.synchronize()
        }
    }

    /// Clear deltas for specific instances
    func clearInstanceDeltas(for instanceIds: Set<String>) {
        var deltas = loadInstanceDeltas()
        deltas.removeAll { instanceIds.contains($0.instanceId) }

        if let data = try? JSONEncoder().encode(deltas) {
            defaults.set(data, forKey: instanceDeltasKey)
            defaults.synchronize()
        }
    }

    /// Check if workout has any deltas (simple check - good enough for beta)
    func hasWorkoutDeltas(_ workoutId: String) -> Bool {
        return loadWorkoutDeltas().contains { $0.workoutId == workoutId }
    }

    /// Get current app version
    var currentVersion: String {
        appVersion
    }

    /// Get summary of current deltas for debugging
    func getDeltaSummary() -> String {
        let workoutDeltas = loadWorkoutDeltas()
        let setDeltas = loadSetDeltas()
        let instanceDeltas = loadInstanceDeltas()
        return """
        DeltaStore Summary (v\(appVersion)):
        - Workout deltas: \(workoutDeltas.count)
        - Set deltas: \(setDeltas.count)
        - Instance deltas: \(instanceDeltas.count)
        """
    }
}
