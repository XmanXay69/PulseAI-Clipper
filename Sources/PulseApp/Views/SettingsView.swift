import AppKit
import PulseCore
import PulseEngine
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, aiProcessing, aiFeatures, brandKit, performance, transcription, files, proxies, shortcuts, statistics, diagnostics, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .aiProcessing: return "AI Processing"
        case .aiFeatures: return "AI Features"
        case .brandKit: return "Brand Kit"
        case .performance: return "Performance"
        case .transcription: return "Transcription"
        case .files: return "Files & Storage"
        case .proxies: return "Proxies"
        case .shortcuts: return "Shortcuts"
        case .statistics: return "Statistics"
        case .diagnostics: return "Diagnostics"
        case .privacy: return "Privacy"
        }
    }

    /// Words people search for that land on this tab (#443).
    var keywords: String {
        switch self {
        case .general: return "theme accent colour appearance timecode transition snapping autosave backups sidebar onboarding update channel beta speakers headphones monitoring"
        case .aiProcessing: return "cloud local privacy provider api key model claude openai"
        case .aiFeatures: return "clips length aggressiveness captions zoom crop silence filler music sound effects extras censor swear banners taste cold open speed ramp hashtags end card follow handle whoosh hook sting"
        case .brandKit: return "logo watermark intro outro bumper name card font colors handle"
        case .performance: return "threads memory cache proxies speed analysis"
        case .transcription: return "whisper speech language vocabulary speakers words"
        case .files: return "folders media projects cache export location storage disk"
        case .proxies: return "proxy resolution playback quality"
        case .shortcuts: return "keys keyboard hotkeys print cheat sheet"
        case .statistics: return "stats hours saved shorts built exports"
        case .diagnostics: return "log report problem dependencies gpu encoder"
        case .privacy: return "data network telemetry offline"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .aiProcessing: return "lock.shield"
        case .aiFeatures: return "sparkles"
        case .brandKit: return "paintbrush.pointed"
        case .performance: return "chart.line.uptrend.xyaxis"
        case .transcription: return "waveform"
        case .files: return "externaldrive"
        case .proxies: return "square.stack.3d.down.right"
        case .shortcuts: return "keyboard"
        case .statistics: return "chart.bar"
        case .diagnostics: return "stethoscope"
        case .privacy: return "hand.raised"
        }
    }
}

/// Settings: shown both as a sidebar section and in the standard ⌘, Settings window.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var tab: SettingsTab = .general
    @State private var query = ""

    /// Tabs whose title or keywords match the search (#443); all of them when it's empty.
    var visibleTabs: [SettingsTab] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsTab.allCases }
        return SettingsTab.allCases.filter { $0.title.lowercased().contains(q) || $0.keywords.contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10).padding(.bottom, 6)
                TextField("Search settings", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.pulseCaption)
                    .padding(.horizontal, 6).padding(.bottom, 8)
                    .onChange(of: query) { _, _ in if let first = visibleTabs.first, !visibleTabs.contains(tab) { tab = first } }
                if visibleTabs.isEmpty {
                    Text("Nothing matches “\(query)”").font(.pulseMicro).foregroundStyle(Theme.textTertiary).padding(.horizontal, 10)
                }
                ForEach(visibleTabs) { t in
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
                    case .brandKit: BrandKitSettings()
                    case .performance: PerformanceSettings()
                    case .transcription: TranscriptionSettings()
                    case .files: FileSettings()
                    case .proxies: ProxySettingsPane()
                    case .shortcuts: ShortcutsPane()
                    case .statistics: StatisticsPane()
                    case .diagnostics: DiagnosticsPane()
                    case .privacy: PrivacyPane()
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
                .raisedSurface()
                .elevation(1)
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
                .accessibilityLabel(label)
        }
    }
}

// MARK: General

struct GeneralSettings: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        SettingsGroup("Your stream") {
            SettingsRow("Set up for my stream", detail: app.settings.streamSetup.map { "\($0.platform.displayName) · \($0.content.displayName) · \($0.facecam ? "facecam" : "no facecam") · shorts for \($0.shortsTarget.displayName)" }
                        ?? "Answer six questions and PULSE sets clip length, captions, extras, safe areas and the export preset to match.") {
                Button(app.settings.streamSetup == nil ? "Set Up…" : "Change…") { app.showSetupWizard = true }.buttonStyle(.pulse(.secondary, compact: true))
            }
        }
        SettingsGroup("Appearance") {
            SettingsRow("Accent colour", detail: "Buttons, selection and the playhead. AI features keep their violet.") {
                HStack(spacing: 8) {
                    ForEach(AccentChoice.allCases, id: \.self) { choice in
                        Button { app.settings.accent = choice } label: {
                            Circle().fill(Color(hex: choice.hex)).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.white, lineWidth: app.settings.accent == choice ? 2 : 0))
                                .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(choice.displayName)
                        .accessibilityLabel(choice.displayName)
                        .accessibilityAddTraits(app.settings.accent == choice ? [.isSelected] : [])
                    }
                }
            }
        }
        SettingsGroup("Settings file", footnote: "Move your settings to another Mac. Folders and the recent-projects list stay this Mac's own.") {
            SettingsRow("Export / import", detail: "Everything in Settings as one JSON file.") {
                HStack(spacing: 6) {
                    Button("Export…") { app.exportSettingsFile() }.buttonStyle(.pulse(.secondary, compact: true))
                    Button("Import…") { app.importSettingsFile() }.buttonStyle(.pulse(.secondary, compact: true))
                }
            }
            SettingsRow("Reset a section", detail: "Back to PULSE's defaults for that part only.") {
                HStack(spacing: 6) {
                    Button("Editing") {
                        let d = AppSettings()
                        app.settings.magneticTimeline = d.magneticTimeline; app.settings.snapping = d.snapping
                        app.settings.showSafeAreas = d.showSafeAreas; app.settings.safeAreaPlatform = d.safeAreaPlatform
                        app.settings.defaultTransitionKind = d.defaultTransitionKind; app.settings.defaultTransitionDuration = d.defaultTransitionDuration
                    }
                    .buttonStyle(.pulse(.ghost, compact: true))
                    Button("AI Features") {
                        var fresh = AISettings()
                        fresh.taste = app.settings.ai.taste; fresh.coachCalibration = app.settings.ai.coachCalibration
                        fresh.analysisSpeed = app.settings.ai.analysisSpeed
                        fresh.whisperModelPath = app.settings.ai.whisperModelPath; fresh.whisperExecutablePath = app.settings.ai.whisperExecutablePath
                        app.settings.ai = fresh
                    }
                    .buttonStyle(.pulse(.ghost, compact: true))
                    Button("Proxies") { app.settings.proxy = ProxySettings() }.buttonStyle(.pulse(.ghost, compact: true))
                }
            }
        }
        SettingsGroup("Editing") {
            SettingsRow("Compact tracks", detail: "Tighter track heights for long timelines; timelines over 300 clips use them regardless.") {
                Toggle("", isOn: $app.settings.compactTimeline).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Follow the playhead", detail: "While playing, the timeline pages forward to keep the playhead in view.") {
                Toggle("", isOn: $app.settings.timelineFollowsPlayhead).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Pause batches on low battery", detail: "The overnight batch waits while the Mac is on battery below 20 %.") {
                Toggle("", isOn: $app.settings.batchPausesOnLowBattery).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            MonitoringNoteRow()
            SettingsRow("Magnetic timeline", detail: "Deleting a clip closes the gap automatically.") {
                Toggle("", isOn: $app.settings.magneticTimeline).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Snapping", detail: "Clips snap to the playhead, markers and other clip edges. Toggle with S.") {
                Toggle("", isOn: $app.settings.snapping).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Time display", detail: "How the viewer shows the playhead and duration.") {
                Picker("", selection: $app.settings.timecodeStyle) {
                    ForEach(TimecodeStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 200)
            }
            SettingsRow("Default transition", detail: "⌘T puts it on the selected clips' edges, or on the cut under the playhead.") {
                HStack(spacing: 8) {
                    Picker("", selection: $app.settings.defaultTransitionKind) {
                        ForEach(TransitionKind.allCases.filter { $0 != .cut }, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().frame(width: 150)
                    Stepper(value: $app.settings.defaultTransitionDuration, in: 0.1...2, step: 0.1) {
                        Text(String(format: "%.1f s", app.settings.defaultTransitionDuration)).font(.pulseMono)
                    }
                }
            }
            SettingsRow("Show safe areas", detail: "Overlay the platform UI zones in the viewer.") {
                Toggle("", isOn: $app.settings.showSafeAreas).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Frame-step tick", detail: "A soft click on every ← / → frame step.") {
                Toggle("", isOn: $app.settings.scrubTick).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Import preset", detail: app.settings.importPreset.detail) {
                Picker("", selection: $app.settings.importPreset) {
                    ForEach(ImportPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 180)
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
        SettingsGroup("Help") {
            SettingsRow("Software update", detail: "You have PULSE \(AppModel.versionString). Updates install from inside the app and keep your projects, settings and caption models.") {
                Button(app.updater.available.map { "Update to \($0.version.description)…" } ?? "Check for Updates…") { app.updater.showSheet = true }
                    .buttonStyle(.pulse(.secondary, compact: true))
            }
            SettingsRow("Update channel", detail: app.settings.updateChannel.detail + " The update sheet lists everything since the version you have.") {
                Picker("", selection: $app.settings.updateChannel) {
                    ForEach(UpdateChannel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 160)
                .onChange(of: app.settings.updateChannel) { _, _ in Task { await app.updater.check(userInitiated: false) } }
            }
            SettingsRow("Something not working?", detail: "Bundles the app log and system info (never your media) and opens a GitHub issue.") {
                Button("Report a Problem…") { app.showReportProblem = true }.buttonStyle(.pulse(.secondary, compact: true))
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
        SettingsGroup("Your taste", footnote: "Every 👍 / 👎 on a clip teaches PULSE what you find entertaining. It re-ranks clips and guides Edit My VOD, shifting scores by up to 25 points once it has a few ratings.") {
            SettingsRow("What PULSE has learned", detail: app.settings.ai.taste.summary) {
                Button("Reset") { app.settings.ai.taste = TasteProfile() }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    .disabled(app.settings.ai.taste.isEmpty)
            }
        }
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
            SettingsRow("Words to censor", detail: "On top of the built-in list — comma-separated. Masked, bleeped or hidden per the caption style.") {
                TextField("e.g. heck, dang", text: Binding(
                    get: { app.settings.ai.extraProfanity.joined(separator: ", ") },
                    set: { app.settings.ai.extraProfanity = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    .textFieldStyle(.roundedBorder).frame(width: 260)
            }
            SettingsRow("Audio under swear words", detail: "What AI-built shorts and VOD edits do to the sound under the words the caption filter masks. Rendered non-destructively; change it per timeline in the captions workspace.") {
                Picker("", selection: $app.settings.ai.censorAudio) {
                    ForEach(CensorAudio.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            SettingsRow("Bleep tone", detail: "Pitch of the bleep over swear words.") {
                Picker("", selection: $app.settings.ai.bleepTone) {
                    Text("Low (440 Hz)").tag(440.0)
                    Text("Classic (1 kHz)").tag(1000.0)
                    Text("High (2 kHz)").tag(2000.0)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            }
            SettingsRow("Cold open on shorts", detail: "Shorts open on 1.6 s of the payoff, cut hard, then tell the story.") {
                Toggle("", isOn: $app.settings.ai.coldOpenShorts).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
            SettingsRow("Whoosh on the hook", detail: "A quiet whoosh under the first words of every short (#77). Needs sound effects on.") {
                Toggle("", isOn: $app.settings.ai.hookSting).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
            EffectChoiceRow(job: "hit", category: "Impacts", title: "Payoff hit", detail: "Which impact lands on a short's payoff and on replays (#105).")
            EffectChoiceRow(job: "whoosh", category: "Transitions", title: "Whoosh", detail: "Which sweep PULSE uses for the hook, replays and cutaways.")
            SettingsRow("End of every short", detail: app.settings.ai.shortsEndCTA.detail) {
                Picker("", selection: $app.settings.ai.shortsEndCTA) {
                    ForEach(EndCTA.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            }
            SettingsRow("Your handle", detail: "Goes on follow cards (“FOLLOW @you FOR MORE”).") {
                TextField("@you", text: $app.settings.ai.socialHandle).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            SettingsRow("Ask about extras once per project", detail: "The Extras question before Edit My VOD is asked the first time in a project, then your answers are reused.") {
                Toggle("", isOn: $app.settings.ai.askExtrasOncePerProject).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
            SettingsRow("Your taste", detail: app.settings.ai.taste.summaryLines.isEmpty
                        ? "Rate clips 👍 / 👎 in AI Clips and PULSE learns what you like. Nothing learned yet."
                        : app.settings.ai.taste.summaryLines.joined(separator: "\n")) {
                Button("Reset") { app.settings.ai.taste = TasteProfile() }.buttonStyle(.pulse(.ghost, compact: true))
                    .disabled(app.settings.ai.taste.isEmpty)
            }
            SettingsRow("Speed ramp on the payoff", detail: "Shorts play 0.9× into the payoff and 1.1× out of it — a small push you feel more than see.") {
                Toggle("", isOn: $app.settings.ai.speedRamp).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
            SettingsRow("Read game banners", detail: "During analysis of gameplay, reads VICTORY, ELIMINATED, DOUBLE KILL, YOU DIED and the like off the screen so wins and deaths score as moments (about a minute per hour of video).") {
                Toggle("", isOn: $app.settings.ai.hudCues).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
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
        ("auto", "Automatic (detect per stream)"), ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("es-ES", "Spanish"), ("fr-FR", "French"), ("de-DE", "German"),
        ("it-IT", "Italian"), ("pt-BR", "Portuguese (Brazil)"), ("ja-JP", "Japanese"), ("ko-KR", "Korean"), ("zh-CN", "Chinese (Simplified)"),
    ]

    var body: some View {
        SettingsGroup("Music", footnote: "Your own licensed tracks are used first for Edit My VOD music (no credits needed); Creative Commons tracks fill in. Favourites and never-again tracks are set from a music clip's inspector.") {
            SettingsRow("Your own music folder", detail: app.settings.ai.musicFolder.isEmpty ? "Not set — Creative Commons / built-in only" : app.settings.ai.musicFolder) {
                HStack(spacing: 6) {
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.message = "Choose a folder of music you have the rights to use"
                        if panel.runModal() == .OK, let url = panel.url { app.settings.ai.musicFolder = url.path }
                    }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    if !app.settings.ai.musicFolder.isEmpty {
                        Button("Clear") { app.settings.ai.musicFolder = "" }.buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
            }
            if !app.settings.ai.blockedTrackIDs.isEmpty || !app.settings.ai.favoriteTrackIDs.isEmpty {
                SettingsRow("Track memory", detail: "\(app.settings.ai.favoriteTrackIDs.count) favourite\(app.settings.ai.favoriteTrackIDs.count == 1 ? "" : "s"), \(app.settings.ai.blockedTrackIDs.count) never again") {
                    Button("Forget all") { app.settings.ai.favoriteTrackIDs = []; app.settings.ai.blockedTrackIDs = [] }.buttonStyle(.pulse(.ghost, compact: true))
                }
            }
        }
        SettingsGroup("B-roll", footnote: "With the B-roll extra on, clips from this folder are cut in first (a file named after the mood — fail, hype, laugh, shocked — is picked for that mood); YouTube Creative Commons clips fill the rest.") {
            SettingsRow("Your own clips folder", detail: app.settings.ai.brollFolder.isEmpty ? "Not set — YouTube only" : app.settings.ai.brollFolder) {
                HStack(spacing: 6) {
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.message = "Choose a folder of your meme / reaction clips"
                        if panel.runModal() == .OK, let url = panel.url { app.settings.ai.brollFolder = url.path }
                    }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    if !app.settings.ai.brollFolder.isEmpty {
                        Button("Clear") { app.settings.ai.brollFolder = "" }.buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
            }
        }
        SettingsGroup("Meme pop-ups", footnote: "Edit My VOD pops one of these on the biggest moments of each kind. Leave a field empty for PULSE's default.") {
            ForEach(LongFormEditor.memeMoods, id: \.self) { mood in
                SettingsRow(mood.displayName, detail: "Default: \(LongFormEditor.defaultMemeText(for: mood))") {
                    TextField(LongFormEditor.defaultMemeText(for: mood), text: Binding(
                        get: { app.settings.ai.memeTexts[mood.rawValue] ?? "" },
                        set: { app.settings.ai.memeTexts[mood.rawValue] = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: 180)
                }
            }
        }
        SettingsGroup("Engine", footnote: TranscriptionEngineFactory.availabilitySummary(settings: app.settings.ai)) {
            SettingsRow("Transcription engine") {
                Picker("", selection: $app.settings.ai.transcriptionEngine) {
                    ForEach(TranscriptionEngineChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 240)
            }
            SettingsRow("Custom vocabulary", detail: "Game names, usernames and catchphrases speech-to-text should get right — comma-separated. Favoured while transcribing and corrected afterwards (“valerant” → “Valorant”).") {
                TextField("e.g. Valorant, xQc, Sea of Thieves", text: Binding(
                    get: { app.settings.ai.customVocabulary.joined(separator: ", ") },
                    set: { app.settings.ai.customVocabulary = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    .textFieldStyle(.roundedBorder).frame(width: 260)
            }
            SettingsRow("Language") {
                Picker("", selection: $app.settings.ai.transcriptionLanguage) {
                    ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden().frame(width: 240)
            }
        }
        SettingsGroup("whisper.cpp", footnote: "The downloadable PULSE app has whisper.cpp and the English base model built in. Leave these empty to use them, or point at your own build (e.g. `brew install whisper-cpp`) or model. Bigger models downloaded below are picked up automatically.") {
            SettingsRow("Executable") {
                pathField($app.settings.ai.whisperExecutablePath, placeholder: WhisperCppTranscriber.locateExecutable()?.path ?? "whisper-cli", directory: false)
            }
            SettingsRow("Model file") {
                pathField($app.settings.ai.whisperModelPath, placeholder: WhisperCppTranscriber.locateModel()?.path ?? "ggml-base.en.bin", directory: false)
            }
        }
        SettingsGroup("Whisper models", footnote: "Models are downloaded once from the official whisper.cpp repository on Hugging Face into ~/Library/Application Support/PULSE/Models. Only the model is downloaded — your audio never leaves this Mac.") {
            ForEach(WhisperModelInfo.catalog) { model in
                WhisperModelRow(model: model)
            }
        }
        SettingsGroup("Speakers", footnote: "Speaker detection runs on this Mac after transcription. With one microphone per person (a multi-camera podcast), use Detect Speakers in the transcript — the loudest mic decides, which is the most reliable.") {
            SettingsRow("Detect who's talking", detail: "Labels the transcript by speaker; you can rename or merge speakers later.") {
                Toggle("", isOn: $app.settings.ai.detectSpeakers).labelsHidden().toggleStyle(.switch).tint(Theme.ai)
            }
            SettingsRow("Number of speakers") {
                Picker("", selection: $app.settings.ai.speakerCount) {
                    Text("Automatic").tag(0)
                    ForEach(1...6, id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden().frame(width: 140)
                .disabled(!app.settings.ai.detectSpeakers)
            }
            SettingsRow("Voice model", detail: SpeakerDiarization.availableMethod == .neural
                        ? "Neural speaker embeddings (GE2E encoder from Resemblyzer, Apache-2.0) — recognises the same voice whatever is said."
                        : "Speaker model not found; using classic voice statistics (pitch + timbre).") {
                Text(SpeakerDiarization.availableMethod == .neural ? "Neural · on device" : "Classic")
                    .font(.pulseCaption).foregroundStyle(SpeakerDiarization.availableMethod == .neural ? Theme.ai : Theme.textSecondary)
            }
        }
        SettingsGroup("Import instead") {
            Text("Already have captions? Import an SRT or VTT file on the Import page and PULSE will use it as the transcript — no transcription needed.")
                .font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WhisperModelRow: View {
    @EnvironmentObject var app: AppModel
    let model: WhisperModelInfo
    @State private var installed = false

    var downloadJob: BackgroundJob? {
        app.jobs.running.first { $0.title == "Download \(model.name)" }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name).font(.pulseBody).foregroundStyle(Theme.textPrimary)
                    if app.settings.ai.whisperModelPath == model.localURL.path { TagChip(text: "In use", color: Theme.success) }
                }
                Text("\(model.sizeMB >= 1000 ? String(format: "%.1f GB", Double(model.sizeMB) / 1000) : "\(model.sizeMB) MB") · \(model.note) · \(estimate)")
                    .font(.pulseCaption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if let job = downloadJob {
                ThinProgressBar(progress: job.progress, color: Theme.info).frame(width: 90, height: 4)
                Button("Cancel") { job.cancel() }.buttonStyle(.pulse(.ghost, compact: true))
            } else if installed {
                if app.settings.ai.whisperModelPath != model.localURL.path {
                    Button("Use") { app.settings.ai.whisperModelPath = model.localURL.path }
                        .buttonStyle(.pulse(.secondary, compact: true))
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting([model.localURL]) } label: { Image(systemName: "folder") }
                    .buttonStyle(.pulse(.ghost, compact: true))
                if model.bundledURL == nil {
                    Button { deleteModel() } label: { Image(systemName: "trash") }
                        .buttonStyle(.pulse(.ghost, compact: true))
                        .help("Delete the downloaded model file (#442)")
                        .accessibilityLabel("Delete model")
                }
            } else if model.bundledURL != nil {
                TagChip(text: "Built in", color: Theme.success)
                    .help("Ships inside PULSE — nothing to download")
            } else {
                Button("Download") { download() }.buttonStyle(.pulse(.secondary, compact: true))
            }
        }
        .onAppear { installed = model.isInstalled }
    }

    /// "≈ 4 min per hour of video" on this Mac (#38), from the learned speed profile and the model's factor
    /// relative to the one in use.
    var estimate: String {
        let inUse = WhisperModelInfo.catalog.first { app.settings.ai.whisperModelPath == $0.localURL.path }
        let minutes = app.settings.ai.analysisSpeed.transcriptionMinutesPerHour(modelFactor: model.speedFactor, learnedFactor: inUse?.speedFactor ?? 1)
        return minutes < 1 ? "under a minute per hour of video" : "≈ \(Int(minutes.rounded())) min per hour of video"
    }

    func deleteModel() {
        guard app.settings.ai.whisperModelPath != model.localURL.path else { return app.toast("This model is in use — pick another first") }
        try? FileManager.default.removeItem(at: model.localURL)
        installed = model.isInstalled
        app.toast("\(model.name) deleted")
    }

    func download() {
        let model = self.model
        app.jobs.start("Download \(model.name)", kind: .transcription) { job in
            job.detail = "\(model.sizeMB) MB"
            let url = try await WhisperModelDownloader.download(model, progress: { p in
                Task { @MainActor in job.progress = p }
            }, isCancelled: job.isCancelledCheck)
            app.settings.ai.whisperModelPath = url.path
            installed = true
            app.toast("\(model.name) model ready for transcription")
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
        SettingsGroup("Watch folder", footnote: "Anything that lands in this folder is imported into the open project (or a new one named after the file). With a nightly hour set, the day's recordings run through the overnight batch — shorts and a YouTube edit by morning.") {
            SettingsRow("Folder") {
                pathField($app.settings.watchFolder, placeholder: "None", directory: true)
            }
            SettingsRow("Analyze on arrival") {
                Toggle("", isOn: $app.settings.watchFolderAnalyzes).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("Nightly batch") {
                Picker("", selection: Binding(get: { app.settings.nightlyBatchHour ?? -1 }, set: { app.settings.nightlyBatchHour = $0 < 0 ? nil : $0 })) {
                    Text("Off").tag(-1)
                    ForEach([0, 1, 2, 3, 4, 5, 22, 23], id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
                }
                .labelsHidden().frame(width: 120)
            }
        }
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
            ForEach(info.cacheBreakdown) { folder in
                HStack(spacing: 8) {
                    Text(folder.name).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: folder.bytes, countStyle: .file)).font(.pulseMono).foregroundStyle(Theme.textTertiary)
                    Button("Clear") { app.clearCacheFolder(folder.name) }.buttonStyle(.pulse(.ghost, compact: true))
                        .help("Safe: everything in here comes back when it's needed")
                }
            }
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
                Button("Clear Audio Renders") { app.clearEnhancedAudioCache() }.buttonStyle(.pulse(.secondary, compact: true))
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
            SettingsRow("Viewer quality", detail: "How large the viewer renders each frame; exports always render in full.") {
                Picker("", selection: Binding(get: { app.settings.playbackQuality }, set: { q in
                    app.settings.playbackQuality = q
                    app.session?.setPlaybackQuality(q)
                })) {
                    ForEach(PlaybackQuality.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            SettingsRow("Drop a step when playback stutters", detail: "PULSE steps the viewer down on its own when it can't keep up, and says so.") {
                Toggle("", isOn: $app.settings.autoPlaybackQuality).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
        }
    }
}

// MARK: Shortcuts

/// What PULSE has done for you so far (#478). Counted on this Mac, never sent anywhere.
struct StatisticsPane: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let stats = app.settings.stats
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Statistics")
            if stats.isEmpty {
                Text("Nothing yet — build a short or edit a VOD and the numbers start here.").font(.pulseCaption).foregroundStyle(Theme.textTertiary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 10)], spacing: 10) {
                    ForEach(Array(stats.lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(line.label.hasPrefix("Hours") ? Theme.ai : Theme.textPrimary)
                            Text(line.label).font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
                    }
                }
                if let since = stats.since {
                    Text("Since \(since.formatted(date: .abbreviated, time: .omitted)). Hours saved is an estimate: about 12 minutes per short, 90 per YouTube edit, twice real time for cutting dead air by hand and half real time for scrubbing a VOD.")
                        .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                Button("Reset Statistics") { app.settings.stats = LifetimeStats() }.buttonStyle(.pulse(.ghost, compact: true))
            }
        }
    }
}

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

    /// A printable page of every shortcut (#451), opened in the browser.
    static func html() -> String {
        var rows = ""
        for group in groups {
            rows += "<h2>\(group.0)</h2><table>"
            for item in group.1 { rows += "<tr><td class=k>\(item.0)</td><td>\(item.1)</td></tr>" }
            rows += "</table>"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>PULSE shortcuts</title>
        <style>body{font:13px -apple-system,Helvetica,Arial;margin:32px;color:#111}h1{font-size:22px}h2{font-size:14px;margin:18px 0 6px;text-transform:uppercase;letter-spacing:.06em;color:#555}
        table{border-collapse:collapse;width:100%}td{padding:4px 8px;border-bottom:1px solid #eee}td.k{font-family:ui-monospace,Menlo,monospace;white-space:nowrap;width:140px;font-weight:600}
        @media print{body{margin:12mm}}</style></head><body><h1>PULSE keyboard shortcuts</h1>\(rows)<p style="color:#888;margin-top:24px">PULSE \(AppModel.versionString) · press ⌘P to print</p></body></html>
        """
    }

    func printSheet() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PULSE Shortcuts.html")
        try? Self.html().write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }

    var body: some View {
        HStack {
            Spacer()
            Button { printSheet() } label: { Label("Printable Cheat Sheet", systemImage: "printer") }
                .buttonStyle(.pulse(.secondary, compact: true))
                .help("Opens every shortcut as a page you can print or keep next to the keyboard (#451)")
        }
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

/// Settings → Brand Kit: logo, intro/outro and caption look applied to every new edit.
struct BrandKitSettings: View {
    @EnvironmentObject var app: AppModel

    var kit: Binding<BrandKit> { $app.settings.brandKit }

    var body: some View {
        SettingsGroup("Brand kit", footnote: "When on, new shorts and Edit My VOD videos get your look automatically. Apply it to any open edit from the Inspector (no clip selected).") {
            SettingsRow("Use my brand kit on new edits") {
                Toggle("", isOn: kit.enabled).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            }
            SettingsRow("See it on the sample project", detail: "Builds the sample short with your logo, intro card and caption look applied (#372).") {
                Button("Preview…") { app.brandKitPreviewPending = true; app.openDemoProject() }.buttonStyle(.pulse(.secondary, compact: true))
                    .disabled(!app.settings.brandKit.hasAnything)
            }
        }
        SettingsGroup("Logo watermark", footnote: "A PNG with transparency looks best. On shorts it stays clear of the platform's top bar and the captions.") {
            SettingsRow("Logo image") {
                HStack(spacing: 8) {
                    if !app.settings.brandKit.logoPath.isEmpty, let image = NSImage(contentsOfFile: app.settings.brandKit.logoPath) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 28)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.well))
                    }
                    pickButton(kit.logoPath, types: ["png", "jpg", "jpeg", "heic", "tiff"])
                }
            }
            SettingsRow("Corner") {
                Picker("", selection: kit.logoCorner) {
                    ForEach(BrandKit.Corner.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().frame(width: 160)
            }
            LabeledSlider(label: "Size", value: Binding(get: { app.settings.brandKit.logoSize * 100 }, set: { app.settings.brandKit.logoSize = $0 / 100 }),
                          range: 5...35, format: "%.0f", unit: "%")
            LabeledSlider(label: "Opacity", value: Binding(get: { app.settings.brandKit.logoOpacity * 100 }, set: { app.settings.brandKit.logoOpacity = $0 / 100 }),
                          range: 10...100, format: "%.0f", unit: "%")
            SettingsRow("Show on shorts") { Toggle("", isOn: kit.logoOnShorts).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
            SettingsRow("Show on YouTube edits") { Toggle("", isOn: kit.logoOnLongForm).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
        }
        SettingsGroup("Intro & outro", footnote: "Added to YouTube edits (Edit My VOD) only — an intro on a 30-second short costs viewers.") {
            SettingsRow("Intro clip") { pickButton(kit.introPath, types: ["mov", "mp4", "m4v"]) }
            SettingsRow("Outro clip") { pickButton(kit.outroPath, types: ["mov", "mp4", "m4v"]) }
            SettingsRow("Intro card", detail: "No intro clip? A 3-second name card instead: a dark slate, your name sliding up, a fade into the first shot.") {
                TextField("Your name", text: kit.bumperName).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            if !app.settings.brandKit.bumperName.isEmpty {
                SettingsRow("Show my handle on it", detail: app.settings.ai.socialHandle.isEmpty ? "Set your handle under AI Features → One-click shorts." : "@\(app.settings.ai.socialHandle.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")))") {
                    Toggle("", isOn: kit.bumperShowsHandle).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                }
            }
        }
        SettingsGroup("Caption look") {
            SettingsRow("Caption style") {
                Picker("", selection: kit.captionPresetName) {
                    Text("Use the AI setting").tag("")
                    ForEach(CaptionStyle.presets, id: \.presetName) { Text($0.presetName).tag($0.presetName) }
                }
                .labelsHidden().frame(width: 200)
            }
            SettingsRow("Colours", detail: "Three colours for the cards PULSE places: text, outline, and the slates behind the end screen and intro card (#364).") {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        ColorPicker("", selection: Binding(get: { Color(app.settings.brandKit.palette.indices.contains(i) ? app.settings.brandKit.palette[i] : (i == 0 ? .white : (i == 1 ? .black : RGBAColor(hex: "#0E0E12")!))) },
                                                           set: { color in
                                                               var palette = app.settings.brandKit.palette
                                                               while palette.count <= i { palette.append(palette.count == 0 ? .white : (palette.count == 1 ? .black : RGBAColor(hex: "#0E0E12")!)) }
                                                               palette[i] = color.rgba
                                                               app.settings.brandKit.palette = palette
                                                           }), supportsOpacity: false)
                            .labelsHidden()
                            .help(i == 0 ? "Text on cards" : (i == 1 ? "Outline on cards" : "Slates"))
                    }
                    if !app.settings.brandKit.palette.isEmpty {
                        Button("Clear") { app.settings.brandKit.palette = [] }.buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
            }
            SettingsRow("Typeface", detail: "For cards and captions (#370); empty keeps each preset's own.") {
                HStack(spacing: 6) {
                    TextField("TikTok Sans", text: kit.fontName).textFieldStyle(.roundedBorder).frame(width: 150)
                    Menu {
                        ForEach(["TikTok Sans", "Inter", "Montserrat", "Helvetica Neue", "Avenir Next", "Futura", "Impact", "SF Pro Display"], id: \.self) { name in
                            Button(name) { app.settings.brandKit.fontName = name }
                        }
                        Divider()
                        Button("None") { app.settings.brandKit.fontName = "" }
                    } label: { Image(systemName: "textformat") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                }
            }
            SettingsRow("Highlight color", detail: "The color of the word being spoken.") {
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(get: { Color(app.settings.brandKit.highlightColor ?? .yellow) },
                                                       set: { app.settings.brandKit.highlightColor = $0.rgba }), supportsOpacity: false)
                        .labelsHidden()
                    if app.settings.brandKit.highlightColor != nil {
                        Button("Clear") { app.settings.brandKit.highlightColor = nil }.buttonStyle(.pulse(.ghost, compact: true))
                    }
                }
            }
        }
        if let session = app.session, let timeline = session.activeTimeline {
            SettingsGroup("Try it") {
                SettingsRow("Apply to “\(timeline.name)”") {
                    Button("Apply Now") { session.applyBrandKit(to: timeline.id) }.buttonStyle(.pulse(.primary, compact: true))
                }
            }
        }
    }

    func pickButton(_ path: Binding<String>, types: [String]) -> some View {
        HStack(spacing: 6) {
            Text(path.wrappedValue.isEmpty ? "None" : (path.wrappedValue as NSString).lastPathComponent)
                .font(.pulseCaption).foregroundStyle(path.wrappedValue.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1).frame(maxWidth: 180, alignment: .trailing)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
                if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
            }
            .buttonStyle(.pulse(.secondary, compact: true))
            if !path.wrappedValue.isEmpty {
                Button { path.wrappedValue = "" } label: { Image(systemName: "xmark") }.buttonStyle(.pulse(.ghost, compact: true)).help("Remove")
            }
        }
    }
}

/// Settings → Performance: match real views to what PULSE predicted, and calibrate the coach to your channel.
struct PerformanceSettings: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject private var memory = MemoryPressure.shared
    @State private var lastImport: String?
    @State private var footprint: String = MemoryPressure.footprintDescription

    var withViews: [PerformanceRecord] { app.performanceHistory.filter { $0.views != nil }.sorted { ($0.views ?? 0) > ($1.views ?? 0) } }

    var body: some View {
        SettingsGroup("Analysis", footnote: "Local transcription uses every core but two by default; fewer keeps the Mac snappier while it runs.") {
            SettingsRow("Transcription threads") {
                Picker("", selection: $app.settings.ai.analysisThreads) {
                    Text("Automatic").tag(0)
                    ForEach([2, 4, 6, 8], id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden().frame(width: 130)
            }
        }
        SettingsGroup("Memory", footnote: "Decoded thumbnails and filmstrip frames stay in memory up to this ceiling; PULSE empties them on its own when the Mac runs short.") {
            SettingsRow("Frame cache ceiling") {
                Picker("", selection: $app.settings.thumbnailCacheMB) {
                    ForEach([100, 200, 400, 800], id: \.self) { Text("\($0) MB").tag($0) }
                }
                .labelsHidden().frame(width: 130)
            }
            SettingsRow("Right now", detail: memory.lastWarning.map { "Last memory warning \($0.formatted(date: .omitted, time: .shortened))" } ?? "No memory warnings this session.") {
                HStack(spacing: 8) {
                    Text(footprint).font(.pulseMono).foregroundStyle(Theme.textSecondary)
                    TagChip(text: memory.level.displayName.uppercased(), color: memory.level == .normal ? Theme.success : Theme.warning)
                    Button { footprint = MemoryPressure.footprintDescription } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.pulse(.ghost, compact: true)).help("Refresh")
                }
            }
        }
        SettingsGroup("Calibrate the score with your real views", footnote: "Every export remembers what PULSE predicted. Import an analytics export and PULSE matches the videos by title, then re-weights the coach toward what actually worked on your channel (after 5 matched videos of a format). Only titles and numbers are read.") {
            SettingsRow("Analytics export", detail: "YouTube Studio → Analytics → Advanced mode → Export (CSV), or TikTok's analytics export.") {
                Button("Import CSV…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType.commaSeparatedText, .plainText]
                    if panel.runModal() == .OK, let url = panel.url {
                        let result = app.importAnalytics(url)
                        lastImport = result.rows == 0 ? "Couldn't find title and views columns in that file."
                            : "Read \(result.rows) videos, matched \(result.matched) to your PULSE exports."
                    }
                }
                .buttonStyle(.pulse(.primary, compact: true))
            }
            if let lastImport { Text(lastImport).font(.pulseCaption).foregroundStyle(Theme.textSecondary) }
            SettingsRow("Status") {
                let c = app.settings.ai.coachCalibration
                Text(c.map { $0.samples > 0 ? "Calibrated: \($0.shortSamples) shorts, \($0.longSamples) YouTube videos" : "Not enough matches yet" } ?? "Using PULSE's default weights")
                    .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
            }
            if let insight = app.settings.ai.coachCalibration?.insight, !insight.isEmpty {
                Label(insight, systemImage: "lightbulb").font(.pulseCaption).foregroundStyle(Theme.ai)
            }
            SettingsRow("Exports remembered", detail: "\(app.performanceHistory.count) exported edits · \(withViews.count) with real views") {
                Button("Reset Calibration") { app.resetCalibration() }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    .disabled(app.settings.ai.coachCalibration == nil)
            }
        }
        if !withViews.isEmpty {
            SettingsGroup("Matched videos") {
                ForEach(withViews.prefix(25)) { record in
                    HStack {
                        Text(record.titles.first ?? "Untitled").font(.pulseCaption).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer()
                        Text("predicted \(record.predictedScore)").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                        Text("\(Int(record.views ?? 0).formatted()) views").font(.pulseMono).foregroundStyle(Theme.textSecondary)
                            .frame(width: 110, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: Diagnostics

/// What support would ask for, on one page, with a copy button (#447).
struct DiagnosticsPane: View {
    @EnvironmentObject var app: AppModel
    @State private var text = ""

    var body: some View {
        SettingsGroup("Diagnostics", footnote: "Nothing here is sent anywhere by itself. Copy it into a bug report if PULSE asks.") {
            HStack {
                Button { app.refreshDiskInfo(); text = app.diagnosticsText() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.pulse(.secondary, compact: true))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    app.toast("Diagnostics copied")
                } label: { Label("Copy for support", systemImage: "doc.on.doc") }
                    .buttonStyle(.pulse(.primary, compact: true))
                Button("Open Log Folder") { NSWorkspace.shared.open(PulseLog.directory) }.buttonStyle(.pulse(.ghost, compact: true))
            }
            ScrollView {
                Text(text.isEmpty ? "Gathering…" : text)
                    .font(.pulseMono).foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 360)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.control))
        }
        .onAppear { text = app.diagnosticsText() }
    }
}

// MARK: Privacy

/// What leaves the Mac, in plain words, with the current state of each switch (#452).
struct PrivacyPane: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        SettingsGroup("What leaves your Mac", footnote: "Video, audio, transcripts and projects stay on this Mac. Nothing is uploaded unless a line below says so, and each one has its own switch.") {
            line("Analysis, transcription, captions, edits, exports", on: false, detail: "On this Mac, always. Whisper and Apple Speech run locally.")
            line("Cloud AI (titles, captions rewrite)", on: app.settings.ai.cloudProvider != .none,
                 detail: app.settings.ai.cloudProvider == .none ? "Off — PULSE's local generator is used." : "Only transcript text goes to \(app.settings.ai.cloudProvider.displayName), and only when you ask (policy: \(app.settings.ai.processingPolicy)).")
            line("Creative Commons music and B-roll", on: app.settings.ai.onlineMusic || app.settings.ai.editExtras.brollClips,
                 detail: "Searches and downloads go to youtube.com / googlevideo.com. Nothing about your video is sent — only the mood words.")
            line("Update check", on: true, detail: "Help → Check for Updates reads GitHub Releases. No identifiers are sent.")
            line("Report a Problem", on: false, detail: "Only when you send one, and you see the text and log first.")
        }
    }

    func line(_ title: String, on: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: on ? "arrow.up.circle.fill" : "lock.fill").foregroundStyle(on ? Theme.warning : Theme.success).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.pulseBody).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// What the Mac plays sound through, with a warning when it's a poor place to judge a mix (#283).
struct MonitoringNoteRow: View {
    @State private var reading: AudioOutput.Reading?

    var body: some View {
        SettingsRow("Monitoring", detail: detail) {
            Button { reading = AudioOutput.current() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.pulse(.ghost, compact: true))
                .help("Check again")
                .accessibilityLabel("Check the output device again")
        }
        .onAppear { reading = AudioOutput.current() }
    }

    var detail: String {
        guard let reading else { return "Couldn't read the output device." }
        return MixingAdvice.line(outputName: reading.name, kind: reading.kind) ?? "Listening through \(reading.name) — fine for judging a mix."
    }
}

/// Which library sound PULSE uses for a job (#105).
struct EffectChoiceRow: View {
    @EnvironmentObject var app: AppModel
    let job: String
    let category: String
    let title: String
    let detail: String

    var choice: Binding<String> {
        Binding(get: { app.settings.ai.preferredEffects[job] ?? "" },
                set: { app.settings.ai.preferredEffects[job] = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        SettingsRow(title, detail: detail) {
            Picker("", selection: choice) {
                Text("PULSE’s pick").tag("")
                ForEach(SoundLibrary.effects.filter { $0.category == category }) { Text($0.name).tag($0.name) }
            }
            .labelsHidden().frame(width: 170)
        }
    }
}
