import AppKit
import Combine
import Foundation

/// A red dot and the elapsed time in the menu bar while PULSE records (#321), with Stop and Pause in its
/// menu — so a recording stays visible with PULSE behind the game.
@MainActor
final class RecordingStatusItem: NSObject {
    private let recording: RecordingController
    private weak var app: AppModel?
    private var item: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private let menu = NSMenu()
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(RecordingStatusItem.togglePause), keyEquivalent: "")

    init(recording: RecordingController, app: AppModel) {
        self.recording = recording
        self.app = app
        super.init()
        let stop = NSMenuItem(title: "Stop Recording", action: #selector(RecordingStatusItem.stop), keyEquivalent: "")
        stop.target = self
        pauseItem.target = self
        menu.addItem(stop)
        menu.addItem(pauseItem)
        recording.$phase.combineLatest(recording.$elapsed)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, elapsed in self?.update(phase: phase, elapsed: elapsed) }
            .store(in: &cancellables)
    }

    private func update(phase: RecordingController.Phase, elapsed: TimeInterval) {
        switch phase {
        case .recording, .paused:
            if item == nil {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item?.menu = menu
            }
            let minutes = Int(elapsed) / 60, seconds = Int(elapsed) % 60
            let mark = phase == .paused ? "⏸" : "●"
            item?.button?.title = String(format: "%@ %d:%02d", mark, minutes, seconds)
            item?.button?.contentTintColor = phase == .paused ? .systemOrange : .systemRed
            item?.button?.toolTip = phase == .paused ? "PULSE recording paused" : "PULSE is recording"
            pauseItem.title = phase == .paused ? "Resume" : "Pause"
        default:
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }

    @objc private func stop() {
        guard let app else { return }
        recording.stop(app: app)
    }

    @objc private func togglePause() {
        if recording.phase == .paused { recording.resume() } else { recording.pause() }
    }
}
