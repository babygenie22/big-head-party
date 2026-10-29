import SwiftUI

// MARK: - Shared pieces

/// Player badge for the top bar: avatar, name and a value (HP, dunks, score).
private struct PlayerBadge: View {
    let character: GameCharacter
    let value: String
    var label: String?
    var active = false
    var trailing = false
    var color: Color = Theme.blue

    var body: some View {
        HStack(spacing: 8) {
            if !trailing { AvatarView(character: character, size: 42, ring: active ? Theme.yellow : color) }
            VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
                Text(label ?? character.name).font(.caption.weight(.bold)).lineLimit(1)
                Text(value).font(.party(17)).contentTransition(.numericText()).animation(.spring, value: value)
            }
            if trailing { AvatarView(character: character, size: 42, ring: active ? Theme.yellow : color) }
        }
    }
}

/// Big tilted announcer text in the middle of the screen.
private struct Callout: View {
    let text: String?
    var body: some View {
        ZStack {
            if let text {
                Text(text)
                    .font(.party(text.count > 12 ? 30 : 46))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LinearGradient(colors: [Theme.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black, radius: 0, x: 3, y: 4)
                    .rotationEffect(.degrees(-5))
                    .transition(.scale(scale: 2).combined(with: .opacity))
                    .id(text)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: text)
    }
}

/// End-of-game card with Snap / Rematch / Back.
private struct ResultCard: View {
    let line: String
    let snap: () -> UIImage?
    let onRematch: () -> Void
    let onExit: () -> Void
    @State private var snapshot: IdentifiableImage?

    var body: some View {
        VStack(spacing: 12) {
            Text(line).font(.party(22)).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button { if let img = snap() { snapshot = IdentifiableImage(image: img) } } label: { Label("Snap", systemImage: "camera.fill") }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.teal, textColor: .black))
                Button("Rematch", action: onRematch).buttonStyle(ChunkyButtonStyle())
            }
            Button("Back to menu", action: onExit).font(.headline)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .sheet(item: $snapshot) { SnapshotSheet(image: $0.image) }
    }
}

private struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "xmark.circle.fill").font(.title2) }
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Quit game")
    }
}

// MARK: - Slap Champs

struct SlapView: View {
    let onRematch: () -> Void
    let onExit: () -> Void
    @StateObject private var game: SlapGame

    init(players: [GameCharacter], vsCPU: Bool, onRematch: @escaping () -> Void, onExit: @escaping () -> Void) {
        _game = StateObject(wrappedValue: SlapGame(players: players, vsCPU: vsCPU))
        self.onRematch = onRematch
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SceneContainer(scene: game.scene, pointOfView: game.camera, onViewCreated: { game.view = $0 }).ignoresSafeArea()
            VStack(spacing: 10) {
                HStack {
                    PlayerBadge(character: game.players[0], value: "\(game.hp[0]) HP", active: game.turn == 0 && game.phase != .finished)
                    Spacer()
                    CloseButton { game.stop(); onExit() }
                    Spacer()
                    PlayerBadge(character: game.players[1], value: "\(game.hp[1]) HP", active: game.turn == 1 && game.phase != .finished,
                                trailing: true, color: Theme.red)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                Spacer()
                Callout(text: game.callout)
                Spacer()
                if game.phase == .finished {
                    ResultCard(line: game.resultLine, snap: game.snapshot, onRematch: onRematch, onExit: { game.stop(); onExit() })
                } else {
                    controls
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .onAppear { game.start() }
        .onDisappear { game.stop() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Text(game.phase == .aiming
                 ? (game.isHumanTurn ? "\(game.players[game.turn].name), stop the needle in the gold!" : "\(game.players[game.turn].name) is winding up…")
                 : "Slap \(min(game.slapNumber + 1, game.totalSlaps)) of \(game.totalSlaps)")
                .font(.headline)
                .multilineTextAlignment(.center)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.15))
                    Rectangle().fill(Theme.yellow.opacity(0.9))
                        .frame(width: geo.size.width * SlapGame.perfectZone)
                        .offset(x: geo.size.width * (0.5 - SlapGame.perfectZone / 2))
                    Capsule().fill(.white)
                        .frame(width: 6, height: 44)
                        .shadow(radius: 2)
                        .offset(x: geo.size.width * game.needle - 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(height: 36)
            .accessibilityHidden(true)
            Button("SLAP!") { game.slap() }
                .buttonStyle(ChunkyButtonStyle(color: Theme.red))
                .disabled(!(game.phase == .aiming && game.isHumanTurn))
                .opacity(game.phase == .aiming && game.isHumanTurn ? 1 : 0.4)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Dunk Tank

struct DunkView: View {
    let onRematch: () -> Void
    let onExit: () -> Void
    @StateObject private var game: DunkGame

    init(players: [GameCharacter], vsCPU: Bool, onRematch: @escaping () -> Void, onExit: @escaping () -> Void) {
        _game = StateObject(wrappedValue: DunkGame(players: players, vsCPU: vsCPU))
        self.onRematch = onRematch
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SceneContainer(scene: game.scene, pointOfView: game.camera, onViewCreated: { game.view = $0 }).ignoresSafeArea()
            VStack(spacing: 10) {
                HStack {
                    PlayerBadge(character: game.players[0], value: dunks(game.score[0]), active: game.thrower == 0 && game.phase != .finished)
                    Spacer()
                    CloseButton { game.stop(); onExit() }
                    Spacer()
                    PlayerBadge(character: game.players[1], value: dunks(game.score[1]), active: game.thrower == 1 && game.phase != .finished,
                                trailing: true, color: Theme.red)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                Text(game.hostLine)
                    .font(.subheadline.weight(.bold))
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
                Spacer()
                Callout(text: game.callout)
                Spacer()
                if game.phase == .finished {
                    ResultCard(line: game.resultLine, snap: game.snapshot, onRematch: onRematch, onExit: { game.stop(); onExit() })
                } else {
                    VStack(spacing: 8) {
                        Text("Ball \(min(game.ball + 1, game.ballsPerHalf)) of \(game.ballsPerHalf)").font(.headline)
                        Button("THROW") { game.throwBall() }
                            .buttonStyle(ChunkyButtonStyle(color: Theme.red))
                            .disabled(!(game.phase == .aiming && game.isHumanTurn))
                            .opacity(game.phase == .aiming && game.isHumanTurn ? 1 : 0.4)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .onAppear { game.start() }
        .onDisappear { game.stop() }
    }

    private func dunks(_ n: Int) -> String { n == 1 ? "1 dunk" : "\(n) dunks" }
}

// MARK: - Whack-a-Head

struct WhackView: View {
    let onRematch: () -> Void
    let onExit: () -> Void
    @StateObject private var game: WhackGame

    init(player: GameCharacter, cast: [GameCharacter], onRematch: @escaping () -> Void, onExit: @escaping () -> Void) {
        _game = StateObject(wrappedValue: WhackGame(player: player, cast: cast))
        self.onRematch = onRematch
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SceneContainer(scene: game.scene, pointOfView: game.camera, onViewCreated: { game.view = $0 },
                           onTap: { point, view in game.handleTap(at: point, in: view) })
                .ignoresSafeArea()
            VStack(spacing: 10) {
                HStack {
                    PlayerBadge(character: game.player, value: "\(game.score)", label: "Score")
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(game.timeLeft)").font(.party(26)).monospacedDigit()
                        CloseButton { game.stop(); onExit() }
                    }
                    Spacer()
                    PlayerBadge(character: game.player, value: "\(game.best)", label: "Best", trailing: true, color: Theme.yellow)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                Spacer()
                Callout(text: game.callout).allowsHitTesting(false)
                Spacer()
                if game.finished {
                    ResultCard(line: game.score >= game.best && game.score > 0 ? "New best: \(game.score) points!" : "Time! \(game.score) points.",
                               snap: game.snapshot, onRematch: onRematch, onExit: { game.stop(); onExit() })
                } else {
                    Text("Tap the heads. Golden = +3. Not the baby!")
                        .font(.headline)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .onAppear { game.start() }
        .onDisappear { game.stop() }
    }
}
