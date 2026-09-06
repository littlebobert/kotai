import Foundation

enum AccountMode: String, CaseIterable, Codable, Sendable {
    case personal
    case work

    var displayName: String {
        rawValue.capitalized
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
