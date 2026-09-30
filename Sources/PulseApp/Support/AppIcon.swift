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
