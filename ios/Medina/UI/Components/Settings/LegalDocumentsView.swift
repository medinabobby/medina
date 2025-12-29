//
// LegalDocumentsView.swift
// Medina
//
// v79.2: Local Terms of Service and Privacy Policy for beta
//

import SwiftUI

// MARK: - Terms of Service

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Last Updated: December 2025")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                section("1. Acceptance of Terms") {
                    """
                    By accessing or using Medina ("the App"), you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the App.
                    """
                }

                section("2. Description of Service") {
                    """
                    Medina is an AI-powered fitness coaching application that helps users create training plans, execute workouts, and track fitness progress. The App provides personalized workout recommendations based on user input and preferences.
                    """
                }

                section("3. Beta Program") {
                    """
                    You acknowledge that Medina is currently in beta testing. The App may contain bugs, errors, or incomplete features. We make no guarantees about the availability, reliability, or functionality of the App during the beta period.
                    """
                }

                section("4. User Responsibilities") {
                    """
                    • You must be at least 18 years old to use the App
                    • You are responsible for maintaining the confidentiality of your account
                    • You agree to provide accurate information when creating your profile
                    • You acknowledge that fitness activities carry inherent risks
                    • You should consult a healthcare provider before starting any exercise program
                    """
                }

                section("5. Health Disclaimer") {
                    """
                    Medina is not a substitute for professional medical advice, diagnosis, or treatment. The workout recommendations provided by the App are for informational purposes only. Always consult with a qualified healthcare provider before beginning any fitness program, especially if you have pre-existing health conditions.
                    """
                }

                section("6. Intellectual Property") {
                    """
                    All content, features, and functionality of the App are owned by Medina and are protected by copyright, trademark, and other intellectual property laws.
                    """
                }

                section("7. Limitation of Liability") {
                    """
                    To the maximum extent permitted by law, Medina shall not be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of the App, including but not limited to physical injury, property damage, or data loss.
                    """
                }

                section("8. Changes to Terms") {
                    """
                    We reserve the right to modify these Terms of Service at any time. Continued use of the App after changes constitutes acceptance of the new terms.
                    """
                }

                section("9. Contact") {
                    """
                    For questions about these Terms of Service, please contact us at support@medina.app
                    """
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            Text(content())
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Last Updated: December 2025")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                section("1. Information We Collect") {
                    """
                    We collect information you provide directly:
                    • Account information (name, email, date of birth)
                    • Fitness profile (goals, experience level, preferences)
                    • Workout data (exercises, sets, reps, weights)
                    • Chat conversations with the AI assistant
                    """
                }

                section("2. How We Use Your Information") {
                    """
                    We use your information to:
                    • Provide personalized workout recommendations
                    • Track your fitness progress over time
                    • Improve our AI coaching capabilities
                    • Send important updates about the App
                    • Ensure the security of your account
                    """
                }

                section("3. Data Storage") {
                    """
                    Your data is stored securely using industry-standard encryption. Workout data and preferences are stored locally on your device and synced to secure cloud servers for backup purposes.
                    """
                }

                section("4. Third-Party Services") {
                    """
                    We use the following third-party services:
                    • OpenAI for AI-powered workout recommendations
                    • Firebase for authentication and data storage
                    • Apple services for App Store distribution

                    These services have their own privacy policies governing how they handle your data.
                    """
                }

                section("5. Data Sharing") {
                    """
                    We do not sell your personal information. We may share anonymized, aggregated data for research purposes. We will share your information only when required by law or to protect our legal rights.
                    """
                }

                section("6. Your Rights") {
                    """
                    You have the right to:
                    • Access your personal data
                    • Correct inaccurate data
                    • Delete your account and associated data
                    • Export your workout history
                    • Opt out of non-essential communications
                    """
                }

                section("7. Data Retention") {
                    """
                    We retain your data for as long as your account is active. Upon account deletion, your personal data will be permanently removed within 30 days, except where retention is required by law.
                    """
                }

                section("8. Children's Privacy") {
                    """
                    Medina is not intended for users under 18 years of age. We do not knowingly collect personal information from children.
                    """
                }

                section("9. Changes to Privacy Policy") {
                    """
                    We may update this Privacy Policy from time to time. We will notify you of significant changes through the App or via email.
                    """
                }

                section("10. Contact") {
                    """
                    For questions about this Privacy Policy or to exercise your data rights, please contact us at privacy@medina.app
                    """
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            Text(content())
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Previews

#Preview("Terms of Service") {
    NavigationStack {
        TermsOfServiceView()
    }
}

#Preview("Privacy Policy") {
    NavigationStack {
        PrivacyPolicyView()
    }
}
