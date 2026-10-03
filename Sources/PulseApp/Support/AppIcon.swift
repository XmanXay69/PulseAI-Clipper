import AVFoundation
import AppKit
import PulseCore
import PulseEngine
import SwiftUI

/// Draws the PULSE app icon programmatically (no bundled artwork needed).
enum AppIcon {
    static func render(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = rect.insetBy(dx: size * 0.08, dy: size * 0.08)
            let path = NSBezierPath(roundedRect: inset, xRadius: size * 0.2, yRadius: size * 0.2)
            NSGradient(colors: [NSColor(red: 0.09, green: 0.09, blue: 0.13, alpha: 1), NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)])?
                .draw(in: path, angle: -90)
            NSColor.white.withAlphaComponent(0.08).setStroke()
            path.lineWidth = size * 0.01
            path.stroke()
            // Pulse line.
            let line = NSBezierPath()
            let midY = inset.midY
            let w = inset.width
            let x0 = inset.minX + w * 0.12
            line.move(to: NSPoint(x: x0, y: midY))
            line.line(to: NSPoint(x: x0 + w * 0.2, y: midY))
            line.line(to: NSPoint(x: x0 + w * 0.3, y: midY + w * 0.22))
            line.line(to: NSPoint(x: x0 + w * 0.42, y: midY - w * 0.26))
            line.line(to: NSPoint(x: x0 + w * 0.52, y: midY + w * 0.1))
            line.line(to: NSPoint(x: x0 + w * 0.58, y: midY))
            line.line(to: NSPoint(x: x0 + w * 0.76, y: midY))
            line.lineWidth = size * 0.055
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            NSColor(red: 1, green: 0.24, blue: 0.43, alpha: 1).setStroke()
            line.stroke()
            // Play triangle (short-form cue).
            let tri = NSBezierPath()
            let tx = inset.minX + w * 0.72
            tri.move(to: NSPoint(x: tx, y: midY - w * 0.1))
            tri.line(to: NSPoint(x: tx + w * 0.16, y: midY))
            tri.line(to: NSPoint(x: tx, y: midY + w * 0.1))
            tri.close()
            NSColor(red: 0.55, green: 0.42, blue: 1, alpha: 1).setFill()
            tri.fill()
            return true
        }
    }

    /// The disk image window: 640 × 400 pt, the app icon goes at (160, 190) and Applications at (480, 190)
    /// (Finder coordinates, top-left origin) — scripts/make-dmg.sh places them there.
    static func writeDMGBackground(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scale in [1, 2] {
            let w = 640 * scale, h = 400 * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            rep.size = NSSize(width: 640, height: 400)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            drawDMGBackground(in: NSRect(x: 0, y: 0, width: 640, height: 400))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: directory.appendingPathComponent(scale == 1 ? "background.png" : "background@2x.png"))
        }
    }

    private static func drawDMGBackground(in rect: NSRect) {
        NSGradient(colors: [NSColor(red: 0.08, green: 0.08, blue: 0.11, alpha: 1), NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)])?
            .draw(in: rect, angle: -90)
        func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                             .foregroundColor: color, .paragraphStyle: style]
            NSAttributedString(string: string, attributes: attributes).draw(in: NSRect(x: 0, y: y, width: rect.width, height: size * 1.5))
        }
        // AppKit's origin is bottom-left: Finder's y = 190 is 210 up from the bottom.
        text("Drag PULSE into Applications", size: 20, weight: .semibold, color: .white, y: 320)
        text("Then open it from Launchpad or your Applications folder.", size: 12, weight: .regular,
             color: NSColor.white.withAlphaComponent(0.55), y: 60)
        // Finder draws the icon names itself, black in Light Mode and white in Dark Mode; a mid-gray plate
        // under each name keeps both readable (names sit ~74 pt below the icon centers).
        NSColor(white: 0.56, alpha: 1).setFill()
        for x in [160.0, 480.0] {
            NSBezierPath(roundedRect: NSRect(x: x - 58, y: 400 - 264 - 11, width: 116, height: 22), xRadius: 11, yRadius: 11).fill()
        }
        // Arrow from the app icon to Applications.
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 250, y: 210))
        arrow.line(to: NSPoint(x: 382, y: 210))
        arrow.lineWidth = 4
        arrow.lineCapStyle = .round
        let pink = NSColor(red: 1, green: 0.24, blue: 0.43, alpha: 1)
        pink.setStroke()
        arrow.stroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 394, y: 210))
        head.line(to: NSPoint(x: 378, y: 222))
        head.line(to: NSPoint(x: 378, y: 198))
        head.close()
        pink.setFill()
        head.fill()
    }

    /// Writes an .iconset for `iconutil` (used by scripts/build-app.sh via `PULSE --render-icon <dir>`).
    static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                // Rasterize at exact pixel dimensions (iconutil rejects mis-sized images).
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                rep.size = NSSize(width: pixels, height: pixels)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                render(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                guard let png = rep.representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}

/// `PULSE --ui-snapshots <dir>` opens the sample project, visits every section and writes PNGs of
/// the window, then quits. CI uses it so the UI can be reviewed without a screen.
@MainActor
enum UISnapshotter {
    static func runIfRequested(app: AppModel) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--ui-snapshots"), i + 1 < args.count else { return }
        let directory = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        app.settings.hasCompletedOnboarding = true
        app.showOnboarding = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            // Consistent size for review regardless of the runner's display.
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }) {
                window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: true)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            capture(app: app, name: "00-home-empty", to: directory)
            app.showOnboarding = true
            try? await Task.sleep(nanoseconds: 600_000_000)
            capture(app: app, name: "01-onboarding", to: directory)
            app.showOnboarding = false
            app.openDemoProject()
            // Wait for the sample project (media generation + analysis + clips).
            var waited = 0.0
            while (app.session?.document.candidates.isEmpty ?? true) && waited < 180 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 0.5
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let sections: [SidebarSection] = [.home, .projects, .importMedia, .aiClips, .editor, .captions, .media, .templates, .exports, .settings]
            for (n, section) in sections.enumerated() {
                app.section = section
                if section == .editor || section == .captions {
                    if let tl = app.session?.document.timelines.first { app.session?.open(timelineID: tl.id) }
                    app.section = section
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    app.session?.playback.seek(to: 3)
                    if let first = app.session?.activeTimeline?.tracks.first?.clips.first { app.session?.selectedClipIDs = [first.id] }
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                capture(app: app, name: String(format: "%02d-%@", n + 2, section.rawValue), to: directory)
                if section == .editor { await captureViewerFrame(app: app, name: String(format: "%02d-%@-viewer-frame", n + 2, section.rawValue), to: directory) }
            }
            // Global search sheet.
            app.showGlobalSearch = true
            try? await Task.sleep(nanoseconds: 800_000_000)
            capture(app: app, name: "12-search", to: directory)
            app.showGlobalSearch = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Export through the app's queue — the same path as the Export button.
            if let session = app.session, let timeline = session.activeTimeline {
                let settings = ExportSettings(preset: .tiktok, outputDirectory: directory.path)
                app.exports.enqueue(timelines: [timeline], document: session.document, settings: settings)
                app.section = .exports
                var exportWait = 0.0
                while app.exports.jobs.contains(where: { !$0.status.isFinished }) && exportWait < 180 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    exportWait += 0.5
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                capture(app: app, name: "13-export-queue", to: directory)
                for job in app.exports.jobs {
                    FileHandle.standardError.write(Data("UI-EXPORT \(job.timelineName): \(job.status)\n".utf8))
                    if case .completed(let path) = job.status {
                        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
                        FileHandle.standardError.write(Data("UI-EXPORT file \((path as NSString).lastPathComponent) \(size) bytes\n".utf8))
                    }
                }
            }
            // Sound library: browse, then add a music bed composed to fit the short.
            if let session = app.session, let short = session.document.timelines.first {
                app.section = .editor
                session.open(timelineID: short.id)
                session.leftTab = .sounds
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                capture(app: app, name: "13b-sounds", to: directory)
                session.playback.seek(to: 0)
                if let bed = SoundLibrary.sound(id: "music.upbeat.goodvibes") { session.addLibrarySound(bed) }
                var soundWait = 0.0
                while !(session.activeTimeline?.allClips.contains { $0.role == .music } ?? false) && soundWait < 90 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    soundWait += 0.5
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                capture(app: app, name: "13c-sounds-added", to: directory)
                FileHandle.standardError.write(Data("UI-SOUNDS music clip added after \(soundWait)s: \(session.activeTimeline?.allClips.contains { $0.role == .music } ?? false)\n".utf8))
                session.leftTab = .media
            }
            // Layout morph: from 2 s the split screen animates into a circle facecam.
            if let session = app.session, let short = session.document.timelines.first {
                app.section = .editor
                session.open(timelineID: short.id)
                session.selectedClipIDs = []
                session.playback.seek(to: 2)
                try? await Task.sleep(nanoseconds: 800_000_000)
                session.addLayoutChange(.circleFacecam, duration: 1)
                session.playback.seek(to: 2.5)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                capture(app: app, name: "13d-layout-morph", to: directory)
                await captureViewerFrame(app: app, name: "13d-layout-morph-viewer-frame", to: directory)
                session.playback.seek(to: 4)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await captureViewerFrame(app: app, name: "13e-layout-morph-after-viewer-frame", to: directory)
            }
            // Record sheet (shows the permission card on machines without Screen Recording access).
            app.showRecordSheet = true
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            capture(app: app, name: "14-record-sheet", to: directory)
            app.showRecordSheet = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            // Multicam: turn the sample into a two-angle session and open the Angles panel.
            if let session = app.session, var camB = session.document.primaryAsset {
                let group = UUID()
                let mainID = camB.id
                camB.id = UUID()
                camB.name = "PULSE Demo Stream (Cam B)"
                camB.role = .camera
                camB.syncGroupID = group
                camB.syncOffset = -12
                session.edit("Snapshot Multicam") { doc in
                    doc.updateAsset(id: mainID) { $0.syncGroupID = group; $0.role = .camera }
                    doc.media.append(camB)
                }
                if let multicam = session.multicamGroups.first {
                    session.createMulticamEdit(groupID: multicam.id, auto: false)
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    session.playback.seek(to: 20)
                    session.cutToAngle(1)
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    capture(app: app, name: "15-multicam-angles", to: directory)
                    session.playback.seek(to: 22)
                    session.applyMulticamGrid(.twoUp, angles: [])
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    capture(app: app, name: "16-multicam-grid", to: directory)
                    await captureViewerFrame(app: app, name: "16-multicam-grid-viewer-frame", to: directory)
                }
            }
            // Edit My VOD: the options sheet, then the finished long-form edit with the coach.
            if let session = app.session {
                app.section = .aiClips
                app.showLongFormSheet = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                capture(app: app, name: "17-longform-sheet", to: directory)
                app.showLongFormSheet = false
                try? await Task.sleep(nanoseconds: 600_000_000)
                let before = Set(session.document.timelines.map(\.id))
                var options = LongFormOptions()
                options.minimumLength = 20
                session.editMyVOD(options: options)
                var waited = 0.0
                while !session.document.timelines.contains(where: { !before.contains($0.id) }) && waited < 120 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    waited += 0.5
                }
                if let edit = session.document.timelines.first(where: { !before.contains($0.id) }) {
                    FileHandle.standardError.write(Data("UI-LONGFORM \(Timecode.short(edit.duration)) after \(waited)s: \(session.lastAIReport ?? "")\n".utf8))
                    // How long until the finished edit is actually in the viewer.
                    let shown = Date()
                    while (session.playback.isBuilding || abs(session.playback.duration - edit.duration) > 0.5) && Date().timeIntervalSince(shown) < 60 {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                    let viewerSeconds = Date().timeIntervalSince(shown)
                    let levelStart = Date()
                    while session.playback.isEnhancingAudio && Date().timeIntervalSince(levelStart) < 120 {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    FileHandle.standardError.write(Data(String(format: "UI-VIEWER edit in the viewer after %.2fs; leveled audio swapped in %.1fs later\n",
                                                               viewerSeconds, Date().timeIntervalSince(levelStart)).utf8))
                    if let review = session.activeReview {
                        FileHandle.standardError.write(Data("UI-COACH score \(review.prediction.score) \(review.prediction.tier.displayName): \(review.suggestions.map(\.title).joined(separator: " | "))\n".utf8))
                    }
                    session.selectedClipIDs = []
                    session.playback.seek(to: 1.2)
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    capture(app: app, name: "18-longform-edit", to: directory)
                    await captureViewerFrame(app: app, name: "18-longform-edit-viewer-frame", to: directory)
                }
            }
            // Edit Like a Reference: study the sample video itself, show the questions, then edit with the answers.
            if let session = app.session, let asset = session.document.primaryAsset {
                app.section = .aiClips
                app.reference.current = nil
                app.showReferenceSheet = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                capture(app: app, name: "19-reference-pick", to: directory)
                app.reference.study(session.url(for: asset))
                var waited = 0.0
                while (app.reference.isStudying || (app.reference.current == nil && app.reference.failure == nil)) && waited < 240 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    waited += 0.5
                }
                if let style = app.reference.current {
                    let line = String(format: "UI-REFERENCE after %.0fs: %@ · %.1f cuts/min · %.1f zooms/min (×%.2f) · captions %@ · music %.2f · %.1f sfx/min · %.1f pop-ups/min · pauses %@\n",
                                      waited, style.summary, style.cutsPerMinute, style.zoomsPerMinute, style.zoomScale, style.hasCaptions ? "yes" : "no",
                                      style.musicBed, style.effectsPerMinute, style.popupsPerMinute, style.pauseRatio.map { String(format: "%.2f", $0) } ?? "–")
                    FileHandle.standardError.write(Data(line.utf8))
                } else {
                    FileHandle.standardError.write(Data("UI-REFERENCE failed after \(waited)s: \(app.reference.failure ?? "no style")\n".utf8))
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                capture(app: app, name: "20-reference-questions", to: directory)
                app.showReferenceSheet = false
                try? await Task.sleep(nanoseconds: 600_000_000)
                if let style = app.reference.current {
                    var answers = ReferenceAnswers.recommended(for: style)
                    answers.length = .short
                    let before = Set(session.document.timelines.map(\.id))
                    session.editLikeReference(style, answers: answers)
                    var editWait = 0.0
                    while !session.document.timelines.contains(where: { !before.contains($0.id) }) && editWait < 120 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        editWait += 0.5
                    }
                    let made = session.document.timelines.first { !before.contains($0.id) }
                    FileHandle.standardError.write(Data("UI-REFERENCE-EDIT \(made.map { "\($0.name) · \(Timecode.short($0.duration)) · captions \($0.captions?.style.presetName ?? "none")" } ?? "none") · \(session.lastAIReport ?? "")\n".utf8))
                }
            }
            // Thumbnail Studio tie-in: the sheet, then real designs written in the studio's format.
            if let session = app.session {
                app.thumbnailRequest = ThumbnailRequest()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                capture(app: app, name: "21-thumbnail-sheet", to: directory)
                app.thumbnailRequest = nil
                try? await Task.sleep(nanoseconds: 600_000_000)
                if let setup = session.thumbnailSetup(for: ThumbnailRequest()) {
                    do {
                        let designs = try await session.writeThumbnailDesigns(asset: setup.asset, picks: Array(setup.picks.prefix(2)),
                                                                              layouts: ThumbnailLayout.allCases)
                        let decoded = designs.compactMap { try? JSONDecoder().decode(ThumbStudioDocument.self, from: Data(contentsOf: $0)) }
                        let frames = Set(decoded.compactMap { doc -> String? in
                            if case .image(let image)? = doc.layers.first?.kind { return image.path } else { return nil }
                        })
                        let framesExist = frames.allSatisfy { FileManager.default.fileExists(atPath: $0) }
                        FileHandle.standardError.write(Data("UI-THUMBNAIL \(designs.count) designs (\(decoded.count) decode), \(frames.count) frames on disk: \(framesExist) — \(designs.map(\.lastPathComponent).joined(separator: " | "))\n".utf8))
                    } catch {
                        FileHandle.standardError.write(Data("UI-THUMBNAIL failed: \(error.localizedDescription)\n".utf8))
                    }
                }
            }
            NSApp.terminate(nil)
        }
    }

    static func capture(app: AppModel, name: String, to directory: URL) {
        guard let main = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }) else { return }
        // Sheets (onboarding, recovery, search) live in their own window.
        let window = main.attachedSheet ?? main
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }

    /// AVPlayerLayer content isn't included in view caching, so grab the viewer's frame straight
    /// from the live player item (same composition + compositor the viewer shows).
    static func captureViewerFrame(app: AppModel, name: String, to directory: URL) async {
        guard let playback = app.session?.playback, let item = playback.player.currentItem else { return }
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.videoComposition = item.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: playback.currentTime, preferredTimescale: 600)
        guard let image = try? await generator.image(at: time).image else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
}
