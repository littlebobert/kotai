import Testing
@testable import Kotai

struct AboutVersionFormatterTests {
    @Test
    func formatsVersionWithoutBuildNumber() {
        #expect(
            AboutVersionFormatter.displayText(version: "0.1.6")
                == "Version 0.1.6"
        )
    }

    @Test
    func reportsUnavailableVersionWhenVersionIsMissing() {
        #expect(
            AboutVersionFormatter.displayText(version: nil)
                == "Version unavailable"
        )
        #expect(
            AboutVersionFormatter.displayText(version: " ")
                == "Version unavailable"
        )
    }
}
