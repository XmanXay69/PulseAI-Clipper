import Foundation

/// Where a piece can be posted.
public enum PostingPlatform: String, CaseIterable, Codable, Sendable {
    case tiktok, youtubeShorts, instagramReels, youtube

    public var displayName: String {
        switch self {
        case .tiktok: return "TikTok"
        case .youtubeShorts: return "YouTube Shorts"
        case .instagramReels: return "Instagram Reels"
        case .youtube: return "YouTube"
        }
    }

    public var isShortForm: Bool { self != .youtube }

    /// The time of day a post goes out when you haven't set your own. Spread across the day so three
    /// platforms don't all go at once. These are starting points, not a study of your audience: your own
    /// analytics say when your viewers are on, and the plan takes whatever times you give it.
    public var defaultTime: (hour: Int, minute: Int) {
        switch self {
        case .instagramReels: return (12, 30)
        case .youtube: return (16, 0)
        case .youtubeShorts: return (17, 0)
        case .tiktok: return (19, 30)
        }
    }
}

/// Something to post: a short (built or still a clip card) or a long video.
public struct PostingItem: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var isLong: Bool
    /// The coach's or the clip finder's score, for ordering: strongest first.
    public var potential: Int
    /// The stretch of the recording it shows, so two pieces of the same moment aren't both posted.
    public var source: TimeRange?
    public var assetID: UUID?
    /// Built and ready to export, or still a card to turn into a short first.
    public var isBuilt: Bool

    public init(id: UUID = UUID(), title: String, isLong: Bool = false, potential: Int, source: TimeRange? = nil, assetID: UUID? = nil, isBuilt: Bool = true) {
        self.id = id
        self.title = title
        self.isLong = isLong
        self.potential = potential
        self.source = source
        self.assetID = assetID
        self.isBuilt = isBuilt
    }
}

/// A week of posts (#906): what goes where and when, from the clips at hand.
public struct PostingPlan: Hashable, Sendable {
    public struct Slot: Hashable, Identifiable, Sendable {
        public var id: String { "\(itemID.uuidString)-\(platform.rawValue)" }
        public var date: Date
        public var platform: PostingPlatform
        public var itemID: UUID
        public var title: String
        /// What to do with this post beyond uploading it ("Point at the full video in the caption").
        public var note: String
        public var needsBuilding: Bool
    }

    public struct Leftover: Hashable, Sendable {
        public var title: String
        public var reason: String
    }

    public var slots: [Slot]
    public var leftovers: [Leftover]
    public var start: Date

    /// One day of the plan.
    public struct Day: Hashable, Identifiable, Sendable {
        public var day: Date
        public var slots: [Slot]
        public var id: Date { day }
    }

    /// The slots day by day, in order.
    public func days(calendar: Calendar = .current) -> [Day] {
        var out: [Day] = []
        for slot in slots.sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: slot.date)
            if let last = out.last, last.day == day { out[out.count - 1].slots.append(slot) } else { out.append(Day(day: day, slots: [slot])) }
        }
        return out
    }

    /// "6 posts of 2 shorts and 1 video over 3 days"
    public func summary(calendar: Calendar = .current) -> String {
        guard !slots.isEmpty else { return "Nothing to post yet" }
        let shorts = Set(slots.filter { $0.platform.isShortForm }.map(\.itemID)).count
        let longs = Set(slots.filter { !$0.platform.isShortForm }.map(\.itemID)).count
        let days = Set(slots.map { calendar.startOfDay(for: $0.date) }).count
        var parts: [String] = []
        if shorts > 0 { parts.append(shorts == 1 ? "1 short" : "\(shorts) shorts") }
        if longs > 0 { parts.append(longs == 1 ? "1 video" : "\(longs) videos") }
        return "\(slots.count) post\(slots.count == 1 ? "" : "s") of \(parts.joined(separator: " and ")) over \(days) day\(days == 1 ? "" : "s")"
    }

    /// The plan as plain text, a day a paragraph, to paste into notes or a message.
    public func text(calendar: Calendar = .current, locale: Locale = .current) -> String {
        let dayFormat = DateFormatter()
        dayFormat.calendar = calendar
        dayFormat.locale = locale
        dayFormat.timeZone = calendar.timeZone
        dayFormat.dateFormat = "EEEE d MMM"
        let timeFormat = DateFormatter()
        timeFormat.calendar = calendar
        timeFormat.locale = locale
        timeFormat.timeZone = calendar.timeZone
        timeFormat.dateFormat = "HH:mm"
        var lines: [String] = []
        for entry in days(calendar: calendar) {
            lines.append(dayFormat.string(from: entry.day))
            for slot in entry.slots {
                lines.append("  \(timeFormat.string(from: slot.date))  \(slot.platform.displayName): \(slot.title)" + (slot.note.isEmpty ? "" : " — \(slot.note)"))
            }
        }
        if !leftovers.isEmpty {
            lines.append("")
            lines.append("Not this week")
            for item in leftovers { lines.append("  \(item.title): \(item.reason)") }
        }
        return lines.joined(separator: "\n")
    }

    /// The plan as a calendar file (iCalendar), one fifteen-minute event per post, in local time so each lands
    /// at that hour wherever the calendar is opened.
    public func calendarFile(calendar: Calendar = .current) -> String {
        let stamp = DateFormatter()
        stamp.calendar = calendar
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = calendar.timeZone
        stamp.dateFormat = "yyyyMMdd'T'HHmmss"
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
        }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//PULSE//Posting plan//EN", "CALSCALE:GREGORIAN"]
        for slot in slots.sorted(by: { $0.date < $1.date }) {
            lines += ["BEGIN:VEVENT", "UID:\(slot.id)@pulse", "DTSTAMP:\(stamp.string(from: start))",
                      "DTSTART:\(stamp.string(from: slot.date))", "DTEND:\(stamp.string(from: slot.date.addingTimeInterval(900)))",
                      "SUMMARY:\(escape("Post “\(slot.title)” to \(slot.platform.displayName)"))"]
            let notes = [slot.note, slot.needsBuilding ? "Still a clip card: open it in PULSE and export it first." : ""].filter { !$0.isEmpty }
            if !notes.isEmpty { lines.append("DESCRIPTION:\(escape(notes.joined(separator: " ")))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

/// Lays a week of posts out from the clips at hand (#906). Editing is half the job; shipping on a schedule
/// is the other half, and a plan made once beats deciding every evening.
///
/// The rules are the plain ones: lead with the strongest clip, one or two shorts a day rather than
/// everything at once, every short on each short-form platform you use, never two clips of the same moment,
/// and the best short the day before the long video so it works as its trailer.
public enum PostingPlanner {
    public struct Options: Hashable, Sendable {
        /// The first day of the plan (its time of day is ignored).
        public var start: Date
        public var days: Int
        public var shortsPerDay: Int
        public var platforms: Set<PostingPlatform>
        /// Your own time of day per platform, as minutes after midnight; a platform not here uses its default.
        public var times: [PostingPlatform: Int]
        /// Which day of the plan the long video goes out on, counted from 0.
        public var longVideoDay: Int

        public init(start: Date = Date(), days: Int = 7, shortsPerDay: Int = 1,
                    platforms: Set<PostingPlatform> = [.tiktok, .youtubeShorts, .instagramReels, .youtube], times: [PostingPlatform: Int] = [:],
                    longVideoDay: Int = 1) {
            self.start = start
            self.days = days
            self.shortsPerDay = shortsPerDay
            self.platforms = platforms
            self.times = times
            self.longVideoDay = longVideoDay
        }
    }

    public static func plan(items: [PostingItem], options: Options = Options(), calendar: Calendar = .current) -> PostingPlan {
        let days = max(1, min(options.days, 28))
        let perDay = max(1, min(options.shortsPerDay, 4))
        let first = calendar.startOfDay(for: options.start)
        func date(day: Int, platform: PostingPlatform) -> Date {
            let minutes = options.times[platform] ?? (platform.defaultTime.hour * 60 + platform.defaultTime.minute)
            let base = calendar.date(byAdding: .day, value: day, to: first) ?? first
            return calendar.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: base) ?? base
        }
        var slots: [PostingPlan.Slot] = []
        var leftovers: [PostingPlan.Leftover] = []

        // The long video: the strongest one, on its day. The rest wait for another week.
        let longs = items.filter(\.isLong).sorted { $0.potential > $1.potential }
        let longDay = max(0, min(options.longVideoDay, days - 1))
        var feature: PostingItem?
        if options.platforms.contains(.youtube), let long = longs.first {
            feature = long
            slots.append(PostingPlan.Slot(date: date(day: longDay, platform: .youtube), platform: .youtube, itemID: long.id, title: long.title,
                                          note: "", needsBuilding: !long.isBuilt))
            for other in longs.dropFirst() { leftovers.append(.init(title: other.title, reason: "one long video a week; this one is next")) }
        } else {
            for long in longs { leftovers.append(.init(title: long.title, reason: "YouTube isn't in the plan")) }
        }

        // The shorts: strongest first, never two of the same moment.
        let shortPlatforms = PostingPlatform.allCases.filter { $0.isShortForm && options.platforms.contains($0) }
        var chosen: [PostingItem] = []
        for item in items.filter({ !$0.isLong }).sorted(by: { $0.potential != $1.potential ? $0.potential > $1.potential : $0.title < $1.title }) {
            guard !shortPlatforms.isEmpty else {
                leftovers.append(.init(title: item.title, reason: "no short-form platform is in the plan"))
                continue
            }
            if let twin = chosen.first(where: { other in
                guard let a = other.source, let b = item.source, other.assetID == item.assetID else { return false }
                return a.iou(b) > 0.3
            }) {
                leftovers.append(.init(title: item.title, reason: "shows the same moment as “\(twin.title)”"))
            } else if chosen.count >= days * perDay {
                leftovers.append(.init(title: item.title, reason: "the week is full; next week"))
            } else {
                chosen.append(item)
            }
        }
        // Which day each short goes out on. Fewer shorts than days are spread across the week, not bunched at
        // its start. With a long video in the plan, the strongest short goes the day before it as its trailer
        // (on the day itself when the video is on the first day).
        var dayOf: [Int] = []
        let spread = chosen.count < days
        for index in chosen.indices {
            dayOf.append(spread ? Int((Double(index) * Double(days) / Double(max(chosen.count, 1))).rounded(.down)) : index / perDay)
        }
        if feature != nil, !chosen.isEmpty {
            let trailerDay = max(0, longDay - 1)
            // Swap the strongest short onto the trailer day.
            if let holder = dayOf.firstIndex(of: trailerDay) {
                dayOf.swapAt(0, holder)
            } else {
                dayOf[0] = trailerDay
            }
        }
        for (index, item) in chosen.enumerated() {
            let day = dayOf[index]
            var note = ""
            if let feature, index == 0 {
                note = longDay == 0 ? "Goes with “\(feature.title)”: point at the full video in the caption."
                                    : "The trailer for “\(feature.title)”, out the next day: say the full video is coming."
            } else if let feature, day >= longDay, item.assetID != nil, item.assetID == feature.assetID {
                note = "From “\(feature.title)”: link the full video in the caption or a pinned comment."
            }
            for platform in shortPlatforms {
                slots.append(PostingPlan.Slot(date: date(day: day, platform: platform), platform: platform, itemID: item.id, title: item.title,
                                              note: note, needsBuilding: !item.isBuilt))
            }
        }
        slots.sort { $0.date != $1.date ? $0.date < $1.date : $0.platform.rawValue < $1.platform.rawValue }
        return PostingPlan(slots: slots, leftovers: leftovers, start: first)
    }
}
