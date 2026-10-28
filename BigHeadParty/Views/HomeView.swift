import SwiftUI

final class ShowcaseHolder: ObservableObject {
    let stage = ShowcaseStage(character: nil)
    var shownID: UUID?

    func show(_ character: GameCharacter?, animated: Bool = true) {
        guard let character, character.id != shownID else { return }
        shownID = character.id
        stage.show(character, animated: animated)
    }
}

enum GameKind: String, Identifiable {
    case pieShow, boxing
    var id: String { rawValue }
    var title: String { self == .pieShow ? "The Pie-Q Test" : "Bobble Boxing" }
    var blurb: String {
        self == .pieShow ? "Game-show trivia. Wrong answer? Pie to the face." : "Big heads. Tiny bodies. Wobbly knockouts."
    }
    var symbol: String { self == .pieShow ? "birthday.cake.fill" : "figure.boxing" }
    var color: Color { self == .pieShow ? Theme.yellow : Theme.red }
}

struct HomeView: View {
    @EnvironmentObject private var store: CharacterStore
    @AppStorage("hasSeenIntro") private var hasSeenIntro = true
    @StateObject private var hero = ShowcaseHolder()
    @State private var showStudio = false
    @State private var showCast = false
    @State private var setupGame: GameKind?

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    header
                    heroCard
                    Button {
                        showStudio = true
                    } label: {
                        Label("Make a Big Head", systemImage: "camera.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle())

                    HStack(spacing: 14) {
                        gameCard(.pieShow)
                        gameCard(.boxing)
                    }
                    castRow
                    comingSoon
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .onAppear { hero.show(store.star, animated: false) }
        .onChange(of: store.characters.map(\.id)) { _, _ in hero.show(store.star) }
        .fullScreenCover(isPresented: $showStudio) { FaceStudioView() }
        .sheet(isPresented: $showCast) { CastView() }
        .sheet(item: $setupGame) { kind in MatchSetupView(kind: kind) }
    }

    private var header: some View {
        HStack {
            PartyTitle(text: "BIG HEAD PARTY", size: 30)
            Spacer()
            Button {
                hasSeenIntro = false
            } label: {
                Image(systemName: "play.rectangle.fill").font(.title2)
            }
            .accessibilityLabel("Watch the demo again")
        }
        .padding(.top, 8)
    }

    private var heroCard: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(RadialGradient(colors: [Theme.pink.opacity(0.55), Theme.deep], center: .center, startRadius: 10, endRadius: 260))
            SceneContainer(scene: hero.stage.scene, pointOfView: hero.stage.camera)
            VStack(spacing: 6) {
                if let star = store.star {
                    Text(star.meta.isDefault ? "Starring \(star.name)" : "Now starring: \(star.name)")
                        .font(.party(18))
                }
                HStack(spacing: 10) {
                    reactButton("Pie!", "birthday.cake") { hero.stage.throwPie() }
                    reactButton("Bonk", "hand.point.right") { hero.stage.react(.skewLeft) }
                    reactButton("Scream", "mouth") { hero.stage.react(.mouthOpen) }
                    reactButton("Clean", "drop") { hero.stage.clean() }
                }
            }
            .padding(.bottom, 12)
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func reactButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text(title).font(.caption.weight(.heavy))
            }
            .frame(width: 62, height: 46)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(.white)
    }

    private func gameCard(_ kind: GameKind) -> some View {
        Button {
            setupGame = kind
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: kind.symbol).font(.system(size: 34, weight: .bold))
                Text(kind.title).font(.party(19)).multilineTextAlignment(.leading)
                Text(kind.blurb).font(.caption.weight(.semibold)).opacity(0.75).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text("PLAY ▶").font(.party(14))
            }
            .foregroundStyle(.black)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(kind.color, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var castRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Cast").font(.party(22))
                Spacer()
                Button("See all") { showCast = true }.font(.headline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    Button { showStudio = true } label: {
                        VStack {
                            ZStack {
                                Circle().strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [6])).frame(width: 66, height: 66)
                                Image(systemName: "plus").font(.title.weight(.bold))
                            }
                            Text("New").font(.caption.weight(.bold))
                        }
                    }
                    .foregroundStyle(Theme.yellow)
                    ForEach(store.characters) { c in
                        Button { hero.show(c) } label: {
                            VStack {
                                AvatarView(character: c, size: 66, ring: c.meta.isDefault ? .white : Theme.yellow)
                                Text(c.name).font(.caption.weight(.bold)).lineLimit(1).frame(width: 76)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming soon").font(.party(22))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    teaser("Dunk Tank Derby", "drop.fill", Theme.teal)
                    teaser("Slap Champs", "hand.raised.fill", Theme.pink)
                    teaser("Bobble Kart", "car.fill", Theme.blue)
                    teaser("Wedding Cake Wars", "gift.fill", Theme.yellow)
                }
            }
        }
    }

    private func teaser(_ title: String, _ symbol: String, _ color: Color) -> some View {
        HStack {
            Image(systemName: symbol)
            Text(title).font(.headline)
            Image(systemName: "lock.fill").font(.caption)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(color.opacity(0.25), in: Capsule())
        .overlay(Capsule().stroke(color, lineWidth: 1.5))
    }
}
