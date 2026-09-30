import SwiftUI
import PulseCore
import PulseEngine

@main
struct PulseMain: App {
    var body: some Scene {
        WindowGroup("PULSE") {
            Text("PULSE \(PulseEngineInfo.version)")
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}
