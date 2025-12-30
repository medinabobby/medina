//
// GymDetailView.swift
// Medina
//
// v74.1: Extracted from SettingsModal.swift
// Created: December 1, 2025
//

import SwiftUI

/// Gym detail view with address, hours, amenities
struct GymDetailView: View {
    @Binding var user: UnifiedUser

    private var gym: Gym? {
        guard let gymId = user.gymId else { return nil }
        return LocalDataStore.shared.gyms[gymId]
    }

    var body: some View {
        List {
            if let gym = gym {
                // Gym Info Section
                Section {
                    // Name
                    HStack {
                        Text("Name")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(gym.name)
                            .foregroundColor(.secondary)
                    }

                    // Address
                    HStack(alignment: .top) {
                        Text("Address")
                            .foregroundColor(.primary)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(gym.address)
                            Text("\(gym.city), \(gym.state) \(gym.zipCode)")
                        }
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                    }

                    // Phone
                    if let phone = gym.phone {
                        HStack {
                            Text("Phone")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(phone)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Hours Section
                Section("Hours") {
                    HoursRow(day: "Monday", hours: gym.hours.monday)
                    HoursRow(day: "Tuesday", hours: gym.hours.tuesday)
                    HoursRow(day: "Wednesday", hours: gym.hours.wednesday)
                    HoursRow(day: "Thursday", hours: gym.hours.thursday)
                    HoursRow(day: "Friday", hours: gym.hours.friday)
                    HoursRow(day: "Saturday", hours: gym.hours.saturday)
                    HoursRow(day: "Sunday", hours: gym.hours.sunday)
                }

                // Amenities Section
                if !gym.amenities.isEmpty {
                    Section("Amenities") {
                        ForEach(gym.amenities, id: \.self) { amenity in
                            Text(amenity)
                        }
                    }
                }
            } else {
                Text("No gym selected")
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Gym Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HoursRow: View {
    let day: String
    let hours: String

    var body: some View {
        HStack {
            Text(day)
                .foregroundColor(.primary)
            Spacer()
            Text(hours)
                .foregroundColor(.secondary)
        }
    }
}
