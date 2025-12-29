//
// URLContentFetcher.swift
// Medina
//
// v106.1: Inline URL content fetching for chat messages
// Created: December 10, 2025
//
// Detects URLs in user messages and fetches webpage content
// to include in AI context (like ChatGPT/Claude browsing).
//

import Foundation

/// Fetches and extracts content from URLs in chat messages
enum URLContentFetcher {

    // MARK: - Types

    /// Result of URL detection and fetching
    struct FetchResult {
        let originalURL: String
        let title: String?
        let content: String
        let success: Bool
        let error: String?
    }

    // MARK: - URL Detection

    /// Detect HTTP/HTTPS URLs in text
    static func detectURLs(in text: String) -> [String] {
        // Use NSDataDetector for robust URL detection
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        return matches.compactMap { match -> String? in
            guard let urlRange = Range(match.range, in: text),
                  let url = URL(string: String(text[urlRange])),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            return String(text[urlRange])
        }
    }

    /// Check if text contains any URLs
    static func containsURL(_ text: String) -> Bool {
        return !detectURLs(in: text).isEmpty
    }

    // MARK: - Content Fetching

    /// Fetch content from a single URL
    static func fetchContent(from urlString: String) async -> FetchResult {
        guard let url = URL(string: urlString) else {
            return FetchResult(
                originalURL: urlString,
                title: nil,
                content: "",
                success: false,
                error: "Invalid URL"
            )
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return FetchResult(
                    originalURL: urlString,
                    title: nil,
                    content: "",
                    success: false,
                    error: "Invalid response"
                )
            }

            guard httpResponse.statusCode == 200 else {
                return FetchResult(
                    originalURL: urlString,
                    title: nil,
                    content: "",
                    success: false,
                    error: "HTTP \(httpResponse.statusCode)"
                )
            }

            guard let html = String(data: data, encoding: .utf8) else {
                return FetchResult(
                    originalURL: urlString,
                    title: nil,
                    content: "",
                    success: false,
                    error: "Could not decode response"
                )
            }

            let title = extractTitle(from: html)
            let content = stripHTML(html)

            // Truncate to reasonable length for AI context (~10k chars)
            let truncatedContent = String(content.prefix(10000))

            Logger.log(.info, component: "URLContentFetcher",
                       message: "Fetched \(truncatedContent.count) chars from \(url.host ?? "unknown")")

            return FetchResult(
                originalURL: urlString,
                title: title,
                content: truncatedContent,
                success: true,
                error: nil
            )

        } catch {
            Logger.log(.error, component: "URLContentFetcher",
                       message: "Fetch failed for \(urlString): \(error.localizedDescription)")

            return FetchResult(
                originalURL: urlString,
                title: nil,
                content: "",
                success: false,
                error: error.localizedDescription
            )
        }
    }

    /// Fetch content from all URLs in text
    static func fetchAllURLs(in text: String) async -> [FetchResult] {
        let urls = detectURLs(in: text)
        guard !urls.isEmpty else { return [] }

        // Fetch all URLs in parallel
        return await withTaskGroup(of: FetchResult.self) { group in
            for url in urls {
                group.addTask {
                    await fetchContent(from: url)
                }
            }

            var results: [FetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    // MARK: - Message Augmentation

    /// Augment user message with fetched URL content
    /// Returns the original message + appended context
    static func augmentMessageWithURLContent(_ message: String) async -> (augmentedMessage: String, fetchedURLs: [FetchResult]) {
        let results = await fetchAllURLs(in: message)

        guard !results.isEmpty else {
            return (message, [])
        }

        var augmentedMessage = message

        for result in results where result.success {
            augmentedMessage += """


            ---
            [Content from \(result.originalURL)]
            Title: \(result.title ?? "Unknown")

            \(result.content)
            ---
            """
        }

        return (augmentedMessage, results)
    }

    // MARK: - HTML Processing

    private static func extractTitle(from html: String) -> String? {
        if let titleRange = html.range(of: "<title>"),
           let titleEndRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
            let title = String(html[titleRange.upperBound..<titleEndRange.lowerBound])
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html

        // Remove script and style blocks
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Collapse whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
