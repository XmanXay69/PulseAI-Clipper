import PulseCore
import SwiftUI

/// A four-step tour over the real window (#432): everything dims except the part being explained, with a
/// card beside it. Return goes on, Escape ends it.
struct TourOverlay: View {
    @EnvironmentObject var app: AppModel
    let step: Int

    enum Region { case sidebar, pageBar, content, topBar }

    struct Step {
        let title: String
        let detail: String
        let region: Region
    }

    static let steps: [Step] = [
        Step(title: "Projects and pages", detail: "The sidebar holds your projects and the pages: Home, Import, AI Clips, Editor, Captions, Media, Exports. Drop a VOD anywhere in the window to import it.", region: .sidebar),
        Step(title: "The workflow, left to right", detail: "Media → AI Clips → Edit → Captions → Deliver along the bottom. Each page is one stage; you can jump back any time.", region: .pageBar),
        Step(title: "Everything is a normal edit", detail: "Viewer, timeline and inspector. Every AI decision is an ordinary clip you can trim, move or delete — and ⌘Z undoes anything.", region: .content),
        Step(title: "Find anything, ask anything", detail: "⌘F searches media, clips, captions and commands. On the timeline toolbar, the speech bubble is Ask PULSE: type what to change in plain English.", region: .topBar),
    ]

    var body: some View {
        GeometryReader { geo in
            let current = Self.steps[min(step, Self.steps.count - 1)]
            let cutout = rect(for: current.region, in: geo.size)
            ZStack(alignment: .topLeading) {
                // The dim with a hole: a compositing group lets the rounded rectangle punch through.
                Color.black.opacity(0.62)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .frame(width: cutout.width, height: cutout.height)
                            .offset(x: cutout.minX, y: cutout.minY)
                            .blendMode(.destinationOut),
                        alignment: .topLeading
                    )
                    .compositingGroup()
                    .onTapGesture { advance() }
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .frame(width: cutout.width, height: cutout.height)
                    .offset(x: cutout.minX, y: cutout.minY)
                    .allowsHitTesting(false)
                card(current)
                    .frame(width: 320)
                    .offset(cardOffset(for: current.region, cutout: cutout, in: geo.size))
            }
            .animation(Theme.motion(.easeInOut(duration: 0.25)), value: step)
        }
        .ignoresSafeArea()
        .onExitCommand { app.tourStep = nil }
        .accessibilityAddTraits(.isModal)
    }

    func card(_ current: Step) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Step \(step + 1) of \(Self.steps.count)").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Skip tour") { app.tourStep = nil }.buttonStyle(.plain).font(.pulseMicro).foregroundStyle(Theme.textTertiary)
            }
            Text(current.title).font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
            Text(current.detail).font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if step > 0 { Button("Back") { app.tourStep = step - 1 }.buttonStyle(.pulse(.ghost, compact: true)) }
                Spacer()
                Button(step + 1 >= Self.steps.count ? "Done" : "Next") { advance() }
                    .buttonStyle(.pulse(.primary, compact: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
    }

    func advance() {
        if step + 1 >= Self.steps.count { app.tourStep = nil } else { app.tourStep = step + 1 }
    }

    /// Where each part of the window is, from the layout the root view uses (sidebar 208 / 52 pt, top bar 50,
    /// page bar 46 when a project is open).
    func rect(for region: Region, in size: CGSize) -> CGRect {
        let sidebar: CGFloat = app.settings.sidebarCollapsed ? 52 : 208
        let topBar: CGFloat = 50
        let pageBar: CGFloat = app.session == nil ? 0 : 46
        switch region {
        case .sidebar: return CGRect(x: 4, y: 4, width: sidebar - 8, height: size.height - 8)
        case .pageBar:
            if pageBar == 0 { return CGRect(x: 4, y: 4, width: sidebar - 8, height: size.height - 8) }
            return CGRect(x: sidebar + 4, y: size.height - pageBar - 2, width: size.width - sidebar - 8, height: pageBar - 2)
        case .content: return CGRect(x: sidebar + 6, y: topBar + 4, width: size.width - sidebar - 12, height: size.height - topBar - pageBar - 10)
        case .topBar: return CGRect(x: sidebar + 4, y: 3, width: size.width - sidebar - 8, height: topBar - 6)
        }
    }

    func cardOffset(for region: Region, cutout: CGRect, in size: CGSize) -> CGSize {
        switch region {
        case .sidebar: return CGSize(width: cutout.maxX + 18, height: 90)
        case .pageBar: return CGSize(width: max(cutout.minX + 24, size.width / 2 - 160), height: max(60, cutout.minY - 210))
        case .content: return CGSize(width: max(cutout.minX + 24, size.width / 2 - 160), height: max(60, size.height / 2 - 100))
        case .topBar: return CGSize(width: max(cutout.minX + 24, size.width - 360), height: cutout.maxY + 14)
        }
    }
}
