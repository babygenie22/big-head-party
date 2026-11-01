import SwiftUI

final class ShowcaseHolder: ObservableObject {
    let stage = ShowcaseStage(character: nil)
    @Published var shownID: UUID?

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
        case .pieShow: return Theme.bubblegum
        case .slap: return Theme.tomato
        case .dunk: return Theme.sky
        case .whack: return Theme.mint
        case .boxing: return Theme.lilac
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
    @State private var debugStudio: IdentifiableImage?
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
                        Label("Make a big head", systemImage: "camera.fill")
                    }
                    .buttonStyle(ChunkyButtonStyle(color: Theme.tomato))

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 18) {
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
        .fullScreenCover(isPresented: $showStudio) { FaceStudioView() }
        .fullScreenCover(item: $debugStudio) { FaceStudioView(testImage: $0.image) }
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
            debugStudio = IdentifiableImage(image: image)
        } else if let raw = defaults.string(forKey: "demoGame"), let kind = GameKind(rawValue: raw), store.defaults.count >= 2 {
            let cast = store.defaults
            debugGame = GameConfig(kind: kind, players: kind.isSolo ? [cast[0]] : [cast[0], cast[1]], vsCPU: true)
        } else if defaults.bool(forKey: "studioCamera") {
            showStudio = true
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            PartyTitle(text: "Big Head Party", size: 32)
            Spacer()
            Menu {
                Picker("Head size", selection: $headSize) {
                    ForEach(HeadSize.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: headSize == .big ? "person.crop.circle.badge.plus" : "person.crop.circle")
                    .frame(width: 22, height: 22)
                    .padding(10)
                    .background(Circle().fill(Theme.cream).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2.5)))
                    .background(Circle().fill(Theme.ink).offset(x: 3, y: 3))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Head size: \(headSize.label)")
            Button {
                hasSeenIntro = false
            } label: {
                Image(systemName: "play.fill").frame(width: 22, height: 22)
            }
            .buttonStyle(StickerIconButtonStyle())
            .accessibilityLabel("Watch the demo again")
        }
        .padding(.top, 8)
    }

    /// The signature piece: today's star standing in a collector box, like a bobblehead on a shelf.
    private var heroCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SERIES 1")
                Spacer()
                Text("COLLECT 'EM ALL")
            }
            .font(.system(size: 12, weight: .black, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.tomato)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: Theme.outline) }

            // The box window.
            ZStack {
                Theme.sky
                Circle().fill(Theme.cream.opacity(0.35)).frame(width: 250, height: 250)
                Circle().fill(Theme.cream.opacity(0.35)).frame(width: 170, height: 170)
                SceneContainer(scene: hero.stage.scene, pointOfView: hero.stage.camera)
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ink, lineWidth: Theme.outline))
            .padding(12)

            VStack(spacing: 10) {
                if let star = store.star {
                    Text(star.meta.isDefault ? "Starring \(star.name)" : "Now starring \(star.name)")
                        .font(.party(20))
                        .foregroundStyle(Theme.ink)
                }
                HStack(spacing: 8) {
                    reactButton("Pie", "birthday.cake.fill", Theme.bubblegum) { hero.stage.throwPie() }
                    reactButton("Bonk", "hand.point.right.fill", Theme.mint) { hero.stage.react(.skewLeft) }
                    reactButton("Scream", "mouth.fill", Theme.lilac) { hero.stage.react(.mouthOpen) }
                    reactButton("Clean", "drop.fill", Theme.sky) { hero.stage.clean() }
                }
            }
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sticker(Theme.cream, cornerRadius: 24, drop: 6)
    }

    private func reactButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold))
                Text(title).font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Theme.ink)
            .frame(width: 66, height: 48)
            .sticker(color, cornerRadius: 12, drop: 3)
        }
        .buttonStyle(.plain)
    }

    private func gameCard(_ kind: GameKind) -> some View {
        let index = GameKind.allCases.firstIndex(of: kind) ?? 0
        return Button {
            setupGame = kind
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.cream).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2.5)))
                Text(kind.title).font(.party(19)).multilineTextAlignment(.leading)
                Text(kind.blurb).font(.system(size: 13, weight: .semibold, design: .rounded)).multilineTextAlignment(.leading)
                    .foregroundStyle(Theme.ink.opacity(0.75))
                Spacer(minLength: 0)
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.cream).overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2)))
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 186, alignment: .topLeading)
            .sticker(kind.color, cornerRadius: 22)
            // Stuck on slightly crooked, like real stickers.
            .rotationEffect(.degrees(index.isMultiple(of: 2) ? -1.2 : 1.2))
        }
        .buttonStyle(.plain)
    }

    private var castRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your cast").font(.party(24)).foregroundStyle(Theme.ink)
                Spacer()
                Button("See all") { showCast = true }
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .stickerCapsule(Theme.cream)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    Button { showStudio = true } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(Theme.cream)
                                Circle().strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                                Image(systemName: "plus").font(.title.weight(.black))
                            }
                            .frame(width: 66, height: 66)
                            Text("New").font(.system(size: 12, weight: .heavy, design: .rounded))
                        }
                    }
                    .foregroundStyle(Theme.ink)
                    ForEach(store.characters) { c in
                        Button { hero.show(c) } label: {
                            VStack(spacing: 6) {
                                AvatarView(character: c, size: 66, ring: hero.shownID == c.id ? Theme.highlight : nil)
                                Text(c.name).font(.system(size: 12, weight: .heavy, design: .rounded)).lineLimit(1).frame(width: 78)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming soon").font(.party(24)).foregroundStyle(Theme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    teaser("Bobble Kart", "car.fill")
                    teaser("Bobble Sumo", "figure.wrestling")
                    teaser("Wedding Cake Wars", "gift.fill")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func teaser(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title).font(.system(size: 15, weight: .heavy, design: .rounded))
            Image(systemName: "lock.fill").font(.caption)
        }
        .foregroundStyle(Theme.ink.opacity(0.7))
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Capsule().fill(Theme.cream.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }
}
