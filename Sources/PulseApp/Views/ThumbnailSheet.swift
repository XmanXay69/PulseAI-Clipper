import AppKit
import PulseCore
import PulseEngine
import SwiftUI

/// "Make Thumbnail": PULSE picks the reaction frames and the words, then hands ready-made,
/// fully editable designs to Thumbnail Studio.
struct ThumbnailSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var session: ProjectSession
    let request: ThumbnailRequest
    @Environment(\.dismiss) private var dismiss

    @State private var setup: ProjectSession.ThumbnailSetup?
    @State private var picks: [ThumbnailPick] = []
    @State private var included: Set<UUID> = []
    @State private var previews: [UUID: CGImage] = [:]
    @State private var layouts: Set<ThumbnailLayout> = [.fullFrame, .faceZoom]
    @State private var working = false
    @State private var studioInstalled = ThumbnailStudioLink.isInstalled

    var designCount: Int {
        picks.filter { included.contains($0.id) }.reduce(0) { total, pick in
            total + layouts.filter { !($0 == .faceZoom && pick.face == nil && layouts.count > 1) }.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "photo.badge.plus").font(.system(size: 20)).foregroundStyle(Theme.ai)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 10).fill(Theme.aiSoft))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make Thumbnail").font(.pulseTitle).foregroundStyle(Theme.textPrimary)
                    Text(setup.map { "Best reaction frames from “\($0.subject)” — opened as editable designs in Thumbnail Studio." }
                         ?? "Nothing to make a thumbnail from yet — import a video first.")
                        .font(.pulseCaption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            .padding(20)
            Divider().overlay(Theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "Frames")
                    ForEach($picks) { $pick in frameRow($pick) }
                    SectionLabel(text: "Layouts")
                    HStack(spacing: 8) {
                        ForEach(ThumbnailLayout.allCases) { layout in layoutChip(layout) }
                    }
                    if app.settings.brandKit.enabled, app.settings.brandKit.hasAnything {
                        Label("Your brand kit's color and logo are used.", systemImage: "paintpalette")
                            .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(20)
            }
            Divider().overlay(Theme.divider)
            footer
        }
        .frame(width: 720, height: 620)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    func frameRow(_ pick: Binding<ThumbnailPick>) -> some View {
        let id = pick.wrappedValue.id
        let on = included.contains(id)
        return HStack(spacing: 12) {
            Button {
                if on { included.remove(id) } else { included.insert(id) }
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 16))
                    .foregroundStyle(on ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.well)
                if let image = previews[id] {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 160, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .opacity(on ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(pick.wrappedValue.reason).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Text(Timecode.short(pick.wrappedValue.time)).font(.pulseMono).foregroundStyle(Theme.textTertiary)
                    if pick.wrappedValue.face == nil {
                        Text("no face found").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                    }
                }
                TextField("Thumbnail text", text: pick.headline)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .heavy))
                Text("Keep it to 2–4 words — it's read at phone size.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
    }

    func layoutChip(_ layout: ThumbnailLayout) -> some View {
        let on = layouts.contains(layout)
        return Button {
            if on { if layouts.count > 1 { layouts.remove(layout) } } else { layouts.insert(layout) }
        } label: {
            Label(layout.displayName, systemImage: layout.symbol)
                .font(.pulseCaption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(on ? Theme.accentSoft : Theme.control))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(on ? Theme.accent.opacity(0.5) : Theme.border))
        }
        .buttonStyle(.plain)
    }

    var footer: some View {
        HStack(spacing: 10) {
            if studioInstalled {
                Label("Thumbnail Studio found", systemImage: "checkmark.circle.fill")
                    .font(.pulseCaption).foregroundStyle(Theme.success)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Thumbnail Studio isn't installed", systemImage: "exclamationmark.triangle.fill")
                        .font(.pulseCaption).foregroundStyle(Theme.warning)
                    Text("Designs are still saved — they'll be in its gallery once you install it.")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                Button("Get It") { NSWorkspace.shared.open(ThumbnailStudioLink.projectURL) }
                    .buttonStyle(.pulse(.ghost, compact: true))
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(.pulseSecondary).keyboardShortcut(.cancelAction)
            Button {
                Task { await create() }
            } label: {
                if working {
                    ProgressView().controlSize(.small)
                } else {
                    Text(studioInstalled ? "Open \(designCount) Design\(designCount == 1 ? "" : "s") in Thumbnail Studio"
                                         : "Save \(designCount) Design\(designCount == 1 ? "" : "s")")
                }
            }
            .buttonStyle(.pulsePrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(working || setup == nil || designCount == 0)
        }
        .padding(16)
    }

    func load() async {
        guard let made = session.thumbnailSetup(for: request) else { return }
        setup = made
        picks = made.picks
        included = Set(made.picks.prefix(3).map(\.id))
        if !made.picks.contains(where: { $0.face != nil }) { layouts = [.fullFrame, .panel] }
        let source = session.url(for: made.asset)
        for pick in made.picks {
            if let image = await ThumbnailService.shared.image(for: source, at: pick.time, maxWidth: 480, precise: true) {
                previews[pick.id] = image
            }
        }
    }

    func create() async {
        guard let setup else { return }
        working = true
        defer { working = false }
        let chosen = picks.filter { included.contains($0.id) }
        let order = ThumbnailLayout.allCases.filter { layouts.contains($0) }
        do {
            let designs = try await session.writeThumbnailDesigns(asset: setup.asset, picks: chosen, layouts: order)
            guard !designs.isEmpty else {
                app.presentMessage(title: "Couldn't grab the frames", message: "PULSE couldn't read frames from this video. Check that the file is still where it was imported from.")
                return
            }
            if studioInstalled, await ThumbnailStudioLink.open(design: designs.first) {
                app.toast("\(designs.count) designs sent to Thumbnail Studio")
            } else {
                NSWorkspace.shared.activateFileViewerSelecting(designs)
                app.toast("\(designs.count) designs saved for Thumbnail Studio")
            }
            dismiss()
        } catch {
            PulseLog.error("Thumbnail designs failed: \(error.localizedDescription)")
            app.presentMessage(title: "Couldn't save the designs", message: error.localizedDescription)
        }
    }
}
