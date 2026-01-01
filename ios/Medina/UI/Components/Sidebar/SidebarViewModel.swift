//
// SidebarViewModel.swift
// Medina
//
// v93.6: Extracted state management from SidebarView
// v99.1: Added admin folder expansion states
// v114: Added Library expansion state
// v116: Updated expansion defaults - collapsed by default except Plans
// v186: Removed class booking (deferred for beta)
// v187: Removed admin folder states (admin UI deferred for beta)
// v194: Added Classes + Gym Access demo sections for District pitch
// Manages folder expansion states, data loading, and search
//

import SwiftUI

/// ViewModel managing sidebar state and data loading
@MainActor
final class SidebarViewModel: ObservableObject {

    // MARK: - Folder Expansion State (v116: mostly collapsed by default)

    @Published var showSchedule = true  // v250: Schedule folder expanded by default
    @Published var showPlans = true   // v116: Expanded so user sees current plan selected
    @Published var showWorkouts = false
    @Published var showExercises = false
    @Published var showProtocols = false
    @Published var showMessages = false
    @Published var showMyPlans = true   // v116: Trainer's own plans expanded
    @Published var showLibrary = false  // Collapsible parent for Exercises + Protocols
    @Published var showClasses = false  // v194: Classes coming soon section

    // v187: Removed admin folder states (admin UI deferred for beta)

    // MARK: - Search State

    @Published var searchText = ""
    @Published var debouncedSearchText = ""
    @Published var searchResults: SearchResults?

    // MARK: - Data

    @Published var plans: [Plan] = []
    @Published var workouts: [Workout] = []
    @Published var allWorkoutIds: [String] = []
    @Published var libraryExercises: [Exercise] = []
    @Published var library: UserLibrary?

    // MARK: - Constants

    let sidebarItemLimit = 3

    // MARK: - User Context

    private let userId: String

    // v105: Removed selectedMemberId - now managed by SidebarContext
    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Data Loading

    func loadData() {
        loadLibrary()
        loadExercises()
        loadPlans()
        loadWorkouts()
    }

    private func loadLibrary() {
        library = LocalDataStore.shared.libraries[userId]
    }

    private func loadExercises() {
        guard let library = library else {
            libraryExercises = []
            return
        }

        let prefs = LocalDataStore.shared.userExercisePreferences(for: userId)
        libraryExercises = library.exercises.compactMap { exerciseId in
            LocalDataStore.shared.exercises[exerciseId]
        }.sorted { ex1, ex2 in
            let isFav1 = prefs.isFavorite(ex1.id)
            let isFav2 = prefs.isFavorite(ex2.id)
            if isFav1 != isFav2 {
                return isFav1  // Favorites come first
            }
            return ex1.name < ex2.name
        }
    }

    private func loadPlans() {
        plans = PlanResolver.allPlans(for: userId)
            .filter { !$0.isSingleWorkout }
            .sorted { $0.startDate > $1.startDate }
    }

    private func loadWorkouts() {
        // v96.1: Show workouts from active plan OR single-workout plans
        // Previously only showed workouts when activePlan existed, missing standalone workouts
        var allUserWorkouts: [Workout] = []

        // 1. Get workouts from active plan (if exists)
        if let activePlan = PlanResolver.activePlan(for: userId) {
            allUserWorkouts = WorkoutResolver.workouts(
                for: userId,
                temporal: .unspecified,
                status: nil,
                modality: .unspecified,
                splitDay: nil,
                source: nil,
                plan: activePlan,
                program: nil,
                dateInterval: nil
            )
        }

        // 2. Also include workouts from single-workout plans (standalone workouts)
        let singleWorkoutPlans = PlanDataStore.allPlans(for: userId).filter { $0.isSingleWorkout }
        for plan in singleWorkoutPlans {
            let planWorkouts = WorkoutResolver.workouts(
                for: userId,
                temporal: .unspecified,
                status: nil,
                modality: .unspecified,
                splitDay: nil,
                source: nil,
                plan: plan,
                program: nil,
                dateInterval: nil
            )
            // Avoid duplicates
            for workout in planWorkouts where !allUserWorkouts.contains(where: { $0.id == workout.id }) {
                allUserWorkouts.append(workout)
            }
        }

        allWorkoutIds = allUserWorkouts.map { $0.id }

        let sortedWorkouts = allUserWorkouts.sorted {
            ($0.scheduledDate ?? Date.distantFuture) < ($1.scheduledDate ?? Date.distantFuture)
        }

        // Find next uncompleted workout
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let nextWorkout = sortedWorkouts.first { workout in
            guard workout.status == .inProgress || workout.status == .scheduled else { return false }
            if workout.status == .scheduled,
               let workoutDate = workout.scheduledDate {
                let workoutDay = calendar.startOfDay(for: workoutDate)
                return workoutDay >= today
            }
            return true
        }

        // Show 1 before + next + 1 after (centered view)
        if let nextWorkout = nextWorkout,
           let nextIndex = sortedWorkouts.firstIndex(where: { $0.id == nextWorkout.id }) {
            let startIndex = max(0, nextIndex - 1)
            let endIndex = min(sortedWorkouts.count, nextIndex + 2)
            workouts = Array(sortedWorkouts[startIndex..<endIndex])
        } else {
            workouts = Array(sortedWorkouts.prefix(sidebarItemLimit))
        }
    }

    // MARK: - Search

    func handleSearchChange(_ newValue: String) {
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if searchText == newValue {
                debouncedSearchText = newValue
                performSearch()
            }
        }
    }

    func clearSearch() {
        searchText = ""
        debouncedSearchText = ""
        searchResults = nil
    }

    private func performSearch() {
        guard !debouncedSearchText.isEmpty else {
            searchResults = nil
            return
        }

        searchResults = EntitySearchService.performSearch(
            query: debouncedSearchText,
            memberId: userId
        )
    }

    // MARK: - Library Protocol Families

    func getLibraryProtocolFamilies() -> [ProtocolFamily] {
        let libraryProtocolIds = Set(library?.protocols.map(\.protocolConfigId) ?? [])
        let allFamilies = ProtocolGroupingService.getProtocolFamilies()

        return allFamilies.compactMap { family -> ProtocolFamily? in
            let libraryVariants = family.variants.filter { libraryProtocolIds.contains($0.id) }
            guard !libraryVariants.isEmpty else { return nil }
            return ProtocolFamily(
                id: family.id,
                displayName: family.displayName,
                variants: libraryVariants,
                defaultVariant: libraryVariants.first
            )
        }
    }

    var libraryProtocolCount: Int {
        library?.protocols.count ?? 0
    }

    // MARK: - Helper Functions

    func stripPlanSuffix(_ planName: String) -> String {
        var simplified = planName

        if simplified.hasSuffix(" Plan") {
            simplified = String(simplified.dropLast(5))
        }

        let pattern = "\\s+[A-Z][a-z]{2}\\s+\\d{1,2}[-–]\\d{1,2}$"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: simplified, range: NSRange(simplified.startIndex..., in: simplified)) {
            if let range = Range(match.range, in: simplified) {
                simplified = String(simplified[..<range.lowerBound])
            }
        }

        return simplified.trimmingCharacters(in: .whitespaces)
    }

    func initials(from name: String) -> String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
}
