import Foundation

/// One thing a reviewer said about one moment of an edit.
public struct ReviewComment: Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Where in the edit, in seconds from its start.
    public var time: Seconds
    /// How long a stretch it is about; 0 for a single moment.
    public var duration: Seconds
    public var text: String
    public var author: String

    public init(id: UUID = UUID(), time: Seconds, duration: Seconds = 0, text: String, author: String = "") {
        self.id = id
        self.time = time
        self.duration = duration
        self.text = text
        self.author = author
    }
}

/// What came back from a reviewer.
public struct ReviewNotes: Hashable, Sendable {
    public var comments: [ReviewComment]
    public var reviewer: String
    /// The edit the comments were written on, when the file says.
    public var timelineID: UUID?
    public var timelineName: String?
    /// How long the video they watched was, when the file says.
    public var duration: Seconds?

    public init(comments: [ReviewComment] = [], reviewer: String = "", timelineID: UUID? = nil, timelineName: String? = nil, duration: Seconds? = nil) {
        self.comments = comments
        self.reviewer = reviewer
        self.timelineID = timelineID
        self.timelineName = timelineName
        self.duration = duration
    }
}

/// A page to watch an export and comment on it, and the way back (#1181): the reviewer plays the video,
/// types what should change at the moment it should change, and sends the comments back as a file or as
/// pasted text. PULSE puts each one on the timeline as a marker at its timecode.
///
/// The page is one HTML file that sits next to the exported video and is sent with it. PULSE runs no server,
/// so this is a file you send, not a hosted link: nothing is uploaded, and it works offline. Comments stay in
/// the reviewer's browser until they copy or save them.
///
/// Coming back, PULSE reads its own comments file and any plain text that starts lines with a timecode
/// ("0:42 the music is too loud"), so notes typed into a message or a document work too.
public enum ReviewComments {
    /// The marker colour review comments get, so they can be told from chapters (blue) and your own.
    public static let markerColor = MarkerColor.orange

    // MARK: The file that comes back

    struct File: Codable {
        struct Entry: Codable {
            var t: Double
            var end: Double?
            var text: String
            var who: String?
        }
        var pulseReview: Int
        var timeline: String?
        var name: String?
        var duration: Double?
        var reviewer: String?
        var comments: [Entry]
    }

    /// "0:42", "0:42.5", "1:02:03": what the page and the text export write, and what `parse` reads back.
    public static func stamp(_ seconds: Seconds) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded())
        let whole = tenths / 10, fraction = tenths % 10
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        let clock = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return fraction == 0 ? clock : "\(clock).\(fraction)"
    }

    /// Reads what a reviewer sent: PULSE's own comments file, or plain text with a timecode at the start of
    /// each comment. `frameRate` is used for timecodes that count frames ("00:00:42:10").
    public static func parse(_ text: String, frameRate: Double = 30) -> ReviewNotes {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let file = try? JSONDecoder().decode(File.self, from: Data(trimmed.utf8)) {
            let reviewer = (file.reviewer ?? "").trimmingCharacters(in: .whitespaces)
            let comments = file.comments.compactMap { entry -> ReviewComment? in
                let body = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty, entry.t.isFinite, entry.t >= 0 else { return nil }
                let length = entry.end.map { max(0, $0 - entry.t) } ?? 0
                return ReviewComment(time: entry.t, duration: length.isFinite ? length : 0, text: body,
                                     author: (entry.who ?? reviewer).trimmingCharacters(in: .whitespaces))
            }
            return ReviewNotes(comments: comments.sorted { $0.time < $1.time }, reviewer: reviewer,
                               timelineID: file.timeline.flatMap(UUID.init(uuidString:)), timelineName: file.name, duration: file.duration)
        }

        var notes = ReviewNotes()
        var comments: [ReviewComment] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let found = leadingTimecode(line, frameRate: frameRate) {
                guard !found.text.isEmpty else { continue }
                comments.append(ReviewComment(time: found.time, duration: found.duration, text: found.text, author: notes.reviewer))
                continue
            }
            let lower = line.lowercased()
            if comments.isEmpty {
                // The header: who wrote it, and which edit it was written on.
                for label in ["reviewer:", "from:", "by:"] where lower.hasPrefix(label) {
                    notes.reviewer = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
                }
                if lower.hasPrefix("pulse review") {
                    if let open = line.firstIndex(of: "“"), let close = line.lastIndex(of: "”"), open < close {
                        notes.timelineName = String(line[line.index(after: open)..<close])
                    }
                    if let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close,
                       let length = clock(String(line[line.index(after: open)..<close]), frameRate: frameRate) {
                        notes.duration = length
                    }
                }
            } else {
                // A line with no timecode carries on the comment above it.
                comments[comments.count - 1].text += " " + line
            }
        }
        for index in comments.indices where comments[index].author.isEmpty { comments[index].author = notes.reviewer }
        notes.comments = comments.sorted { $0.time < $1.time }
        return notes
    }

    /// "0:42", "1:02:03", "0:42.5" or "00:00:42:10" (frames) as seconds; nil for anything else. A lone number
    /// is not a timecode: "42 things are wrong" is a sentence.
    static func clock(_ text: String, frameRate: Double) -> Seconds? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count) else { return nil }
        var values: [Double] = []
        for (index, part) in parts.enumerated() {
            let isSeconds = index == min(parts.count, 3) - 1
            let pieces = part.split(separator: ".", omittingEmptySubsequences: false)
            guard pieces.count == 1 || (isSeconds && pieces.count == 2) else { return nil }
            guard pieces.allSatisfy({ !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isNumber) && $0.allSatisfy(\.isASCII) }),
                  let value = Double(part) else { return nil }
            values.append(value)
        }
        var frames = 0.0
        if values.count == 4 { frames = values.removeLast() }
        guard let seconds = values.last, seconds < 60 else { return nil }
        if values.count == 3, values[1] >= 60 { return nil }
        if frames >= max(frameRate, 1).rounded(.up) { return nil }
        let whole = values.count == 3 ? values[0] * 3600 + values[1] * 60 + seconds : values[0] * 60 + seconds
        return whole + frames / max(frameRate, 1)
    }

    /// The timecode a line starts with, the stretch it names when it gives two ("0:42-0:50"), and the comment
    /// after it. Brackets, a list bullet or number, and an @ in front are allowed.
    static func leadingTimecode(_ line: String, frameRate: Double) -> (time: Seconds, duration: Seconds, text: String)? {
        var rest = Substring(line)
        func skip(_ characters: String) { rest = rest.drop { characters.contains($0) } }
        func takeClock() -> Seconds? {
            let token = rest.prefix { $0.isNumber || $0 == ":" || $0 == "." }
            // A full stop that ends the sentence is not part of the time.
            var candidate = String(token)
            while candidate.hasSuffix(".") || candidate.hasSuffix(":") { candidate.removeLast() }
            guard let value = clock(candidate, frameRate: frameRate) else { return nil }
            rest = rest.dropFirst(candidate.count)
            return value
        }
        skip(" \t")
        // "- 0:42", "• 0:42", "3. 0:42", "3) 0:42"
        if let first = rest.first, "-*•–".contains(first) {
            rest = rest.dropFirst()
        } else {
            let digits = rest.prefix { $0.isNumber }
            let after = rest.dropFirst(digits.count)
            if !digits.isEmpty, digits.count <= 3, let mark = after.first, ".)".contains(mark), after.dropFirst().first == " " {
                rest = after.dropFirst()
            }
        }
        skip(" \t[(@")
        guard let start = takeClock() else { return nil }
        skip("])")
        var length = 0.0
        // A second timecode after a dash or "to" makes it a stretch.
        let saved = rest
        skip(" \t")
        var joined = false
        if let first = rest.first, "-–—".contains(first) { rest = rest.dropFirst(); joined = true }
        else if rest.lowercased().hasPrefix("to ") { rest = rest.dropFirst(3); joined = true }
        if joined {
            skip(" \t[(")
            if let end = takeClock(), end > start { length = end - start; skip("])") } else { rest = saved }
        } else {
            rest = saved
        }
        skip(" \t-–—:|>")
        return (start, length, rest.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Onto the timeline

    public struct Report: Hashable, Sendable {
        public var added: Int
        /// Comments that were already on the timeline from an earlier import.
        public var repeated: Int
        /// Comments written past the end of this edit, placed at its end.
        public var pastEnd: Int
        /// Set when the comments were written on a different edit, or on this one at a different length.
        public var warning: String?

        /// "4 comments from Sam are on the timeline as orange markers."
        public var summary: String {
            guard added > 0 || repeated > 0 else { return "No comments with a timecode were found." }
            var parts: [String] = []
            if added > 0 { parts.append("\(added) comment\(added == 1 ? " is" : "s are") on the timeline as \(ReviewComments.markerColor.rawValue) markers.") }
            if repeated > 0 { parts.append("\(repeated) \(repeated == 1 ? "was" : "were") already there.") }
            if pastEnd > 0 { parts.append("\(pastEnd) \(pastEnd == 1 ? "was" : "were") written past the end of this edit and sit\(pastEnd == 1 ? "s" : "") at its end.") }
            if let warning { parts.append(warning) }
            return parts.joined(separator: " ")
        }
    }

    /// The marker one comment becomes: who and what in the name, the whole comment in the note.
    static func marker(for comment: ReviewComment, at time: Seconds, pastEnd: Bool) -> Marker {
        let oneLine = comment.text.split(whereSeparator: \.isNewline).joined(separator: " ")
        let lead = comment.author.isEmpty ? "" : "\(comment.author): "
        let room = max(20, 60 - lead.count)
        let name = lead + (oneLine.count > room ? String(oneLine.prefix(room - 1)).trimmingCharacters(in: .whitespaces) + "…" : oneLine)
        var note = comment.text
        if pastEnd { note += " (Written at \(stamp(comment.time)), past the end of this edit.)" }
        return Marker(time: time, duration: comment.duration, name: name, note: note, color: markerColor)
    }

    /// Puts each comment on the timeline as a marker at its timecode. Importing the same comments twice adds
    /// nothing the second time.
    @discardableResult
    public static func apply(_ notes: ReviewNotes, to timeline: inout Timeline) -> Report {
        var report = Report(added: 0, repeated: 0, pastEnd: 0, warning: nil)
        let length = timeline.duration
        for comment in notes.comments {
            let late = comment.time > length + 0.5
            let time = min(max(0, comment.time), length)
            var placed = marker(for: comment, at: time, pastEnd: late)
            placed.duration = min(placed.duration, max(0, length - time))
            if timeline.markers.contains(where: { $0.color == markerColor && abs($0.time - time) < 0.05 && $0.note == placed.note }) {
                report.repeated += 1
                continue
            }
            timeline.markers.append(placed)
            report.added += 1
            if late { report.pastEnd += 1 }
        }
        if report.added > 0 {
            timeline.markers.sort { $0.time < $1.time }
            timeline.modifiedAt = Date()
        }
        if let id = notes.timelineID, id != timeline.id {
            report.warning = "These were written on “\(notes.timelineName ?? "another edit")”, not this one, and were placed by time."
        } else if let watched = notes.duration, abs(watched - length) > 0.5 {
            report.warning = "The edit was \(stamp(watched)) long when it was sent and is \(stamp(length)) now, so markers after what changed may sit early or late."
        }
        return report
    }

    // MARK: The way out: comments as text

    /// The comments as plain text, the same shape the page copies: a header and a line per comment.
    public static func text(_ notes: ReviewNotes) -> String {
        var lines: [String] = []
        if let name = notes.timelineName {
            lines.append("PULSE review — “\(name)”" + (notes.duration.map { " (\(stamp($0)))" } ?? ""))
        }
        if !notes.reviewer.isEmpty { lines.append("Reviewer: \(notes.reviewer)") }
        for comment in notes.comments.sorted(by: { $0.time < $1.time }) {
            let range = comment.duration > 0 ? "-\(stamp(comment.time + comment.duration))" : ""
            lines.append("\(stamp(comment.time))\(range) \(comment.text.split(whereSeparator: \.isNewline).joined(separator: " "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: The page

    /// The page's file name for a video: "My Short review.html" next to "My Short.mp4".
    public static func pageName(forVideo fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return (stem.isEmpty ? "video" : stem) + " review.html"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// A value as JSON that is safe inside a script element.
    static func script<T: Encodable>(_ value: T) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("null".utf8)
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    struct PageData: Encodable {
        struct Chapter: Encodable {
            var t: Double
            var name: String
        }
        var id: String
        var name: String
        var project: String
        var duration: Double
        var reviewer: String
        var chapters: [Chapter]
    }

    /// The watch-and-comment page for `timeline`, to save next to its exported video `videoFileName`.
    public static func page(timeline: Timeline, projectName: String, videoFileName: String, reviewer: String = "") -> String {
        let chapters = timeline.markers.filter { $0.color == .blue }.sorted { $0.time < $1.time }
            .map { PageData.Chapter(t: $0.time, name: $0.name) }
        let data = PageData(id: timeline.id.uuidString, name: timeline.name, project: projectName, duration: timeline.duration,
                            reviewer: reviewer, chapters: chapters)
        let source = videoFileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? videoFileName
        let portrait = timeline.canvas.height > timeline.canvas.width
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(escape(timeline.name)) review</title>
        <style>
        :root{--bg:#f4f4f6;--panel:#fff;--ink:#16161a;--dim:#6b6b76;--line:#e2e2e8;--accent:#e8590c;--accent-ink:#fff}
        @media(prefers-color-scheme:dark){:root{--bg:#111114;--panel:#1b1b20;--ink:#f1f1f4;--dim:#9a9aa6;--line:#2c2c34;--accent:#ff8a3d;--accent-ink:#1a0d04}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
        header{padding:18px 20px 6px}h1{font-size:20px;margin:0}.dim{color:var(--dim);font-size:13px;margin:2px 0}
        main{display:grid;grid-template-columns:\(portrait ? "minmax(0,380px) minmax(0,1fr)" : "minmax(0,1.7fr) minmax(0,1fr)");gap:18px;padding:12px 20px 28px;align-items:start}
        @media(max-width:820px){main{grid-template-columns:minmax(0,1fr)}}
        video{width:100%;max-height:78vh;background:#000;border-radius:10px;display:block}
        #missing{border:2px dashed var(--line);border-radius:10px;padding:26px 18px;text-align:center}#missing.over{border-color:var(--accent)}
        .panel{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px}
        .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
        button,.btn{font:inherit;border:1px solid var(--line);background:var(--panel);color:var(--ink);border-radius:8px;padding:7px 12px;cursor:pointer}
        button.go{background:var(--accent);border-color:var(--accent);color:var(--accent-ink);font-weight:600}
        button.tc{font-variant-numeric:tabular-nums;font-weight:600;color:var(--accent);padding:4px 8px}
        input[type=text],textarea{font:inherit;width:100%;border:1px solid var(--line);border-radius:8px;padding:8px 10px;background:var(--bg);color:var(--ink)}
        textarea{margin:8px 0;resize:vertical}#who{flex:1;min-width:120px}
        ol{list-style:none;margin:12px 0;padding:0}li{display:grid;grid-template-columns:auto minmax(0,1fr) auto;gap:8px;align-items:start;padding:8px 0;border-top:1px solid var(--line)}
        li p{margin:3px 0;white-space:pre-wrap;overflow-wrap:anywhere}li .x{border:none;color:var(--dim);padding:2px 6px}
        #chapters button{font-size:13px;padding:3px 8px}#said{min-height:1.4em}
        </style></head><body>
        <header><h1>\(escape(timeline.name))</h1>
        <p class="dim">\(escape(projectName)) · \(stamp(timeline.duration))\(reviewer.isEmpty ? "" : " · for \(escape(reviewer))")</p></header>
        <main>
        <section>
        <video id="v" controls playsinline preload="metadata" src="\(escape(source))"></video>
        <div id="missing" hidden><p><b>The video isn't next to this page.</b></p>
        <p class="dim">Keep “\(escape(videoFileName))” in the same folder as this page, or pick it here. It stays on this computer.</p>
        <label class="btn">Choose the video<input type="file" id="pick" accept="video/*" hidden></label></div>
        <div id="chapters" class="row" style="margin-top:10px"></div>
        </section>
        <section class="panel">
        <div class="row"><button type="button" class="tc" id="at" title="Use the time the video is at now">0:00</button>
        <input type="text" id="who" placeholder="Your name" autocomplete="name"></div>
        <textarea id="text" rows="3" placeholder="What should change here? The video pauses while you type."></textarea>
        <div class="row"><button type="button" class="go" id="add">Add comment</button><span class="dim">or ⌘↩ / Ctrl+↩</span></div>
        <ol id="list"></ol>
        <div class="row"><button type="button" id="copy">Copy comments</button><button type="button" id="save">Save comments file</button></div>
        <p class="dim" id="said"></p>
        <p class="dim">Send the comments back by pasting them into a message or by sending the file. They stay in this browser until you do; nothing is uploaded.</p>
        </section>
        </main>
        <script>
        const R = \(script(data));
        const $ = id => document.getElementById(id);
        const v = $("v"), key = "pulse-review-" + R.id;
        let comments = [], stamped = null;
        try { comments = JSON.parse(localStorage.getItem(key) || "[]"); $("who").value = localStorage.getItem("pulse-review-who") || ""; } catch (e) {}
        function stamp(t) {
          const tenths = Math.round(Math.max(0, t) * 10), whole = Math.floor(tenths / 10), f = tenths % 10;
          const h = Math.floor(whole / 3600), m = Math.floor(whole % 3600 / 60), s = whole % 60, two = n => String(n).padStart(2, "0");
          return (h > 0 ? h + ":" + two(m) : String(m)) + ":" + two(s) + (f ? "." + f : "");
        }
        function keep() { try { localStorage.setItem(key, JSON.stringify(comments)); localStorage.setItem("pulse-review-who", $("who").value); } catch (e) {} }
        function now() { return stamped === null ? (v.currentTime || 0) : stamped; }
        function showTime() { $("at").textContent = stamp(now()); }
        function draw() {
          comments.sort((a, b) => a.t - b.t);
          const list = $("list"); list.textContent = "";
          comments.forEach((c, i) => {
            const li = document.createElement("li"), go = document.createElement("button"), body = document.createElement("div"), x = document.createElement("button");
            go.className = "tc"; go.type = "button"; go.textContent = stamp(c.t); go.onclick = () => { v.currentTime = c.t; v.play().catch(() => {}); };
            const p = document.createElement("p"); p.textContent = c.text; body.appendChild(p);
            if (c.who) { const w = document.createElement("p"); w.className = "dim"; w.textContent = c.who; body.appendChild(w); }
            x.className = "x"; x.type = "button"; x.textContent = "✕"; x.title = "Remove this comment"; x.onclick = () => { comments.splice(i, 1); keep(); draw(); };
            li.append(go, body, x); list.appendChild(li);
          });
        }
        function add() {
          const text = $("text").value.trim(); if (!text) return;
          comments.push({ t: Math.round(now() * 100) / 100, text: text, who: $("who").value.trim() });
          $("text").value = ""; stamped = null; keep(); draw(); showTime();
        }
        function asFile() {
          return JSON.stringify({ pulseReview: 1, timeline: R.id, name: R.name, duration: R.duration, reviewer: $("who").value.trim(), comments: comments }, null, 1);
        }
        function asText() {
          const who = $("who").value.trim(), lines = ["PULSE review — “" + R.name + "” (" + stamp(R.duration) + ")"];
          if (who) lines.push("Reviewer: " + who);
          comments.forEach(c => lines.push(stamp(c.t) + " " + c.text.replace(/\\s*\\n\\s*/g, " ")));
          return lines.join("\\n");
        }
        function say(text) { $("said").textContent = text; }
        v.addEventListener("timeupdate", showTime);
        v.addEventListener("error", () => { v.hidden = true; $("missing").hidden = false; });
        $("text").addEventListener("input", () => { if (stamped === null && $("text").value.trim()) { stamped = v.currentTime || 0; v.pause(); showTime(); } if (!$("text").value.trim()) stamped = null; });
        $("text").addEventListener("keydown", e => { if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); add(); } });
        $("at").onclick = () => { stamped = v.currentTime || 0; showTime(); };
        $("add").onclick = add;
        $("who").addEventListener("change", keep);
        $("copy").onclick = () => {
          if (!comments.length) return say("No comments yet.");
          const text = asText(), done = () => say("Copied " + comments.length + " comment" + (comments.length === 1 ? "" : "s") + ". Paste them into a message.");
          if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, () => say("Copying was blocked here. Use Save comments file."));
          else { const t = document.createElement("textarea"); t.value = text; document.body.appendChild(t); t.select(); try { document.execCommand("copy"); done(); } catch (e) { say("Copying was blocked here. Use Save comments file."); } t.remove(); }
        };
        $("save").onclick = () => {
          if (!comments.length) return say("No comments yet.");
          const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([asFile()], { type: "application/json" }));
          a.download = R.name.replace(/[\\\\/:*?"<>|]+/g, " ").trim() + " review comments.json"; document.body.appendChild(a); a.click(); a.remove();
          say("Saved. Send that file back.");
        };
        function use(file) { if (!file) return; v.src = URL.createObjectURL(file); v.hidden = false; $("missing").hidden = true; }
        $("pick").onchange = e => use(e.target.files[0]);
        const drop = $("missing");
        ["dragenter", "dragover"].forEach(n => drop.addEventListener(n, e => { e.preventDefault(); drop.classList.add("over"); }));
        ["dragleave", "drop"].forEach(n => drop.addEventListener(n, e => { e.preventDefault(); drop.classList.remove("over"); }));
        drop.addEventListener("drop", e => use(e.dataTransfer.files[0]));
        document.addEventListener("keydown", e => {
          if (e.target === $("text") || e.target === $("who") || e.key !== " ") return;
          e.preventDefault(); if (v.paused) v.play().catch(() => {}); else v.pause();
        });
        R.chapters.forEach(c => { const b = document.createElement("button"); b.type = "button"; b.textContent = stamp(c.t) + " " + c.name; b.onclick = () => { v.currentTime = c.t; }; $("chapters").appendChild(b); });
        draw(); showTime();
        </script>
        </body></html>
        """
    }
}
