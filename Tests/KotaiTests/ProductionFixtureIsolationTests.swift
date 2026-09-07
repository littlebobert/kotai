import Foundation
import Testing

struct ProductionFixtureIsolationTests {
    @Test
    func existingTokenFixtureDoesNotAppearInProductionSources() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesDirectory = repositoryRoot.appending(
            path: "Sources",
            directoryHint: .isDirectory
        )
        let sourceFiles = FileManager.default.enumerator(
            at: sourcesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )

        var filesContainingFixture: [String] = []
        while let fileURL = sourceFiles?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true,
                  let contents = try? String(contentsOf: fileURL, encoding: .utf8),
                  contents.contains("existing-token")
            else {
                continue
            }
            filesContainingFixture.append(fileURL.path)
        }

        #expect(filesContainingFixture.isEmpty)
    }
}
