import PulseCore
import SwiftUI

/// "Update PULSE": what's new, then download → install → relaunch, all from inside the app.
struct UpdateSheet: View {
    @ObservedObject var updater: AppUpdater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.pulseTitle).foregroundStyle(Theme.textPrimary)
                    Text("You have \(updater.current.description) (build \(updater.current.build))")
                        .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(20)
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let release = updater.available {
                        Text(notes(release)).font(.pulseBody).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                    } else if case .failed(let message) = updater.state {
                        Label(message, systemImage: "exclamationmark.triangle.fill").font(.pulseBody).foregroundStyle(Theme.warning)
                    } else if updater.state == .checking {
                        HStack { ProgressView().controlSize(.small); Text("Checking GitHub…").font(.pulseBody) }
                    } else {
                        Label("You're on the latest version.", systemImage: "checkmark.seal.fill").font(.pulseBody).foregroundStyle(Theme.success)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            Divider().overlay(Theme.divider)
            VStack(alignment: .leading, spacing: 10) {
                if case .downloading(let release, let fraction) = updater.state {
                    ProgressView(value: fraction).tint(Theme.accent)
                    Text("Downloading \(ByteCountFormatter.string(fromByteCount: Int64(Double(release.sizeBytes) * fraction), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: release.sizeBytes, countStyle: .file))")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                } else if case .installing = updater.state {
                    HStack { ProgressView().controlSize(.small); Text("Installing — PULSE will reopen in a moment…").font(.pulseCaption) }
                }
                Label("Your projects, settings and downloaded caption models are kept — they live outside the app, so nothing is re-downloaded.",
                      systemImage: "externaldrive.badge.checkmark")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Toggle("Check for updates automatically", isOn: Binding(get: { updater.autoCheck }, set: { updater.autoCheck = $0 }))
                        .toggleStyle(.checkbox).font(.pulseCaption)
                    Spacer()
                    Button("Close") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
                    actionButton
                }
            }
            .padding(16)
        }
        .frame(width: 600, height: 520)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .task { if updater.state == .idle || updater.state == .upToDate { await updater.check(userInitiated: true) } }
    }

    var title: String {
        if let release = updater.available { return "PULSE \(release.version.description) is available" }
        return "Software Update"
    }

    @ViewBuilder var actionButton: some View {
        switch updater.state {
        case .available:
            if updater.canInstall {
                Button { Task { await updater.install() } } label: { Label("Install & Relaunch", systemImage: "arrow.down.circle") }
                    .buttonStyle(.pulsePrimary).keyboardShortcut(.defaultAction)
            } else {
                Button("Open Download Page") { NSWorkspace.shared.open(AppUpdater.releasesPage) }.buttonStyle(.pulsePrimary)
            }
        case .downloading:
            Button("Cancel Download") { updater.cancelDownload() }.buttonStyle(.pulseSecondary)
        case .failed:
            Button("Try Again") { Task { await updater.check(userInitiated: true) } }.buttonStyle(.pulsePrimary)
        case .installing, .checking:
            EmptyView()
        case .idle, .upToDate:
            Button("Check Again") { Task { await updater.check(userInitiated: true) } }.buttonStyle(.pulseSecondary)
        }
    }

    func notes(_ release: ReleaseInfo) -> AttributedString {
        let text = release.whatsNew.isEmpty ? release.name : release.whatsNew
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
