import Testing
@testable import Kotai

struct AboutVersionFormatterTests {
    @Test
    func formatsVersionAndBuild() {
        #expect(
            AboutVersionFormatter.displayText(version: "0.1.6", build: "7")
                == "Version 0.1.6 (7)"
        )
    }

    @Test
    func reportsUnavailableVersionWhenEitherValueIsMissing() {
        #expect(
            AboutVersionFormatter.displayText(version: nil, build: "7")
                == "Version unavailable"
        )
        #expect(
            AboutVersionFormatter.displayText(version: "0.1.6", build: " ")
                == "Version unavailable"
        )
    }
}
