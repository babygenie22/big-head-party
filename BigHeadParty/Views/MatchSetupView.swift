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
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .card(kind.color, cornerRadius: 18)
                .rotationEffect(.degrees(-1.5))
                .padding(.top, 28)
                Text(kind.blurb).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink.opacity(0.75))

                HStack(alignment: .center, spacing: 18) {
                    slot(0, p1, color: Theme.blue)
                    if !kind.isSolo {
                        Text("VS").font(.party(30)).foregroundStyle(Theme.surface)
                            .frame(width: 60, height: 60)
                            .card(Theme.ink, cornerRadius: 30)
                            .rotationEffect(.degrees(-8))
                        slot(1, p2, color: Theme.red)
                    }
                }

                if !kind.isSolo {
                    Picker("Mode", selection: $vsCPU) {
                        Text("vs Computer").tag(true)
                        Text("2 Players, 1 Phone").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                Text(kind.isSolo ? "Whose face pops up most?" : (editing == 0 ? "Pick Player 1" : (vsCPU ? "Pick the opponent" : "Pick Player 2")))
                    .font(.party(17))
                    .foregroundStyle(Theme.ink)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                        ForEach(store.characters) { c in
                            Button { choose(c) } label: {
                                VStack(spacing: 4) {
                                    AvatarView(character: c, size: 70,
                                               ring: c.id == p1?.id ? Theme.blue : (c.id == p2?.id ? Theme.red : nil))
                                    Text(c.name).font(.system(size: 11, weight: .heavy, design: .rounded)).lineLimit(1)
                                }
                            }
                            .foregroundStyle(Theme.ink)
                        }
                    }
                    .padding(.horizontal)
                }
                Button("Let's go!") {
                    guard let p1 else { return }
                    if kind.isSolo {
                        game = GameConfig(kind: kind, players: [p1], vsCPU: true)
                    } else if let p2 {
                        game = GameConfig(kind: kind, players: [p1, p2], vsCPU: vsCPU)
                    }
                }
                .buttonStyle(CandyButtonStyle(color: kind.color))
                .disabled(!ready)
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
                    AvatarView(character: c, size: 96, ring: color)
                        .scaleEffect(editing == index ? 1.06 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: editing)
                } else {
                    Circle().strokeBorder(Theme.ink.opacity(0.25), style: StrokeStyle(lineWidth: 3, dash: [7, 5])).frame(width: 96, height: 96)
                }
                Text(c?.name ?? "?").font(.party(16)).lineLimit(1)
                Text(index == 0 ? "P1" : (vsCPU ? "CPU" : "P2"))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .pill(editing == index ? color : Theme.surface)
            }
            .frame(width: 120)
        }
        .foregroundStyle(Theme.ink)
    }

    private var ready: Bool { p1 != nil && (kind.isSolo || p2 != nil) }

    private func choose(_ c: GameCharacter) {
        if kind.isSolo { p1 = c; return }
        if editing == 0 { p1 = c; editing = 1 } else { p2 = c; editing = 0 }
    }
}

/// Owns the running game; bumping `rematch` rebuilds it from scratch.
struct GameHost: View {
    let config: GameConfig
    @EnvironmentObject private var store: CharacterStore
    @State private var rematch = 0
    @Environment(\.dismiss) private var dismiss
    /// Outlives rematches, so one recording can span several rounds.
    @StateObject private var recorder = GameRecorder()

    var body: some View {
        Group {
            switch config.kind {
            case .pieShow:
                PieShowView(players: config.players, vsCPU: config.vsCPU, onRematch: { rematch += 1 }, onExit: { dismiss() })
            case .boxing:
                BoxingView(players: config.players, vsCPU: config.vsCPU, onRematch: { rematch += 1 }, onExit: { dismiss() })
            case .slap:
                SlapView(players: config.players, vsCPU: config.vsCPU, onRematch: { rematch += 1 }, onExit: { dismiss() })
            case .dunk:
                DunkView(players: config.players, vsCPU: config.vsCPU, onRematch: { rematch += 1 }, onExit: { dismiss() })
            case .whack:
                WhackView(player: config.players[0], cast: store.defaults, onRematch: { rematch += 1 }, onExit: { dismiss() })
            }
        }
        .id(rematch)
        .overlay(alignment: .topTrailing) {
            if recorder.isAvailable {
                RecordButton(recorder: recorder)
                    .padding(.top, 160)   // below every game's top bar and banner
                    .padding(.trailing, 14)
            }
        }
        .onDisappear { recorder.stop() }
    }
}
