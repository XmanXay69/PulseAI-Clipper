import Foundation
import PulseCore
import PulseEngine

/// The brand kit: your logo, intro/outro and caption look, applied to edits automatically or on demand.
extension ProjectSession {
    /// The kit's files as project media (imported the first time they're used).
    func prepareBrandAssets(_ kit: BrandKit) async -> BrandKitAssets {
        var assets = BrandKitAssets()
        var added: [MediaAsset] = []
        func asset(for path: String) async -> MediaAsset? {
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
            if let existing = document.media.first(where: { $0.path == path }) ?? added.first(where: { $0.path == path }) { return existing }
            let plan = ImportPlan.make(urls: [URL(fileURLWithPath: path)], existingPaths: [])
            guard let item = plan.items.first, var made = try? await MediaImporter.makeAsset(for: item, cacheRoot: app.cacheFolder) else { return nil }
            made.role = .graphic
            made.tags.append("brand-kit")
            added.append(made)
            return made
        }
        assets.logo = await asset(for: kit.logoPath)
        assets.intro = await asset(for: kit.introPath)
        assets.outro = await asset(for: kit.outroPath)
        if !added.isEmpty { edit("Add Brand Kit Media") { $0.media.append(contentsOf: added) } }
        return assets
    }

    /// Applies the kit to one edit (replacing a previous logo / intro / outro).
    func applyBrandKit(to timelineID: UUID, announce: Bool = true) {
        let kit = app.settings.brandKit
        guard kit.hasAnything else {
            if announce { app.presentMessage(title: "No brand kit yet", message: "Add your logo, intro/outro or caption look in Settings → Brand Kit.") }
            return
        }
        app.jobs.start("Applying brand kit", kind: .autoEdit) { [weak self] job in
            guard let self else { return }
            let assets = await self.prepareBrandAssets(kit)
            if (!kit.logoPath.isEmpty && assets.logo == nil) || (!kit.introPath.isEmpty && assets.intro == nil) || (!kit.outroPath.isEmpty && assets.outro == nil) {
                self.app.toast("Some brand kit files are missing — check Settings → Brand Kit")
            }
            guard let timeline = self.document.timeline(id: timelineID) else { return }
            let longForm = EditFormat.of(timeline) == .longForm
            self.edit("Apply Brand Kit") { doc in
                doc.editTimeline(id: timelineID) { BrandKitApplier.apply(kit, assets: assets, to: &$0, longForm: longForm) }
            }
            if announce { self.app.toast("Brand kit applied") }
        }
    }

    /// New shorts and YouTube edits get the kit when it's switched on.
    func autoApplyBrandKit(to timelineID: UUID) {
        let kit = app.settings.brandKit
        guard kit.enabled, kit.hasAnything else { return }
        applyBrandKit(to: timelineID, announce: false)
    }
}
