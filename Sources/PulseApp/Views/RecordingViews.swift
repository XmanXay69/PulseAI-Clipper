import PulseCore
import PulseEngine
import SwiftUI

/// "Record" sheet: pick a display/window, system audio, webcam and mic, then record.
struct RecordView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var recorder: RecordingController
    @Environment(\.dismiss) private var dismiss

    init(recorder: RecordingController) {
        self.recorder = recorder
    }

    var displays: [CaptureSource] { recorder.sources.filter { $0.kind == .display } }
    var windows: [CaptureSource] { recorder.sources.filter { $0.kind == .window } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "record.circle").font(.system(size: 20)).foregroundStyle(Theme.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Recording").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
                    Text("Screen, system audio, webcam and mic are saved as separate synced files — perfect for gameplay + facecam shorts.")
                        .font(.pulseCaption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                ProcessingBadge(location: .local)
            }
            .padding(18)
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                sourcePicker.frame(maxWidth: .infinity)
                Rectangle().fill(Theme.divider).frame(width: 1)
                optionsPanel.frame(width: 300)
            }
            .frame(height: 400)
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack {
                Text("Saves to \(recorder.outputDirectory(app: app).path)").font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.pulse(.ghost))
                Button {
                    recorder.start(app: app)
                    dismiss()
                } label: { Label("Start Recording", systemImage: "record.circle") }
                    .buttonStyle(.pulse(.destructive))
                    .keyboardShortcut(.defaultAction)
                    .disabled(recorder.selectedSourceID == nil || recorder.isActive)
            }
            .padding(14)
        }
        .frame(width: 820)
        .background(Theme.panel)
        .onAppear { recorder.refreshDevices() }
    }

    var sourcePicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if recorder.isLoadingSources {
                    HStack { ProgressView().controlSize(.small); Text("Finding screens and windows…").font(.pulseCaption).foregroundStyle(Theme.textSecondary) }
                } else if let error = recorder.loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Screen Recording permission needed", systemImage: "lock.shield").font(.pulseHeadline).foregroundStyle(Theme.warning)
                        Text(error).font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open System Settings") { RecordingController.openScreenRecordingSettings() }.buttonStyle(.pulse(.secondary, compact: true))
                            Button("Try Again") { recorder.refreshDevices() }.buttonStyle(.pulse(.ghost, compact: true))
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.panelRaised))
                }
                if !displays.isEmpty {
                    SectionLabel(text: "Displays")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(displays) { source in sourceTile(source, symbol: "display") }
                    }
                }
                if !windows.isEmpty {
                    SectionLabel(text: "Windows")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(windows) { source in sourceTile(source, symbol: "macwindow") }
                    }
                }
            }
            .padding(16)
        }
    }

    func sourceTile(_ source: CaptureSource, symbol: String) -> some View {
        let selected = recorder.selectedSourceID == source.id
        return Button { recorder.selectedSourceID = source.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                Text(source.title).font(.pulseCaption.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(source.subtitle).font(.pulseMicro).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(selected ? Theme.accentSoft : Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(selected ? Theme.accent : Theme.border))
        }
        .buttonStyle(.plain)
    }

    var optionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Audio & camera")
                ToggleRow(label: "System audio (game, browser…)", isOn: $recorder.captureSystemAudio)
                Picker("Microphone", selection: $recorder.microphoneID) {
                    Text("None").tag(String?.none)
                    ForEach(recorder.microphones) { Text($0.name).tag(String?.some($0.id)) }
                }
                .font(.pulseCaption)
                Picker("Webcam", selection: $recorder.cameraID) {
                    Text("None").tag(String?.none)
                    ForEach(recorder.cameras) { Text($0.name).tag(String?.some($0.id)) }
                }
                .font(.pulseCaption)
                if recorder.cameras.isEmpty {
                    Text("No camera found.").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
                SectionLabel(text: "Video")
                Picker("Frame rate", selection: $recorder.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                ToggleRow(label: "Show cursor", isOn: $recorder.showsCursor)
                ToggleRow(label: "Hide PULSE from the recording", isOn: $recorder.hidePulse)
                ToggleRow(label: "3-second countdown", isOn: $recorder.countdown)
                SectionLabel(text: "After recording")
                ToggleRow(label: "Analyze & find clips automatically", isOn: $recorder.analyzeAfter)
                Text("Stop from the red bar at the top of PULSE or with ⇧⌘R.")
                    .font(.pulseMicro).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }
}

/// Floating bar shown while counting down / recording / saving.
struct RecordingHUD: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var recorder: RecordingController
    @State private var pulse = false

    var body: some View {
        switch recorder.phase {
        case .idle:
            EmptyView()
        case .countdown(let n):
            HStack(spacing: 12) {
                Text("\(n)").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Recording starts…").font(.pulseBody).foregroundStyle(.white.opacity(0.8))
                Button("Cancel") { recorder.cancelCountdown() }.buttonStyle(.pulse(.ghost, compact: true))
            }
            .modifier(HUDBackground())
        case .recording, .paused:
            let paused = recorder.phase == .paused
            HStack(spacing: 10) {
                Circle().fill(paused ? Theme.warning : Theme.danger).frame(width: 10, height: 10)
                    .opacity(pulse && !paused ? 0.35 : 1)
                    .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
                Text(paused ? "PAUSED" : "REC").font(.system(size: 11, weight: .heavy)).foregroundStyle(paused ? Theme.warning : Theme.danger)
                Text(Timecode.duration(recorder.elapsed)).font(.pulseTimecode).foregroundStyle(.white)
                Button { recorder.togglePause() } label: {
                    Label(paused ? "Resume" : "Pause", systemImage: paused ? "record.circle" : "pause.fill")
                }
                .buttonStyle(.pulse(.secondary, compact: true))
                .help(paused ? "Resume recording (⇧⌘P)" : "Pause recording (⇧⌘P) — the files continue without a gap")
                Button { recorder.stop(app: app) } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.pulse(.destructive, compact: true))
                    .help("Stop recording (⇧⌘R)")
            }
            .modifier(HUDBackground())
        case .finishing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Saving recording…").font(.pulseBody).foregroundStyle(.white)
            }
            .modifier(HUDBackground())
        }
    }
}

struct HUDBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.85)))
            .overlay(Capsule().strokeBorder(Theme.danger.opacity(0.6)))
            .shadow(color: .black.opacity(0.4), radius: 12)
            .padding(.top, 10)
    }
}

/// Offered on the Import page when the project holds a synchronized multi-camera session.
struct MulticamSessionCard: View {
    @ObservedObject var session: ProjectSession
    let group: MulticamGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "video.badge.checkmark").foregroundStyle(Theme.info)
                Text("Multicam session · \(group.videoAngles.count) angles").font(.pulseHeadline).foregroundStyle(Theme.textPrimary)
            }
            Text(group.videoAngles.map(\.name).joined(separator: " · "))
                .font(.pulseCaption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            HStack(spacing: 8) {
                Button { session.createMulticamEdit(groupID: group.id, auto: true) } label: { Label("AI Multicam", systemImage: "sparkles") }
                    .buttonStyle(.pulse(.ai, compact: true))
                    .help("Cuts to whoever is talking (each camera's own mic), wide shot when nobody or everybody talks")
                Button { session.createMulticamEdit(groupID: group.id, auto: false) } label: { Label("Switch Manually", systemImage: "video") }
                    .buttonStyle(.pulse(.secondary, compact: true))
                    .help("Opens an editable multicam timeline — press 1–9 while playing to cut live")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusLarge).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).strokeBorder(Theme.border))
    }
}
