import AppKit
import SwiftUI

struct DiagnosticsView: View {
    let controller: AppController
    let openSetup: () -> Void

    @State private var logText = ""
    @State private var selectedLevels = Set(DiagnosticLogLevel.allCases)
    @State private var filterQuery = ""
    @State private var followsLatestEntry = true
    @State private var scrollToLatestRequest = 0

    private var filteredLogText: String {
        DiagnosticLogFilter.filteredText(
            logText,
            selectedLevels: selectedLevels,
            query: filterQuery
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if controller.runtimeStatus == .needsConfiguration {
                Button(action: openSetup) {
                    Label(
                        controller.runtimeStatus.displayName,
                        systemImage: controller.runtimeStatus.symbolName
                    )
                }
                .buttonStyle(.link)
                .foregroundStyle(statusColor)
                .help("Open Kotai Setup")
            } else {
                Label(
                    controller.runtimeStatus.displayName,
                    systemImage: controller.runtimeStatus.symbolName
                )
                .foregroundStyle(statusColor)
            }

            if let publicURL = controller.configuredPublicURL() {
                Text("ngrok active at \(publicURL.absoluteString)")
                    .textSelection(.enabled)
            }

            if let statusDetail = controller.statusDetail {
                Text(statusDetail)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Divider()

            HStack {
                Text("Recent activity")
                    .font(.headline)

                Spacer()

                TextField("Filter logs", text: $filterQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Menu {
                    ForEach(DiagnosticLogLevel.allCases) { level in
                        Toggle(level.displayName, isOn: binding(for: level))
                    }
                    Divider()
                    Button("Show All") {
                        selectedLevels = Set(DiagnosticLogLevel.allCases)
                    }
                } label: {
                    Label("Levels", systemImage: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            NativeLogTextView(
                text: filteredLogText,
                followsLatestEntry: $followsLatestEntry,
                scrollToLatestRequest: scrollToLatestRequest
            )
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }

            HStack {
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        filteredLogText,
                        forType: .string
                    )
                }
                Button("Report a bug…") {
                    BugReporter.composeEmail()
                }
                Spacer()
                Text(followsLatestEntry ? "Following latest" : "Follow paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !followsLatestEntry {
                    Button("Resume Autoscroll") {
                        scrollToLatestRequest += 1
                    }
                    .help("Resume following new log entries")
                }
                Button("Refresh") {
                    refresh()
                }
            }
        }
        .padding(20)
        .frame(
            minWidth: 520,
            maxWidth: .infinity,
            minHeight: 320,
            maxHeight: .infinity
        )
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var statusColor: Color {
        switch controller.runtimeStatus {
        case .needsConfiguration:
            .orange
        case .starting:
            .blue
        case .running:
            .green
        case .failed:
            .red
        }
    }

    private func binding(for level: DiagnosticLogLevel) -> Binding<Bool> {
        Binding(
            get: { selectedLevels.contains(level) },
            set: { isSelected in
                if isSelected {
                    selectedLevels.insert(level)
                } else {
                    selectedLevels.remove(level)
                }
            }
        )
    }

    private func refresh() {
        logText = KotaiLogger.shared.recentLogText()
    }
}

enum DiagnosticLogLevel: String, CaseIterable, Identifiable {
    case debug = "DEBG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERRO"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .debug:
            String(localized: "Debug")
        case .info:
            String(localized: "Info")
        case .warning:
            String(localized: "Warnings")
        case .error:
            String(localized: "Errors")
        }
    }
}

enum DiagnosticLogFilter {
    static func filteredText(
        _ text: String,
        selectedLevels: Set<DiagnosticLogLevel>,
        query: String = ""
    ) -> String {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let includesAllLevels = selectedLevels == Set(DiagnosticLogLevel.allCases)
        guard !includesAllLevels || !normalizedQuery.isEmpty else {
            return text
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                if let level = level(in: line), !selectedLevels.contains(level) {
                    return false
                }
                guard !normalizedQuery.isEmpty else {
                    return true
                }
                return line.localizedCaseInsensitiveContains(normalizedQuery)
            }
            .joined(separator: "\n")
    }

    private static func level(in line: Substring) -> DiagnosticLogLevel? {
        DiagnosticLogLevel.allCases.first { level in
            line.contains("[\(level.rawValue)]")
        }
    }
}
