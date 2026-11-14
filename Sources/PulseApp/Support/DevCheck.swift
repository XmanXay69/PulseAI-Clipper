#if PULSE_DEV
import Foundation
import PulseCore

/// DEV BUILD ONLY. `PULSE --claude-check`: finds the Claude Code command, asks it for one word under the
/// owner's login and says what happened, in a line a script can read (`CLAUDE-CHECK ok …` or
/// `CLAUDE-CHECK failed: …`). Exits 0 when Claude answered.
enum DevCheck {
    @MainActor static func run() -> Never {
        let settings = AppModel.loadSettings().ai
        let model = settings.cloudModel.isEmpty ? "claude-opus-5-5" : settings.cloudModel
        guard let executable = ClaudeCodeCLI.locate(custom: settings.claudeCodePath) else {
            print("CLAUDE-CHECK failed: \(ClaudeCodeCLI.notInstalled)")
            exit(2)
        }
        let provider = ClaudeCodeProvider(model: model, executable: executable)
        Task.detached {
            do {
                let served = try await provider.check()
                print("CLAUDE-CHECK ok command=\(executable.path) asked=\(model) answered=\(served)")
                exit(0)
            } catch {
                print("CLAUDE-CHECK failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                exit(1)
            }
        }
        // The answer arrives on another thread, which ends the program.
        while true { Thread.sleep(forTimeInterval: 1) }
    }
}
#endif
