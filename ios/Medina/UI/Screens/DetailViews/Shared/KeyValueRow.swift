//
// KeyValueRow.swift
// Medina
//
// v48 Navigation Refactor
// Created: November 2025
// Purpose: Reusable key-value row component for detail views
//

import SwiftUI

/// Displays a key-value pair in a horizontal row
struct KeyValueRow: View {
    let key: String
    let value: String
    var keyColor: Color = Color("SecondaryText")
    var valueColor: Color = Color("PrimaryText")
    var valueWeight: Font.Weight = .regular

    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(size: 15))
                .foregroundColor(keyColor)
                .frame(width: 100, alignment: .leading)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: valueWeight))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Previews

#Preview("Basic") {
    VStack(spacing: 12) {
        KeyValueRow(key: "Status", value: "Active")
        KeyValueRow(key: "Start Date", value: "Nov 1, 2025")
        KeyValueRow(key: "Intensity", value: "70-80%")
    }
    .padding()
}

#Preview("Highlighted") {
    VStack(spacing: 12) {
        KeyValueRow(
            key: "Target",
            value: "215 lbs",
            valueColor: .accentColor,
            valueWeight: .semibold
        )
        KeyValueRow(
            key: "Current",
            value: "200 lbs",
            valueColor: .accentColor,
            valueWeight: .semibold
        )
    }
    .padding()
}
