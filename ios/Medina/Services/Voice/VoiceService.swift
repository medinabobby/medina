//
// VoiceService.swift
// Medina
//
// v31.0: Voice workout execution - OpenAI TTS integration
// v86.0: Removed MacPaw/OpenAI dependency, using direct HTTP calls
// Last reviewed: December 2025
//

import Foundation
import AVFoundation

/// Service for text-to-speech voice guidance during workouts
///
/// Uses OpenAI TTS-1 API for natural, human-like coaching voice.
/// Recommended voice: nova (warm, energetic female voice for motivation)
///
/// Usage:
/// ```swift
/// let service = VoiceService(apiKey: Config.openAIKey)
/// try await service.speak("Starting your workout! First exercise: Back Squat")
/// ```
@MainActor
class VoiceService: ObservableObject {
    private let apiKey: String
    private var audioPlayer: AVAudioPlayer?
    private let dataManager: TestDataManager

    @Published var isSpeaking = false

    /// Available TTS voices
    enum Voice: String {
        case alloy, echo, fable, onyx, nova, shimmer
    }

    /// Initialize voice service with OpenAI API key
    /// - Parameter apiKey: OpenAI API key (get from https://platform.openai.com/api-keys)
    /// - Parameter dataManager: Data manager for accessing user voice settings
    init(apiKey: String, dataManager: TestDataManager = .shared) {
        self.apiKey = apiKey
        self.dataManager = dataManager

        // Configure audio session for playback on iOS devices
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            Logger.log(.info, component: "VoiceService", message: "Audio session configured for playback")
        } catch {
            Logger.log(.error, component: "VoiceService", message: "Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    /// Speak text using OpenAI TTS with natural voice
    ///
    /// v47: Checks user's voice settings before speaking. If voice is disabled, returns silently.
    ///
    /// Cost: ~$0.015 per 1000 characters (~$0.002 per workout start message)
    ///
    /// - Parameters:
    ///   - text: Text to speak (workout guidance, exercise instructions, etc.)
    ///   - userId: User ID to check voice settings for
    ///   - voice: Voice to use (default: .nova - warm, energetic)
    /// - Throws: Network errors, API errors, audio playback errors
    func speak(_ text: String, userId: String, voice: Voice = .nova) async throws {
        // v47: Check if user has voice enabled
        // If voiceSettings is nil OR isEnabled is false, skip speech
        guard let user = dataManager.users[userId],
              let voiceSettings = user.memberProfile?.voiceSettings,
              voiceSettings.isEnabled else {
            Logger.log(.debug, component: "VoiceService", message: "Voice disabled for user \(userId), skipping speech")
            return
        }

        isSpeaking = true
        defer { isSpeaking = false }

        Logger.log(.info, component: "VoiceService", message: "Speaking: \(text.prefix(50))...")

        // Build request
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            throw NSError(domain: "VoiceService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": voice.rawValue,
            "response_format": "mp3",
            "speed": 1.0
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "VoiceService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                Logger.log(.error, component: "VoiceService", message: "TTS API error: \(httpResponse.statusCode) - \(errorBody)")
                throw NSError(domain: "VoiceService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorBody])
            }

            // Play audio
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = 1.0

            let success = audioPlayer?.play() ?? false
            if !success {
                Logger.log(.error, component: "VoiceService", message: "Audio playback failed to start")
                throw NSError(domain: "VoiceService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio playback failed"])
            }

            Logger.log(.info, component: "VoiceService", message: "Audio playback started (\(data.count) bytes)")

            // Wait for playback to complete
            while audioPlayer?.isPlaying == true {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }

            Logger.log(.info, component: "VoiceService", message: "Audio playback completed")
        } catch {
            Logger.log(.error, component: "VoiceService", message: "TTS failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Stop current speech playback
    func stopSpeaking() {
        audioPlayer?.stop()
        isSpeaking = false
        Logger.log(.info, component: "VoiceService", message: "Speech stopped")
    }
}
