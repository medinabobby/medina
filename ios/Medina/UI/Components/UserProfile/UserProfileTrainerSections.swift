//
// UserProfileTrainerSections.swift
// Medina
//
// v93.7: Trainer-specific content sections for UserProfileView
// Bio, Specialties, Certifications, Contact sections
//

import SwiftUI

// MARK: - Trainer Profile Header

struct TrainerProfileHeader: View {
    let user: UnifiedUser

    var body: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 100, height: 100)

                Text(user.firstName.prefix(1).uppercased())
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.blue)
            }

            // Name
            Text(user.name)
                .font(.title2)
                .fontWeight(.bold)

            // Role subtitle
            Text("Personal Trainer")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Years experience
            if let years = user.trainerProfile?.yearsExperience {
                HStack(spacing: 4) {
                    Image(systemName: "medal.fill")
                        .foregroundColor(.orange)
                    Text("\(years) years experience")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Bio Section

struct TrainerBioSection: View {
    let bio: String

    var body: some View {
        ProfileSection(title: "About", icon: "person.text.rectangle") {
            Text(bio)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }
}

// MARK: - Specialties Section

struct TrainerSpecialtiesSection: View {
    let specialties: [TrainerSpecialty]

    var body: some View {
        ProfileSection(title: "Specialties", icon: "star.fill") {
            FlowLayout(spacing: 8) {
                ForEach(specialties, id: \.self) { specialty in
                    SpecialtyChip(specialty: specialty)
                }
            }
        }
    }
}

// MARK: - Certifications Section

struct TrainerCertificationsSection: View {
    let certifications: [String]

    var body: some View {
        ProfileSection(title: "Certifications", icon: "checkmark.seal.fill") {
            ForEach(certifications, id: \.self) { cert in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text(cert)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Contact Section

struct TrainerContactSection: View {
    let email: String?
    let phone: String?

    var body: some View {
        VStack(spacing: 12) {
            if let email = email {
                Button(action: {
                    // TODO: Open email compose
                }) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.blue)
                        Text(email)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
            }

            if let phone = phone {
                Button(action: {
                    // TODO: Open phone dialer
                }) {
                    HStack {
                        Image(systemName: "phone.fill")
                            .foregroundColor(.green)
                        Text(phone)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
            }
        }
    }
}

// MARK: - Combined Trainer Content

struct TrainerContentSections: View {
    let user: UnifiedUser
    let mode: ProfileViewMode

    var body: some View {
        // Bio
        if let bio = user.trainerProfile?.bio, !bio.isEmpty {
            TrainerBioSection(bio: bio)
        }

        // Specialties
        if let specialties = user.trainerProfile?.specialties, !specialties.isEmpty {
            TrainerSpecialtiesSection(specialties: specialties)
        }

        // Certifications
        if let certifications = user.trainerProfile?.certifications, !certifications.isEmpty {
            TrainerCertificationsSection(certifications: certifications)
        }

        // Contact (only in view mode, not when editing own profile)
        if mode == .view {
            TrainerContactSection(email: user.email, phone: user.phoneNumber)
        }
    }
}
