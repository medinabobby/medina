//
// LibraryPersistenceService.swift
// Medina
//
// v51.0 - Exercise & Protocol Library (Phase 1a)
// Created: November 5, 2025
//
// Purpose: Save and load user libraries to/from disk
// Storage: Documents/{userId}/library/exercises.json and protocols.json
// Separate from UserPersistenceStore to keep library concerns isolated
//

import Foundation

enum LibraryPersistenceService {

    // MARK: - Storage Paths

    private static func libraryDirectory(for userId: String) -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL
            .appendingPathComponent(userId)
            .appendingPathComponent("library")
    }

    private static func exercisesFileURL(for userId: String) -> URL {
        libraryDirectory(for: userId).appendingPathComponent("exercises.json")
    }

    private static func protocolsFileURL(for userId: String) -> URL {
        libraryDirectory(for: userId).appendingPathComponent("protocols.json")
    }

    // MARK: - Save

    /// Save user library to disk
    static func save(_ library: UserLibrary) throws {
        let libraryDir = libraryDirectory(for: library.id)

        // Create directory if needed
        try FileManager.default.createDirectory(
            at: libraryDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Save exercises
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let exercisesData = try encoder.encode(library.exercises)
        try exercisesData.write(to: exercisesFileURL(for: library.id))

        // Save protocols
        let protocolsData = try encoder.encode(library.protocols)
        try protocolsData.write(to: protocolsFileURL(for: library.id))

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Saved library for user \(library.id): \(library.exercises.count) exercises, \(library.protocols.count) protocols")
    }

    // MARK: - Load

    /// Load user library from disk
    /// Returns nil if no library exists (first time user)
    static func load(userId: String) throws -> UserLibrary? {
        let exercisesURL = exercisesFileURL(for: userId)
        let protocolsURL = protocolsFileURL(for: userId)

        // Check if library exists
        guard FileManager.default.fileExists(atPath: exercisesURL.path),
              FileManager.default.fileExists(atPath: protocolsURL.path) else {
            Logger.log(.info, component: "LibraryPersistenceService",
                       message: "No library found for user \(userId)")
            return nil
        }

        // Load exercises (now just Set<String>)
        let exercisesData = try Data(contentsOf: exercisesURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exercises = try decoder.decode(Set<String>.self, from: exercisesData)

        // Load protocols
        let protocolsData = try Data(contentsOf: protocolsURL)
        let protocols = try decoder.decode([ProtocolLibraryEntry].self, from: protocolsData)

        // Reconstruct library
        var library = UserLibrary(userId: userId)
        library.exercises = exercises
        library.protocols = protocols
        library.lastModified = Date()  // Update to current time

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Loaded library for user \(userId): \(exercises.count) exercises, \(protocols.count) protocols")

        // v82.0: Migrate to add new equipment-optimized protocols if missing
        let migratedLibrary = migrateLibraryIfNeeded(library)

        return migratedLibrary
    }

    // MARK: - v82.0 Migration (DISABLED in v89)

    /// v89: Migration disabled - users now build libraries through usage
    /// Keeping method for backward compatibility but it no longer auto-adds items
    private static func migrateLibraryIfNeeded(_ library: UserLibrary) -> UserLibrary {
        // v89: No longer auto-add exercises/protocols to libraries
        // Users build their library through:
        // 1. Starring items
        // 2. Creating workouts (auto-adds selected items)
        // 3. Activating plans (auto-adds all items)
        return library
    }

    // MARK: - Exercise Library Management (v70.0)

    /// Add an exercise to user's library
    @MainActor
    static func addExercise(_ exerciseId: String, userId: String) throws {
        var library = LocalDataStore.shared.libraries[userId] ?? UserLibrary(userId: userId)

        // Check if already in library
        guard !library.exercises.contains(exerciseId) else {
            Logger.log(.info, component: "LibraryPersistenceService",
                       message: "Exercise \(exerciseId) already in library")
            return
        }

        library.exercises.insert(exerciseId)
        library.lastModified = Date()

        // Update in-memory
        LocalDataStore.shared.libraries[userId] = library

        // Persist to disk
        try save(library)

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Added exercise \(exerciseId) to library (now \(library.exercises.count) exercises)")
    }

    /// Remove an exercise from user's library
    @MainActor
    static func removeExercise(_ exerciseId: String, userId: String) throws {
        guard var library = LocalDataStore.shared.libraries[userId] else {
            Logger.log(.warning, component: "LibraryPersistenceService",
                       message: "No library found for user \(userId)")
            return
        }

        guard library.exercises.contains(exerciseId) else {
            Logger.log(.info, component: "LibraryPersistenceService",
                       message: "Exercise \(exerciseId) not in library")
            return
        }

        library.exercises.remove(exerciseId)
        library.lastModified = Date()

        // Update in-memory
        LocalDataStore.shared.libraries[userId] = library

        // Persist to disk
        try save(library)

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Removed exercise \(exerciseId) from library (now \(library.exercises.count) exercises)")
    }

    /// Add multiple exercises to user's library (batch operation for plan activation)
    @MainActor
    static func addExercises(_ exerciseIds: [String], userId: String) throws {
        var library = LocalDataStore.shared.libraries[userId] ?? UserLibrary(userId: userId)

        let previousCount = library.exercises.count
        for exerciseId in exerciseIds {
            library.exercises.insert(exerciseId)
        }
        library.lastModified = Date()

        let addedCount = library.exercises.count - previousCount

        // Update in-memory
        LocalDataStore.shared.libraries[userId] = library

        // Persist to disk
        try save(library)

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Added \(addedCount) exercises to library (now \(library.exercises.count) exercises)")
    }

    /// Check if an exercise is in user's library
    @MainActor
    static func isExerciseInLibrary(_ exerciseId: String, userId: String) -> Bool {
        guard let library = LocalDataStore.shared.libraries[userId] else {
            return false
        }
        return library.exercises.contains(exerciseId)
    }

    // MARK: - Protocol Library Management (v71.0)

    /// Add multiple protocols to user's library (batch operation for plan activation)
    @MainActor
    static func addProtocols(_ protocolIds: [String], userId: String) throws {
        var library = LocalDataStore.shared.libraries[userId] ?? UserLibrary(userId: userId)

        let existingProtocolIds = Set(library.protocols.map { $0.protocolConfigId })
        let newProtocolIds = protocolIds.filter { !existingProtocolIds.contains($0) }

        guard !newProtocolIds.isEmpty else {
            Logger.log(.debug, component: "LibraryPersistenceService",
                       message: "All protocols already in library")
            return
        }

        // Create new protocol entries with default settings
        for protocolId in newProtocolIds {
            let entry = ProtocolLibraryEntry(
                protocolConfigId: protocolId,
                isEnabled: true,
                applicableTo: [.compound, .isolation],
                intensityRange: 0.0...1.0,
                preferredGoals: []
            )
            library.protocols.append(entry)
        }
        library.lastModified = Date()

        // Update in-memory
        LocalDataStore.shared.libraries[userId] = library

        // Persist to disk
        try save(library)

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Added \(newProtocolIds.count) protocols to library (now \(library.protocols.count) protocols)")
    }

    /// Check if a protocol is in user's library
    @MainActor
    static func isProtocolInLibrary(_ protocolId: String, userId: String) -> Bool {
        guard let library = LocalDataStore.shared.libraries[userId] else {
            return false
        }
        return library.protocols.contains { $0.protocolConfigId == protocolId }
    }

    // MARK: - Delete

    /// Delete user library from disk
    static func delete(userId: String) throws {
        let libraryDir = libraryDirectory(for: userId)

        guard FileManager.default.fileExists(atPath: libraryDir.path) else {
            return  // Nothing to delete
        }

        try FileManager.default.removeItem(at: libraryDir)

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Deleted library for user \(userId)")
    }

    // MARK: - Seed Data Import

    /// v89: Empty seed library for new users
    /// Users build their library through:
    /// 1. Starring exercises/protocols
    /// 2. Creating workouts (auto-adds selected items)
    /// 3. Activating plans (auto-adds all exercises/protocols)
    static func loadSeedLibrary() throws -> UserLibrary {
        var library = UserLibrary(userId: "seed")
        library.exercises = []      // v89: Empty - users build through usage
        library.protocols = []      // v89: Empty - users build through usage
        library.lastModified = Date()

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "v89: Created empty seed library for new user")

        return library
    }

    // MARK: - Single Protocol Management (v89)

    /// Add a single protocol to user's library (for starring)
    @MainActor
    static func addProtocol(_ protocolId: String, userId: String) throws {
        var library = LocalDataStore.shared.libraries[userId] ?? UserLibrary(userId: userId)

        // Check if already in library
        guard !library.protocols.contains(where: { $0.protocolConfigId == protocolId }) else {
            Logger.log(.debug, component: "LibraryPersistenceService",
                       message: "Protocol \(protocolId) already in library")
            return
        }

        // Create entry with defaults
        let entry = ProtocolLibraryEntry(
            protocolConfigId: protocolId,
            isEnabled: true,
            applicableTo: [.compound, .isolation],
            intensityRange: 0.0...1.0,
            preferredGoals: []
        )
        library.protocols.append(entry)
        library.lastModified = Date()

        // Update in-memory
        LocalDataStore.shared.libraries[userId] = library

        // Persist to disk
        try save(library)

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Added protocol \(protocolId) to library (now \(library.protocols.count) protocols)")
    }

    /// Remove a single protocol from user's library (for un-starring)
    @MainActor
    static func removeProtocol(_ protocolId: String, userId: String) throws {
        guard var library = LocalDataStore.shared.libraries[userId] else {
            Logger.log(.warning, component: "LibraryPersistenceService",
                       message: "No library found for user \(userId)")
            return
        }

        let previousCount = library.protocols.count
        library.protocols.removeAll { $0.protocolConfigId == protocolId }

        guard library.protocols.count < previousCount else {
            Logger.log(.debug, component: "LibraryPersistenceService",
                       message: "Protocol \(protocolId) was not in library")
            return
        }

        library.lastModified = Date()

        // Update in-memory
        LocalDataStore.shared.libraries[userId] = library

        // Persist to disk
        try save(library)

        Logger.log(.info, component: "LibraryPersistenceService",
                   message: "Removed protocol \(protocolId) from library (now \(library.protocols.count) protocols)")
    }
}

// MARK: - Errors

enum LibraryPersistenceError: LocalizedError {
    // No errors needed - programmatic seed building can't fail
}
