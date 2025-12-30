//
// LocalDataLoader.swift
// Medina
//
// Created: October 2025
// Purpose: JSON data loading service for LocalDataStore
//
// v196: Zero local JSONs
// - Protocols, gyms, exercises all loaded from Firestore
// - Local JSONs used for initial seeding only
// - All user data loaded from Firestore via loadUserDataFromFirestore()
//

import Foundation

/// Loads JSON data files from the main bundle into LocalDataStore
/// Used by both the app (LoginView) and test suite
enum LocalDataLoader {

    /// Initialize data manager for Firestore loading
    /// v196: Zero local JSONs - all reference data loaded from Firestore
    static func loadAll() throws {
        let manager = LocalDataStore.shared

        Logger.log(.info, component: "DataLoader", message: "v196: Zero local JSONs - Firestore is source of truth")

        // v196: No local JSONs to load
        // All reference data (exercises, protocols, gyms) loaded from Firestore
        // via loadReferenceDataFromFirestore() after Firebase Auth

        manager.isDataLoaded = true
        Logger.log(.info, component: "DataLoader", message: "Data manager initialized (awaiting Firestore)")
    }

    // MARK: - v196 Reference Data from Firestore

    /// Load all reference data from Firestore
    /// v196: Primary source for protocols, gyms, exercises
    @MainActor
    static func loadReferenceDataFromFirestore() async {
        Logger.log(.info, component: "DataLoader", message: "Loading reference data from Firestore...")

        // Load protocols from Firestore
        await loadProtocolsFromFirestore()

        // Load gyms from Firestore
        await loadGymsFromFirestore()

        // Load exercises from Firestore (already implemented)
        await loadExercisesFromFirestore()

        Logger.log(.info, component: "DataLoader", message: "☁️ Reference data loaded from Firestore")
    }

    /// Load protocols from Firestore
    /// v196: Firestore is sole source (no local fallback)
    @MainActor
    static func loadProtocolsFromFirestore() async {
        let manager = LocalDataStore.shared

        do {
            Logger.log(.info, component: "DataLoader", message: "Loading protocols from Firestore...")
            let protocols = try await FirestoreProtocolRepository.shared.fetchAll()
            manager.protocolConfigs = protocols
            Logger.log(.info, component: "DataLoader", message: "Loaded \(protocols.count) protocols from Firestore")
        } catch {
            Logger.log(.error, component: "DataLoader",
                      message: "Failed to load protocols from Firestore: \(error.localizedDescription)")
        }
    }

    /// Load gyms from Firestore
    /// v196: Firestore is sole source (no local fallback)
    @MainActor
    static func loadGymsFromFirestore() async {
        let manager = LocalDataStore.shared

        do {
            Logger.log(.info, component: "DataLoader", message: "Loading gyms from Firestore...")
            let gyms = try await FirestoreGymRepository.shared.fetchAll()
            manager.gyms = gyms
            Logger.log(.info, component: "DataLoader", message: "Loaded \(gyms.count) gyms from Firestore")
        } catch {
            Logger.log(.error, component: "DataLoader",
                      message: "Failed to load gyms from Firestore: \(error.localizedDescription)")
        }
    }

    // MARK: - v195 Cloud-Only User Data Loading

    /// Load all user data from Firestore
    /// v195: Replaces local file loading with Firestore-only
    @MainActor
    static func loadUserDataFromFirestore(userId: String) async {
        Logger.log(.info, component: "DataLoader", message: "Loading user data from Firestore for \(userId)...")

        // Load user profile
        await loadUserFromFirestore(userId: userId)

        // Load plans and programs
        await loadPlansFromFirestore(userId: userId)

        // Load workouts, instances, and sets
        await loadWorkoutsFromFirestore(userId: userId)

        // Load exercise preferences
        await loadPreferencesFromFirestore(userId: userId)

        // Load exercise targets (1RM data)
        await loadTargetsFromFirestore(userId: userId)

        // Initialize empty library if needed (library will be populated from preferences)
        let manager = LocalDataStore.shared
        if manager.libraries[userId] == nil {
            manager.libraries[userId] = UserLibrary(userId: userId)
        }

        Logger.log(.info, component: "DataLoader", message: "☁️ User data loaded from Firestore for \(userId)")
    }

    /// Load user profile from Firestore
    /// v195.1: Merge instead of overwrite - preserve name if Firestore has empty
    @MainActor
    static func loadUserFromFirestore(userId: String) async {
        let manager = LocalDataStore.shared
        let existingUser = manager.users[userId]  // Keep reference to existing

        do {
            if let firestoreUser = try await FirestoreUserRepository.shared.fetchUser(userId: userId) {
                // v195.1: Merge instead of overwrite - preserve name if Firestore has empty
                var finalUser = firestoreUser
                if firestoreUser.name.isEmpty, let existing = existingUser, !existing.name.isEmpty {
                    // Firestore has empty name but we have a good name locally - keep it
                    finalUser = UnifiedUser(
                        id: firestoreUser.id,
                        firebaseUID: firestoreUser.firebaseUID,
                        authProvider: firestoreUser.authProvider,
                        email: firestoreUser.email,
                        phoneNumber: firestoreUser.phoneNumber,
                        name: existing.name,  // Keep existing name
                        photoURL: firestoreUser.photoURL,
                        providerUID: firestoreUser.providerUID,
                        emailVerified: firestoreUser.emailVerified,
                        birthdate: firestoreUser.birthdate ?? existing.birthdate,
                        gender: firestoreUser.gender,
                        roles: firestoreUser.roles,
                        gymId: firestoreUser.gymId,
                        passwordHash: nil,
                        memberProfile: firestoreUser.memberProfile ?? existing.memberProfile,
                        trainerProfile: firestoreUser.trainerProfile ?? existing.trainerProfile
                    )
                    Logger.log(.info, component: "DataLoader",
                              message: "Merged Firestore user with local name: \(existing.name)")
                }
                manager.users[userId] = finalUser
                Logger.log(.info, component: "DataLoader", message: "Loaded user profile from Firestore")
            } else {
                Logger.log(.debug, component: "DataLoader", message: "No user profile in Firestore (new user)")
            }
        } catch {
            Logger.log(.warning, component: "DataLoader",
                      message: "Failed to load user from Firestore: \(error.localizedDescription)")
        }
    }

    /// Load exercise preferences from Firestore
    @MainActor
    static func loadPreferencesFromFirestore(userId: String) async {
        do {
            if let prefs = try await FirestoreExercisePreferencesRepository.shared.fetchPreferences(userId: userId) {
                LocalDataStore.shared.exercisePreferences[userId] = prefs
                Logger.log(.info, component: "DataLoader",
                          message: "Loaded exercise preferences from Firestore: \(prefs.favorites.count) favorites")
            } else {
                Logger.log(.debug, component: "DataLoader", message: "No exercise preferences in Firestore (new user)")
            }
        } catch {
            Logger.log(.warning, component: "DataLoader",
                      message: "Failed to load preferences from Firestore: \(error.localizedDescription)")
        }
    }

    /// Load exercise targets (1RM data) from Firestore
    @MainActor
    static func loadTargetsFromFirestore(userId: String) async {
        do {
            let targets = try await FirestoreTargetsRepository.shared.fetchTargets(memberId: userId)
            for target in targets {
                LocalDataStore.shared.targets[target.id] = target
            }
            if !targets.isEmpty {
                Logger.log(.info, component: "DataLoader",
                          message: "Loaded \(targets.count) exercise targets from Firestore")
            }
        } catch {
            Logger.log(.warning, component: "DataLoader",
                      message: "Failed to load targets from Firestore: \(error.localizedDescription)")
        }
    }

    // v186: Removed loadClassesModule (class booking deferred for beta)
    // v190: Removed loadMessageThreads (unused)
    // v195: Removed loadUserData, loadPersistedUsers, loadAssignedMembersLibraries (cloud-only)

    // MARK: - Firestore Loading (v196)

    /// Load exercises from Firestore
    /// v196: Firestore is sole source (no local fallback)
    @MainActor
    static func loadExercisesFromFirestore() async {
        let manager = LocalDataStore.shared

        do {
            Logger.log(.info, component: "DataLoader", message: "Loading exercises from Firestore...")
            let exercises = try await FirestoreExerciseRepository.shared.fetchAll()
            manager.exercises = exercises
            Logger.log(.info, component: "DataLoader", message: "Loaded \(exercises.count) exercises from Firestore")
        } catch {
            Logger.log(.error, component: "DataLoader",
                      message: "Failed to load exercises from Firestore: \(error.localizedDescription)")
        }
    }

    /// v188.3: Load plans and programs from Firestore for trainer-member sync
    /// Plans are fetched from cloud and merged with local plans
    @MainActor
    static func loadPlansFromFirestore(userId: String) async {
        let manager = LocalDataStore.shared

        do {
            Logger.log(.info, component: "DataLoader", message: "Loading plans from Firestore for user \(userId)...")

            // Fetch plans from Firestore
            let firestorePlans = try await FirestorePlanRepository.shared.fetchPlans(forMember: userId)
            Logger.log(.info, component: "DataLoader", message: "Fetched \(firestorePlans.count) plans from Firestore")

            // Merge with local plans (Firestore is source of truth)
            for plan in firestorePlans {
                manager.plans[plan.id] = plan

                // Fetch programs for each plan
                let programs = try await FirestorePlanRepository.shared.fetchPrograms(forPlan: plan.id, memberId: userId)
                for program in programs {
                    manager.programs[program.id] = program
                }
                Logger.log(.debug, component: "DataLoader", message: "Loaded \(programs.count) programs for plan \(plan.id)")
            }

            Logger.log(.info, component: "DataLoader",
                      message: "☁️ Synced \(firestorePlans.count) plans from Firestore")

        } catch {
            Logger.log(.warning, component: "DataLoader",
                      message: "Firestore plans failed, using local: \(error.localizedDescription)")
            // Local plans should already be loaded from loadUserData()
        }
    }

    /// v208: Load workout metadata only - instances/sets loaded on demand in WorkoutDetailView
    /// This reduces login time from 25s to <2s by eliminating ~800 Firestore calls
    @MainActor
    static func loadWorkoutsFromFirestore(userId: String) async {
        let manager = LocalDataStore.shared

        do {
            Logger.log(.info, component: "DataLoader", message: "Loading workouts from Firestore for user \(userId)...")

            // Fetch workouts from Firestore (metadata only - no instances/sets)
            let firestoreWorkouts = try await FirestoreWorkoutRepository.shared.fetchWorkouts(forMember: userId)
            Logger.log(.info, component: "DataLoader", message: "Fetched \(firestoreWorkouts.count) workouts from Firestore")

            // v208: Just store workout metadata - instances/sets loaded lazily in WorkoutDetailView
            for workout in firestoreWorkouts {
                manager.workouts[workout.id] = workout
            }

            Logger.log(.info, component: "DataLoader",
                      message: "☁️ Synced \(firestoreWorkouts.count) workouts from Firestore (lazy load instances)")

        } catch {
            Logger.log(.warning, component: "DataLoader",
                      message: "Firestore workouts failed: \(error.localizedDescription)")
        }
    }

    /// v208: Lazy load instances and sets for a specific workout
    /// Called from WorkoutDetailView when user opens a workout
    @MainActor
    static func loadWorkoutDetails(workoutId: String, userId: String) async {
        let manager = LocalDataStore.shared

        // Skip if already loaded (instances exist for this workout)
        let existingInstances = manager.exerciseInstances.values.filter { $0.workoutId == workoutId }
        if !existingInstances.isEmpty {
            Logger.log(.debug, component: "DataLoader",
                      message: "Workout \(workoutId) already has \(existingInstances.count) instances - skipping load")
            return
        }

        do {
            // Fetch instances for this workout
            let instances = try await FirestoreWorkoutRepository.shared.fetchInstances(
                forWorkout: workoutId,
                memberId: userId
            )

            for instance in instances {
                manager.exerciseInstances[instance.id] = instance

                // Fetch sets for this instance
                let sets = try await FirestoreWorkoutRepository.shared.fetchSets(
                    forInstance: instance.id,
                    workoutId: workoutId,
                    memberId: userId
                )
                for set in sets {
                    manager.exerciseSets[set.id] = set
                }
            }

            Logger.log(.info, component: "DataLoader",
                      message: "☁️ Lazy loaded \(instances.count) instances for workout \(workoutId)")

        } catch {
            Logger.log(.warning, component: "DataLoader",
                      message: "Failed to load workout details: \(error.localizedDescription)")
        }
    }

    private static func loadDictionary<T: Decodable>(
        _ resource: String,
        decoder: JSONDecoder
    ) throws -> [String: T] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            Logger.log(.error, component: "DataLoader", message: "File not found: \(resource).json")
            throw LocalDataLoaderError.fileMissing("\(resource).json")
        }

        do {
            let data = try Data(contentsOf: url)
            Logger.log(.debug, component: "DataLoader", message: "File \(resource).json loaded, size: \(data.count) bytes")

            let result = try decoder.decode([String: T].self, from: data)
            Logger.log(.debug, component: "DataLoader", message: "Successfully decoded \(resource).json")
            return result
        } catch {
            Logger.log(.error, component: "DataLoader", message: "Decoding error in \(resource).json", data: error)

            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    Logger.log(.error, component: "DataLoader", message: "Type mismatch for \(type) at path: \(context.codingPath.map{$0.stringValue}.joined(separator: "."))", data: context.debugDescription)
                case .valueNotFound(let type, let context):
                    Logger.log(.error, component: "DataLoader", message: "Value not found for \(type) at path: \(context.codingPath.map{$0.stringValue}.joined(separator: "."))", data: context.debugDescription)
                case .keyNotFound(let key, let context):
                    Logger.log(.error, component: "DataLoader", message: "Key '\(key.stringValue)' not found at path: \(context.codingPath.map{$0.stringValue}.joined(separator: "."))", data: context.debugDescription)
                case .dataCorrupted(let context):
                    Logger.log(.error, component: "DataLoader", message: "Data corrupted at path: \(context.codingPath.map{$0.stringValue}.joined(separator: "."))", data: context.debugDescription)
                @unknown default:
                    Logger.log(.error, component: "DataLoader", message: "Unknown decoding error", data: decodingError)
                }
            }

            throw LocalDataLoaderError.decodingFailed(resource, underlying: error)
        }
    }

    private static func loadArrayDict<T: Decodable & Identifiable>(
        _ resource: String,
        decoder: JSONDecoder
    ) throws -> [String: T] where T.ID == String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw LocalDataLoaderError.fileMissing("\(resource).json")
        }

        do {
            let data = try Data(contentsOf: url)
            let array = try decoder.decode([T].self, from: data)
            return Dictionary(uniqueKeysWithValues: array.map { ($0.id, $0) })
        } catch {
            throw LocalDataLoaderError.decodingFailed(resource, underlying: error)
        }
    }

    private static var isoDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum LocalDataLoaderError: LocalizedError {
    case fileMissing(String)
    case decodingFailed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileMissing(let name):
            return "Missing bundled data file: \(name)"
        case .decodingFailed(let resource, let underlying):
            return "Failed to decode \(resource).json (\(underlying.localizedDescription))"
        }
    }
}
