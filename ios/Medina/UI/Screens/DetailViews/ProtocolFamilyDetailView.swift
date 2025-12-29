//
//  ProtocolFamilyDetailView.swift
//  Medina
//
//  v88.0: Protocol family view with variant selector
//  Created: December 7, 2025
//
//  Shows protocol family with variant selector chips (like ExerciseDetailView equipment selector)
//  Users can tap chips to switch between variants within the same family
//

import SwiftUI

struct ProtocolFamilyDetailView: View {
    let family: ProtocolFamily
    let userId: String

    @State private var selectedVariant: ProtocolConfig?
    @State private var isInLibrary: Bool = false

    init(family: ProtocolFamily, userId: String? = nil) {
        self.family = family
        self.userId = userId ?? TestDataManager.shared.currentUserId ?? "bobby"
        self._selectedVariant = State(initialValue: family.defaultVariant)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Variant selector (only if multiple variants)
                if family.hasMultipleVariants {
                    variantSelector
                }

                // Protocol info for selected variant
                if let variant = selectedVariant {
                    protocolInfoSection(variant)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle(family.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                libraryToggleButton
            }
        }
        .onAppear {
            selectedVariant = family.defaultVariant
            updateLibraryStatus()
        }
    }

    // MARK: - Variant Selector

    @ViewBuilder
    private var variantSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VARIANT")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("SecondaryText"))

            // Horizontal chip selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(family.variants) { variant in
                        variantChip(variant)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func variantChip(_ variant: ProtocolConfig) -> some View {
        let isSelected = selectedVariant?.id == variant.id

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedVariant = variant
                updateLibraryStatus()
            }
        } label: {
            Text(variant.variantLabel)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color("AccentBlue") : Color("BackgroundSecondary"))
                .foregroundColor(isSelected ? .white : Color("PrimaryText"))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Protocol Info Section

    @ViewBuilder
    private func protocolInfoSection(_ config: ProtocolConfig) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Instructions
            if !config.executionNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("INSTRUCTIONS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color("SecondaryText"))

                    Text(config.executionNotes)
                        .font(.body)
                        .foregroundColor(Color("PrimaryText"))
                }
            }

            // Structure card
            structureCard(config)

            // Methodology (if available)
            if let methodology = config.methodology, !methodology.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHY IT WORKS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color("SecondaryText"))

                    Text(methodology)
                        .font(.body)
                        .foregroundColor(Color("PrimaryText"))
                }
            }
        }
    }

    @ViewBuilder
    private func structureCard(_ config: ProtocolConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STRUCTURE")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color("SecondaryText"))

            VStack(spacing: 12) {
                // Sets row
                KeyValueRow(key: "Sets", value: "\(config.sets)")

                // Reps row
                let repsDisplay = config.reps.map(String.init).joined(separator: " → ")
                KeyValueRow(key: "Reps", value: repsDisplay)

                // Rest row
                let restDisplay = config.restBetweenSets.map { "\($0)s" }.joined(separator: ", ")
                KeyValueRow(key: "Rest", value: restDisplay)

                // RPE row (if available)
                if let rpe = config.rpe, !rpe.isEmpty {
                    let rpeDisplay = rpe.map { String(format: "%.1f", $0) }.joined(separator: " → ")
                    KeyValueRow(key: "RPE", value: rpeDisplay)
                }

                // Tempo row (if available)
                if let tempo = config.tempo {
                    KeyValueRow(key: "Tempo", value: tempo)
                }
            }
            .padding(16)
            .background(Color("BackgroundSecondary"))
            .cornerRadius(12)
        }
    }

    // MARK: - Library Toggle

    private var libraryToggleButton: some View {
        Button(action: toggleLibrary) {
            Image(systemName: isInLibrary ? "star.fill" : "star")
                .foregroundColor(isInLibrary ? Color("AccentBlue") : Color("SecondaryText"))
                .font(.system(size: 18))
        }
        .accessibilityLabel(isInLibrary ? "Remove from library" : "Add to library")
    }

    private func updateLibraryStatus() {
        guard let variant = selectedVariant else { return }
        if let library = TestDataManager.shared.libraries[userId] {
            isInLibrary = library.protocols.contains { $0.protocolConfigId == variant.id }
        } else {
            isInLibrary = false
        }
    }

    // v89: Use LibraryPersistenceService methods for consistency
    @MainActor
    private func toggleLibrary() {
        guard let variant = selectedVariant else { return }

        do {
            if isInLibrary {
                // Remove from library
                try LibraryPersistenceService.removeProtocol(variant.id, userId: userId)
                isInLibrary = false
                Logger.log(.info, component: "ProtocolFamilyDetailView",
                           message: "v89: Removed protocol '\(variant.variantName)' from library")
            } else {
                // Add to library
                try LibraryPersistenceService.addProtocol(variant.id, userId: userId)
                isInLibrary = true
                Logger.log(.info, component: "ProtocolFamilyDetailView",
                           message: "v89: Added protocol '\(variant.variantName)' to library")
            }
        } catch {
            Logger.log(.error, component: "ProtocolFamilyDetailView",
                       message: "Failed to toggle library: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        let families = ProtocolGroupingService.getProtocolFamilies()
        if let straightSets = families.first(where: { $0.id == "straightSets" }) {
            ProtocolFamilyDetailView(family: straightSets)
        } else if let first = families.first {
            ProtocolFamilyDetailView(family: first)
        }
    }
}
