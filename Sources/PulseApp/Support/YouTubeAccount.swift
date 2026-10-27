import Foundation
import PulseCore
import PulseEngine

/// The signed-in YouTube account (#482): tokens in the Keychain, the client secret in the Keychain, the
/// client id in Settings. Uploads run as jobs.
@MainActor
enum YouTubeAccount {
    static let tokensAccount = "youtube.tokens"
    static let secretAccount = "youtube.secret"

    static func credentials() -> YouTubeUploader.Credentials? {
        guard let text = KeychainStore.read(account: tokensAccount), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(YouTubeUploader.Credentials.self, from: data)
    }

    static func store(_ credentials: YouTubeUploader.Credentials?) {
        guard let credentials, let data = try? JSONEncoder().encode(credentials), let text = String(data: data, encoding: .utf8) else {
            _ = KeychainStore.delete(account: tokensAccount)
            return
        }
        _ = KeychainStore.write(account: tokensAccount, value: text)
    }

    /// Browser sign-in; stores the tokens.
    static func signIn(app: AppModel) {
        let clientID = app.settings.youtubeClientID.trimmingCharacters(in: .whitespaces)
        guard !clientID.isEmpty else {
            app.presentMessage(title: "Add a Google client id first", message: "Settings → Publishing explains how to make one in the Google Cloud console (a Desktop app OAuth client with the YouTube Data API on).")
            return
        }
        let secret = KeychainStore.read(account: secretAccount)
        app.jobs.start("Signing in to YouTube", kind: .export, location: .cloud) { job in
            job.detail = "Finish in the browser"
            let credentials = try await YouTubeUploader.signIn(clientID: clientID, clientSecret: secret)
            store(credentials)
            app.toast("Signed in to YouTube — exports now have a YouTube… button")
        }
    }

    static func signOut(app: AppModel) {
        store(nil)
        app.settings.youtubeChannel = ""
        app.toast("Signed out of YouTube")
    }

    /// A fresh token (refreshing when needed), or nil when signed out.
    static func freshCredentials(app: AppModel) async throws -> YouTubeUploader.Credentials? {
        guard var credentials = credentials() else { return nil }
        if !credentials.isFresh {
            credentials = try await YouTubeUploader.refresh(credentials, clientID: app.settings.youtubeClientID, clientSecret: KeychainStore.read(account: secretAccount))
            store(credentials)
        }
        return credentials
    }

    static func publish(file: URL, upload: YouTubeUpload, app: AppModel) {
        app.jobs.start("Uploading to YouTube · \(upload.title)", kind: .export, location: .cloud) { job in
            guard let credentials = try await freshCredentials(app: app) else {
                app.presentMessage(title: "Not signed in", message: "Settings → Publishing → Sign in with Google, then try again.")
                return
            }
            job.detail = "Sending \(ByteCountFormatter.string(fromByteCount: (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0, countStyle: .file))"
            let id = try await YouTubeUploader.upload(file: file, metadata: upload, credentials: credentials,
                                                      progress: { p in Task { @MainActor in job.progress = p } }, isCancelled: job.isCancelledCheck)
            let link = "https://youtu.be/\(id)"
            let when = upload.publishAt.map { " · goes live \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
            app.logActivity(.export, title: "Uploaded “\(upload.title)” to YouTube", detail: "\(upload.privacy.displayName)\(when) · \(link)", location: .cloud)
            app.toast("On YouTube (\(upload.privacy.displayName.lowercased())\(when)) — \(link)")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        }
    }
}
