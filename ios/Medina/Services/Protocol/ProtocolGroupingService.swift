//
//  ProtocolGroupingService.swift
//  Medina
//
//  v88.0: Protocol family grouping for sidebar/search display
//  Created: December 7, 2025
//
//  Groups protocols by family for cleaner UI presentation.
//  Shows base families in sidebar, with variant selectors in detail views.
//

import Foundation

// MARK: - Protocol Family Model

/// Represents a protocol family (base entity) for grouped display
struct ProtocolFamily: Identifiable {
    let id: String                          // Family ID (e.g., "straightSets", "gbc")
    let displayName: String                 // Human-readable name (e.g., "Straight Sets")
    let variants: [ProtocolConfig]          // All variants in this family
    let defaultVariant: ProtocolConfig?     // First/default variant

    var variantCount: Int { variants.count }
    var hasMultipleVariants: Bool { variants.count > 1 }

    /// Description from the first variant (family-level description)
    var description: String? {
        defaultVariant?.executionNotes
    }

    /// Methodology from the first variant (family-level methodology)
    var methodology: String? {
        defaultVariant?.methodology
    }
}

// MARK: - Grouping Service

/// Groups protocols by family for sidebar/search display
enum ProtocolGroupingService {

    /// Get all protocol families for sidebar display
    /// Returns families sorted alphabetically by display name
    static func getProtocolFamilies() -> [ProtocolFamily] {
        let allConfigs = Array(LocalDataStore.shared.protocolConfigs.values)

        // Group by protocolFamily
        var grouped: [String: [ProtocolConfig]] = [:]

        for config in allConfigs {
            let family = config.protocolFamily ?? "other"
            grouped[family, default: []].append(config)
        }

        // Convert to ProtocolFamily structs
        return grouped.map { family, configs in
            // Sort variants within each family
            let sortedVariants = configs.sorted { $0.variantName < $1.variantName }

            return ProtocolFamily(
                id: family,
                displayName: sortedVariants.first?.familyDisplayName ?? family.capitalized,
                variants: sortedVariants,
                defaultVariant: sortedVariants.first
            )
        }.sorted { $0.displayName < $1.displayName }
    }

    /// Get a specific protocol family by ID
    static func getFamily(id: String) -> ProtocolFamily? {
        getProtocolFamilies().first { $0.id == id }
    }

    /// Get all variants for a given protocol family
    static func getVariants(for familyId: String) -> [ProtocolConfig] {
        LocalDataStore.shared.protocolConfigs.values
            .filter { $0.protocolFamily == familyId }
            .sorted { $0.variantName < $1.variantName }
    }

    /// Search protocol families (returns families where name or any variant matches)
    static func searchFamilies(query: String) -> [ProtocolFamily] {
        let families = getProtocolFamilies()

        if query.isEmpty {
            return families
        }

        let lowercased = query.lowercased()

        return families.filter { family in
            // Match family display name
            if family.displayName.lowercased().contains(lowercased) {
                return true
            }

            // Match family ID
            if family.id.lowercased().contains(lowercased) {
                return true
            }

            // Match any variant name
            if family.variants.contains(where: { $0.variantName.lowercased().contains(lowercased) }) {
                return true
            }

            // Match any variant label
            if family.variants.contains(where: { $0.variantLabel.lowercased().contains(lowercased) }) {
                return true
            }

            return false
        }
    }
}
