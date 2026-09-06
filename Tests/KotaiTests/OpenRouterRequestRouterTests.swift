import Foundation
import NIOCore
import Testing
@testable import Kotai

struct OpenRouterRequestRouterTests {
    @Test
    func personalPrefixSelectsPersonalAndNormalizesModel() throws {
        let result = try resolve(
            #"{"model":"kotai/personal/openai/gpt-5","messages":[],"temperature":0.2}"#,
            defaultAccountMode: .work
        )

        #expect(result.accountMode == .personal)
        #expect(result.normalizedModel == "openai/gpt-5")
        #expect(try model(in: result.body) == "openai/gpt-5")
        #expect(try number(in: result.body, key: "temperature") == 0.2)
    }

    @Test
    func workPrefixSelectsWorkAndNormalizesModel() throws {
        let result = try resolve(
            #"{"model":"kotai/work/anthropic/claude-sonnet-4.5"}"#,
            defaultAccountMode: .personal
        )

        #expect(result.accountMode == .work)
        #expect(result.normalizedModel == "anthropic/claude-sonnet-4.5")
        #expect(try model(in: result.body) == "anthropic/claude-sonnet-4.5")
    }

    @Test
    func providerAndModelSlashesArePreserved() throws {
        let result = try resolve(
            #"{"model":"kotai/work/provider/family/model/version"}"#,
            defaultAccountMode: .personal
        )

        #expect(result.normalizedModel == "provider/family/model/version")
    }

    @Test
    func unprefixedModelUsesDefaultAndPreservesOriginalBytes() throws {
        let json = #"{ "model" : "anthropic/claude", "custom" : true }"#
        let result = try resolve(json, defaultAccountMode: .work)

        #expect(result.accountMode == .work)
        #expect(result.normalizedModel == "anthropic/claude")
        #expect(String(buffer: result.body!) == json)
    }

    @Test(arguments: [
        #"{"model":"kotai/team/openai/gpt-5"}"#,
        #"{"model":"kotai/work/"}"#,
        #"{"model":"kotai//openai/gpt-5"}"#,
        #"{"model":"kotai/work/openai//gpt-5"}"#,
    ])
    func malformedKotaiModelIsRejected(_ json: String) {
        #expect(throws: OpenRouterRoutingError.malformedModel) {
            try resolve(json, defaultAccountMode: .personal)
        }
    }

    @Test
    func prefixMatchingIsCaseSensitive() throws {
        let json = #"{"model":"Kotai/work/anthropic/claude"}"#
        let result = try resolve(json, defaultAccountMode: .personal)

        #expect(result.accountMode == .personal)
        #expect(result.normalizedModel == "Kotai/work/anthropic/claude")
        #expect(String(buffer: result.body!) == json)
    }

    @Test
    func objectWithoutModelUsesDefaultAndPreservesOriginalBytes() throws {
        let json = #"{"messages":[]}"#
        let result = try resolve(json, defaultAccountMode: .work)

        #expect(result.accountMode == .work)
        #expect(result.normalizedModel == nil)
        #expect(String(buffer: result.body!) == json)
    }

    @Test
    func invalidJSONUsesDefaultAndPreservesOriginalBytes() throws {
        let json = #"{"model":"kotai/work/openai/gpt-5""#
        let result = try resolve(json, defaultAccountMode: .personal)

        #expect(result.accountMode == .personal)
        #expect(result.normalizedModel == nil)
        #expect(String(buffer: result.body!) == json)
    }

    private func resolve(
        _ json: String,
        defaultAccountMode: AccountMode
    ) throws -> OpenRouterRequestRouting {
        try OpenRouterRequestRouter.resolve(
            body: ByteBuffer(string: json),
            defaultAccountMode: defaultAccountMode
        )
    }

    private func model(in body: ByteBuffer?) throws -> String? {
        try object(in: body)["model"] as? String
    }

    private func number(in body: ByteBuffer?, key: String) throws -> Double? {
        try object(in: body)[key] as? Double
    }

    private func object(in body: ByteBuffer?) throws -> [String: Any] {
        guard let body else {
            return [:]
        }
        let data = Data(body.readableBytesView)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
