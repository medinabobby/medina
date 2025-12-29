//
// SetActionCard.swift
// Medina
//
// v76.0: Bottom action card for focused workout execution
// v78.0: Replaced +/- steppers with wheel pickers (matches old InteractiveSetCard UX)
// Created: December 2025
// Purpose: Weight/reps display with wheel pickers and LOG SET button
//

import SwiftUI

/// Bottom card showing current exercise, weight/reps controls, and log button
struct SetActionCard: View {
    let exerciseName: String
    let setNumber: Int
    let totalSets: Int
    @Binding var weight: Double
    @Binding var reps: Int
    // v78.2: Removed protocolInfo parameter - now only shown in tappable header pill
    let onLog: () -> Void
    let onDetailsSheet: () -> Void

    @State private var isEditingValues = false

    var body: some View {
        VStack(spacing: 16) {
            // Handle indicator for sheet-like appearance
            handleIndicator

            // Set progress with status dots
            setProgressRow

            // Weight and reps input (tappable to open picker)
            inputSection

            // Inline wheel pickers when editing
            if isEditingValues {
                pickerSection
            }

            // Primary action button
            logButton

            // Exercise details hint
            detailsHint
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color("CardBackground"))
                .shadow(color: Color.black.opacity(0.1), radius: 10, y: -5)
        )
        .animation(.easeInOut(duration: 0.2), value: isEditingValues)
    }

    // MARK: - Subviews

    /// Drag handle indicator at top
    private var handleIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 36, height: 5)
    }

    /// v78.0: Set progress row with status dots
    private var setProgressRow: some View {
        VStack(spacing: 8) {
            // Set X of Y label
            Text("Set \(setNumber) of \(totalSets)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color("PrimaryText"))

            // Status dots row
            HStack(spacing: 8) {
                ForEach(1...totalSets, id: \.self) { setIndex in
                    Circle()
                        .fill(dotColor(for: setIndex))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(dotStrokeColor(for: setIndex), lineWidth: 1.5)
                        )
                }
            }

            // v78.2: Removed redundant protocolInfo display here
            // RPE/Tempo is now only shown in the tappable header pill
        }
    }

    /// v78.0: Dot fill color based on set position
    private func dotColor(for setIndex: Int) -> Color {
        if setIndex < setNumber {
            return .green  // Completed
        } else if setIndex == setNumber {
            return .blue   // Current (active)
        } else {
            return .clear  // Pending (outlined only)
        }
    }

    /// v78.0: Dot stroke color based on set position
    private func dotStrokeColor(for setIndex: Int) -> Color {
        if setIndex < setNumber || setIndex == setNumber {
            return .clear  // No stroke for filled dots
        } else {
            return Color(uiColor: .systemGray4)  // Gray outline for pending
        }
    }

    /// v78.0: Weight and reps input - tappable fields (like old InteractiveSetCard)
    /// v125: Swapped order to reps × weight (natural: "10 reps at 72 lbs")
    private var inputSection: some View {
        HStack(spacing: 16) {
            // Reps field (first - natural order: "10 reps at 72 lbs")
            VStack(spacing: 4) {
                Button(action: {
                    isEditingValues.toggle()
                }) {
                    Text("\(reps)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color("PrimaryText"))
                        .frame(minWidth: 60)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isEditingValues ? Color.blue : Color(uiColor: .systemGray4), lineWidth: isEditingValues ? 2 : 1)
                        )
                }

                Text("reps")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))
            }

            // Separator
            Text("×")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color("SecondaryText"))

            // Weight field (second)
            VStack(spacing: 4) {
                Button(action: {
                    isEditingValues.toggle()
                }) {
                    Text("\(Int(weight))")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color("PrimaryText"))
                        .frame(minWidth: 80)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isEditingValues ? Color.blue : Color(uiColor: .systemGray4), lineWidth: isEditingValues ? 2 : 1)
                        )
                }

                Text("lbs")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))
            }
        }
        .padding(.vertical, 8)
    }

    /// v78.0: Dual wheel pickers (Zing-style, from InteractiveSetCard)
    private var pickerSection: some View {
        VStack(spacing: 8) {
            // Close button
            HStack {
                Spacer()
                Button(action: {
                    isEditingValues = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color("SecondaryText"))
                }
            }

            // Side-by-side wheel pickers (v125: reps first to match display order)
            HStack(spacing: 12) {
                // Reps picker (0-50 reps)
                Picker("", selection: Binding(
                    get: { Double(reps) },
                    set: { reps = Int($0) }
                )) {
                    ForEach(Array(stride(from: 0.0, through: 50.0, by: 1.0)), id: \.self) { val in
                        Text("\(Int(val)) reps")
                            .tag(val)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                // Weight picker (0-500 lbs in 2.5 lb increments)
                Picker("", selection: $weight) {
                    ForEach(Array(stride(from: 0.0, through: 500.0, by: 2.5)), id: \.self) { val in
                        Text(formatWeight(val))
                            .tag(val)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }
        }
        .padding(12)
        .background(Color("Background"))
        .cornerRadius(12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Primary LOG SET button
    private var logButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            isEditingValues = false  // Close picker on log
            onLog()
        }) {
            Text("LOG SET")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(14)
        }
    }

    /// Swipe up hint for details
    private var detailsHint: some View {
        Button(action: onDetailsSheet) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                Text("Exercise Details")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(Color("SecondaryText"))
        }
    }

    // MARK: - Helpers

    private func formatWeight(_ val: Double) -> String {
        if val.truncatingRemainder(dividingBy: 1.0) == 0 {
            return "\(Int(val)) lbs"
        } else {
            return String(format: "%.1f lbs", val)
        }
    }
}

// MARK: - Preview

#Preview("Set Action Card") {
    ZStack {
        Color("Background")
            .ignoresSafeArea()

        VStack {
            Spacer()

            SetActionCard(
                exerciseName: "Barbell Bench Press",
                setNumber: 2,
                totalSets: 4,
                weight: .constant(135),
                reps: .constant(8),
                onLog: { print("Logged!") },
                onDetailsSheet: { print("Show details") }
            )
        }
    }
}

#Preview("Set Action Card - Editing") {
    ZStack {
        Color("Background")
            .ignoresSafeArea()

        VStack {
            Spacer()

            SetActionCard(
                exerciseName: "Squat",
                setNumber: 1,
                totalSets: 3,
                weight: .constant(225),
                reps: .constant(5),
                onLog: { print("Logged!") },
                onDetailsSheet: { print("Show details") }
            )
        }
    }
}
