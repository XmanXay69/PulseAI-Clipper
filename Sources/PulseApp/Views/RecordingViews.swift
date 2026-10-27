import AVFoundation
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
                    BusyLine("Finding screens and windows…")
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
                SectionLabel(text: "Setup")
                HStack(spacing: 6) {
                    ForEach(RecordingPreset.allCases, id: \.self) { preset in
                        Button(preset.displayName) { recorder.apply(preset) }
                            .buttonStyle(.pulse(.secondary, compact: true))
                            .help(preset.detail)
                    }
                }
                if let estimate = recorder.diskEstimate {
                    Text("About \(estimate) at these settings (#319).").font(.pulseMicro).foregroundStyle(Theme.textTertiary)
                }
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
                // See yourself before you press record, with a guide for where your face should sit (#324).
                if let cameraID = recorder.cameraID, recorder.phase == .idle {
                    CameraPreview(deviceID: cameraID)
                        .overlay(FaceGuide())
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
                        .help("Line your face up inside the guide — the facecam crop PULSE cuts later is centred on it")
                }
                SectionLabel(text: "Video")
                Picker("Frame rate", selection: $recorder.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Picker("Codec", selection: $recorder.codec) {
                    Text("HEVC (smaller)").tag(VideoCodec.hevc)
                    Text("H.264 (shares anywhere)").tag(VideoCodec.h264)
                }
                .pickerStyle(.segmented)
                Picker("Split files", selection: Binding(get: { app.settings.recordingSplitGB }, set: { app.settings.recordingSplitGB = $0 })) {
                    Text("Never").tag(0.0)
                    Text("Every 2 GB").tag(2.0)
                    Text("Every 4 GB").tag(4.0)
                    Text("Every 8 GB").tag(8.0)
                    Text("Every 16 GB").tag(16.0)
                }
                .help("A long recording is cut into parts under this size when it stops (no re-encoding) and the parts are joined back together on one timeline, so a single file never outgrows a disk or a sync folder (#322)")
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
                    .onAppear { withAnimation(Theme.motion(.easeInOut(duration: 0.8).repeatForever())) { pulse = true } }
                Text(paused ? "PAUSED" : "REC").font(.system(size: 11, weight: .heavy)).foregroundStyle(paused ? Theme.warning : Theme.danger)
                Text(Timecode.duration(recorder.elapsed)).font(.pulseTimecode).foregroundStyle(.white)
                RecordingMeter(levelDB: recorder.audioLevelDB)
                Button { recorder.markMoment() } label: {
                    Label(recorder.markedMoments.isEmpty ? "Clip it" : "Clip it · \(recorder.markedMoments.count)", systemImage: "flag.fill")
                }
                .buttonStyle(.pulse(.primary, compact: true))
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(paused)
                .help("Mark this moment — the AI treats it as a sure thing (⇧⌘M)")
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
                if group.videoAngles.contains(where: { $0.role == .gameplay || !$0.hasAudio }) {
                    Button { session.createMulticamEdit(groupID: group.id, auto: true, pip: true) } label: { Label("Game + Cam", systemImage: "pip") }
                        .buttonStyle(.pulse(.secondary, compact: true))
                        .help("The game stays full-frame and whoever is talking sits small in the corner (#328)")
                }
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


/// A small level bar for the recording HUD (#323): green, amber over −12 dBFS, red at clipping.
struct RecordingMeter: View {
    let levelDB: Float

    var body: some View {
        let fraction = CGFloat(max(0, min(1, (levelDB + 60) / 60)))
        let color: Color = levelDB > -1 ? Theme.danger : (levelDB > -12 ? Theme.warning : Theme.success)
        HStack(spacing: 5) {
            Image(systemName: "mic.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(color).frame(width: max(2, 60 * fraction))
            }
            .frame(width: 60, height: 5)
        }
        .help(levelDB > -1 ? "Clipping — turn the microphone down" : String(format: "%.0f dBFS", levelDB))
        .accessibilityLabel("Audio level")
    }
}

/// A live view of the chosen webcam before recording starts (#324).
struct CameraPreview: NSViewRepresentable {
    let deviceID: String

    func makeNSView(context: Context) -> CameraPreviewNSView { CameraPreviewNSView() }

    func updateNSView(_ view: CameraPreviewNSView, context: Context) { view.show(deviceID: deviceID) }

    static func dismantleNSView(_ view: CameraPreviewNSView, coordinator: ()) { view.stop() }
}

final class CameraPreviewNSView: NSView {
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var currentID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    func show(deviceID: String) {
        guard deviceID != currentID else { return }
        currentID = deviceID
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        if let device = AVCaptureDevice(uniqueID: deviceID), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { if session.isRunning { session.stopRunning() } }
    }
}

/// An oval where the face should be, plus the eye line a third of the way down.
struct FaceGuide: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse()
                    .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: h * 0.42, height: h * 0.6)
                    .position(x: w / 2, y: h * 0.47)
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: w * 0.6, height: 1).position(x: w / 2, y: h * 0.38)
                Text("Eyes on the line, face in the oval").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(.black.opacity(0.45)))
                    .position(x: w / 2, y: h - 12)
            }
        }
        .allowsHitTesting(false)
    }
}
