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

enum GameKind: String, Identifiable, CaseIterable {
    case pieShow, slap, dunk, whack, boxing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pieShow: return "The Pie-Q Test"
        case .slap: return "Slap Champs"
        case .dunk: return "Dunk Tank"
        case .whack: return "Whack-a-Head"
        case .boxing: return "Bobble Boxing"
        }
    }
    var blurb: String {
        switch self {
        case .pieShow: return "Game-show trivia. Wrong answer? Pie to the face."
        case .slap: return "Time the meter. Perfect slaps go slow-mo."
        case .dunk: return "Hit the bullseye. Splash."
        case .whack: return "Bonk the faces. Not the baby."
        case .boxing: return "Big heads. Wobbly knockouts."
        }
    }
    var symbol: String {
        switch self {
        case .pieShow: return "birthday.cake.fill"
        case .slap: return "hand.raised.fill"
        case .dunk: return "drop.fill"
        case .whack: return "hammer.fill"
        case .boxing: return "figure.boxing"
        }
    }
    var color: Color {
        switch self {
        case .pieShow: return Theme.yellow
        case .slap: return Theme.pink
        case .dunk: return Theme.teal
        case .whack: return Color(red: 0.55, green: 0.85, blue: 0.4)
        case .boxing: return Theme.red
        }
    }
    /// Whack-a-Head is solo; everything else is head-to-head.
    var isSolo: Bool { self == .whack }
}

struct HomeView: View {
    @EnvironmentObject private var store: CharacterStore
    @AppStorage("hasSeenIntro") private var hasSeenIntro = true
    @StateObject private var hero = ShowcaseHolder()
    @State private var showStudio = false
    @State private var showCast = false
    @State private var setupGame: GameKind?
    @State private var debugGame: GameConfig?
    @State private var debugStudioImage: UIImage?
    @AppStorage(HeadSize.storageKey) private var headSize: HeadSize = .big

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

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(GameKind.allCases) { gameCard($0) }
                    }
                    castRow
                    comingSoon
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            hero.show(store.star, animated: false)
            startDebugScenarioIfRequested()
        }
        .onChange(of: store.characters.map(\.id)) { _, _ in hero.show(store.star) }
        .fullScreenCover(isPresented: $showStudio) { FaceStudioView(testImage: debugStudioImage) }
        .fullScreenCover(item: $debugGame) { GameHost(config: $0) }
        .sheet(isPresented: $showCast) { CastView() }
        .sheet(item: $setupGame) { kind in MatchSetupView(kind: kind) }
    }

    /// Debug builds only: launch arguments that jump straight to a screen, used by the CI
    /// simulator run to screenshot every game (`-demoGame slap`) and the photo pipeline
    /// (`-studioTestImage /path/to/photo.jpg`).
    private func startDebugScenarioIfRequested() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "studioTestImage"), let image = UIImage(contentsOfFile: path) {
            debugStudioImage = image
            showStudio = true
        } else if let raw = defaults.string(forKey: "demoGame"), let kind = GameKind(rawValue: raw), store.defaults.count >= 2 {
            let cast = store.defaults
            debugGame = GameConfig(kind: kind, players: kind.isSolo ? [cast[0]] : [cast[0], cast[1]], vsCPU: true)
        }
        #endif
    }

    private var header: some View {
        HStack {
            PartyTitle(text: "BIG HEAD PARTY", size: 30)
            Spacer()
            Menu {
                Picker("Head size", selection: $headSize) {
                    ForEach(HeadSize.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: headSize == .big ? "person.crop.circle.badge.plus" : "person.crop.circle").font(.title2)
            }
            .accessibilityLabel("Head size: \(headSize.label)")
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
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
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
                    teaser("Bobble Kart", "car.fill", Theme.blue)
                    teaser("Bobble Sumo", "figure.wrestling", Theme.pink)
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
