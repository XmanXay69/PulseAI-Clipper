import PulseCore
import SwiftUI

/// Small mock-ups of what an extra does (#104, #126), so the choice is visual: memes in their colours,
/// a title card, a film strip with a Creative Commons badge, a replay, a beat grid, a punch-in.
struct ExtraPreview: View {
    enum Kind { case memes, titleCards, broll, replays, beatSync, punchIns, speakers }
    let kind: Kind

    var body: some View {
        ZStack {
            Color(hex: 0x1C1F2A)
            content
        }
        .frame(width: 88, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
        .accessibilityHidden(true)
    }

    @ViewBuilder var content: some View {
        switch kind {
        case .memes:
            let yellow = Color(hex: 0xFFD60A), pink = Color(hex: 0xFF3D6E)
            HStack(spacing: 3) {
                ForEach(Array(LongFormEditor.memeMoods.prefix(3).enumerated()), id: \.offset) { i, mood in
                    Text(LongFormEditor.defaultMemeText(for: mood))
                        .font(.system(size: 11, weight: .black)).foregroundStyle([yellow, .white, pink][i % 3])
                        .rotationEffect(.degrees([-6, 4, -3][i % 3]))
                        .shadow(color: .black, radius: 1)
                }
            }
        case .titleCards:
            VStack(spacing: 2) {
                Text("THEN THIS").font(.system(size: 10, weight: .black)).foregroundStyle(.white)
                Text("HAPPENED…").font(.system(size: 10, weight: .black)).foregroundStyle(Color(hex: 0xFFD60A))
            }
            .padding(6).background(Color.black.opacity(0.75))
        case .broll:
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Theme.ai.opacity(0.35 + Double(i) * 0.2)).frame(width: 22, height: 30)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("CC").font(.system(size: 8, weight: .black)).foregroundStyle(.black)
                    .padding(.horizontal, 3).background(Capsule().fill(.white)).padding(3)
            }
        case .replays:
            VStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text("REPLAY").font(.system(size: 8, weight: .black)).foregroundStyle(Color(hex: 0xFFD60A))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.35))
            .saturation(0.4)
        case .beatSync:
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    Rectangle().fill(i % 2 == 0 ? Theme.accent : Theme.accent.opacity(0.4)).frame(width: 2, height: CGFloat(12 + (i * 7) % 20))
                }
            }
        case .punchIns:
            ZStack {
                RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.5)).frame(width: 60, height: 34)
                RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ai, lineWidth: 1.5).frame(width: 36, height: 20)
                Image(systemName: "plus.magnifyingglass").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ai)
            }
        case .speakers:
            HStack(spacing: 4) {
                Circle().fill(Theme.accent).frame(width: 14, height: 14)
                Rectangle().fill(.white.opacity(0.4)).frame(width: 18, height: 2)
                Circle().fill(Theme.ai).frame(width: 14, height: 14)
            }
        }
    }
}
