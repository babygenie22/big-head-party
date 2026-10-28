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
            SceneContainer(scene: game.scene, pointOfView: game.camera) { game.view = $0 }
                .ignoresSafeArea()
            VStack {
                hud
                Spacer()
                if let callout = game.callout {
                    Text(callout)
                        .font(.party(callout.count > 8 ? 40 : 64))
                        .foregroundStyle(LinearGradient(colors: [Theme.yellow, .orange], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black, radius: 0, x: 4, y: 5)
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
                Button { game.stop(); onExit() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
                    .foregroundStyle(.white.opacity(0.7))
            }
            healthBar(1, color: Theme.red)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func healthBar(_ i: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            if i == 0 { AvatarView(character: game.players[0], size: 42, ring: color) }
            VStack(alignment: i == 0 ? .leading : .trailing, spacing: 4) {
                Text(game.players[i].name).font(.caption.weight(.heavy)).lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: i == 0 ? .leading : .trailing) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(game.hp[i] > 30 ? color : Theme.yellow)
                            .frame(width: geo.size.width * game.hp[i] / 100)
                            .animation(.spring, value: game.hp[i])
                    }
                }
                .frame(height: 12)
            }
            if i == 1 { AvatarView(character: game.players[1], size: 42, ring: color) }
        }
    }

    private func controls(player: Int, color: Color, compact: Bool) -> some View {
        let size: CGFloat = compact ? 58 : 76
        return VStack(spacing: 10) {
            if game.vsCPU && game.combo >= 2 {
                Text("Combo ×\(game.combo)").font(.party(16)).foregroundStyle(Theme.yellow)
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
                Text("Tap to punch • Hold BLOCK to cover up").font(.caption.weight(.semibold)).opacity(0.7)
            }
        }
    }

    private func punchButton(_ punch: Punch, player: Int, color: Color, size: CGFloat) -> some View {
        Button { game.punch(punch, by: player) } label: {
            Text(punch.label)
                .font(.party(size > 60 ? 16 : 13))
                .frame(width: size, height: size)
                .background(Circle().fill(color).shadow(color: .black.opacity(0.4), radius: 0, y: 4))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var finishedCard: some View {
        VStack(spacing: 12) {
            Text(game.resultLine).font(.party(22)).multilineTextAlignment(.center)
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
            .background(Circle().fill(pressed ? Theme.yellow : Color.gray.opacity(0.85)))
            .foregroundStyle(pressed ? Color.black : Color.white)
            .scaleEffect(pressed ? 0.92 : 1)
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
