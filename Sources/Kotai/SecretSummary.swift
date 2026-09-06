import Foundation

struct SecretSummary: Equatable {
    private static let hiddenValue = "••••••••"

    let value: String

    var displayValue: String {
        guard !value.isEmpty else {
            return String(localized: "Not configured")
        }
        guard value.count > 10 else {
            return Self.hiddenValue
        }

        return String(value.prefix(5)) + "…" + String(value.suffix(5))
    }
}
