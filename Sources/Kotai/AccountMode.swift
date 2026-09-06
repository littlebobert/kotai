import Foundation

enum AccountMode: String, CaseIterable, Codable, Sendable {
    case personal
    case work

    var displayName: String {
        switch self {
        case .personal:
            String(localized: "Personal")
        case .work:
            String(localized: "Work")
        }
    }

    var symbolName: String {
        switch self {
        case .personal:
            "person.crop.circle"
        case .work:
            "briefcase.circle"
        }
    }
}
