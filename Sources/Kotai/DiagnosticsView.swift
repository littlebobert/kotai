import AppKit
import SwiftUI

struct DiagnosticsView: View {
    let controller: AppController

    @State private var logText = ""

    private let logBottomID = "diagnostics-log-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                controller.runtimeStatus.displayName,
                systemImage: controller.runtimeStatus.symbolName
            )
            .foregroundStyle(statusColor)

            if let publicURL = controller.configuredPublicURL() {
                LabeledContent("ngrok") {
                    Text(publicURL.host ?? publicURL.absoluteString)
                        .textSelection(.enabled)
                }
            }

            if let statusDetail = controller.statusDetail {
                Text(statusDetail)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Divider()

            Text("Recent activity")
                .font(.headline)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(logText)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .topLeading
                            )
                            .padding(10)

                        Color.clear
                            .frame(height: 1)
                            .id(logBottomID)
                    }
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .onAppear {
                    scrollToMostRecent(using: scrollProxy)
                }
                .onChange(of: logText) {
                    scrollToMostRecent(using: scrollProxy)
                }
            }

            HStack {
                Button("Copy Log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                Button("Report a bug…") {
                    BugReporter.composeEmail()
                }
                Spacer()
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

    private func refresh() {
        logText = KotaiLogger.shared.recentLogText()
    }

    private func scrollToMostRecent(using scrollProxy: ScrollViewProxy) {
        Task { @MainActor in
            scrollProxy.scrollTo(logBottomID, anchor: .bottom)
        }
    }
}
