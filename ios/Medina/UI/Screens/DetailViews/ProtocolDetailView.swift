//
// ProtocolDetailView.swift
// Medina
//
// v51.0 - Exercise & Protocol Library (Phase 2 Refactor)
// v70.0 - Added library toggle (star icon) for adding/removing from user's library
// Created: November 6, 2025
//
// Purpose: Detail view for protocol config with library context
// Displays: Protocol config, library settings, intensity range, applicable types, goals
//

import SwiftUI

struct ProtocolDetailView: View {
    let userId: String
    let protocolConfigId: String
    let onDismiss: () -> Void

    @State private var entry: ProtocolLibraryEntry?
    @State private var config: ProtocolConfig?
    @State private var isInLibrary: Bool = false

    var body: some View {
        NavigationView {
            Group {
                if let config = config {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            protocolInfoSection(for: config)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                } else {
                    emptyState
                }
            }
            .navigationTitle(config?.variantName ?? "Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    libraryToggleButton
                }
            }
        }
        .onAppear {
            loadProtocol()
        }
    }

    // MARK: - Library Toggle (v70.0, v71.0 styling)

    private var libraryToggleButton: some View {
        Button(action: toggleLibrary) {
            Image(systemName: isInLibrary ? "star.fill" : "star")
                .foregroundColor(isInLibrary ? Color("AccentBlue") : Color("SecondaryText"))
                .font(.system(size: 18))
        }
        .accessibilityLabel(isInLibrary ? "Remove from library" : "Add to library")
    }

    private func toggleLibrary() {
        guard var library = LocalDataStore.shared.libraries[userId] else {
            // No library exists, create one and add protocol
            var newLibrary = UserLibrary(userId: userId)
            let newEntry = ProtocolLibraryEntry(
                protocolConfigId: protocolConfigId,
                isEnabled: true,
                applicableTo: [.compound, .isolation],
                intensityRange: 0.0...1.0,
                preferredGoals: []
            )
            newLibrary.protocols.append(newEntry)
            newLibrary.lastModified = Date()
            LocalDataStore.shared.libraries[userId] = newLibrary
            do {
                try LibraryPersistenceService.save(newLibrary)
                isInLibrary = true
                entry = newEntry
            } catch {
                Logger.log(.error, component: "ProtocolDetailView",
                           message: "Failed to save library: \(error)")
            }
            return
        }

        do {
            if isInLibrary {
                // Remove from library
                var updatedLibrary = library
                updatedLibrary.protocols.removeAll { $0.protocolConfigId == protocolConfigId }
                updatedLibrary.lastModified = Date()
                LocalDataStore.shared.libraries[userId] = updatedLibrary
                try LibraryPersistenceService.save(updatedLibrary)
                isInLibrary = false
                entry = nil
                Logger.log(.info, component: "ProtocolDetailView",
                           message: "Removed \(protocolConfigId) from library")
            } else {
                // Add to library
                var updatedLibrary = library
                let newEntry = ProtocolLibraryEntry(
                    protocolConfigId: protocolConfigId,
                    isEnabled: true,
                    applicableTo: [.compound, .isolation],
                    intensityRange: 0.0...1.0,
                    preferredGoals: []
                )
                updatedLibrary.protocols.append(newEntry)
                updatedLibrary.lastModified = Date()
                LocalDataStore.shared.libraries[userId] = updatedLibrary
                try LibraryPersistenceService.save(updatedLibrary)
                isInLibrary = true
                entry = newEntry
                Logger.log(.info, component: "ProtocolDetailView",
                           message: "Added \(protocolConfigId) to library")
            }
        } catch {
            Logger.log(.error, component: "ProtocolDetailView",
                       message: "Failed to toggle library: \(error)")
        }
    }

    // MARK: - Section Builders

    @ViewBuilder
    private func protocolInfoSection(for config: ProtocolConfig) -> some View {
        // Instructions
        if !config.executionNotes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color("PrimaryText"))

                Text(config.executionNotes)
                    .font(.body)
                    .foregroundColor(Color("SecondaryText"))
            }
            .padding(.bottom, 8)
        }

        // Configuration
        KeyValueRow(key: "Sets", value: "\(config.reps.count)")
        KeyValueRow(key: "Reps", value: config.reps.map(String.init).joined(separator: ", "))

        // RPE
        if let rpe = config.rpe, !rpe.isEmpty {
            KeyValueRow(key: "RPE", value: rpe.map { String(format: "%.1f", $0) }.joined(separator: " → "))
        }

        // Tempo
        if let tempo = config.tempo {
            KeyValueRow(key: "Tempo", value: tempo)
        }

        // Rest
        let restValues = config.restBetweenSets.map { "\($0)s" }.joined(separator: ", ")
        KeyValueRow(key: "Rest", value: restValues)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.number")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)

            Text("Protocol not found")
                .font(.headline)
                .foregroundColor(.primary)

            Text("This protocol is not in your library")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Data Loading

    private func loadProtocol() {
        // Load from library
        if let library = LocalDataStore.shared.libraries[userId] {
            entry = library.protocols.first { $0.protocolConfigId == protocolConfigId }
            isInLibrary = entry != nil
        } else {
            isInLibrary = false
        }

        // Load protocol config
        config = LocalDataStore.shared.protocolConfigs[protocolConfigId]
    }
}
