import SwiftUI

struct PieShowView: View {
    let onRematch: () -> Void
    let onExit: () -> Void
    @StateObject private var game: PieShowGame
    @State private var snapshot: IdentifiableImage?

    init(players: [GameCharacter], vsCPU: Bool, onRematch: @escaping () -> Void, onExit: @escaping () -> Void) {
        _game = StateObject(wrappedValue: PieShowGame(players: players, vsCPU: vsCPU))
        self.onRematch = onRematch
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SceneContainer(scene: game.stage.scene, pointOfView: game.stage.camera) { game.view = $0 }
                .ignoresSafeArea()
            VStack(spacing: 10) {
                scoreboard
                hostBubble
                Spacer()
                if game.phase == .finished {
                    finishedCard
                } else if let q = game.question {
                    questionCard(q)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .onAppear { game.start() }
        .onDisappear { game.stop() }
        .sheet(item: $snapshot) { SnapshotSheet(image: $0.image) }
    }

    private var scoreboard: some View {
        HStack {
            playerBadge(0, color: Theme.blue)
            Spacer()
            VStack(spacing: 2) {
                Text("Q \(min(game.round + 1, game.totalRounds))/\(game.totalRounds)").font(.party(16))
                Button { game.stop(); onExit() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            playerBadge(1, color: Theme.red)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func playerBadge(_ i: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            if i == 1 { pieCount(i) }
            AvatarView(character: game.players[i], size: 44, ring: game.turn == i && game.phase != .finished ? Theme.yellow : color)
            if i == 0 { pieCount(i) }
        }
    }

    private func pieCount(_ i: Int) -> some View {
        VStack(alignment: i == 0 ? .leading : .trailing, spacing: 0) {
            Text(game.players[i].name).font(.caption.weight(.bold)).lineLimit(1)
            Text("🥧 × \(game.pies[i])").font(.party(18))
                .contentTransition(.numericText())
                .animation(.spring, value: game.pies[i])
        }
        .frame(maxWidth: 100, alignment: i == 0 ? .leading : .trailing)
    }

    private var hostBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("🎤").font(.title2)
            Text(game.hostLine)
                .font(.subheadline.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.black)
        .animation(.spring, value: game.hostLine)
    }

    private func questionCard(_ q: TriviaQuestion) -> some View {
        VStack(spacing: 10) {
            if game.phase == .asking || game.phase == .cpuThinking {
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Capsule().fill(game.timeLeft < 3 ? Theme.red : Theme.yellow)
                                .frame(width: geo.size.width * game.timeLeft / game.answerTime)
                        }
                }
                .frame(height: 8)
            }
            Text(q.prompt).font(.party(21)).multilineTextAlignment(.center)
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                Button { game.answer(i) } label: {
                    Text(option)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(optionColor(i, q), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .disabled(game.phase != .asking)
            }
            if game.phase == .cpuThinking {
                Text("\(game.currentName) is answering…").font(.caption.weight(.bold)).opacity(0.8)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func optionColor(_ i: Int, _ q: TriviaQuestion) -> Color {
        guard game.phase == .reveal else { return Theme.purple.opacity(0.9) }
        if i == q.answer { return .green }
        if i == game.picked { return Theme.red }
        return Theme.purple.opacity(0.5)
    }

    private var finishedCard: some View {
        VStack(spacing: 14) {
            if let w = game.winnerIndex {
                AvatarView(character: game.players[w], size: 80, ring: Theme.yellow)
                Text("\(game.players[w].name) WINS!").font(.party(28))
            } else {
                Text("IT'S A TIE!").font(.party(30))
            }
            Text("Final tally: 🥧 \(game.pies[0]) – \(game.pies[1])").font(.headline)
            HStack(spacing: 10) {
                Button { if let img = game.snapshot() { snapshot = IdentifiableImage(image: img) } } label: {
                    Label("Snap", systemImage: "camera.fill")
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.teal, textColor: .black))
                Button("Rematch") { onRematch() }
                    .buttonStyle(ChunkyButtonStyle())
            }
            Button("Back to menu") { game.stop(); onExit() }.font(.headline)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .transition(.scale.combined(with: .opacity))
    }
}
