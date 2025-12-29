//
// CardioSetActionCard.swift
// Medina
//
// v101.2: Bottom action card for cardio workout execution
// Created: December 2025
// Purpose: Duration/distance display with wheel pickers and LOG button for cardio exercises
//

import SwiftUI

/// Bottom card showing current cardio exercise, duration/distance controls, and log button
struct CardioSetActionCard: View {
    let exerciseName: String
    let setNumber: Int
    let totalSets: Int
    @Binding var durationSeconds: Int  // Duration in seconds
    @Binding var distance: Double       // Distance in miles
    let showDistance: Bool              // Whether to show distance input (treadmill/bike yes, stretching no)
    let onLog: () -> Void
    let onDetailsSheet: () -> Void

    @State private var isEditingValues = false

    var body: some View {
        VStack(spacing: 16) {
            // Handle indicator for sheet-like appearance
            handleIndicator

            // Set progress with status dots
            setProgressRow

            // Duration and distance input (tappable to open picker)
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

    /// Set progress row with status dots (for cardio, typically just 1 set)
    private var setProgressRow: some View {
        VStack(spacing: 8) {
            // Set X of Y label
            Text(totalSets == 1 ? "Session" : "Set \(setNumber) of \(totalSets)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color("PrimaryText"))

            // Status dots row (only show if multiple sets)
            if totalSets > 1 {
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
            }
        }
    }

    /// Dot fill color based on set position
    private func dotColor(for setIndex: Int) -> Color {
        if setIndex < setNumber {
            return .green  // Completed
        } else if setIndex == setNumber {
            return .blue   // Current (active)
        } else {
            return .clear  // Pending (outlined only)
        }
    }

    /// Dot stroke color based on set position
    private func dotStrokeColor(for setIndex: Int) -> Color {
        if setIndex < setNumber || setIndex == setNumber {
            return .clear  // No stroke for filled dots
        } else {
            return Color(uiColor: .systemGray4)  // Gray outline for pending
        }
    }

    /// Duration and distance input - tappable fields
    private var inputSection: some View {
        HStack(spacing: 16) {
            // Duration field (always shown)
            VStack(spacing: 4) {
                Button(action: {
                    isEditingValues.toggle()
                }) {
                    Text(formatDuration(durationSeconds))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color("PrimaryText"))
                        .frame(minWidth: 100)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isEditingValues ? Color.blue : Color(uiColor: .systemGray4), lineWidth: isEditingValues ? 2 : 1)
                        )
                }

                Text("time")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))
            }

            // Distance field (optional - for treadmill, bike, etc.)
            if showDistance {
                // Separator
                Text("•")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color("SecondaryText"))

                VStack(spacing: 4) {
                    Button(action: {
                        isEditingValues.toggle()
                    }) {
                        Text(formatDistance(distance))
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

                    Text("miles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color("SecondaryText"))
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// Dual wheel pickers for duration and distance
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

            // Side-by-side wheel pickers
            HStack(spacing: 12) {
                // Minutes picker (0-120 min)
                VStack(spacing: 4) {
                    Text("Minutes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color("SecondaryText"))

                    Picker("", selection: Binding(
                        get: { durationSeconds / 60 },
                        set: { durationSeconds = $0 * 60 + (durationSeconds % 60) }
                    )) {
                        ForEach(0..<121, id: \.self) { minutes in
                            Text("\(minutes)")
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 120)
                }

                // Seconds picker (0-59)
                VStack(spacing: 4) {
                    Text("Seconds")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color("SecondaryText"))

                    Picker("", selection: Binding(
                        get: { durationSeconds % 60 },
                        set: { durationSeconds = (durationSeconds / 60) * 60 + $0 }
                    )) {
                        ForEach(0..<60, id: \.self) { seconds in
                            Text(String(format: "%02d", seconds))
                                .tag(seconds)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 120)
                }

                // Distance picker (only if showing distance)
                if showDistance {
                    VStack(spacing: 4) {
                        Text("Miles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color("SecondaryText"))

                        Picker("", selection: $distance) {
                            ForEach(Array(stride(from: 0.0, through: 26.2, by: 0.1)), id: \.self) { val in
                                Text(String(format: "%.1f", val))
                                    .tag(val)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 80, height: 120)
                    }
                }
            }
        }
        .padding(12)
        .background(Color("Background"))
        .cornerRadius(12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Primary LOG button
    private var logButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            isEditingValues = false  // Close picker on log
            onLog()
        }) {
            Text("LOG SESSION")
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

    /// Format seconds as MM:SS
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Format distance with 1 decimal place
    private func formatDistance(_ miles: Double) -> String {
        return String(format: "%.1f", miles)
    }
}

// MARK: - Preview

#Preview("Cardio Action Card - Treadmill") {
    ZStack {
        Color("Background")
            .ignoresSafeArea()

        VStack {
            Spacer()

            CardioSetActionCard(
                exerciseName: "Treadmill Run",
                setNumber: 1,
                totalSets: 1,
                durationSeconds: .constant(1800),  // 30 minutes
                distance: .constant(3.5),
                showDistance: true,
                onLog: { print("Logged!") },
                onDetailsSheet: { print("Show details") }
            )
        }
    }
}

#Preview("Cardio Action Card - No Distance") {
    ZStack {
        Color("Background")
            .ignoresSafeArea()

        VStack {
            Spacer()

            CardioSetActionCard(
                exerciseName: "Stretching",
                setNumber: 1,
                totalSets: 1,
                durationSeconds: .constant(900),  // 15 minutes
                distance: .constant(0),
                showDistance: false,
                onLog: { print("Logged!") },
                onDetailsSheet: { print("Show details") }
            )
        }
    }
}
