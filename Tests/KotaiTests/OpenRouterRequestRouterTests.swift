import Foundation
import NIOCore
import Testing
@testable import Kotai

struct OpenRouterRequestRouterTests {
    @Test
    func personalPrefixSelectsPersonalAndNormalizesModel() throws {
        let result = try resolve(
            #"{"model":"kotai/personal/openai/gpt-5","messages":[],"temperature":0.2}"#
        )

        #expect(result.accountMode == .personal)
        #expect(result.normalizedModel == "openai/gpt-5")
        #expect(try model(in: result.body) == "openai/gpt-5")
        #expect(try number(in: result.body, key: "temperature") == 0.2)
    }

    @Test
    func workPrefixSelectsWorkAndNormalizesModel() throws {
        let result = try resolve(
            #"{"model":"kotai/work/anthropic/claude-sonnet-4.5"}"#
        )

        #expect(result.accountMode == .work)
        #expect(result.normalizedModel == "anthropic/claude-sonnet-4.5")
        #expect(try model(in: result.body) == "anthropic/claude-sonnet-4.5")
    }

    @Test
    func providerAndModelSlashesArePreserved() throws {
        let result = try resolve(
            #"{"model":"kotai/work/provider/family/model/version"}"#
        )

        #expect(result.normalizedModel == "provider/family/model/version")
    }

    @Test
    func unprefixedModelIsRejected() {
        #expect(throws: OpenRouterRoutingError.unprefixedModel) {
            try resolve(#"{"model":"anthropic/claude"}"#)
        }
    }

    @Test(arguments: [
        #"{"model":"kotai/team/openai/gpt-5"}"#,
        #"{"model":"kotai/work/"}"#,
        #"{"model":"kotai/work/gpt-5"}"#,
        #"{"model":"kotai/work/openai/gpt 5"}"#,
        #"{"model":"kotai//openai/gpt-5"}"#,
        #"{"model":"kotai/work/openai//gpt-5"}"#,
    ])
    func malformedKotaiModelIsRejected(_ json: String) {
        #expect(throws: OpenRouterRoutingError.malformedModel) {
            try resolve(json)
        }
    }

    @Test(arguments: [
        #"{"model":"Kotai/work/anthropic/claude"}"#,
        #"{"model":"kotai/Work/anthropic/claude"}"#,
        #"{"model":"KOTAI/PERSONAL/openai/gpt-5"}"#,
    ])
    func caseMismatchedPrefixIsRejected(_ json: String) {
        #expect(throws: OpenRouterRoutingError.unprefixedModel) {
            try resolve(json)
        }
    }

    @Test
    func objectWithoutModelUsesPersonalAndPreservesOriginalBytes() throws {
        let json = #"{"messages":[]}"#
        let result = try resolve(json)

        #expect(result.accountMode == .personal)
        #expect(result.normalizedModel == nil)
        #expect(String(buffer: result.body!) == json)
    }

    @Test
    func nonStringModelUsesPersonalAndPreservesOriginalBytes() throws {
        let json = #"{"model":42,"messages":[]}"#
        let result = try resolve(json)

        #expect(result.accountMode == .personal)
        #expect(result.normalizedModel == nil)
        #expect(String(buffer: result.body!) == json)
    }

    @Test
    func invalidJSONUsesPersonalAndPreservesOriginalBytes() throws {
        let json = #"{"model":"kotai/work/openai/gpt-5""#
        let result = try resolve(json)

        #expect(result.accountMode == .personal)
        #expect(result.normalizedModel == nil)
        #expect(String(buffer: result.body!) == json)
    }

    private func resolve(_ json: String) throws -> OpenRouterRequestRouting {
        try OpenRouterRequestRouter.resolve(body: ByteBuffer(string: json))
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
