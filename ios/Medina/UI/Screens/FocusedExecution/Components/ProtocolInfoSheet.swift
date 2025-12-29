//
// ProtocolInfoSheet.swift
// Medina
//
// v79.3: Educational sheet explaining protocol methodology
// Created: December 2025
// Purpose: Quick tooltip explaining special protocols (Myo, Waves, Drop Sets, etc.)
//

import SwiftUI

/// Compact sheet explaining a special protocol during workout execution
/// Shows variant name, execution notes, and methodology
struct ProtocolInfoSheet: View {
    let protocolConfig: ProtocolConfig
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with protocol name and family badge
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(protocolConfig.variantName)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(Color("PrimaryText"))

                            if let family = protocolFamilyDisplayName {
                                Text(family)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("SecondaryText"))
                            }
                        }

                        Spacer()

                        // Protocol family badge
                        Text(protocolTypeBadge)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(protocolTypeColor)
                            .cornerRadius(12)
                    }

                    // How to Execute section
                    if !protocolConfig.executionNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("HOW TO EXECUTE")

                            Text(protocolConfig.executionNotes)
                                .font(.system(size: 15))
                                .foregroundColor(Color("PrimaryText"))
                                .lineSpacing(4)
                        }
                    }

                    // Why It Works section
                    if let methodology = protocolConfig.methodology, !methodology.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("WHY IT WORKS")

                            Text(methodology)
                                .font(.system(size: 15))
                                .foregroundColor(Color("PrimaryText"))
                                .lineSpacing(4)
                        }
                    }

                    // Set Structure section
                    setStructureSection

                    // Done button
                    Button(action: onDismiss) {
                        Text("Got it")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
        }
        .background(Color("Background"))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Set Structure Section

    private var setStructureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("SET STRUCTURE")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(protocolConfig.reps.enumerated()), id: \.offset) { index, reps in
                    HStack(spacing: 12) {
                        // Set number badge
                        Text("Set \(index + 1)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color("SecondaryText"))
                            .frame(width: 50, alignment: .leading)

                        // Reps
                        Text("\(reps) reps")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color("PrimaryText"))

                        Spacer()

                        // Intensity adjustment if different from base
                        if index < protocolConfig.intensityAdjustments.count {
                            let adjustment = protocolConfig.intensityAdjustments[index]
                            if adjustment != 0 {
                                Text(intensityLabel(adjustment))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(adjustment > 0 ? .orange : .green)
                            }
                        }

                        // Rest time after set (except last)
                        if index < protocolConfig.restBetweenSets.count {
                            Text("\(protocolConfig.restBetweenSets[index])s rest")
                                .font(.system(size: 12))
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color("BackgroundSecondary"))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color("SecondaryText"))
    }

    private func intensityLabel(_ adjustment: Double) -> String {
        let percentage = Int(adjustment * 100)
        return percentage > 0 ? "+\(percentage)%" : "\(percentage)%"
    }

    private var protocolFamilyDisplayName: String? {
        guard let family = protocolConfig.protocolFamily else { return nil }

        switch family {
        case "myo_protocol": return "Rest-Pause Technique"
        case "waves_protocol": return "Wave Loading"
        case "pyramid_ascending": return "Pyramid Training"
        case "pyramid_descending": return "Reverse Pyramid"
        case "advanced_ratchet": return "Ratchet Loading"
        case "gbc_protocol": return "German Body Comp"
        case "calibration_protocol": return "Calibration Set"
        case "drop_set": return "Drop Set"
        case "emom": return "Every Minute on the Minute"
        default: return family.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var protocolTypeBadge: String {
        guard let family = protocolConfig.protocolFamily else { return "Protocol" }

        switch family {
        case "myo_protocol": return "Intensity"
        case "waves_protocol": return "Strength"
        case "pyramid_ascending", "pyramid_descending": return "Volume"
        case "advanced_ratchet": return "Advanced"
        case "gbc_protocol": return "Conditioning"
        case "calibration_protocol": return "Testing"
        case "drop_set": return "Fatigue"
        case "emom": return "Conditioning"
        default: return "Protocol"
        }
    }

    private var protocolTypeColor: Color {
        guard let family = protocolConfig.protocolFamily else { return .blue }

        switch family {
        case "myo_protocol": return .red
        case "waves_protocol": return .purple
        case "pyramid_ascending", "pyramid_descending": return .orange
        case "advanced_ratchet": return .red
        case "gbc_protocol": return .green
        case "calibration_protocol": return .blue
        case "drop_set": return .orange
        case "emom": return .green
        default: return .blue
        }
    }
}

// MARK: - Preview

#Preview("Myo Rest-Pause") {
    ProtocolInfoSheet(
        protocolConfig: ProtocolConfig(
            id: "myo_rest_pause_variant",
            protocolFamily: "myo_protocol",
            variantName: "Myo Rest-Pause Protocol",
            reps: [10, 3, 3, 3, 3, 3, 3, 3],
            intensityAdjustments: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            restBetweenSets: [5, 5, 5, 5, 5, 5, 5],
            tempo: "3010",
            rpe: [8.5, 9, 9, 9, 9, 9, 9, 9],
            loadingPattern: .straightSets,
            executionNotes: "Perform initial set to near failure. Rest 5 seconds, then perform clusters of 3 reps with 5 second rests until you hit the target total reps or reach failure.",
            methodology: "Myo reps extend time under tension and metabolic stress by accumulating volume near failure. The brief rest periods allow partial ATP recovery while maintaining high motor unit recruitment.",
            createdByMemberId: nil,
            createdByTrainerId: nil,
            createdByGymId: nil
        ),
        onDismiss: {}
    )
}

#Preview("Waves Protocol") {
    ProtocolInfoSheet(
        protocolConfig: ProtocolConfig(
            id: "waves_5_4_3_2_1_variant",
            protocolFamily: "waves_protocol",
            variantName: "5/4/3/2/1 Waves Protocol",
            reps: [5, 4, 3, 2, 1],
            intensityAdjustments: [0.0, 0.05, 0.10, 0.15, 0.20],
            restBetweenSets: [180, 180, 180, 180],
            tempo: "20X0",
            rpe: [7, 7.5, 8, 8.5, 9],
            loadingPattern: .progressive,
            executionNotes: "Start at base weight for 5 reps, add weight each set as reps decrease. Focus on explosive concentric with controlled eccentric.",
            methodology: "Wave loading potentiates the nervous system. Each wave primes the body for heavier loads in subsequent sets.",
            createdByMemberId: nil,
            createdByTrainerId: nil,
            createdByGymId: nil
        ),
        onDismiss: {}
    )
}

// MARK: - Manual Initializer for Previews

extension ProtocolConfig {
    init(
        id: String,
        protocolFamily: String?,
        variantName: String,
        reps: [Int],
        intensityAdjustments: [Double],
        restBetweenSets: [Int],
        tempo: String?,
        rpe: [Double]?,
        loadingPattern: LoadingPattern?,
        executionNotes: String,
        methodology: String?,
        createdByMemberId: String?,
        createdByTrainerId: String?,
        createdByGymId: String?
    ) {
        self.id = id
        self.protocolFamily = protocolFamily
        self.variantName = variantName
        self.reps = reps
        self.intensityAdjustments = intensityAdjustments
        self.restBetweenSets = restBetweenSets
        self.tempo = tempo
        self.rpe = rpe
        self.loadingPattern = loadingPattern
        self.executionNotes = executionNotes
        self.methodology = methodology
        self.createdByMemberId = createdByMemberId
        self.createdByTrainerId = createdByTrainerId
        self.createdByGymId = createdByGymId
    }
}
