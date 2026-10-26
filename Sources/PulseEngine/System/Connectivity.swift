import Foundation
import Network

/// Is the Mac online? (#300) Read by the sound and music pickers so they can say "offline — using your
/// library" instead of waiting on a search.
@MainActor
public final class Connectivity: ObservableObject {
    public static let shared = Connectivity()

    @Published public private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "pulse.connectivity"))
    }
}
