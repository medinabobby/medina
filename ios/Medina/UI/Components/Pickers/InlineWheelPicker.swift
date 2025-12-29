//
// InlineWheelPicker.swift
// Medina
//
// Touch-centric set entry feature
// Created: November 10, 2025
// Purpose: Compact scrollable wheel picker that appears inline (Zing-style)
//

import SwiftUI

struct InlineWheelPicker: View {
    let label: String
    @Binding var value: Double
    let min: Double
    let max: Double
    let step: Double
    let unit: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Header with label and done button
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color("PrimaryText"))

                Spacer()

                Button("Done") {
                    onDone()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
            }

            // Compact wheel picker
            Picker("", selection: $value) {
                ForEach(Array(stride(from: min, through: max, by: step)), id: \.self) { val in
                    Text(formatValue(val))
                        .tag(val)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
        }
        .padding(12)
        .background(Color("Background"))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func formatValue(_ val: Double) -> String {
        if step >= 1.0 {
            return "\(Int(val)) \(unit)"
        } else {
            return String(format: "%.1f \(unit)", val)
        }
    }
}

// MARK: - Previews

#Preview("Weight Picker") {
    InlineWheelPicker(
        label: "Weight",
        value: .constant(225.0),
        min: 0,
        max: 500,
        step: 2.5,
        unit: "lbs",
        onDone: {}
    )
    .padding()
}

#Preview("Reps Picker") {
    InlineWheelPicker(
        label: "Reps",
        value: .constant(5.0),
        min: 0,
        max: 50,
        step: 1,
        unit: "reps",
        onDone: {}
    )
    .padding()
}
