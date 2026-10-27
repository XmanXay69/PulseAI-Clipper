import PulseCore
import PulseEngine
import SwiftUI

/// Publish an export to YouTube (#482): title, description and tags from the edit, who can see it, and an
/// optional schedule. The upload runs as a job; the link lands in a toast and the activity log.
struct PublishSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var queue: ExportQueueController
    let job: ExportJob
    @State private var upload = YouTubeUpload(title: "")
    @State private var scheduled = false
    @State private var publishAt = Date().addingTimeInterval(3600)
    @State private var tagsText = ""

    var signedIn: Bool { YouTubeAccount.credentials() != nil }
    var problems: [String] { var u = upload; u.tags = tags; u.publishAt = scheduled ? publishAt : nil; return u.problems }
    var tags: [String] { tagsText.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader("Publish to YouTube", symbol: "play.rectangle.fill", tint: Theme.danger,
                        subtitle: "“\(job.timelineName)” · \(job.outputPath.map { ($0 as NSString).lastPathComponent } ?? "")", padded: false)
            if !signedIn {
                Label("Sign in first: Settings → Publishing → Sign in with Google.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.pulseCaption).foregroundStyle(Theme.warning)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Title").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    TextField("Title", text: $upload.title).textFieldStyle(.roundedBorder).frame(width: 420)
                }
                GridRow {
                    Text("Description").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    TextEditor(text: $upload.description).font(.pulseCaption).frame(width: 420, height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                }
                GridRow {
                    Text("Tags").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    TextField("comma separated", text: $tagsText).textFieldStyle(.roundedBorder).frame(width: 420)
                }
                GridRow {
                    Text("Visibility").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $upload.privacy) {
                        ForEach(YouTubeUpload.Privacy.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    .disabled(scheduled)
                }
                GridRow {
                    Text("Schedule").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    HStack {
                        Toggle("Go live at", isOn: $scheduled).toggleStyle(.checkbox).font(.pulseCaption)
                            .onChange(of: scheduled) { _, on in if on { upload.privacy = .private } }
                        DatePicker("", selection: $publishAt, in: Date()..., displayedComponents: [.date, .hourAndMinute]).labelsHidden().disabled(!scheduled)
                    }
                }
                GridRow {
                    Text("Category").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Picker("", selection: $upload.categoryID) {
                        Text("Gaming").tag("20"); Text("Entertainment").tag("24"); Text("People & Blogs").tag("22"); Text("Comedy").tag("23"); Text("Education").tag("27")
                    }
                    .labelsHidden().frame(width: 200)
                }
                GridRow {
                    Text("").font(.pulseCaption)
                    HStack(spacing: 14) {
                        Toggle("Notify subscribers", isOn: $upload.notifySubscribers).toggleStyle(.checkbox).font(.pulseCaption)
                        Toggle("Made for kids", isOn: $upload.madeForKids).toggleStyle(.checkbox).font(.pulseCaption)
                    }
                }
            }
            ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.pulseMicro).foregroundStyle(Theme.warning) }
            Text(scheduled ? "Scheduled uploads stay private until the time comes, then go public." : "Private: only you. Unlisted: anyone with the link. Public: everyone, right away.")
                .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pulse(.secondary, compact: true)).keyboardShortcut(.cancelAction)
                Button(scheduled ? "Schedule" : "Upload") { publish() }
                    .buttonStyle(.pulse(.primary, compact: true)).keyboardShortcut(.defaultAction)
                    .disabled(!signedIn || !problems.isEmpty || job.outputPath == nil)
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(Theme.panel)
        .onAppear {
            if let draft = queue.publishDraft(for: job) { upload = draft; tagsText = draft.tags.joined(separator: ", ") }
            else { upload.title = job.timelineName }
        }
    }

    func publish() {
        guard let path = job.outputPath else { return }
        var final = upload
        final.tags = tags
        final.publishAt = scheduled ? publishAt : nil
        if scheduled { final.privacy = .private }
        YouTubeAccount.publish(file: URL(fileURLWithPath: path), upload: final, app: app)
        dismiss()
    }
}
