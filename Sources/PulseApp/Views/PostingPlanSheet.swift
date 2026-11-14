import AppKit
import PulseCore
import SwiftUI
import UniformTypeIdentifiers

/// Exports → Posting plan (#906): a week of posts from the shorts and videos in the project. What goes where
/// and when, to copy as text or put in a calendar. PULSE doesn't post anything from here.
struct PostingPlanSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @AppStorage("postingPlan.days") private var days = 7
    @AppStorage("postingPlan.perDay") private var perDay = 1
    @AppStorage("postingPlan.longDay") private var longDay = 1
    @AppStorage("postingPlan.platforms") private var platformsRaw = PostingPlatform.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage("postingPlan.times") private var timesRaw = ""
    @AppStorage("postingPlan.cards") private var includeCards = true

    var platforms: Set<PostingPlatform> {
        Set(platformsRaw.split(separator: ",").compactMap { PostingPlatform(rawValue: String($0)) })
    }

    /// Your own time of day per platform, as minutes after midnight.
    var times: [PostingPlatform: Int] {
        var out: [PostingPlatform: Int] = [:]
        for pair in timesRaw.split(separator: ",") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let platform = PostingPlatform(rawValue: String(parts[0])), let minutes = Int(parts[1]) { out[platform] = minutes }
        }
        return out
    }

    var items: [PostingItem] { session.postingItems(includeCards: includeCards) }

    var plan: PostingPlan {
        PostingPlanner.plan(items: items, options: PostingPlanner.Options(start: start, days: days, shortsPerDay: perDay, platforms: platforms,
                                                                         times: times, longVideoDay: longDay))
    }

    func timeBinding(_ platform: PostingPlatform) -> Binding<Date> {
        Binding(get: {
            let minutes = times[platform] ?? (platform.defaultTime.hour * 60 + platform.defaultTime.minute)
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var all = times
            all[platform] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            timesRaw = all.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
        })
    }

    func platformBinding(_ platform: PostingPlatform) -> Binding<Bool> {
        Binding(get: { platforms.contains(platform) }, set: { on in
            var all = platforms
            if on { all.insert(platform) } else { all.remove(platform) }
            platformsRaw = PostingPlatform.allCases.filter { all.contains($0) }.map(\.rawValue).joined(separator: ",")
        })
    }

    var body: some View {
        let plan = self.plan
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader("Posting plan", symbol: "calendar",
                        subtitle: "A week of posts from the shorts and videos in this project: the strongest first, each short on every platform you use, the best one as the trailer for the long video.")
            Divider().overlay(Theme.divider)
            HStack(alignment: .top, spacing: 0) {
                ScrollView { options.padding(18) }
                    .frame(width: 290)
                Divider().overlay(Theme.divider)
                ScrollView { schedule(plan).padding(18).frame(maxWidth: .infinity, alignment: .leading) }
            }
            Divider().overlay(Theme.divider)
            HStack(spacing: 8) {
                Text("PULSE doesn't post for you. The calendar file puts each post in your calendar; a YouTube upload can be scheduled from Exports.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { copy(plan) } label: { Label("Copy as Text", systemImage: "doc.on.doc") }
                    .buttonStyle(.pulse(.secondary, compact: true)).fixedSize().disabled(plan.slots.isEmpty)
                Button { saveCalendar(plan) } label: { Label("Save Calendar File…", systemImage: "calendar.badge.plus") }
                    .buttonStyle(.pulse(.primary, compact: true)).fixedSize().disabled(plan.slots.isEmpty)
                Button("Close") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 860, height: 660)
        .background(Theme.panel)
        .preferredColorScheme(AppModel.current?.colorScheme)
    }

    var options: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("The week")
                DatePicker("Starts", selection: $start, displayedComponents: [.date])
                Stepper(value: $days, in: 1...14) { Text("\(days) day\(days == 1 ? "" : "s")") }
                Stepper(value: $perDay, in: 1...3) { Text(perDay == 1 ? "1 short a day" : "\(perDay) shorts a day") }
                if items.contains(where: \.isLong), platforms.contains(.youtube) {
                    Stepper(value: $longDay, in: 0...max(0, days - 1)) { Text("Long video on day \(min(longDay, max(0, days - 1)) + 1)") }
                        .help("The strongest short goes out the day before it, as its trailer")
                }
            }
            .font(.pulseBody)
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Where and when")
                ForEach(PostingPlatform.allCases, id: \.self) { platform in
                    HStack(spacing: 6) {
                        Toggle(platform.displayName, isOn: platformBinding(platform)).toggleStyle(.checkbox)
                        Spacer(minLength: 4)
                        DatePicker("", selection: timeBinding(platform), displayedComponents: [.hourAndMinute])
                            .labelsHidden().frame(width: 84).disabled(!platforms.contains(platform))
                    }
                }
                Text("These times are starting points, not a study of your audience. Your own analytics say when your viewers are on: set the times from those.")
                    .font(.pulseCaption).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .font(.pulseBody)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("What goes in")
                Toggle("Clip cards that aren't shorts yet", isOn: $includeCards).toggleStyle(.checkbox)
                    .help("Favourites and cards scoring 70 or more. They are planned and marked “Build first”.")
            }
            .font(.pulseBody)
        }
    }

    @ViewBuilder
    func schedule(_ plan: PostingPlan) -> some View {
        if plan.slots.isEmpty {
            EmptyStateView(symbol: "calendar", title: "Nothing to post yet",
                           message: items.isEmpty ? "Make a short from a clip card, or run Edit My VOD, and the plan fills in."
                                                  : "Tick at least one platform these pieces can go to.")
                .frame(maxWidth: .infinity).padding(.top, 60)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text(plan.summary()).font(.pulseSubtitle).foregroundStyle(Theme.textPrimary)
                ForEach(plan.days()) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(entry.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        ForEach(entry.slots) { slot in row(slot) }
                    }
                }
                if !plan.leftovers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("Not this week")
                        ForEach(Array(plan.leftovers.enumerated()), id: \.offset) { _, item in
                            Text("\(item.title): \(item.reason)").font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    func row(_ slot: PostingPlan.Slot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(slot.date.formatted(date: .omitted, time: .shortened)).font(.pulseMono).foregroundStyle(Theme.textSecondary)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    TagChip(text: slot.platform.displayName)
                    Text(slot.title).font(.pulseHeadline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if slot.needsBuilding { TagChip(text: "Build first", color: Theme.warning, symbol: "hammer") }
                }
                if !slot.note.isEmpty {
                    Text(slot.note).font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .insetRow()
    }

    func copy(_ plan: PostingPlan) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plan.text(), forType: .string)
        app.toast("Posting plan copied")
    }

    func saveCalendar(_ plan: PostingPlan) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ExportSettings.cleanComponent(session.document.name) + " posting plan.ics"
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.prompt = "Save"
        panel.message = "A calendar file with one event per post. Open it to add them to Calendar."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try plan.calendarFile().write(to: url, atomically: true, encoding: .utf8)
            app.logActivity(.export, title: "Posting plan for “\(session.document.name)”", detail: plan.summary())
            app.toast("Saved \(url.lastPathComponent)")
        } catch {
            app.present(error, title: "Couldn't save the calendar file")
        }
    }
}
