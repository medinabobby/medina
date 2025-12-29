//
// EmptyStateGreetingView.swift
// Medina
//
// v99.8: Claude mobile-style centered greeting
// v99.9: Simplified - just greeting, chips moved to ChatInputView area
// v100.2: More varied, engaging greetings with fitness context
// v179: Added isNewUser parameter for brand-agnostic new user greetings
//

import SwiftUI

/// Empty state greeting shown when no messages exist
/// Just the time-of-day greeting, centered in the content area
/// v179: New users see brand-agnostic greeting, existing users see time-of-day greeting
struct EmptyStateGreetingView: View {
    let userName: String
    let isNewUser: Bool

    // v179: Default to false for backward compatibility
    init(userName: String, isNewUser: Bool = false) {
        self.userName = userName
        self.isNewUser = isNewUser
    }

    var body: some View {
        VStack {
            Spacer()

            // v179: New users see brand-agnostic greeting, existing users see time-of-day greeting
            Text(isNewUser ? newUserGreeting : timeOfDayGreeting)
                .font(.title)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundPrimary)
    }

    // MARK: - New User Greeting (v179)

    /// Brand-agnostic greeting for new users (works for white-label gym apps)
    private var newUserGreeting: String {
        let varietyIndex = Calendar.current.component(.weekday, from: Date()) % 3
        let greetings = [
            "Let's get started, \(userName)!",
            "Hi \(userName). Tell me about your fitness goals.",
            "Hey \(userName)! How can I help you today?"
        ]
        return greetings[varietyIndex]
    }

    // MARK: - Time of Day Greeting

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        let isWeekend = dayOfWeek == 1 || dayOfWeek == 7

        // Use day + hour to create variety while being deterministic per session
        let varietyIndex = (dayOfWeek + hour) % 3

        switch hour {
        case 5..<12:
            let morningGreetings = [
                "Good morning, \(userName). Ready to start strong?",
                "Morning, \(userName). What's on the agenda today?",
                "Good morning, \(userName). Let's make it count."
            ]
            return morningGreetings[varietyIndex]

        case 12..<17:
            let afternoonGreetings = [
                "Good afternoon, \(userName). How can I help?",
                "Hey \(userName). What are we working on today?",
                "Afternoon, \(userName). Ready when you are."
            ]
            return afternoonGreetings[varietyIndex]

        case 17..<21:
            let eveningGreetings = [
                "Good evening, \(userName). Time to train?",
                "Evening, \(userName). What should we tackle?",
                isWeekend ? "Hey \(userName). Weekend workout?" : "Hey \(userName). End the day strong?"
            ]
            return eveningGreetings[varietyIndex]

        default:
            let lateGreetings = [
                "Hey \(userName). Night owl session?",
                "Still going, \(userName)? I'm here to help.",
                "Hey \(userName). What can I help with?"
            ]
            return lateGreetings[varietyIndex]
        }
    }
}
