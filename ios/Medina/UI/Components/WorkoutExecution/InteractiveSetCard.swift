//
// InteractiveSetCard.swift
// Medina
//
// Touch-centric set entry feature
// Created: November 10, 2025
// v52.3: Added manual completion behavior for simple data entry mode
// Purpose: Interactive set card with one-tap logging and inline pickers
//

import SwiftUI

/// Determines how set completion is handled
enum CompletionBehavior {
    case automatic  // Guided mode: Auto-green when data entered, blue dot triggers log
    case manual     // Simple mode: Grey outlined until circle tapped to mark complete
}

struct InteractiveSetCard: View {
    let exerciseSet: ExerciseSet
    let onLog: (Double, Int) -> Void
    let isDisabled: Bool  // v52.1: Disable interaction when not current set
    let completionBehavior: CompletionBehavior  // v52.3: Manual vs automatic completion
    let onSkip: (() -> Void)?  // v55.0 Phase 3: Optional skip handler
    let onUnskip: (() -> Void)?  // v55.0 Phase 3: Optional unskip handler

    @State private var isEditingValues = false
    @State private var adjustedWeight: Double?  // Optional to support uncalibrated exercises
    @State private var adjustedReps: Int?       // Optional to support uncalibrated exercises

    init(
        set: ExerciseSet,
        isDisabled: Bool = false,
        completionBehavior: CompletionBehavior = .automatic,
        onLog: @escaping (Double, Int) -> Void,
        onSkip: (() -> Void)? = nil,  // v55.0 Phase 3
        onUnskip: (() -> Void)? = nil  // v55.0 Phase 3
    ) {
        self.exerciseSet = set
        self.isDisabled = isDisabled
        self.completionBehavior = completionBehavior
        self.onLog = onLog
        self.onSkip = onSkip
        self.onUnskip = onUnskip
        _adjustedWeight = State(initialValue: set.targetWeight)  // Keep nil as nil
        _adjustedReps = State(initialValue: set.targetReps)      // Keep nil as nil
    }

    // MARK: - Computed Properties

    var isLogged: Bool {
        exerciseSet.actualWeight != nil && exerciseSet.actualReps != nil
    }

    // v55.0 Phase 3: Check if set is skipped
    var isSkipped: Bool {
        exerciseSet.completion == .skipped
    }

    // v52.3: Check if values have been adjusted (for manual completion mode)
    var hasAdjustedValues: Bool {
        adjustedWeight != exerciseSet.targetWeight || adjustedReps != exerciseSet.targetReps
    }

    var displayWeight: String {
        if isLogged {
            return "\(Int(exerciseSet.actualWeight ?? 0))"
        } else if let weight = adjustedWeight {
            return "\(Int(weight))"
        } else {
            return "—"  // Em dash for blank/uncalibrated
        }
    }

    var displayReps: String {
        if isLogged {
            return "\(exerciseSet.actualReps ?? 0)"
        } else if let reps = adjustedReps {
            return "\(reps)"
        } else {
            return "—"  // Em dash for blank/uncalibrated
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main card content
            HStack(spacing: 12) {
                // Set number - just the digit
                Text("\(exerciseSet.setNumber)")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color("PrimaryText"))
                    .frame(width: 30, alignment: .leading)

                // Weight input field with label below
                VStack(spacing: 4) {
                    Button(action: {
                        if !isLogged && !isDisabled {
                            isEditingValues.toggle()
                        }
                    }) {
                        Text(displayWeight)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(adjustedWeight == nil && !isLogged ? Color("SecondaryText") : Color("PrimaryText"))
                            .frame(minWidth: 60)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isLogged ? Color.clear : Color(uiColor: .systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isLogged ? Color.clear : Color(uiColor: .systemGray4), lineWidth: 1)
                            )
                    }
                    .disabled(isLogged)

                    Text("lbs")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color("SecondaryText"))
                }

                Text("×")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))

                // Reps input field with label below
                VStack(spacing: 4) {
                    Button(action: {
                        if !isLogged && !isDisabled {
                            isEditingValues.toggle()
                        }
                    }) {
                        Text(displayReps)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(adjustedReps == nil && !isLogged ? Color("SecondaryText") : Color("PrimaryText"))
                            .frame(minWidth: 44)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isLogged ? Color.clear : Color(uiColor: .systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isLogged ? Color.clear : Color(uiColor: .systemGray4), lineWidth: 1)
                            )
                    }
                    .disabled(isLogged)

                    Text("reps")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color("SecondaryText"))
                }

                Spacer()

                // v55.0 Phase 3 UX: Status dot (unified for all states)
                // Tap behavior: pending→complete, completed→edit, skipped→unskip
                Button(action: {
                    handleDotTap()
                }) {
                    Circle()
                        .fill(dotFillColor)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(dotStrokeColor, lineWidth: 1.5)
                        )
                }
                .frame(width: 32, height: 32)  // Maintain tap area
                .contentShape(Rectangle())
                .disabled(isDisabled && !isSkipped)  // Allow tap on skipped even if disabled
                .accessibilityIdentifier("statusDot_\(exerciseSet.id)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("CardBackground"))
            )
            .accessibilityIdentifier("setCard_\(exerciseSet.id)")
            // v55.0 Phase 3 UX: Long-press context menu (iOS-native pattern)
            // Note: Skip removed from set-level menu (skip entire exercise instead)
            .contextMenu {
                if isSkipped {
                    Button(action: {
                        handleUnskip()
                    }) {
                        Label("Unskip Set", systemImage: "arrow.uturn.backward")
                    }
                    Button(action: {
                        handleComplete()
                    }) {
                        Label("Complete Set", systemImage: "checkmark.circle")
                    }
                } else if isLogged {
                    Button(action: {
                        // TODO: Phase 4 - Open edit modal
                        print("Edit set")
                    }) {
                        Label("Edit Set", systemImage: "pencil")
                    }
                } else {
                    // Pending
                    Button(action: {
                        handleComplete()
                    }) {
                        Label("Complete Set", systemImage: "checkmark.circle")
                    }
                }
            }

            // Dual picker (weight + reps side-by-side, Zing-style)
            if isEditingValues {
                VStack(spacing: 8) {
                    // Close button (X icon)
                    HStack {
                        Spacer()
                        Button(action: {
                            isEditingValues = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }

                    // Side-by-side pickers
                    HStack(spacing: 12) {
                        // Weight picker (supports optional binding)
                        Picker("", selection: Binding(
                            get: { adjustedWeight ?? 0.0 },
                            set: { adjustedWeight = $0 }
                        )) {
                            ForEach(Array(stride(from: 0.0, through: 500.0, by: 2.5)), id: \.self) { val in
                                Text(formatWeight(val))
                                    .tag(val)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)

                        // Reps picker (supports optional binding)
                        Picker("", selection: Binding(
                            get: { Double(adjustedReps ?? 0) },
                            set: { adjustedReps = Int($0) }
                        )) {
                            ForEach(Array(stride(from: 0.0, through: 50.0, by: 1.0)), id: \.self) { val in
                                Text("\(Int(val)) reps")
                                    .tag(val)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 120)
                    }
                }
                .padding(12)
                .background(Color("Background"))
                .cornerRadius(8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .opacity(isDisabled && !isLogged ? 0.4 : 1.0)  // v52.1: Dim disabled sets
        .animation(.easeInOut(duration: 0.2), value: isEditingValues)
    }

    // MARK: - Helpers

    /// v55.0 Phase 3 UX: Dot fill color (iOS-native)
    /// Green = completed, Orange = skipped, Blue/Clear = pending
    private var dotFillColor: Color {
        if isLogged {
            return Color.green  // Completed: green filled
        }

        if isSkipped {
            return Color.orange  // Skipped: orange filled
        }

        // Pending: Blue when active (guided mode), clear when disabled
        switch completionBehavior {
        case .automatic:
            return !isDisabled ? Color.blue : Color.clear
        case .manual:
            return Color.clear
        }
    }

    /// v55.0 Phase 3 UX: Dot stroke color (iOS-native)
    /// Clear for filled dots, gray outline for pending disabled
    private var dotStrokeColor: Color {
        if isLogged || isSkipped {
            return Color.clear  // No outline for filled dots
        }

        // Pending sets get gray outline when disabled, no outline when active
        switch completionBehavior {
        case .automatic:
            return isDisabled ? Color(uiColor: .systemGray4) : Color.clear
        case .manual:
            return Color(uiColor: .systemGray4)
        }
    }

    // MARK: - Action Handlers (v55.0 Phase 3 UX)

    /// Handle tap on status dot (state-dependent behavior)
    private func handleDotTap() {
        if isSkipped {
            // Skipped → Unskip
            handleUnskip()
        } else if isLogged {
            // Completed → Edit (Phase 4)
            print("TODO: Open edit modal")
        } else if !isDisabled, let weight = adjustedWeight, let reps = adjustedReps {
            // Pending → Complete
            handleComplete()
        }
    }

    /// Complete the set (log it)
    private func handleComplete() {
        guard let weight = adjustedWeight, let reps = adjustedReps else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onLog(weight, reps)
    }

    /// Skip the set
    private func handleSkip() {
        guard let onSkip = onSkip else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        onSkip()
    }

    /// Unskip the set
    private func handleUnskip() {
        guard let onUnskip = onUnskip else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onUnskip()
    }

    private func formatWeight(_ val: Double) -> String {
        if val.truncatingRemainder(dividingBy: 1.0) == 0 {
            return "\(Int(val)) lbs"
        } else {
            return String(format: "%.1f lbs", val)
        }
    }
}

// MARK: - Previews

#Preview("Unlogged Set") {
    let set = ExerciseSet(
        id: "test_set_1",
        exerciseInstanceId: "test_instance",
        setNumber: 1,
        targetWeight: 225.0,
        targetReps: 5,
        targetRPE: nil,
        actualWeight: nil,
        actualReps: nil,
        completion: nil,
        startTime: nil,
        endTime: nil,
        notes: nil,
        recordedDate: nil
    )

    return InteractiveSetCard(set: set, onLog: { weight, reps in
        print("Logged: \(weight) lbs × \(reps) reps")
    })
    .padding()
}

#Preview("Logged Set") {
    let set = ExerciseSet(
        id: "test_set_2",
        exerciseInstanceId: "test_instance",
        setNumber: 2,
        targetWeight: 225.0,
        targetReps: 5,
        targetRPE: nil,
        actualWeight: 230.0,
        actualReps: 6,
        completion: .completed,
        startTime: nil,
        endTime: nil,
        notes: nil,
        recordedDate: Date()
    )

    return InteractiveSetCard(set: set, onLog: { weight, reps in
        print("Logged: \(weight) lbs × \(reps) reps")
    })
    .padding()
}
