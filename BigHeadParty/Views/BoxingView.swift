import SwiftUI

struct BoxingView: View {
    let onRematch: () -> Void
    let onExit: () -> Void
    @StateObject private var game: BoxingGame
    @State private var snapshot: IdentifiableImage?

    init(players: [GameCharacter], vsCPU: Bool, onRematch: @escaping () -> Void, onExit: @escaping () -> Void) {
        _game = StateObject(wrappedValue: BoxingGame(players: players, vsCPU: vsCPU))
        self.onRematch = onRematch
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SceneContainer(scene: game.scene, pointOfView: game.camera, onViewCreated: { game.view = $0 })
                .ignoresSafeArea()
            VStack {
                hud
                Spacer()
                if let callout = game.callout {
                    Text(callout)
                        .font(.party(callout.count > 8 ? 40 : 64))
                        .foregroundStyle(Theme.butter)
                        .background(Text(callout).font(.party(callout.count > 8 ? 40 : 64)).foregroundStyle(Theme.ink).offset(x: 4, y: 5))
                        .rotationEffect(.degrees(-6))
                        .transition(.scale(scale: 2.5).combined(with: .opacity))
                        .id(callout)
                }
                Spacer()
                if game.phase == .finished {
                    finishedCard
                } else if game.vsCPU {
                    controls(player: 0, color: Theme.blue, compact: false)
                } else {
                    HStack(alignment: .bottom) {
                        controls(player: 0, color: Theme.blue, compact: true)
                        Spacer(minLength: 20)
                        controls(player: 1, color: Theme.red, compact: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: game.callout)
        }
        .onAppear { game.start() }
        .onDisappear { game.stop() }
        .sheet(item: $snapshot) { SnapshotSheet(image: $0.image) }
    }

    private var hud: some View {
        HStack(spacing: 10) {
            healthBar(0, color: Theme.blue)
            VStack(spacing: 2) {
                Text("\(game.timeLeft)").font(.party(26)).monospacedDigit()
                Button { game.stop(); onExit() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .black)) }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Quit game")
            }
            healthBar(1, color: Theme.red)
        }
        .padding(10)
        .foregroundStyle(Theme.ink)
                .card(Theme.surface, cornerRadius: 18)
    }

    private func healthBar(_ i: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            if i == 0 { AvatarView(character: game.players[0], size: 42, ring: color) }
            VStack(alignment: i == 0 ? .leading : .trailing, spacing: 4) {
                Text(game.players[i].name).font(.caption.weight(.heavy)).lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: i == 0 ? .leading : .trailing) {
                        Capsule().fill(Theme.ink.opacity(0.12))
                        Capsule().fill(game.hp[i] > 30 ? color : Theme.coral)
                            .frame(width: geo.size.width * game.hp[i] / 100)
                            .animation(.spring, value: game.hp[i])
                    }
                    .clipShape(Capsule())
                    
                }
                .frame(height: 14)
            }
            if i == 1 { AvatarView(character: game.players[1], size: 42, ring: color) }
        }
    }

    private func controls(player: Int, color: Color, compact: Bool) -> some View {
        let size: CGFloat = compact ? 58 : 76
        return VStack(spacing: 10) {
            if game.vsCPU && game.combo >= 2 {
                Text("Combo ×\(game.combo)").font(.party(16)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 3).pill(Theme.butter)
            }
            HStack(spacing: compact ? 8 : 14) {
                if compact {
                    VStack(spacing: 8) {
                        punchButton(.uppercut, player: player, color: color, size: size)
                        HStack(spacing: 8) {
                            punchButton(.jab, player: player, color: color, size: size)
                            punchButton(.hook, player: player, color: color, size: size)
                        }
                        BlockButton(size: size) { game.setBlocking($0, player: player) }
                    }
                } else {
                    BlockButton(size: size) { game.setBlocking($0, player: player) }
                    punchButton(.jab, player: player, color: color, size: size)
                    punchButton(.hook, player: player, color: color, size: size)
                    punchButton(.uppercut, player: player, color: color, size: size)
                }
            }
            if !compact {
                Text("Tap to punch • Hold BLOCK to cover up")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .pill(Theme.surface)
            }
        }
    }

    private func punchButton(_ punch: Punch, player: Int, color: Color, size: CGFloat) -> some View {
        Button { game.punch(punch, by: player) } label: {
            Text(punch.label)
                .font(.party(size > 60 ? 16 : 13))
                .frame(width: size, height: size)
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(PunchButtonStyle(color: color))
    }

    private var finishedCard: some View {
        VStack(spacing: 12) {
            Text(game.resultLine).font(.party(22)).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button { if let img = game.snapshot() { snapshot = IdentifiableImage(image: img) } } label: {
                    Label("Snap", systemImage: "camera.fill")
                }
                .buttonStyle(CandyButtonStyle(color: Theme.lime))
                Button("Rematch") { onRematch() }
                    .buttonStyle(CandyButtonStyle())
            }
            Button("Back to menu") { game.stop(); onExit() }.font(.party(16))
        }
        .padding(20)
        .foregroundStyle(Theme.ink)
                .card(Theme.surface, cornerRadius: 24)
    }
}

/// Press-and-hold button: reports press began / ended.
private struct BlockButton: View {
    let size: CGFloat
    let onChange: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text("BLOCK")
            .font(.party(size > 60 ? 15 : 12))
            .frame(width: size, height: size)
            .foregroundStyle(Theme.ink)
            .background(Circle().fill(pressed ? Theme.butter : Theme.surface))
            .offset(x: pressed ? 4 : 0, y: pressed ? 4 : 0)
            .softShadow(0.6)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { pressed = true; onChange(true) }
                    }
                    .onEnded { _ in
                        pressed = false
                        onChange(false)
                    }
            )
    }
}

/// Round sticker punch buttons that press into their shadow.
private struct PunchButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(Circle().fill(color))
            .offset(x: pressed ? 4 : 0, y: pressed ? 4 : 0)
            .softShadow(0.6)
            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: pressed)
    }
}
