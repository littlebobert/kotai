import AsyncHTTPClient
import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import NIOHTTP1
import NIOHTTPTypesHTTP1

struct OpenRouterProxy: HTTPResponder {
    typealias Context = BasicRequestContext

    private static let maximumRequestBodySize = 16 * 1024 * 1024
    private static let upstreamTimeout = TimeAmount.seconds(90)

    private let configuration: ProxyConfiguration
    private let httpClient: HTTPClient

    init(configuration: ProxyConfiguration, httpClient: HTTPClient) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    func respond(
        to request: Request,
        context: BasicRequestContext
    ) async throws -> Response {
        if request.uri.path == "/health" {
            return jsonResponse(
                status: .ok,
                object: ["status": "ok"]
            )
        }

        let requestID = String(UUID().uuidString.prefix(8))
        let startedAt = Date()
        KotaiLogger.shared.info(
            "Proxy \(requestID) received; method=\(request.method.rawValue) " +
                "path=\(request.uri.path) " +
                "contentLength=\(request.headers[.contentLength] ?? "unknown")"
        )

        guard let upstreamURL = OpenRouterRoute.upstreamURL(
            path: request.uri.path,
            query: request.uri.query
        ) else {
            KotaiLogger.shared.warning(
                "Proxy \(requestID) rejected unknown route"
            )
            return jsonResponse(
                status: .notFound,
                object: ["error": "Not found"]
            )
        }

        guard
            let expectedToken = try await configuration.credential(.proxyToken),
            !expectedToken.isEmpty,
            let authorization = request.headers[.authorization],
            authorization.hasPrefix("Bearer "),
            constantTimeEqual(
                String(authorization.dropFirst("Bearer ".count)),
                expectedToken
            )
        else {
            KotaiLogger.shared.warning(
                "Proxy \(requestID) rejected client authentication"
            )
            return jsonResponse(
                status: .unauthorized,
                object: ["error": "Unauthorized"]
            )
        }

        guard
            let openRouterKey = try await configuration.activeOpenRouterKey(),
            !openRouterKey.isEmpty
        else {
            KotaiLogger.shared.error(
                "Proxy \(requestID) has no active OpenRouter key"
            )
            return jsonResponse(
                status: .serviceUnavailable,
                object: ["error": "The active OpenRouter key is not configured"]
            )
        }

        do {
            return try await forward(
                request,
                openRouterKey: openRouterKey,
                upstreamURL: upstreamURL,
                requestID: requestID,
                startedAt: startedAt
            )
        } catch is CancellationError {
            KotaiLogger.shared.warning(
                "Proxy \(requestID) cancelled after " +
                    "\(elapsedSeconds(since: startedAt))s"
            )
            throw CancellationError()
        } catch {
            let errorDescription = String(describing: error)
            KotaiLogger.shared.error(
                "Proxy \(requestID) failed after " +
                    "\(elapsedSeconds(since: startedAt))s: " +
                    errorDescription
            )
            return jsonResponse(
                status: .badGateway,
                object: [
                    "error": "Kotai could not reach OpenRouter",
                    "detail": errorDescription,
                ]
            )
        }
    }

    private func forward(
        _ request: Request,
        openRouterKey: String,
        upstreamURL: URL,
        requestID: String,
        startedAt: Date
    ) async throws -> Response {
        var upstreamRequest = HTTPClientRequest(
            url: upstreamURL.absoluteString
        )
        upstreamRequest.method = HTTPMethod(rawValue: request.method.rawValue)
        upstreamRequest.headers = HTTPHeaders(request.headers)
        upstreamRequest.headers.replaceOrAdd(
            name: "Authorization",
            value: "Bearer \(openRouterKey)"
        )
        removeHopByHopHeaders(from: &upstreamRequest.headers)

        if request.method != .get && request.method != .head {
            let body = try await request.body.collect(
                upTo: Self.maximumRequestBodySize
            )
            upstreamRequest.body = .bytes(body)
            KotaiLogger.shared.debug(
                "Proxy \(requestID) buffered \(body.readableBytes) request bytes"
            )
            if let summary = completionRequestSummary(body) {
                KotaiLogger.shared.info(
                    "Proxy \(requestID) payload; \(summary)"
                )
            }
        }

        KotaiLogger.shared.info(
            "Proxy \(requestID) forwarding to " +
                "\(upstreamURL.host ?? "unknown")\(upstreamURL.path)"
        )
        let upstreamResponse = try await httpClient.execute(
            upstreamRequest,
            deadline: .now() + Self.upstreamTimeout
        )
        KotaiLogger.shared.info(
            "Proxy \(requestID) received upstream status " +
                "\(upstreamResponse.status.code) after " +
                "\(elapsedSeconds(since: startedAt))s"
        )
        var responseHeaders = HTTPFields(
            upstreamResponse.headers,
            splitCookie: false
        )
        removeHopByHopHeaders(from: &responseHeaders)

        return Response(
            status: HTTPResponse.Status(
                code: Int(upstreamResponse.status.code),
                reasonPhrase: upstreamResponse.status.reasonPhrase
            ),
            headers: responseHeaders,
            body: ResponseBody(asyncSequence: upstreamResponse.body)
        )
    }
}

private func elapsedSeconds(since date: Date) -> String {
    String(format: "%.3f", Date().timeIntervalSince(date))
}

private func completionRequestSummary(_ buffer: ByteBuffer) -> String? {
    let data = Data(buffer.readableBytesView)
    guard
        let object = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any]
    else {
        return nil
    }

    let model = object["model"] as? String ?? "unknown"
    let messageCount = (object["messages"] as? [Any])?.count ?? 0
    let toolCount = (object["tools"] as? [Any])?.count ?? 0
    return "model=\(model) messages=\(messageCount) tools=\(toolCount)"
}

enum OpenRouterRoute {
    private static let cursorPrefix = "/cursor/v1"
    private static let genericPrefix = "/v1"
    private static let cursorUpstreamBaseURL =
        "https://openrouter.ai/api/v1/cursor"
    private static let genericUpstreamBaseURL =
        "https://openrouter.ai/api/v1"

    static func upstreamURL(path: String, query: String?) -> URL? {
        let route: (prefix: String, upstreamBaseURL: String)

        if path == cursorPrefix || path.hasPrefix("\(cursorPrefix)/") {
            route = (cursorPrefix, cursorUpstreamBaseURL)
        } else if path == genericPrefix || path.hasPrefix("\(genericPrefix)/") {
            route = (genericPrefix, genericUpstreamBaseURL)
        } else {
            return nil
        }

        let upstreamPath = String(path.dropFirst(route.prefix.count))
        let querySuffix = query.map { "?\($0)" } ?? ""
        return URL(
            string: "\(route.upstreamBaseURL)\(upstreamPath)\(querySuffix)"
        )
    }
}

private func jsonResponse(
    status: HTTPResponse.Status,
    object: [String: String]
) -> Response {
    let data = try! JSONSerialization.data(withJSONObject: object)
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)

    return Response(
        status: status,
        headers: [.contentType: "application/json; charset=utf-8"],
        body: ResponseBody(byteBuffer: buffer)
    )
}

private func constantTimeEqual(_ left: String, _ right: String) -> Bool {
    let leftBytes = Array(left.utf8)
    let rightBytes = Array(right.utf8)
    let comparedLength = max(leftBytes.count, rightBytes.count)
    var difference = leftBytes.count ^ rightBytes.count

    for index in 0..<comparedLength {
        let leftByte = index < leftBytes.count ? leftBytes[index] : 0
        let rightByte = index < rightBytes.count ? rightBytes[index] : 0
        difference |= Int(leftByte ^ rightByte)
    }

    return difference == 0
}

private func removeHopByHopHeaders(from headers: inout HTTPHeaders) {
    [
        "Connection",
        "Content-Length",
        "Host",
        "Keep-Alive",
        "Proxy-Authenticate",
        "Proxy-Authorization",
        "TE",
        "Trailer",
        "Transfer-Encoding",
        "Upgrade",
        "X-Forwarded-For",
    ].forEach { headers.remove(name: $0) }
}

private func removeHopByHopHeaders(from headers: inout HTTPFields) {
    [
        "connection",
        "content-length",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    ].forEach { headerName in
        if let fieldName = HTTPField.Name(headerName) {
            headers[fieldName] = nil
        }
    }
}
