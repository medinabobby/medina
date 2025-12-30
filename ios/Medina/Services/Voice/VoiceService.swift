//
// VoiceService.swift
// Medina
//
// v31.0: Voice workout execution - OpenAI TTS integration
// v86.0: Removed MacPaw/OpenAI dependency, using direct HTTP calls
// v215: Migrated to Firebase TTS endpoint (API key on server)
// Last reviewed: December 2025
//

import Foundation
import AVFoundation

/// Service for text-to-speech voice guidance during workouts
///
/// Uses Firebase /api/tts endpoint which proxies to OpenAI TTS-1 API.
/// API key is stored securely on server - iOS never has access.
/// Recommended voice: nova (warm, energetic female voice for motivation)
///
/// Usage:
/// ```swift
/// let service = VoiceService()
/// try await service.speak("Starting your workout!", userId: user.id)
/// ```
@MainActor
class VoiceService: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private let dataManager: LocalDataStore

    @Published var isSpeaking = false

    /// Available TTS voices
    enum Voice: String {
        case alloy, echo, fable, onyx, nova, shimmer
    }

    /// Initialize voice service
    /// - Parameter dataManager: Data manager for accessing user voice settings
    init(dataManager: LocalDataStore = .shared) {
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

    /// Legacy initializer for backwards compatibility (apiKey ignored)
    /// - Parameter apiKey: Ignored - API key now on server
    /// - Parameter dataManager: Data manager for accessing user voice settings
    @available(*, deprecated, message: "API key no longer needed - stored on server")
    convenience init(apiKey: String, dataManager: LocalDataStore = .shared) {
        self.init(dataManager: dataManager)
    }

    /// Speak text using Firebase TTS endpoint
    ///
    /// v47: Checks user's voice settings before speaking. If voice is disabled, returns silently.
    /// v215: Now uses Firebase /api/tts endpoint (API key on server)
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

        Logger.log(.info, component: "VoiceService", message: "Speaking via Firebase: \(text.prefix(50))...")

        do {
            // v215: Call Firebase TTS endpoint instead of OpenAI directly
            let audioData = try await FirebaseAPIClient.shared.tts(
                text: text,
                voice: voice.rawValue,
                speed: 1.0
            )

            // Play audio
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = 1.0

            let success = audioPlayer?.play() ?? false
            if !success {
                Logger.log(.error, component: "VoiceService", message: "Audio playback failed to start")
                throw NSError(domain: "VoiceService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio playback failed"])
            }

            Logger.log(.info, component: "VoiceService", message: "Audio playback started (\(audioData.count) bytes)")

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
