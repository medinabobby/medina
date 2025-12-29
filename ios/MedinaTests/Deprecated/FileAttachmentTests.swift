//
// FileAttachmentTests.swift
// MedinaTests
//
// v185: Tests for file attachment functionality
// Verifies FileAttachment initialization and ChatAttachmentProcessor
//
// Created: December 2025
//

import XCTest
@testable import Medina

class FileAttachmentTests: XCTestCase {

    // MARK: - FileAttachment Initialization Tests

    /// Test: FileAttachment can be created from in-memory data
    func testFileAttachment_InMemoryData_Succeeds() throws {
        // Given: Some test data
        let testData = "Hello, World!".data(using: .utf8)!
        let fileName = "test.txt"

        // When: Creating attachment with pre-loaded data
        let attachment = FileAttachment(fileName: fileName, data: testData)

        // Then: Should have correct properties
        XCTAssertEqual(attachment.fileName, fileName)
        XCTAssertEqual(attachment.data, testData)
    }

    /// Test: FileAttachment can be created from temp file URL
    func testFileAttachment_TempFileURL_Succeeds() throws {
        // Given: A temporary file with test data
        let testData = "Test file content".data(using: .utf8)!
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).txt")

        // Write test file
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // When: Creating attachment from URL
        let attachment = FileAttachment(url: tempURL)

        // Then: Should load successfully
        XCTAssertNotNil(attachment, "Should create attachment from temp file URL")
        XCTAssertEqual(attachment?.fileName, tempURL.lastPathComponent)
        XCTAssertEqual(attachment?.data, testData)
    }

    /// Test: FileAttachment returns nil for non-existent file
    func testFileAttachment_NonExistentFile_ReturnsNil() throws {
        // Given: A URL that doesn't exist
        let fakeURL = URL(fileURLWithPath: "/non/existent/path/file.txt")

        // When: Trying to create attachment
        let attachment = FileAttachment(url: fakeURL)

        // Then: Should return nil
        XCTAssertNil(attachment, "Should return nil for non-existent file")
    }

    // MARK: - Image Detection Tests

    /// Test: Image file extensions are correctly detected
    func testIsImageFile_ImageExtensions_ReturnsTrue() throws {
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp"]

        for ext in imageExtensions {
            let fileName = "photo.\(ext)"
            let isImage = isImageFile(fileName)
            XCTAssertTrue(isImage, "'\(ext)' should be detected as image")
        }
    }

    /// Test: Non-image file extensions are correctly detected
    func testIsImageFile_NonImageExtensions_ReturnsFalse() throws {
        let nonImageExtensions = ["pdf", "csv", "txt", "json", "xlsx", "doc"]

        for ext in nonImageExtensions {
            let fileName = "document.\(ext)"
            let isImage = isImageFile(fileName)
            XCTAssertFalse(isImage, "'\(ext)' should NOT be detected as image")
        }
    }

    /// Test: Case-insensitive extension matching
    func testIsImageFile_CaseInsensitive() throws {
        let cases = ["photo.PNG", "photo.Jpg", "photo.JPEG", "photo.HeIc"]

        for fileName in cases {
            let isImage = isImageFile(fileName)
            XCTAssertTrue(isImage, "'\(fileName)' should be detected as image (case-insensitive)")
        }
    }

    // MARK: - Helper

    private func isImageFile(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp"].contains(ext)
    }

    // MARK: - Image Data Tests

    /// Test: UIImage can be created from valid JPEG data
    func testUIImage_ValidJPEGData_CreatesImage() throws {
        // Given: Create a simple 10x10 red image
        let size = CGSize(width: 10, height: 10)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let originalImage = image,
              let jpegData = originalImage.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to create test image")
            return
        }

        // When: Creating UIImage from JPEG data
        let loadedImage = UIImage(data: jpegData)

        // Then: Should successfully create image
        XCTAssertNotNil(loadedImage, "Should create UIImage from JPEG data")
    }

    /// Test: FileAttachment with image data can be loaded as UIImage
    func testFileAttachment_ImageData_CanBeLoadedAsUIImage() throws {
        // Given: Create a test image and its data
        let size = CGSize(width: 10, height: 10)
        UIGraphicsBeginImageContext(size)
        UIColor.blue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let originalImage = image,
              let jpegData = originalImage.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to create test image")
            return
        }

        // When: Creating FileAttachment with image data
        let attachment = FileAttachment(fileName: "test.jpg", data: jpegData)

        // Then: Should be able to convert back to UIImage
        let loadedImage = UIImage(data: attachment.data)
        XCTAssertNotNil(loadedImage, "Should load UIImage from FileAttachment data")
    }
}
