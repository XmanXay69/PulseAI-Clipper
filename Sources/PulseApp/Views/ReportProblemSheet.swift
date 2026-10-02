import PulseCore
import PulseEngine
import SwiftUI

/// Help → Report a Problem: describe it, PULSE bundles its log + system info into a zip on the Desktop
/// and opens a pre-filled GitHub issue to drop it into.
struct ReportProblemSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: URL?
    @State private var failure: String?
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "ladybug.fill").font(.system(size: 22)).foregroundStyle(Theme.warning)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Report a Problem").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
                    Text("PULSE bundles its log and system info so the problem can be fixed fast.").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            Text("What happened? What were you doing?").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            TextEditor(text: $text)
                .font(.pulseBody)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            VStack(alignment: .leading, spacing: 4) {
                Label("Included: the app log, macOS and Mac model, recent activity, the open project's settings and file names, recent PULSE crash reports.", systemImage: "doc.zipper")
                Label("Never included: your videos, audio, transcripts or API keys.", systemImage: "lock.shield")
            }
            .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            DisclosureGroup("Show recent log", isExpanded: $showLog) {
                ScrollView {
                    Text(PulseLog.tail(80).joined(separator: "\n")).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(height: 140)
            }
            .font(.pulseCaption)
            if let result {
                Label("Saved \(result.lastPathComponent) to your Desktop. Drag it into the GitHub issue that just opened.", systemImage: "checkmark.circle.fill")
                    .font(.pulseCaption).foregroundStyle(Theme.success)
            }
            if let failure { Text(failure).font(.pulseCaption).foregroundStyle(Theme.danger) }
            HStack {
                Button("Open Log Folder") { NSWorkspace.shared.open(PulseLog.directory) }.buttonStyle(.pulseSecondary)
                Spacer()
                Button(result == nil ? "Cancel" : "Done") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
                Button {
                    do {
                        let zip = try ProblemReporter.makeReport(app: app, description: text)
                        result = zip
                        NSWorkspace.shared.activateFileViewerSelecting([zip])
                        if let url = ProblemReporter.issueURL(description: text) { NSWorkspace.shared.open(url) }
                    } catch {
                        failure = "Couldn't create the report: \(error.localizedDescription)"
                    }
                } label: { Label("Create Report", systemImage: "paperplane.fill") }
                    .buttonStyle(.pulsePrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}
