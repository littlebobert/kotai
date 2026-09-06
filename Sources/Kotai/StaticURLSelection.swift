import Foundation

struct StaticURLSelection: Equatable {
    let confirmedURL: URL?
    let setupSuggestionURL: URL?

    init(confirmedValue: String?, legacyValue: String?) {
        confirmedURL = Self.normalizedURL(from: confirmedValue)
        setupSuggestionURL = confirmedURL ?? Self.normalizedURL(from: legacyValue)
    }

    private static func normalizedURL(from value: String?) -> URL? {
        guard let value, let staticURL = try? NgrokStaticURL(value) else {
            return nil
        }
        return staticURL.url
    }
}
