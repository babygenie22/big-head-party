import SwiftUI

struct GameConfig: Identifiable {
    let id = UUID()
    let kind: GameKind
    let players: [GameCharacter]
    let vsCPU: Bool
}

/// Pick two big heads and a mode, then go.
struct MatchSetupView: View {
    let kind: GameKind
    @EnvironmentObject private var store: CharacterStore
    @Environment(\.dismiss) private var dismiss
    @State private var p1: GameCharacter?
    @State private var p2: GameCharacter?
    @State private var editing = 0
    @State private var vsCPU = true
    @State private var game: GameConfig?

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 18) {
                HStack {
                    Image(systemName: kind.symbol)
                    Text(kind.title)
                }
                .font(.party(26))
                .padding(.top, 24)
                Text(kind.blurb).font(.subheadline).foregroundStyle(.white.opacity(0.8))

                HStack(alignment: .center, spacing: 18) {
                    slot(0, p1, color: Theme.blue)
                    Text("VS").font(.party(34)).foregroundStyle(Theme.yellow)
                    slot(1, p2, color: Theme.red)
                }

                Picker("Mode", selection: $vsCPU) {
                    Text("vs Computer").tag(true)
                    Text("2 Players, 1 Phone").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Text(editing == 0 ? "Pick Player 1" : (vsCPU ? "Pick the opponent" : "Pick Player 2"))
                    .font(.headline)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                        ForEach(store.characters) { c in
                            Button { choose(c) } label: {
                                VStack(spacing: 4) {
                                    AvatarView(character: c, size: 70,
                                               ring: c.id == p1?.id ? Theme.blue : (c.id == p2?.id ? Theme.red : .white.opacity(0.6)))
                                    Text(c.name).font(.caption2.weight(.bold)).lineLimit(1)
                                }
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal)
                }
                Button("Let's go!") {
                    guard let p1, let p2 else { return }
                    game = GameConfig(kind: kind, players: [p1, p2], vsCPU: vsCPU)
                }
                .buttonStyle(ChunkyButtonStyle(color: kind.color, textColor: .black))
                .disabled(p1 == nil || p2 == nil)
                .opacity(p1 == nil || p2 == nil ? 0.5 : 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            // Sensible default: newest custom face vs a random house character.
            if p1 == nil { p1 = store.star }
            if p2 == nil { p2 = store.defaults.filter { $0.id != p1?.id }.randomElement() }
            editing = 0
        }
        .fullScreenCover(item: $game) { config in GameHost(config: config) }
    }

    private func slot(_ index: Int, _ c: GameCharacter?, color: Color) -> some View {
        Button { editing = index } label: {
            VStack(spacing: 6) {
                if let c {
                    AvatarView(character: c, size: 96, ring: editing == index ? Theme.yellow : color)
                } else {
                    Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 3, dash: [6])).frame(width: 96, height: 96)
                }
                Text(c?.name ?? "?").font(.headline).lineLimit(1)
                Text(index == 0 ? "P1" : (vsCPU ? "CPU" : "P2")).font(.caption.weight(.black)).foregroundStyle(color)
            }
            .frame(width: 120)
        }
        .foregroundStyle(.white)
    }

    private func choose(_ c: GameCharacter) {
        if editing == 0 { p1 = c; editing = 1 } else { p2 = c; editing = 0 }
    }
}

/// Owns the running game; bumping `rematch` rebuilds it from scratch.
struct GameHost: View {
    let config: GameConfig
    @State private var rematch = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch config.kind {
            case .pieShow:
                PieShowView(players: config.players, vsCPU: config.vsCPU, onRematch: { rematch += 1 }, onExit: { dismiss() })
            case .boxing:
                BoxingView(players: config.players, vsCPU: config.vsCPU, onRematch: { rematch += 1 }, onExit: { dismiss() })
            }
        }
        .id(rematch)
    }
}
