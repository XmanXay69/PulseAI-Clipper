import CoreImage
import Foundation
import PulseCore
import PulseEngine

extension ProjectSession {
    /// AI Clips → Review on Phone (#494): serves the moments on the local network; Approve favourites a short,
    /// Reject sends it to Maybe later, Undo puts it back. Stops with the project, or on Stop.
    func startPhoneReview() {
        let server = phoneReviewServer ?? ReviewServer()
        server.projectName = document.name
        server.items = { [weak self] in
            await MainActor.run {
                guard let self else { return [] }
                return self.document.candidates.filter { $0.status != .exported }.sorted { $0.potential > $1.potential }.map { c in
                    PhoneReview.Item(id: c.id, title: c.title, subtitle: "\(Timecode.duration(c.duration)) · \(c.transcriptSnippet.prefix(90))",
                                     potential: c.potential, status: c.status == .dismissed ? .rejected : (c.isFavorite ? .approved : .new))
                }
            }
        }
        server.thumbnail = { [weak self] id in
            let source: (URL, Seconds)? = await MainActor.run {
                guard let self, let c = self.document.candidates.first(where: { $0.id == id }), let asset = self.document.asset(id: c.assetID) else { return nil }
                return (self.url(for: asset), c.payoffTime)
            }
            guard let (url, time) = source else { return nil }
            return await ThumbnailService.shared.image(for: url, at: time, maxWidth: 640)
        }
        server.act = { [weak self] id, action in
            await MainActor.run {
                guard let self, self.document.candidates.contains(where: { $0.id == id }) else { return false }
                switch action {
                case .approve:
                    self.rateCandidate(id, liked: true)
                    self.edit("Approve from Phone") { doc in if let i = doc.candidates.firstIndex(where: { $0.id == id }) { doc.candidates[i].isFavorite = true; if doc.candidates[i].status == .dismissed { doc.candidates[i].status = .new } } }
                case .reject:
                    self.rateCandidate(id, liked: false)
                    self.edit("Reject from Phone") { doc in if let i = doc.candidates.firstIndex(where: { $0.id == id }) { doc.candidates[i].status = .dismissed; doc.candidates[i].isFavorite = false } }
                case .undo:
                    self.rateCandidate(id, liked: nil)
                    self.edit("Undo from Phone") { doc in if let i = doc.candidates.firstIndex(where: { $0.id == id }) { doc.candidates[i].status = .new; doc.candidates[i].isFavorite = false } }
                }
                return true
            }
        }
        do {
            try server.start()
            phoneReviewServer = server
            app.logActivity(.clipGeneration, title: "Phone review page started", detail: "Approve and Reject from a phone on the same network (#494)")
        } catch {
            app.present(error, title: "Couldn't start the review page")
        }
    }

    func stopPhoneReview() {
        phoneReviewServer?.stop()
        phoneReviewServer = nil
    }

    /// A QR code of the page's address, for the popover.
    static func qrCode(for url: URL, side: CGFloat = 180) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { return nil }
        let scale = side / image.extent.width
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
