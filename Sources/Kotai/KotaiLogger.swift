import Foundation

final class KotaiLogger: @unchecked Sendable {
    enum Level: String {
        case debug = "DEBUG"
        case error = "ERROR"
        case info = "INFO"
        case warning = "WARN"
    }

    static let shared = KotaiLogger()

    private static let maximumLogSize = 5 * 1024 * 1024
    private let lock = NSLock()
    private let formatter = ISO8601DateFormatter()
    private var sensitiveValues = Set<String>()
    private let currentLogURL: URL
    private let previousLogURL: URL

    private init() {
        let directoryURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Kotai", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        currentLogURL = directoryURL.appendingPathComponent("Kotai.log")
        previousLogURL = directoryURL.appendingPathComponent(
            "Kotai.previous.log"
        )
        if !FileManager.default.fileExists(atPath: currentLogURL.path) {
            FileManager.default.createFile(
                atPath: currentLogURL.path,
                contents: nil
            )
        }
    }

    func debug(_ message: @autoclosure () -> String) {
        write(.debug, message())
    }

    func error(_ message: @autoclosure () -> String) {
        write(.error, message())
    }

    func info(_ message: @autoclosure () -> String) {
        write(.info, message())
    }

    func warning(_ message: @autoclosure () -> String) {
        write(.warning, message())
    }

    func registerSensitiveValue(_ value: String) {
        let normalizedValue = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedValue.isEmpty else {
            return
        }

        lock.lock()
        sensitiveValues.insert(normalizedValue)
        lock.unlock()
    }

    func makeDiagnosticAttachment() -> URL? {
        lock.lock()
        defer { lock.unlock() }

        let diagnosticURL = currentLogURL
            .deletingLastPathComponent()
            .appendingPathComponent("Kotai-diagnostics.txt")
        var contents = """
        Kotai diagnostics
        Generated: \(formatter.string(from: Date()))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)

        """

        for logURL in [currentLogURL, previousLogURL] {
            guard
                let logContents = try? String(
                    contentsOf: logURL,
                    encoding: .utf8
                ),
                !logContents.isEmpty
            else {
                continue
            }
            contents += """
            --- \(logURL.lastPathComponent) ---
            \(redactingSensitiveData(in: logContents))

            """
        }

        do {
            try contents.write(
                to: diagnosticURL,
                atomically: true,
                encoding: .utf8
            )
            return diagnosticURL
        } catch {
            NSLog(
                "Kotai diagnostic export failed: %@",
                error.localizedDescription
            )
            return nil
        }
    }

    func recentLogText(maxLines: Int = 200) -> String {
        lock.lock()
        defer { lock.unlock() }

        guard
            let contents = try? String(
                contentsOf: currentLogURL,
                encoding: .utf8
            )
        else {
            return String(localized: "No diagnostic activity recorded.")
        }

        let lines = contents.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        let recentContents = lines.suffix(maxLines).joined(separator: "\n")
        return redactingSensitiveData(in: recentContents)
    }

    private func write(_ level: Level, _ rawMessage: String) {
        lock.lock()
        defer { lock.unlock() }

        let message = redactingSensitiveData(in: rawMessage)
            .replacingOccurrences(of: "\n", with: " ")
        rotateIfNeeded()
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [\(level.rawValue)] \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: currentLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            NSLog("Kotai logging failed: %@", error.localizedDescription)
        }
    }


    private func redactingSensitiveData(in text: String) -> String {
        let valueRedactedText = sensitiveValues
            .sorted { $0.count > $1.count }
            .reduce(text) { redactedText, sensitiveValue in
                redactedText.replacingOccurrences(
                    of: sensitiveValue,
                    with: "[REDACTED]"
                )
            }
        return Self.redactingSensitivePatterns(in: valueRedactedText)
    }

    static func redactingSensitivePatterns(in text: String) -> String {
        let rules: [(pattern: String, replacement: String)] = [
            (
                #"(?i)(\b(?:authorization|proxy-authorization)\b\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+"#,
                "$1[REDACTED]"
            ),
            (
                #"(?i)([?&](?:api[_-]?key|token|auth[_-]?token|authtoken|access[_-]?token|secret)=)[^&#\s]+"#,
                "$1[REDACTED]"
            ),
            (
                #"(?i)([\"'](?:api[_-]?key|apikey|openrouter[_-]?key|proxy[_-]?token|auth[_-]?token|authtoken|access[_-]?token|secret)[\"']\s*:\s*[\"'])[^\"']+"#,
                "$1[REDACTED]"
            ),
            (
                #"(?i)(\b(?:api[_-]?key|apikey|openrouter[_-]?key|proxy[_-]?token|auth[_-]?token|authtoken|access[_-]?token|secret)\b\s*=\s*)[^\s,;]+"#,
                "$1[REDACTED]"
            ),
            (
                #"(?i)\bbearer\s+[^\s,;]+"#,
                "Bearer [REDACTED]"
            ),
            (
                #"\bsk-or(?:-v\d+)?-[A-Za-z0-9_-]+\b"#,
                "[REDACTED]"
            ),
        ]

        return rules.reduce(text) { redactedText, rule in
            redactedText.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
    }

    private func rotateIfNeeded() {
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: currentLogURL.path
            ),
            let size = attributes[.size] as? NSNumber,
            size.intValue >= Self.maximumLogSize
        else {
            return
        }

        try? FileManager.default.removeItem(at: previousLogURL)
        try? FileManager.default.moveItem(
            at: currentLogURL,
            to: previousLogURL
        )
        FileManager.default.createFile(
            atPath: currentLogURL.path,
            contents: nil
        )
    }
}
