import SwiftUI

/// A small "?" that opens a paragraph about a feature right where you are (#433).
enum HelpTopic: String, CaseIterable {
    case loudness, enhance, chromaKey, speedEdit, viewerQuality, retention, proxies

    var title: String {
        switch self {
        case .loudness: return "Loudness"
        case .enhance: return "Enhance"
        case .chromaKey: return "Chroma key"
        case .speedEdit: return "Speed Edit"
        case .viewerQuality: return "Viewer quality"
        case .retention: return "Predicted retention"
        case .proxies: return "Proxies"
        }
    }

    var text: String {
        switch self {
        case .loudness:
            return "Platforms turn loud videos down and leave quiet ones alone. PULSE measures the whole mix in LUFS before an export and can bring it to −14 LUFS (YouTube) or −16 (podcast). True peak is the loudest point between samples; keep it at or under −1 dBTP so nothing clips after the platform re-encodes."
        case .enhance:
            return "Enhance renders a processed copy of the clip's audio: noise removal, voice EQ, compression and a limiter. The original plays until the render is ready. “Hear 10 s raw vs processed” lets you compare before committing."
        case .chromaKey:
            return "Chroma key makes one colour transparent. Pick Green or Blue, raise Tolerance until the backdrop is gone, add a little Softness for edges, and use Spill to pull the backdrop's tint out of hair and shoulders. Min. colour keeps dark or grey pixels so shadows stay."
        case .speedEdit:
            return "Speed Edit is a keyboard pass over the recording's moments: N and P step through them with in and out set around each, X makes a short, D dismisses, return exports in → out, J K L shuttle and escape leaves."
        case .viewerQuality:
            return "Full renders the viewer at the canvas size; ½ and ¼ are lighter on the GPU. With the automatic option, PULSE drops a step when playback falls behind the clock. Exports always render in full."
        case .retention:
            return "The retention line guesses where viewers leave: slowly through lively stretches, fast through flat ones, with the first 30 seconds mattering most. It's a model, not a measurement — use it to find dead stretches to cut."
        case .proxies:
            return "Proxies are smaller copies of big recordings that play smoothly in the viewer. Exports always use the originals."
        }
    }
}

struct HelpChip: View {
    let topic: HelpTopic
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
        .buttonStyle(.plain)
        .help("What is \(topic.title.lowercased())?")
        .accessibilityLabel("Help: \(topic.title)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title).font(.pulseHeadline)
                Text(topic.text).font(.pulseCaption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320)
        }
    }
}
