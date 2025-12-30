//
// UploadModal.swift
// Medina
//
// v74.4: Comprehensive upload modal with import, profile, and connect sections
// v74.6: Added onImportComplete callback for chat summary UX
// v74.9: Claude-style file attachment UX - onFileSelected passes file back to chat
// v79.2: UX audit - hidden drag indicator, profile nav fix, removed unimplemented services
// v87.5: Expanded file picker to support PDFs, images, and all file types for Claude-style attachment
// v80.3.8: Replaced "Update Profile" with "Training Preferences" for quick access
// v79.5: Photo import with Vision API - camera and photo picker integrated
// v80.2: Added COACHING section with Training Style and Voice Coaching
// v82.3: Voice settings now functional - removed Coming Soon badges
// v106.2: Renamed Voice & Verbosity to Workout Audio
// v106.1: URL import now handled inline in chat (like ChatGPT/Claude)
// v185: Added camera authorization check before showing camera picker
// Matches existing Settings modal UI patterns
// Created: December 1, 2025
// Updated: December 16, 2025
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct UploadModal: View {
    @Environment(\.dismiss) var dismiss
    let user: UnifiedUser
    var onFilesSelected: (([URL]) -> Void)?  // v87.6: Pass files back for Claude-style attachment UX (supports multiple)
    var onImportComplete: ((ImportProcessingResult) -> Void)?

    // Navigation state
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var showCSVImport = false
    @State private var importedFileURLs: [URL] = []  // v87.6: Support multiple files
    // v87.1: Removed showTrainingPreferences & showVoiceCoaching - now use NavigationLink
    // v182: Removed showTrainingStyle - training style feature removed for beta simplicity
    @State private var isProcessingImport = false
    @State private var currentUser: UnifiedUser

    // v87.6: Photo/camera state - now creates FileAttachment for Claude-style
    @State private var capturedImage: UIImage?

    // v185: Camera availability and authorization state
    @State private var showCameraUnavailableAlert = false
    @State private var cameraAlertMessage = ""

    init(user: UnifiedUser, onFilesSelected: (([URL]) -> Void)? = nil, onImportComplete: ((ImportProcessingResult) -> Void)? = nil) {
        self.user = user
        self.onFilesSelected = onFilesSelected
        self.onImportComplete = onImportComplete
        // v85.1: Fetch fresh user from LocalDataStore to get latest settings
        // (voiceSettings may have been changed and saved)
        let freshUser = LocalDataStore.shared.users[user.id] ?? user
        _currentUser = State(initialValue: freshUser)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Import Section - 3 options like ChatGPT
                    importSection

                    // Profile & Preferences Section
                    quickActionsSection

                    // v80.2: Coaching Section (Training Style + Voice Coaching)
                    coachingSection

                    // Connect Services Section
                    connectSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Quick Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            // v87.6: Camera picker - captured images become attachments
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView(selectedImage: $capturedImage)
            }
            // v87.6: Photo library picker - supports multiple selection
            .sheet(isPresented: $showPhotoPicker) {
                MultiPhotoPickerView(onImagesSelected: { images in
                    // Convert images to temp URLs for attachment
                    var urls: [URL] = []
                    for (index, image) in images.enumerated() {
                        if let url = saveImageToTempFile(image, index: index) {
                            urls.append(url)
                        }
                    }
                    if !urls.isEmpty {
                        onFilesSelected?(urls)
                        dismiss()
                    }
                })
            }
            // v87.6: Handle captured camera image
            .onChange(of: capturedImage) { newImage in
                guard let image = newImage else { return }
                if let url = saveImageToTempFile(image, index: 0) {
                    onFilesSelected?([url])
                    dismiss()
                }
                capturedImage = nil
            }
            // v87.6: File picker - supports multiple selection
            .fullScreenCover(isPresented: $showFilePicker) {
                DocumentPicker(fileURLs: $importedFileURLs)
            }
            // CSV Import view (after file selected - legacy fallback)
            .sheet(isPresented: $showCSVImport) {
                if let url = importedFileURLs.first {
                    CSVImportView(fileURL: url, user: user)
                }
            }
            // v87.6: Handle selected files (supports multiple)
            .onChange(of: importedFileURLs) { newURLs in
                guard !newURLs.isEmpty else { return }
                // v87.6: Pass files back to chat for Claude-style attachment UX
                if onFilesSelected != nil {
                    onFilesSelected?(newURLs)
                    dismiss()
                } else {
                    // Fallback: Process import immediately (legacy behavior)
                    if let url = newURLs.first {
                        processImportFile(url)
                    }
                }
            }
            // v182: Removed Training Style sheet - feature removed for beta simplicity
            // v87.1: Voice Settings now uses NavigationLink for slide-in behavior
            // v185: Camera unavailable alert
            .alert("Camera Unavailable", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(cameraAlertMessage)
            }
        }
        // v87.1: Full-size modal like Settings for consistency
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Import Section

    private var importSection: some View {
        SettingsSection(title: "IMPORT WORKOUT DATA") {
            HStack(spacing: 0) {
                // Camera
                ImportButton(
                    icon: "camera.fill",
                    iconColor: .blue,
                    label: "Camera"
                ) {
                    requestCameraAccess()
                }

                VerticalDivider()

                // Photos
                ImportButton(
                    icon: "photo.fill",
                    iconColor: .green,
                    label: "Photos"
                ) {
                    showPhotoPicker = true
                }

                VerticalDivider()

                // Files
                ImportButton(
                    icon: "doc.fill",
                    iconColor: .orange,
                    label: "Files"
                ) {
                    showFilePicker = true
                }
            }
            .frame(height: 100)
        }
    }

    // MARK: - Quick Actions Section
    // v80.3.8: Changed from "Update Profile" to "Training Preferences" for quick access
    // v87.1: Changed to NavigationLink for consistent slide-in behavior

    private var quickActionsSection: some View {
        SettingsSection(title: "TRAINING") {
            // Training Preferences (schedule, duration, equipment)
            NavigationLink {
                TrainingPreferencesView(
                    user: $currentUser,
                    onSave: { }
                )
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                        .frame(width: 28, height: 28)

                    Text("Training Preferences")
                        .font(.system(size: 17))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Coaching Section
    // v80.2: Training Style and Voice Coaching
    // v82.3: Removed Coming Soon badges - both are now functional
    // v87.1: Added inline voice toggle for 1-click access

    // v110.2: Removed Voice Chat toggle - microphone icon in chat bar serves same purpose
    // v182: Removed Training Style row - feature removed for beta simplicity
    private var coachingSection: some View {
        SettingsSection(title: "COACHING") {
            // Workout Audio row (v106.2: Renamed from Voice & Verbosity)
            NavigationLink {
                VoiceCoachingView(user: $currentUser)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 20))
                        .foregroundColor(.orange)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout Audio")
                            .font(.system(size: 17))
                            .foregroundColor(.primary)

                        Text("Voice coaching during workouts")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Show voice status
                    if let voiceSettings = currentUser.memberProfile?.voiceSettings {
                        Text(voiceSettings.isEnabled ? "On" : "Off")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Connect Section
    // v79.2: Removed unimplemented services (Strava, Garmin, Peloton) - only Apple Health for now

    private var connectSection: some View {
        SettingsSection(title: "CONNECT SERVICES") {
            // Apple Health
            ConnectServiceRow(
                icon: "heart.fill",
                iconColor: .red,
                title: "Apple Health",
                status: .comingSoon
            )
        }
    }

    // MARK: - Helper Functions

    // MARK: - v185: Camera Authorization

    /// Check camera availability and request authorization
    private func requestCameraAccess() {
        // Check if camera is available (not available on simulator)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlertMessage = "Camera is not available on this device."
            showCameraUnavailableAlert = true
            return
        }

        // Check authorization status
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        cameraAlertMessage = "Camera access denied. Please enable it in Settings."
                        showCameraUnavailableAlert = true
                    }
                }
            }
        case .denied, .restricted:
            cameraAlertMessage = "Camera access denied. Please enable it in Settings > Medina > Camera."
            showCameraUnavailableAlert = true
        @unknown default:
            cameraAlertMessage = "Unable to access camera."
            showCameraUnavailableAlert = true
        }
    }

    /// v87.6: Save image to temp file for attachment
    private func saveImageToTempFile(_ image: UIImage, index: Int) -> URL? {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else { return nil }

        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "photo_\(timestamp)_\(index).jpg"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try jpegData.write(to: tempURL)
            return tempURL
        } catch {
            Logger.log(.error, component: "UploadModal", message: "Failed to save temp image: \(error)")
            return nil
        }
    }

    // MARK: - Import Processing (v74.6)

    private func processImportFile(_ url: URL) {
        isProcessingImport = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Parse CSV
                let data = try Data(contentsOf: url)
                let csvResult = try CSVImportService.parseCSV(data: data)

                // Convert to ImportedWorkoutData with full session history
                let importData = CSVImportService.toImportedWorkoutData(from: csvResult, userId: user.id)

                DispatchQueue.main.async {
                    // Process through common pipeline
                    do {
                        let result = try ImportProcessingService.process(importData, userId: user.id)

                        Logger.log(.info, component: "UploadModal",
                                   message: "Import complete: \(result.targets.count) targets, \(result.importData.sessionCount) sessions")

                        // Call completion handler and dismiss
                        onImportComplete?(result)
                        isProcessingImport = false
                        dismiss()
                    } catch {
                        Logger.log(.error, component: "UploadModal",
                                   message: "Import processing failed: \(error)")
                        isProcessingImport = false
                        // Fall back to old preview modal
                        showCSVImport = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    Logger.log(.error, component: "UploadModal",
                               message: "CSV parsing failed: \(error)")
                    isProcessingImport = false
                    // Fall back to old preview modal for error display
                    showCSVImport = true
                }
            }
        }
    }
}

// MARK: - Import Button

private struct ImportButton: View {
    let icon: String
    let iconColor: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                }

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vertical Divider

private struct VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5)
            .padding(.vertical, 16)
    }
}

// MARK: - Connect Service Row

private enum ConnectionStatus {
    case connected
    case disconnected
    case comingSoon

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Connect"
        case .comingSoon: return "Coming Soon"
        }
    }

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .blue
        case .comingSoon: return .secondary
        }
    }
}

private struct ConnectServiceRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 17))
                .foregroundColor(.primary)

            Spacer()

            Text(status.label)
                .font(.system(size: 15))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Document Picker (v87.6: Multi-selection)

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var fileURLs: [URL]
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // v87.5: Support all common file types for Claude-style attachment
        // PDFs, images, text files, spreadsheets, and more can be attached to chat
        let supportedTypes: [UTType] = [
            .pdf,
            .image,
            .png,
            .jpeg,
            .heic,
            .commaSeparatedText,
            .plainText,
            .text,
            .spreadsheet,
            .json,
            .data  // Fallback for other file types
        ]

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: supportedTypes,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true  // v87.6: Allow multiple files
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // v87.6: Store all selected URLs
            parent.fileURLs = urls
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Multi Photo Picker (v87.6)

import PhotosUI

struct MultiPhotoPickerView: UIViewControllerRepresentable {
    let onImagesSelected: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 10  // v87.6: Allow up to 10 images
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiPhotoPickerView

        init(_ parent: MultiPhotoPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard !results.isEmpty else { return }

            // Load all images
            var images: [UIImage] = []
            let group = DispatchGroup()

            for result in results {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async {
                            images.append(image)
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.parent.onImagesSelected(images)
            }
        }
    }
}

#Preview {
    UploadModal(
        user: UnifiedUser(
            id: "bobby",
            firebaseUID: "test",
            authProvider: .email,
            email: "bobby@medina.com",
            name: "Bobby Tulsiani",
            birthdate: Date(),
            gender: .male,
            roles: [.member],
            memberProfile: MemberProfile(
                fitnessGoal: .strength,
                experienceLevel: .intermediate,
                preferredSessionDuration: 60,
                membershipStatus: .active,
                memberSince: Date()
            )
        )
    )
}
