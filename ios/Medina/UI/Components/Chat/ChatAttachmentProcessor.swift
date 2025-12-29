//
// ChatAttachmentProcessor.swift
// Medina
//
// v93.8: Extracted file attachment processing from ChatView
// Handles image vision and CSV import processing
//

import SwiftUI

/// Processes file attachments for chat - images via AI vision, CSV/text parsed
@MainActor
enum ChatAttachmentProcessor {

    /// Process multiple attachments - images go to AI vision, CSV/text parsed
    /// Claude-style: no wizard, natural conversation with vision
    static func process(
        _ attachments: [FileAttachment],
        userMessage: String,
        viewModel: ChatViewModel
    ) {
        Logger.log(.info, component: "ChatAttachmentProcessor",
                   message: "Processing \(attachments.count) attachment(s)")

        // Build display message with all file names
        let fileNames = attachments.map { "📎 \($0.fileName)" }.joined(separator: "\n")
        let displayMessage = userMessage.isEmpty
            ? fileNames
            : "\(fileNames)\n\n\(userMessage)"
        viewModel.addMessage(Message(content: displayMessage, isUser: true))

        // Separate images from other files
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp"]
        var images: [UIImage] = []
        var csvAttachments: [FileAttachment] = []

        for attachment in attachments {
            let ext = (attachment.fileName as NSString).pathExtension.lowercased()
            Logger.log(.debug, component: "ChatAttachmentProcessor",
                       message: "File: \(attachment.fileName), ext: \(ext), size: \(attachment.data.count) bytes")

            if imageExtensions.contains(ext) {
                if let uiImage = UIImage(data: attachment.data) {
                    images.append(uiImage)
                    Logger.log(.info, component: "ChatAttachmentProcessor",
                               message: "✅ Image loaded: \(attachment.fileName) (\(Int(uiImage.size.width))x\(Int(uiImage.size.height)))")
                } else {
                    Logger.log(.error, component: "ChatAttachmentProcessor",
                               message: "❌ Failed to create UIImage from: \(attachment.fileName)")
                    csvAttachments.append(attachment)  // Fall back to treating as file
                }
            } else {
                csvAttachments.append(attachment)
            }
        }

        // Send images directly to AI (Claude-style)
        if !images.isEmpty {
            Logger.log(.info, component: "ChatAttachmentProcessor",
                       message: "📤 Sending \(images.count) image(s) to vision API")
            Task {
                viewModel.setTyping(true)
                await viewModel.sendMessageWithImages(
                    userMessage.isEmpty ? "What's in this image?" : userMessage,
                    images: images
                )
                viewModel.setTyping(false)
            }
        } else {
            Logger.log(.warning, component: "ChatAttachmentProcessor",
                       message: "⚠️ No images to send (images array empty)")
        }

        // Process CSV/text files separately
        if let csvAttachment = csvAttachments.first {
            processCSVAttachment(csvAttachment, userMessage: userMessage, viewModel: viewModel)
        }
    }

    /// Process CSV/text attachment for workout data import
    private static func processCSVAttachment(
        _ attachment: FileAttachment,
        userMessage: String,
        viewModel: ChatViewModel
    ) {
        Task {
            viewModel.setTyping(true)

            do {
                // Parse CSV - use pre-loaded data from attachment
                let csvResult = try CSVImportService.parseCSV(data: attachment.data)

                // Convert to ImportedWorkoutData
                let importData = CSVImportService.toImportedWorkoutData(from: csvResult, userId: viewModel.user.id)

                // Process through pipeline - updates library, creates targets, infers experience
                let result = try ImportProcessingService.process(importData, userId: viewModel.user.id)

                Logger.log(.info, component: "ChatAttachmentProcessor",
                           message: "Import complete: \(result.targets.count) targets, \(result.importData.sessionCount) sessions")

                // Build context message for AI with import data + user request
                let aiContextMessage = buildImportContextForAI(result: result, userMessage: userMessage)

                viewModel.setTyping(false)
                await viewModel.sendContextToAI(aiContextMessage)

            } catch {
                Logger.log(.error, component: "ChatAttachmentProcessor",
                           message: "Import failed: \(error)")
                viewModel.addMessage(Message(
                    content: "Sorry, I couldn't import that file. Please ensure it's a CSV file with workout data.",
                    isUser: false
                ))
                viewModel.setTyping(false)
            }
        }
    }

    /// Build context message for AI that includes import data
    private static func buildImportContextForAI(result: ImportProcessingResult, userMessage: String) -> String {
        let summary = result.summary

        // Format top exercises with maxes
        let topExercises = summary.topExercises.prefix(5)
            .map { "\($0.name): \(Int($0.max)) lbs" }
            .joined(separator: ", ")

        // Format experience level if inferred
        let experienceInfo = result.intelligence?.inferredExperience.map { "Experience level: \($0.displayName)" } ?? ""

        // Build the context
        var context = """
        [User just imported workout history from CSV]
        Exercises with estimated 1RMs: \(topExercises)
        \(experienceInfo)
        """

        // Add user's request if provided
        if !userMessage.isEmpty {
            context += "\n\nUser request: \(userMessage)"
        } else {
            context += "\n\nUser request: Please acknowledge this import and offer to create a plan using these exercises."
        }

        return context
    }
}
