import Foundation
import Observation

enum UsageMenuBarAccount: String, CaseIterable, Identifiable {
    case personal
    case work
    var id: Self { self }
    var displayName: String { self == .personal ? "Personal" : "Work" }
    var mode: AccountMode { self == .personal ? .personal : .work }
}

@MainActor @Observable
final class UsageMenuBarSettings {
    private enum Key { static let enabled = "usage-menu-bar-enabled"; static let account = "usage-menu-bar-account" }
    private let defaults: UserDefaults
    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.enabled) } }
    var account: UsageMenuBarAccount { didSet { defaults.set(account.rawValue, forKey: Key.account) } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        account = UsageMenuBarAccount(rawValue: defaults.string(forKey: Key.account) ?? "") ?? .work
    }
}
