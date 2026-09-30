import AppKit
import PulseCore
import PulseEngine
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, aiProcessing, aiFeatures, transcription, files, proxies, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .aiProcessing: return "AI Processing"
        case .aiFeatures: return "AI Features"
        case .transcription: return "Transcription"
        case .files: return "Files & Storage"
        case .proxies: return "Proxies"
        case .shortcuts: return "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .aiProcessing: return "lock.shield"
        case .aiFeatures: return "sparkles"
        case .transcription: return "waveform"
        case .files: return "externaldrive"
        case .proxies: return "square.stack.3d.down.right"
        case .shortcuts: return "keyboard"
        }
    }
}

/// Settings: shown both as a sidebar section and in the standard ⌘, Settings window.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var tab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10).padding(.bottom, 10)
                ForEach(SettingsTab.allCases) { t in
                    Button { tab = t } label: {
                        HStack(spacing: 8) {
                            Image(systemName: t.symbol).frame(width: 16)
                            Text(t.title)
                            Spacer()
                        }
                        .font(.pulseBody)
                        .foregroundStyle(tab == t ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(tab == t ? Theme.control : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 200)
            .background(Theme.panel)
            Rectangle().fill(Theme.divider).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .general: GeneralSettings()
                    case .aiProcessing: AIProcessingSettings()
                    case .aiFeatures: AIFeatureSettings()
                    case .transcription: TranscriptionSettings()
                    case .files: FileSettings()
                    case .proxies: ProxySettingsPane()
                    case .shortcuts: ShortcutsPane()
                    }
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.window)
    }
}

/// A titled group of settings rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, footnote: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border))
            if let footnote {
                Text(footnote).font(.pulseCaption).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.pulseBody).foregroundStyle(Theme.textPrimary)
                if let detail { Text(detail).font(.pulseCaption).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control()
        }
    }
}

// MARK: General

struct GeneralSettings: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        SettingsGroup("Editing") {
            SettingsRow("Magnetic timeline", detail: "Deleting a clip closes the gap automatically.") {
                Toggle("", isOn: $app.settings.magneticTimeline).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Snapping", detail: "Clips snap to the playhead, markers and other clip edges. Toggle with S.") {
                Toggle("", isOn: $app.settings.snapping).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Show safe areas", detail: "Overlay the platform UI zones in the viewer.") {
                Toggle("", isOn: $app.settings.showSafeAreas).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Target platform", detail: "Used for new shorts, safe areas and default export preset.") {
                Picker("", selection: $app.settings.safeAreaPlatform) {
                    ForEach(SafeAreaPlatform.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 180)
            }
        }
        SettingsGroup("Saving", footnote: "Recovery snapshots protect unsaved work if PULSE quits unexpectedly. Backups are rotating copies of project.json inside each project.") {
            SettingsRow("Autosave every") {
                Picker("", selection: $app.settings.autosaveInterval) {
                    Text("15 seconds").tag(TimeInterval(15))
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                }
                .labelsHidden().frame(width: 180)
            }
            SettingsRow("Backups to keep") {
                Stepper("\(app.settings.backupsToKeep)", value: $app.settings.backupsToKeep, in: 1...50)
                    .font(.pulseBody).foregroundStyle(Theme.textSecondary)
            }
        }
        SettingsGroup("Welcome") {
            SettingsRow("Show the welcome guide again") {
                Button("Show Guide") { app.showOnboarding = true }.buttonStyle(.pulse(.secondary, compact: true))
            }
            SettingsRow("Open the sample project", detail: "A generated 75-second gameplay + facecam stream with two big moments.") {
                Button("Open Sample") { app.openDemoProject() }.buttonStyle(.pulse(.secondary, compact: true))
            }
        }
    }
}

// MARK: AI Processing

struct AIProcessingSettings: View {
    @EnvironmentObject var app: AppModel
    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var keyStatus: String?
    @State private var testing = false

    var body: some View {
        SettingsGroup("Privacy", footnote: "Video and audio never leave your Mac. Cloud providers only ever receive transcript text for titles, descriptions and hook advice.") {
            ForEach(AIProcessingPolicy.allCases, id: \.self) { policy in
                Button { app.settings.ai.processingPolicy = policy } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: app.settings.ai.processingPolicy == policy ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(app.settings.ai.processingPolicy == policy ? Theme.accent : Theme.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(policy.displayName).font(.pulseBody.weight(.medium)).foregroundStyle(Theme.textPrimary)
                            Text(policy.summary).font(.pulseCaption).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        SettingsGroup("Cloud AI provider (optional)", footnote: "API keys are stored in your macOS Keychain, never in project files.") {
            SettingsRow("Provider") {
                Picker("", selection: $app.settings.ai.cloudProvider) {
                    ForEach(CloudProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 260)
                .disabled(app.settings.ai.processingPolicy == .alwaysLocal)
            }
            if app.settings.ai.processingPolicy == .alwaysLocal {
                Label("Always Local is on, so cloud providers are disabled.", systemImage: "lock.fill")
                    .font(.pulseCaption).foregroundStyle(Theme.success)
            }
            switch app.settings.ai.cloudProvider {
            case .none:
                EmptyView()
            case .anthropic:
                SettingsRow("Model") {
                    TextField("claude-opus-5-5", text: $app.settings.ai.cloudModel).textFieldStyle(.roundedBorder).frame(width: 260)
                }
                SettingsRow("API key") {
                    SecureField(KeychainStore.read(account: "anthropic") == nil ? "sk-ant-…" : "Saved in Keychain", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder).frame(width: 260)
                        .onSubmit { saveKey(account: "anthropic", value: anthropicKey) }
                }
                keyButtons(account: "anthropic", value: anthropicKey)
            case .openAICompatible:
                SettingsRow("Base URL", detail: "LM Studio, Ollama (OpenAI mode), llama.cpp server, or a hosted endpoint.") {
                    TextField("http://localhost:1234/v1", text: $app.settings.ai.openAIBaseURL).textFieldStyle(.roundedBorder).frame(width: 260)
                }
                SettingsRow("Runs on this Mac", detail: "Mark local servers so PULSE labels their results LOCAL and allows them under Always Local.") {
                    Toggle("", isOn: $app.settings.ai.openAIIsLocalServer).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                }
                SettingsRow("Model") {
                    TextField("model name", text: $app.settings.ai.cloudModel).textFieldStyle(.roundedBorder).frame(width: 260)
                }
                SettingsRow("API key", detail: "Optional for local servers.") {
                    SecureField(KeychainStore.read(account: "openai") == nil ? "optional" : "Saved in Keychain", text: $openAIKey)
                        .textFieldStyle(.roundedBorder).frame(width: 260)
                        .onSubmit { saveKey(account: "openai", value: openAIKey) }
                }
                keyButtons(account: "openai", value: openAIKey)
            }
            if let keyStatus {
                Text(keyStatus).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    func keyButtons(account: String, value: String) -> some View {
        HStack(spacing: 8) {
            Spacer()
            if KeychainStore.read(account: account) != nil {
                Button("Remove Key") {
                    KeychainStore.delete(account: account)
                    keyStatus = "Key removed."
                }
                .buttonStyle(.pulse(.ghost, compact: true))
            }
            Button(testing ? "Testing…" : "Test Connection") { test() }
                .buttonStyle(.pulse(.secondary, compact: true))
                .disabled(testing)
            Button("Save Key") { saveKey(account: account, value: value) }
                .buttonStyle(.pulse(.primary, compact: true))
                .disabled(value.isEmpty)
        }
    }

    func saveKey(account: String, value: String) {
        guard !value.isEmpty else { return }
        if KeychainStore.write(account: account, value: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            keyStatus = "Saved to Keychain."
            anthropicKey = ""
            openAIKey = ""
        } else {
            keyStatus = "Couldn't save to the Keychain."
        }
    }

    func test() {
        testing = true
        keyStatus = nil
        let settings = app.settings.ai
        Task {
            let provider = AIProviders.insightProvider(settings: settings)
            do {
                let copy = try await provider.copy(for: ClipContext(transcript: "No way, that was the craziest clutch I've ever seen, let's go!", tags: ["hype"], duration: 12))
                keyStatus = "\(provider.displayName) responded: “\(copy.titles.first ?? "OK")”"
            } catch {
                keyStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            testing = false
        }
    }
}

// MARK: AI Features

struct AIFeatureSettings: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        SettingsGroup("Clip finding") {
            SettingsRow("Default clip length") {
                Picker("", selection: $app.settings.ai.defaultClipLength) {
                    ForEach(ClipLengthPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }
            if app.settings.ai.defaultClipLength == .custom {
                SettingsRow("Custom length", detail: "10–90 seconds") {
                    HStack {
                        Slider(value: $app.settings.ai.customClipLength, in: 10...90, step: 1).frame(width: 200).tint(Theme.accent)
                        Text("\(Int(app.settings.ai.customClipLength)) s").font(.pulseMono).foregroundStyle(Theme.textSecondary).frame(width: 40)
                    }
                }
            }
            SettingsRow("Aggressiveness", detail: "Higher finds more clips, including weaker moments.") {
                Slider(value: $app.settings.ai.clipAggressiveness, in: 0...1).frame(width: 240).tint(Theme.ai)
            }
            SettingsRow("Minimum AI Potential", detail: "Hide candidates scoring below this.") {
                HStack {
                    Slider(value: Binding(get: { Double(app.settings.ai.entertainmentThreshold) }, set: { app.settings.ai.entertainmentThreshold = Int($0) }), in: 0...90, step: 5)
                        .frame(width: 200).tint(Theme.ai)
                    Text("\(app.settings.ai.entertainmentThreshold)").font(.pulseMono).foregroundStyle(Theme.textSecondary).frame(width: 40)
                }
            }
        }
        SettingsGroup("One-click shorts", footnote: "Everything AI adds is marked with a violet AI badge and stays fully editable. Remove all AI edits from the Timeline menu.") {
            SettingsRow("Caption style") {
                Picker("", selection: $app.settings.ai.captionPresetName) {
                    ForEach(CaptionStyle.presets, id: \.presetName) { Text($0.presetName).tag($0.presetName) }
                }
                .labelsHidden().frame(width: 180)
            }
            SettingsRow("AI framing", detail: "Detect facecam, choose a layout and reframe to 9:16.") {
                Toggle("", isOn: $app.settings.ai.aiFraming).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
            SettingsRow("Auto crop") { Toggle("", isOn: $app.settings.ai.autoCrop).labelsHidden().toggleStyle(.switch).tint(Theme.ai) }
            SettingsRow("Auto zoom / punch-ins") { Toggle("", isOn: $app.settings.ai.autoZoom).labelsHidden().toggleStyle(.switch).tint(Theme.ai) }
            SettingsRow("Silence removal") {
                HStack {
                    Picker("", selection: $app.settings.ai.silencePreset) {
                        ForEach(SilencePreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                    .disabled(!app.settings.ai.silenceRemoval)
                    Toggle("", isOn: $app.settings.ai.silenceRemoval).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
                }
            }
            SettingsRow("Filler word removal", detail: "“um”, “uh”, “like”… Off by default — review in the transcript first.") {
                Toggle("", isOn: $app.settings.ai.fillerRemoval).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
            SettingsRow("AI sound effects", detail: "Uses sound effects you import into the project.") {
                Toggle("", isOn: $app.settings.ai.aiSoundEffects).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
            SettingsRow("AI music", detail: "Adds your imported music bed with automatic ducking under speech.") {
                Toggle("", isOn: $app.settings.ai.aiMusic).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
        }
    }
}

// MARK: Transcription

struct TranscriptionSettings: View {
    @EnvironmentObject var app: AppModel

    static let languages: [(String, String)] = [
        ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("es-ES", "Spanish"), ("fr-FR", "French"), ("de-DE", "German"),
        ("it-IT", "Italian"), ("pt-BR", "Portuguese (Brazil)"), ("ja-JP", "Japanese"), ("ko-KR", "Korean"), ("zh-CN", "Chinese (Simplified)"),
    ]

    var body: some View {
        SettingsGroup("Engine", footnote: TranscriptionEngineFactory.availabilitySummary(settings: app.settings.ai)) {
            SettingsRow("Transcription engine") {
                Picker("", selection: $app.settings.ai.transcriptionEngine) {
                    ForEach(TranscriptionEngineChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 240)
            }
            SettingsRow("Language") {
                Picker("", selection: $app.settings.ai.transcriptionLanguage) {
                    ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden().frame(width: 240)
            }
        }
        SettingsGroup("whisper.cpp (optional)", footnote: "Install with `brew install whisper-cpp` and download a ggml model (e.g. ggml-base.en.bin). PULSE also looks in /opt/homebrew/bin and ~/Library/Application Support/PULSE/Models automatically.") {
            SettingsRow("Executable") {
                pathField($app.settings.ai.whisperExecutablePath, placeholder: WhisperCppTranscriber.locateExecutable()?.path ?? "whisper-cli", directory: false)
            }
            SettingsRow("Model file") {
                pathField($app.settings.ai.whisperModelPath, placeholder: WhisperCppTranscriber.locateModel()?.path ?? "ggml-base.en.bin", directory: false)
            }
        }
        SettingsGroup("Import instead") {
            Text("Already have captions? Import an SRT or VTT file on the Import page and PULSE will use it as the transcript — no transcription needed.")
                .font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Text field + "Choose…" button bound to a file or folder path.
@MainActor
func pathField(_ binding: Binding<String>, placeholder: String, directory: Bool) -> some View {
    HStack(spacing: 6) {
        TextField(placeholder, text: binding).textFieldStyle(.roundedBorder).frame(width: 260)
        Button("Choose…") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = directory
            panel.canChooseFiles = !directory
            panel.canCreateDirectories = directory
            if panel.runModal() == .OK, let url = panel.url { binding.wrappedValue = url.path }
        }
        .buttonStyle(.pulse(.secondary, compact: true))
    }
}

// MARK: Files

struct FileSettings: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        SettingsGroup("Folders", footnote: "Leave a folder empty to use the default. Media is referenced in place, never copied, unless you choose otherwise.") {
            SettingsRow("Projects", detail: app.projectsFolder.path) {
                pathField($app.settings.projectFolder, placeholder: "Default", directory: true)
            }
            SettingsRow("Exports", detail: app.exportFolder.path) {
                pathField($app.settings.exportFolder, placeholder: "Default", directory: true)
            }
            SettingsRow("Cache", detail: app.cacheFolder.path) {
                pathField($app.settings.cacheFolder, placeholder: "Default", directory: true)
            }
            SettingsRow("Media", detail: "Where recordings from future screen capture will be saved.") {
                pathField($app.settings.mediaFolder, placeholder: "Default", directory: true)
            }
        }
        SettingsGroup("Storage") {
            let info = app.diskInfo
            KeyValueRow(key: "Projects", value: ByteCountFormatter.string(fromByteCount: info.projectsBytes, countStyle: .file))
            KeyValueRow(key: "Cache (thumbnails, waveforms, analysis, proxies)", value: ByteCountFormatter.string(fromByteCount: info.cacheBytes, countStyle: .file))
            KeyValueRow(key: "Referenced media", value: ByteCountFormatter.string(fromByteCount: info.mediaBytes, countStyle: .file))
            KeyValueRow(key: "Free space", value: ByteCountFormatter.string(fromByteCount: info.availableBytes, countStyle: .file))
            if info.totalBytes > 0 {
                ThinProgressBar(progress: 1 - Double(info.availableBytes) / Double(info.totalBytes), color: info.availableBytes < 10_000_000_000 ? Theme.warning : Theme.info)
            }
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.cacheFolder]) }
                    .buttonStyle(.pulse(.ghost, compact: true))
                Spacer()
                Button("Refresh") { app.refreshDiskInfo() }.buttonStyle(.pulse(.secondary, compact: true))
                Button("Clear Cache") { app.clearCache() }.buttonStyle(.pulse(.secondary, compact: true))
                    .help("Thumbnails, waveforms, proxies and analysis caches are rebuilt when needed. Projects and media are untouched.")
            }
        }
        .onAppear { app.refreshDiskInfo() }
    }
}

// MARK: Proxies

struct ProxySettingsPane: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        SettingsGroup("Proxy media", footnote: "Proxies are lightweight copies used for smooth playback of 4K or very long recordings. Exports always use the original media.") {
            SettingsRow("Generate proxies automatically") {
                Toggle("", isOn: $app.settings.proxy.enabled).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("For sources taller than") {
                Picker("", selection: $app.settings.proxy.autoThresholdHeight) {
                    Text("1080p").tag(1080)
                    Text("1440p").tag(1440)
                    Text("2160p").tag(2160)
                }
                .labelsHidden().frame(width: 140)
            }
            SettingsRow("Proxy size") {
                Picker("", selection: $app.settings.proxy.quality) {
                    ForEach(ProxyQuality.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            if app.settings.proxy.quality == .custom {
                SettingsRow("Custom height") {
                    Stepper("\(app.settings.proxy.customHeight)p", value: $app.settings.proxy.customHeight, in: 144...1080, step: 36)
                        .font(.pulseBody).foregroundStyle(Theme.textSecondary)
                }
            }
            SettingsRow("Use proxies for playback") {
                Toggle("", isOn: $app.settings.proxy.useProxiesForPlayback).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
        }
    }
}

// MARK: Shortcuts

struct ShortcutsPane: View {
    static let groups: [(String, [(String, String)])] = [
        ("Playback", [("Space", "Play / Pause"), ("J / K / L", "Reverse / Stop / Forward (press L again for 2×)"), ("← / →", "Step one frame (⇧ for 10)"), ("Home / End", "Go to start / end")]),
        ("Editing", [("A", "Select tool"), ("B", "Blade tool"), ("⌘K", "Split at playhead"), ("Delete", "Delete (leaves gap)"), ("⇧Delete", "Ripple delete"),
                     ("⌘D", "Duplicate"), ("⇧⌘D", "Detach audio"), ("I / O", "Set in / out point"), ("⌥⌘Delete", "Ripple delete in → out"),
                     ("M", "Add marker"), ("S", "Toggle snapping"), ("= / −", "Zoom timeline")]),
        ("AI", [("⌥⌘E", "Make More Entertaining"), ("⌥⌘T", "Add text")]),
        ("Project", [("⌘N", "New project"), ("⌘O", "Open project"), ("⌘I", "Import media"), ("⌘S", "Save"), ("⌥⌘S", "Save version"),
                     ("⌘Z / ⇧⌘Z", "Undo / Redo"), ("⌘F", "Search everything"), ("⌘1 … ⌘9", "Switch section"), ("⌃⌘0", "Toggle sidebar")]),
    ]

    var body: some View {
        ForEach(Self.groups, id: \.0) { group in
            SettingsGroup(group.0) {
                ForEach(group.1, id: \.0) { item in
                    HStack {
                        Text(item.1).font(.pulseBody).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(item.0).font(.pulseMono).foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.control))
                    }
                }
            }
        }
    }
}
