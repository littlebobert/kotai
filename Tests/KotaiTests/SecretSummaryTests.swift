import Testing
@testable import Kotai

struct SecretSummaryTests {
    @Test
    func longASCIIValueRevealsExactlyFiveCharactersAtEachEnd() {
        let summary = SecretSummary(value: "sk-or-1234567890abcde")

        #expect(summary.displayValue == "sk-or…abcde")
    }

    @Test
    func unicodeValueUsesCharacterBoundaries() {
        let summary = SecretSummary(value: "🔐あいうえおかきくけこさしすせそ")

        #expect(summary.displayValue == "🔐あいうえ…さしすせそ")
    }

    @Test
    func shortValueIsFullyHidden() {
        #expect(SecretSummary(value: "secret1234").displayValue == "••••••••")
    }

    @Test
    func emptyValueIsNotConfigured() {
        #expect(SecretSummary(value: "").displayValue == "Not configured")
    }
}
