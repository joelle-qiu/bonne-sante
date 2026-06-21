import Foundation

/// Simple debug logger that saves logs to a file for debugging
final class DebugLogger {
    static let shared = DebugLogger()

    private let fileURL: URL
    private let maxLogSize = 100_000 // 100KB max

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("debug_log.txt")
    }

    /// Log a message with timestamp
    func log(_ message: String, function: String = #function, file: String = #file) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let entry = "[\(timestamp)] [\(fileName):\(function)] \(message)\n"

        // Print to console
        print(entry)

        // Append to file
        appendToFile(entry)
    }

    /// Log API request
    func logAPIRequest(endpoint: String, body: String?) {
        var msg = "API REQUEST: \(endpoint)"
        if let body = body {
            msg += "\nBody: \(body.prefix(500))"
        }
        log(msg)
    }

    /// Log API response
    func logAPIResponse(statusCode: Int, body: String) {
        log("API RESPONSE [\(statusCode)]:\n\(body.prefix(1000))")
    }

    /// Log error
    func logError(_ error: Error, context: String = "") {
        log("ERROR \(context): \(error.localizedDescription)\n\(error)")
    }

    /// Get all logs
    func getAllLogs() -> String {
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return "No logs available"
        }
    }

    /// Clear logs
    func clearLogs() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Get log file path (for sharing)
    func getLogFilePath() -> URL {
        return fileURL
    }

    private func appendToFile(_ entry: String) {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Check file size
                let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let size = attrs[.size] as? Int, size > maxLogSize {
                    // Truncate old logs
                    try entry.write(to: fileURL, atomically: true, encoding: .utf8)
                    return
                }

                // Append
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                // Create new file
                try entry.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Failed to write log: \(error)")
        }
    }
}
