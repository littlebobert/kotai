import Charts
import SwiftUI

struct UsageStatisticsView: View {
    let controller: AppController

    @State private var days = 30
    @State private var personal: Result<AccountUsageSnapshot, Error>?
    @State private var work: Result<AccountUsageSnapshot, Error>?
    @State private var isLoading = false
    @State private var lastUpdated: Date?

    private let metricColumns = [
        GridItem(.adaptive(minimum: 130), spacing: 16, alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Range", selection: $days) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                Spacer()
                if let lastUpdated {
                    Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                Button("Refresh") { refresh() }
                    .disabled(isLoading)
            }
            if isLoading && personal == nil && work == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    VStack(spacing: 16) {
                        accountSection(title: "Personal", result: personal)
                        accountSection(title: "Work", result: work)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 520)
        .task { refresh() }
        .onChange(of: days) { refresh() }
    }

    @ViewBuilder private func accountSection(title: String, result: Result<AccountUsageSnapshot, Error>?) -> some View {
        GroupBox(title) {
            switch result {
            case .success(let snapshot):
                VStack(alignment: .leading, spacing: 12) {
                    Text(accountDescription(snapshot.connection))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                        metric("Spend", currency(snapshot.usage.spend))
                        metric(
                            "Requests",
                            snapshot.usage.requests.formatted(
                                .number.precision(.fractionLength(0))
                            )
                        )
                        metric(
                            "Input tokens",
                            snapshot.usage.promptTokens.formatted(
                                .number.notation(.compactName)
                            )
                        )
                        metric(
                            "Output tokens",
                            snapshot.usage.completionTokens.formatted(
                                .number.notation(.compactName)
                            )
                        )
                        metric(
                            "Credits remaining",
                            currency(max(
                                0,
                                snapshot.credits.totalCredits - snapshot.credits.totalUsage
                            ))
                        )
                        metric(
                            "OpenAI cost",
                            snapshot.openAICost.map(currency) ?? "Unavailable"
                        )
                    }
                    if !snapshot.usage.daily.isEmpty {
                        Chart(snapshot.usage.daily) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Spend", point.spend))
                            AreaMark(x: .value("Date", point.date), y: .value("Spend", point.spend)).opacity(0.12)
                        }.frame(height: 120)
                    }
                    if !snapshot.usage.models.isEmpty {
                        Text("Top models").font(.headline)
                        ForEach(snapshot.usage.models.prefix(5)) { model in
                            HStack { Text(model.model); Spacer(); Text(currency(model.spend)); Text("\(Int(model.requests)) requests").foregroundStyle(.secondary) }
                        }
                    }
                    if snapshot.usage.isTruncated { Label("OpenRouter truncated this result. Narrow the date range for complete totals.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            case .failure(let error):
                ContentUnavailableView("Usage unavailable", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
            case nil:
                Text("Loading…").foregroundStyle(.secondary).padding(20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountDescription(_ connection: ManagedAccountConnection) -> String {
        guard let project = connection.openAIProject else {
            return "\(connection.openRouterWorkspace.name) · OpenRouter credits"
        }
        return "\(connection.openRouterWorkspace.name) · OpenAI \(project.name)"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currency(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
    private func refresh() {
        guard !isLoading else { return }; isLoading = true
        Task {
            async let personalResult = load(.personal)
            async let workResult = load(.work)
            personal = await personalResult; work = await workResult
            lastUpdated = Date(); isLoading = false
        }
    }
    private func load(_ mode: AccountMode) async -> Result<AccountUsageSnapshot, Error> {
        do {
            let result = try await controller.managedUsage(for: mode, days: days)
            return .success(AccountUsageSnapshot(connection: result.connection, credits: result.credits, usage: result.usage, openAICost: result.openAICost))
        } catch { return .failure(error) }
    }
}

struct AccountUsageSnapshot {
    let connection: ManagedAccountConnection
    let credits: OpenRouterCredits
    let usage: WorkspaceUsage
    let openAICost: Double?
}
