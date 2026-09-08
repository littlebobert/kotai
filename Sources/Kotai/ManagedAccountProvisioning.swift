import Foundation

struct OpenRouterWorkspace: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let slug: String
}

struct OpenAIProject: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct ManagedAccountConnection: Codable, Equatable, Sendable {
    let openRouterWorkspace: OpenRouterWorkspace
    let openRouterKeyHash: String
    let openRouterKeyName: String
    let openAIProject: OpenAIProject?
    let openAIServiceAccountID: String?
    let openAIServiceAccountName: String?
    let openRouterBYOKCredentialID: String?
}

struct ManagedAccountDraft: Sendable {
    let accountMode: AccountMode
    let openRouterManagementKey: String
    let openAIAdminKey: String?
    let openRouterWorkspace: OpenRouterWorkspace
    let openAIProject: OpenAIProject?
}

struct StagedManagedAccount: Sendable {
    let draft: ManagedAccountDraft
    let connection: ManagedAccountConnection
    let inferenceKey: String
}

struct OpenRouterCredits: Sendable {
    let totalCredits: Double
    let totalUsage: Double
}

struct UsageDataPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let spend: Double
    let requests: Double
    let promptTokens: Double
    let completionTokens: Double
    let reasoningTokens: Double
}

struct ModelUsage: Identifiable, Sendable {
    var id: String { model }
    let model: String
    let spend: Double
    let requests: Double
}

struct WorkspaceUsage: Sendable {
    let daily: [UsageDataPoint]
    let models: [ModelUsage]
    let isTruncated: Bool

    var spend: Double { daily.reduce(0) { $0 + $1.spend } }
    var requests: Double { daily.reduce(0) { $0 + $1.requests } }
    var promptTokens: Double { daily.reduce(0) { $0 + $1.promptTokens } }
    var completionTokens: Double { daily.reduce(0) { $0 + $1.completionTokens } }
    var reasoningTokens: Double { daily.reduce(0) { $0 + $1.reasoningTokens } }
}

enum AdministrationAPIError: LocalizedError, Equatable {
    case invalidCredential(String)
    case forbidden(String)
    case rateLimited
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredential(let service): "The \(service) administrative key is not valid."
        case .forbidden(let message): message
        case .rateLimited: "The service is rate limiting administrative requests. Try again shortly."
        case .invalidResponse: "The service returned an invalid response."
        case .server(let message): message
        }
    }
}

private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

struct OpenRouterManagementClient: Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://openrouter.ai/api/v1")!

    init(session: URLSession = .shared) { self.session = session }

    func listWorkspaces(managementKey: String) async throws -> [OpenRouterWorkspace] {
        var workspaces: [OpenRouterWorkspace] = []
        var offset = 0
        while true {
            let response: WorkspaceList = try await request(
                path: "workspaces?limit=100&offset=\(offset)", key: managementKey
            )
            workspaces.append(contentsOf: response.data)
            offset += response.data.count
            if offset >= response.totalCount || response.data.isEmpty { return workspaces }
        }
    }

    func createWorkspace(name: String, managementKey: String) async throws -> OpenRouterWorkspace {
        let slug = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let response: DataEnvelope<OpenRouterWorkspace> = try await request(
            path: "workspaces", method: "POST", key: managementKey,
            body: ["name": name, "slug": slug]
        )
        return response.data
    }

    func createInferenceKey(
        name: String, workspaceID: String, managementKey: String
    ) async throws -> (key: String, hash: String) {
        let response: CreatedKey = try await request(
            path: "keys", method: "POST", key: managementKey,
            body: ["name": name, "workspace_id": workspaceID]
        )
        return (response.key, response.data.hash)
    }

    func createOpenAIBYOK(
        name: String, openAIKey: String, workspaceID: String,
        allowedKeyHash: String, managementKey: String
    ) async throws -> String {
        let response: BYOKResponse = try await request(
            path: "byok", method: "POST", key: managementKey,
            body: [
                "name": name, "provider": "openai", "key": openAIKey,
                "workspace_id": workspaceID,
                "allowed_api_key_hashes": [allowedKeyHash],
            ] as [String: Any]
        )
        return response.data.id
    }

    func deleteInferenceKey(hash: String, managementKey: String) async {
        try? await requestWithoutResponse(path: "keys/\(hash)", method: "DELETE", key: managementKey)
    }

    func deleteBYOK(id: String, managementKey: String) async {
        try? await requestWithoutResponse(path: "byok/\(id)", method: "DELETE", key: managementKey)
    }

    func credits(managementKey: String) async throws -> OpenRouterCredits {
        let response: CreditsResponse = try await request(path: "credits", key: managementKey)
        return OpenRouterCredits(totalCredits: response.data.totalCredits, totalUsage: response.data.totalUsage)
    }

    func workspaceUsage(
        workspaceID: String, managementKey: String, days: Int
    ) async throws -> WorkspaceUsage {
        let end = Date()
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: end)!
        async let daily: AnalyticsResponse = request(
            path: "analytics/query", method: "POST", key: managementKey,
            body: analyticsBody(start: start, end: end, workspaceID: workspaceID, dimensions: ["workspace"], granularity: "day")
        )
        async let models: AnalyticsResponse = request(
            path: "analytics/query", method: "POST", key: managementKey,
            body: analyticsBody(start: start, end: end, workspaceID: workspaceID, dimensions: ["model"], granularity: nil)
        )
        return try parseUsage(daily: await daily, models: await models)
    }

    private func analyticsBody(
        start: Date, end: Date, workspaceID: String,
        dimensions: [String], granularity: String?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "metrics": ["total_usage", "request_count", "prompt_tokens", "completion_tokens", "reasoning_tokens"],
            "dimensions": dimensions,
            "filters": [["field": "workspace", "operator": "eq", "value": workspaceID]],
            "time_range": ["start": ISO8601DateFormatter().string(from: start), "end": ISO8601DateFormatter().string(from: end)],
            "limit": 1000,
        ]
        if let granularity { body["granularity"] = granularity }
        return body
    }

    private func parseUsage(daily: AnalyticsResponse, models: AnalyticsResponse) throws -> WorkspaceUsage {
        let formatter = ISO8601DateFormatter()
        let dailyPoints = daily.data.compactMap { row -> UsageDataPoint? in
            guard let dateString = row.stringValue(prefixes: ["date__", "created_at__"]),
                  let date = formatter.date(from: dateString) ?? Self.dayFormatter.date(from: dateString)
            else { return nil }
            return UsageDataPoint(
                date: date, spend: row.number("total_usage"), requests: row.number("request_count"),
                promptTokens: row.number("prompt_tokens"), completionTokens: row.number("completion_tokens"),
                reasoningTokens: row.number("reasoning_tokens")
            )
        }.sorted { $0.date < $1.date }
        let modelRows = models.data.map { row in
            ModelUsage(model: row.string("model") ?? "Unknown", spend: row.number("total_usage"), requests: row.number("request_count"))
        }.sorted { $0.spend > $1.spend }
        return WorkspaceUsage(daily: dailyPoints, models: modelRows, isTruncated: daily.metadata?.truncated == true || models.metadata?.truncated == true)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0); return formatter
    }()

    private func request<T: Decodable>(
        path: String, method: String = "GET", key: String, body: [String: Any]? = nil
    ) async throws -> T {
        let (data, response) = try await perform(path: path, method: method, key: key, body: body)
        try validate(response: response, data: data, service: "OpenRouter")
        guard let value = try? JSONDecoder.snakeCase.decode(T.self, from: data) else { throw AdministrationAPIError.invalidResponse }
        return value
    }

    private func requestWithoutResponse(path: String, method: String, key: String) async throws {
        let (data, response) = try await perform(path: path, method: method, key: key, body: nil)
        try validate(response: response, data: data, service: "OpenRouter")
    }

    private func perform(path: String, method: String, key: String, body: [String: Any]?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL.appendingPathComponent("/"))!)
        request.httpMethod = method; request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw AdministrationAPIError.invalidResponse }
        return (data, response)
    }

    private struct WorkspaceList: Decodable { let data: [OpenRouterWorkspace]; let totalCount: Int }
    private struct CreatedKey: Decodable { struct Metadata: Decodable { let hash: String }; let data: Metadata; let key: String }
    private struct BYOKResponse: Decodable { struct Metadata: Decodable { let id: String }; let data: Metadata }
    private struct CreditsResponse: Decodable { struct Credits: Decodable { let totalCredits: Double; let totalUsage: Double }; let data: Credits }
    private struct AnalyticsResponse: Decodable { let data: [DynamicRow]; let metadata: Metadata?; struct Metadata: Decodable { let truncated: Bool? } }
}

struct OpenAIAdministrationClient: Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.openai.com/v1")!

    init(session: URLSession = .shared) { self.session = session }

    func listProjects(adminKey: String) async throws -> [OpenAIProject] {
        var projects: [OpenAIProject] = []; var after: String?
        while true {
            var path = "organization/projects?limit=100"
            if let after { path += "&after=\(after.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
            let response: ProjectList = try await request(path: path, key: adminKey)
            projects.append(contentsOf: response.data.filter { $0.status != "archived" }.map { OpenAIProject(id: $0.id, name: $0.name ?? $0.id) })
            guard response.hasMore, let lastID = response.lastID else { return projects }
            after = lastID
        }
    }

    func createServiceAccount(name: String, projectID: String, adminKey: String) async throws -> (id: String, key: String) {
        let response: ServiceAccountResponse = try await request(
            path: "organization/projects/\(projectID)/service_accounts", method: "POST", key: adminKey, body: ["name": name]
        )
        guard let key = response.apiKey?.value else { throw AdministrationAPIError.invalidResponse }
        return (response.id, key)
    }

    func deleteServiceAccount(id: String, projectID: String, adminKey: String) async {
        try? await requestWithoutResponse(path: "organization/projects/\(projectID)/service_accounts/\(id)", method: "DELETE", key: adminKey)
    }

    func projectCosts(projectID: String, adminKey: String, days: Int) async throws -> Double {
        let end = Int(Date().timeIntervalSince1970)
        let start = end - (days * 86_400)
        let encodedProjectID = projectID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectID
        let response: CostsResponse = try await request(
            path: "organization/costs?start_time=\(start)&end_time=\(end)&bucket_width=1d&limit=\(min(days, 180))&project_ids=\(encodedProjectID)",
            key: adminKey
        )
        return response.data.flatMap(\.results).compactMap { $0.amount?.value }.reduce(0, +)
    }

    private func request<T: Decodable>(path: String, method: String = "GET", key: String, body: [String: Any]? = nil) async throws -> T {
        let (data, response) = try await perform(path: path, method: method, key: key, body: body)
        try validate(response: response, data: data, service: "OpenAI")
        guard let value = try? JSONDecoder.snakeCase.decode(T.self, from: data) else { throw AdministrationAPIError.invalidResponse }
        return value
    }

    private func requestWithoutResponse(path: String, method: String, key: String) async throws {
        let (data, response) = try await perform(path: path, method: method, key: key, body: nil)
        try validate(response: response, data: data, service: "OpenAI")
    }

    private func perform(path: String, method: String, key: String, body: [String: Any]?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL.appendingPathComponent("/"))!)
        request.httpMethod = method; request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw AdministrationAPIError.invalidResponse }
        return (data, response)
    }

    private struct ProjectList: Decodable { struct Project: Decodable { let id: String; let name: String?; let status: String? }; let data: [Project]; let hasMore: Bool; let lastID: String? }
    private struct ServiceAccountResponse: Decodable { struct APIKey: Decodable { let value: String }; let id: String; let apiKey: APIKey? }
    private struct CostsResponse: Decodable {
        struct Bucket: Decodable { let results: [Cost] }
        struct Cost: Decodable { struct Amount: Decodable { let value: Double }; let amount: Amount? }
        let data: [Bucket]
    }
}

struct DataEnvelope<Value: Decodable>: Decodable { let data: Value }

private struct DynamicRow: Decodable {
    let values: [String: JSONValue]
    init(from decoder: Decoder) throws { values = try decoder.singleValueContainer().decode([String: JSONValue].self) }
    func number(_ key: String) -> Double { values[key]?.number ?? 0 }
    func string(_ key: String) -> String? { values[key]?.string }
    func stringValue(prefixes: [String]) -> String? { values.first { key, _ in prefixes.contains { key.hasPrefix($0) } }?.value.string }
}

private enum JSONValue: Decodable {
    case string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported analytics value") }
    }
    var number: Double? { switch self { case .number(let value): value; case .string(let value): Double(value); default: nil } }
    var string: String? { switch self { case .string(let value): value; case .number(let value): String(value); default: nil } }
}

private extension JSONDecoder {
    static var snakeCase: JSONDecoder { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return decoder }
}

private func validate(response: HTTPURLResponse, data: Data, service: String) throws {
    guard (200..<300).contains(response.statusCode) else {
        let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message) ?? "\(service) request failed (HTTP \(response.statusCode))."
        switch response.statusCode {
        case 401: throw AdministrationAPIError.invalidCredential(service)
        case 403: throw AdministrationAPIError.forbidden(message)
        case 429: throw AdministrationAPIError.rateLimited
        default: throw AdministrationAPIError.server(message)
        }
    }
}

actor ManagedAccountProvisioner {
    private let openRouter = OpenRouterManagementClient()
    private let openAI = OpenAIAdministrationClient()

    func provision(_ draft: ManagedAccountDraft) async throws -> StagedManagedAccount {
        let label = draft.accountMode == .personal ? "Personal" : "Work"
        let resourceName = "Kotai \(label)"

        let openRouterKey = try await openRouter.createInferenceKey(
            name: resourceName,
            workspaceID: draft.openRouterWorkspace.id,
            managementKey: draft.openRouterManagementKey
        )

        guard let openAIAdminKey = draft.openAIAdminKey,
              let openAIProject = draft.openAIProject else {
            return StagedManagedAccount(
                draft: draft,
                connection: ManagedAccountConnection(
                    openRouterWorkspace: draft.openRouterWorkspace,
                    openRouterKeyHash: openRouterKey.hash,
                    openRouterKeyName: resourceName,
                    openAIProject: nil,
                    openAIServiceAccountID: nil,
                    openAIServiceAccountName: nil,
                    openRouterBYOKCredentialID: nil
                ),
                inferenceKey: openRouterKey.key
            )
        }

        do {
            let serviceAccount = try await openAI.createServiceAccount(
                name: resourceName,
                projectID: openAIProject.id,
                adminKey: openAIAdminKey
            )
            do {
                let byokID = try await openRouter.createOpenAIBYOK(
                    name: "\(resourceName) OpenAI",
                    openAIKey: serviceAccount.key,
                    workspaceID: draft.openRouterWorkspace.id,
                    allowedKeyHash: openRouterKey.hash,
                    managementKey: draft.openRouterManagementKey
                )
                return StagedManagedAccount(
                    draft: draft,
                    connection: ManagedAccountConnection(
                        openRouterWorkspace: draft.openRouterWorkspace,
                        openRouterKeyHash: openRouterKey.hash,
                        openRouterKeyName: resourceName,
                        openAIProject: openAIProject,
                        openAIServiceAccountID: serviceAccount.id,
                        openAIServiceAccountName: resourceName,
                        openRouterBYOKCredentialID: byokID
                    ),
                    inferenceKey: openRouterKey.key
                )
            } catch {
                await openAI.deleteServiceAccount(
                    id: serviceAccount.id,
                    projectID: openAIProject.id,
                    adminKey: openAIAdminKey
                )
                throw error
            }
        } catch {
            await openRouter.deleteInferenceKey(
                hash: openRouterKey.hash,
                managementKey: draft.openRouterManagementKey
            )
            throw error
        }
    }

    func cleanup(_ stagedAccount: StagedManagedAccount) async {
        let connection = stagedAccount.connection
        let draft = stagedAccount.draft
        if let byokID = connection.openRouterBYOKCredentialID {
            await openRouter.deleteBYOK(
                id: byokID,
                managementKey: draft.openRouterManagementKey
            )
        }
        await openRouter.deleteInferenceKey(
            hash: connection.openRouterKeyHash,
            managementKey: draft.openRouterManagementKey
        )
        if let serviceAccountID = connection.openAIServiceAccountID,
           let projectID = connection.openAIProject?.id,
           let adminKey = draft.openAIAdminKey {
            await openAI.deleteServiceAccount(
                id: serviceAccountID,
                projectID: projectID,
                adminKey: adminKey
            )
        }
    }
}
