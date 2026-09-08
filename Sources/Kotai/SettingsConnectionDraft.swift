import Foundation

struct SettingsConnectionDraft: Equatable {
    let rawValue: String
    let confirmedURL: URL?
    let runtimeStatus: AppController.RuntimeStatus
    let hasCompleteCredentials: Bool

    var normalizedURL: URL? {
        try? NgrokStaticURL(rawValue).url
    }

    var validationError: String? {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              normalizedURL == nil
        else {
            return nil
        }
        return String(localized: "Enter a valid HTTPS URL without a path, query, or fragment.")
    }

    var isCanonicalURLChanged: Bool {
        guard let proposedURL = try? NgrokStaticURL(rawValue) else {
            return false
        }
        guard let confirmedURL,
              let confirmedStaticURL = try? NgrokStaticURL(confirmedURL.absoluteString)
        else {
            return true
        }
        return proposedURL != confirmedStaticURL
    }

    var canRestartNgrok: Bool {
        normalizedURL != nil
    }
}
